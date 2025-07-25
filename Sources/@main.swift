import Foundation

import ArgumentParser
import Logging
import TOMLDecoder
import XDG

@main
struct Main : AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "apple-music-to-slack"
	)
	
	@Flag(inversion: .prefixedNo)
	var verbose: Bool = false
	
	@Flag(inversion: .prefixedNo, help: "Use a random emoji from a list of pre-defined ones. If set to false, the :notes: emoji will be used.")
	var useRandomEmoji: Bool = false
	
	@Flag(inversion: .prefixedNo, help: "Restore original Slack status when Apple Music isn't playing. When false, the status will remain unchanged.")
	var clearWhenNotPlaying: Bool = true
	
	@Option
	var slackToken: String?
	
	func run() async throws {
		let logger = logger(verbose ? .debug : .notice)
		
		/* Load configuration settings first. */
		let conf: Conf = try {
			let directories = try BaseDirectories(prefixAll: "apple-music-to-slack")
			guard let confFile = try directories.findConfigFile("settings.toml"), let confURL = URL(filePath: confFile) else {
				throw SimpleError(message: "Cannot find the settings.toml file. Please create a settings.toml file in the config directory.")
			}

			let confData = try Data(contentsOf: confURL)

			return try TOMLDecoder().decode(Conf.self, from: confData)
		}()
		
		/* Retrieve the Slack token from command line, environment, or config file. */
		let slackToken = slackToken ?? ProcessInfo.processInfo.environment["AMTS_SLACK_TOKEN"] ?? conf.slackToken
		guard let slackToken else {
			throw SimpleError(message: "Cannot find the Slack token. You should either provide it as an argument or set the environment variable AMTS_SLACK_TOKEN, or set it in the settings.toml file.")
		}
		
		let includeAlbumName = conf.includeAlbumName ?? true
		
		/* Retrieve the initial Slack status to restore later when not playing. */
		var initialStatus = try await getCurrentSlackStatus(slackToken: slackToken, logger: logger)
		
		logger.info("Starting continuous monitoring loop. Press Ctrl+C to stop.")

		// Initialize the last update status.
		// This variable tracks whether the last update was a music track info update.
		// If it was, we can restore the original status when no music is playing.
		// If it wasn't, we can skip restoring the original status.
		// This is useful to avoid unnecessary updates when the status is already set to the original status.
		// This is especially useful when the user starts the script while no music is playing		
		var lastUpdateWasMusic = false

		/* Run the track info and profile updating in a loop every 10 seconds. */
		while true {
			/* Retrieve the current track info and the new profile status. */
			let currentTrackInfo = try CurrentTrackInfo.get(logger: logger)
			logger.debug("Grabbed music info.", metadata: ["info": "\(currentTrackInfo)"])

			var content: ProfileUpdateContent? = nil

			if case let .playing(songInfo) = currentTrackInfo {
				let statusText: String

				if includeAlbumName {
					statusText = "\(songInfo.artist) — \(songInfo.album) — \(songInfo.name)"
				} else {
					statusText = "\(songInfo.artist) — \(songInfo.name)"
				}
				
				content = ProfileUpdateContent(
					statusText: statusText,
					statusEmoji: (useRandomEmoji ? MusicEmoji.allCases.randomElement()! : .notes).rawValue,
					statusExpiration: nil
				)

				lastUpdateWasMusic = true
			} else if clearWhenNotPlaying {
				if lastUpdateWasMusic {
					logger.debug("We do not have music playing; restoring original Slack status.")

					lastUpdateWasMusic = false

					content = ProfileUpdateContent(
						statusText: initialStatus.statusText,
						statusEmoji: initialStatus.statusEmoji,
						statusExpiration: initialStatus.statusExpiration
					)
				} else {
					logger.debug("We do not have music playing and previous status was not music; skipping update.")

					// Retrieve the current Slack status to ensure we have the latest one.
					initialStatus = try await getCurrentSlackStatus(slackToken: slackToken, logger: logger)

					logger.debug("Retrieved current Slack status.", metadata: ["current-status": "\(initialStatus)"])
				}
			} else {
				logger.debug("No music playing; skipping Slack profile update.", metadata: ["current-track-info": "\(currentTrackInfo)"])
				
				lastUpdateWasMusic = false

				// Retrieve the current Slack status to ensure we have the latest one.
				initialStatus = try await getCurrentSlackStatus(slackToken: slackToken, logger: logger)
			}
			
			/* Send the track info to Slack as a profile update if we have content. */
			if content != nil {
				var urlRequest = URLRequest(url: URL(string: "https://slack.com/api/users.profile.set")!)
				urlRequest.httpMethod = "POST"
				urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
				urlRequest.addValue("Bearer \(slackToken)", forHTTPHeaderField: "Authorization")
				urlRequest.httpBody = try JSONEncoder().encode(content)

				let (data, urlResponse) = try await URLSession.shared.data(for: urlRequest)
				guard let httpResponse = urlResponse as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
					logger.error("Cannot send the profile update to Slack.")
					// Continue the loop instead of throwing
					try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
					continue
				}

				let response = try JSONDecoder().decode(ProfileUpdateResponse.self, from: data)
				guard response.ok else {
					logger.error("Error sending profile update to Slack. Error message: \(response.error ?? "<No Error in Response>")")
					// Continue the loop instead of throwing
					try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
					continue
				}
				
				logger.info("Successfully updated Slack profile.")
			}
			
			/* Wait 10 seconds before the next iteration. */
			try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
		}
	}
	
	private func getCurrentSlackStatus(slackToken: String, logger: Logger) async throws -> SlackStatus {
		var urlRequest = URLRequest(url: URL(string: "https://slack.com/api/users.profile.get")!)
		urlRequest.httpMethod = "GET"
		urlRequest.addValue("Bearer \(slackToken)", forHTTPHeaderField: "Authorization")
		
		let (data, urlResponse) = try await URLSession.shared.data(for: urlRequest)
		guard let httpResponse = urlResponse as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
			throw SimpleError(message: "Cannot retrieve current Slack profile.")
		}
		
		let response = try JSONDecoder().decode(ProfileGetResponse.self, from: data)
		guard response.ok else {
			throw SimpleError(message: "Error retrieving Slack profile. Error message: \(response.error ?? "<No Error in Response>")")
		}
		
		let profile = response.profile
		let statusExpiration: Date? = if let expiration = profile.statusExpiration, expiration > 0 {
			Date(timeIntervalSince1970: expiration)
		} else {
			nil
		}
		
		return SlackStatus(
			statusText: profile.statusText ?? "",
			statusEmoji: profile.statusEmoji ?? "",
			statusExpiration: statusExpiration
		)
	}
	
	private struct SlackStatus {
		let statusText: String
		let statusEmoji: String
		let statusExpiration: Date?
	}
	
	private struct ProfileGetResponse: Decodable {
		let ok: Bool
		let error: String?
		let profile: SlackProfile
	}
	
	private struct SlackProfile: Decodable {
		let statusText: String?
		let statusEmoji: String?
		let statusExpiration: Double?
		
		enum CodingKeys: String, CodingKey {
			case statusText = "status_text"
			case statusEmoji = "status_emoji"
			case statusExpiration = "status_expiration"
		}
	}
	
	private struct ProfileUpdateContent : Encodable {
		var statusText: String
		var statusEmoji: String
		var statusExpiration: Date?
		
		init(statusText: String, statusEmoji: String, statusExpiration: Date? = nil) {
			let maxStatusLength: Int = 100 /* Empirically tested to be the max (2025-05-02). */
			if statusText.count <= maxStatusLength {
				self.statusText = statusText
			} else {
				self.statusText = String(statusText[statusText.startIndex..<statusText.index(statusText.startIndex, offsetBy: maxStatusLength - 1)]) + "…"
			}
			self.statusEmoji = statusEmoji
			self.statusExpiration = statusExpiration
		}
		
		func encode(to encoder: any Encoder) throws {
			var container = encoder.container(keyedBy: RootCodingKey.self)
			var subContainer = container.nestedContainer(keyedBy: StatusCodingKeys.self, forKey: .profile)
			try subContainer.encodeIfPresent(statusText, forKey: .statusText)
			try subContainer.encodeIfPresent(statusEmoji, forKey: .statusEmoji)
			try subContainer.encodeIfPresent(statusExpiration?.timeIntervalSince1970, forKey: .statusExpiration)
		}
		
		enum RootCodingKey : String, CodingKey {
			case profile
		}
		
		enum StatusCodingKeys : String, CodingKey {
			case statusText = "status_text"
			case statusEmoji = "status_emoji"
			case statusExpiration = "status_expiration"
		}	
	}
	
	private struct ProfileUpdateResponse : Decodable {
		var ok: Bool
		var error: String?
	}
}
