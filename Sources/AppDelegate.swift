import Cocoa
import Foundation
import Logging
import TOMLDecoder
import XDG

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var monitoringTask: Task<Void, Never>?
    private var isMonitoring = false
    
    // Status icons
    private var playingIcon: NSImage!
    private var stoppedIcon: NSImage!
    
    // Configuration
    private var conf: Conf!
    private var slackToken: String!
    private var includeAlbumName: Bool = true
    private var useRandomEmoji: Bool = false
    private var clearWhenNotPlaying: Bool = true
    
    // Monitoring state
    private var initialStatus: SlackStatus?
    private var lastUpdateWasMusic = false
    private var lastPlayedTrack: CurrentTrackInfo.TrackInfo?
    
    private var appLogger: Logger = {
        var logger = logger(.info)
        return logger
    }()
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        loadStatusIcons()
        setupMenuBar()
        loadConfiguration()
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        stopMonitoring()
    }
    
    private func loadStatusIcons() {
        let playingImagePath = Bundle.main.path(forResource: "statusicon-playing-v1", ofType: "png")!
        let stoppedImagePath = Bundle.main.path(forResource: "statusicon-stopped-v1", ofType: "png")!

        // Load the status icons from the Resources folder
        playingIcon = NSImage(contentsOfFile: playingImagePath)
        stoppedIcon = NSImage(contentsOfFile: stoppedImagePath)
            
        // Set icon size to fit in the menu bar
        playingIcon?.size = NSSize(width: 18, height: 18)
        stoppedIcon?.size = NSSize(width: 18, height: 18)
    }
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = stoppedIcon
        statusItem.button?.toolTip = "Apple Music to Slack"
        
        menu = NSMenu()
        
        let statusMenuItem = NSMenuItem(title: "Status: Not monitoring", action: nil, keyEquivalent: "")
        statusMenuItem.tag = 1
        menu.addItem(statusMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let startStopMenuItem = NSMenuItem(title: "Start Monitoring", action: #selector(toggleMonitoring), keyEquivalent: "")
        startStopMenuItem.tag = 2
        startStopMenuItem.target = self
        menu.addItem(startStopMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let preferencesMenuItem = NSMenuItem(title: "Preferences", action: #selector(showPreferences), keyEquivalent: ",")
        preferencesMenuItem.target = self
        menu.addItem(preferencesMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitMenuItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitMenuItem.target = self
        menu.addItem(quitMenuItem)
        
        statusItem.menu = menu
    }
    
    private func loadConfiguration() {
        do {
            let directories = try BaseDirectories(prefixAll: "apple-music-to-slack")
            guard let confFile = try directories.findConfigFile("settings.toml"), let confURL = URL(filePath: confFile) else {
                showAlert(message: "Cannot find the settings.toml file. Please create a settings.toml file in the config directory.")
                return
            }
            
            let confData = try Data(contentsOf: confURL)
            conf = try TOMLDecoder().decode(Conf.self, from: confData)
            
            // Get Slack token from environment or config
            slackToken = ProcessInfo.processInfo.environment["AMTS_SLACK_TOKEN"] ?? conf.slackToken
            guard slackToken != nil else {
                showAlert(message: "Cannot find the Slack token. Please set the environment variable AMTS_SLACK_TOKEN or set it in the settings.toml file.")
                return
            }
            
            includeAlbumName = conf.includeAlbumName ?? true
            
            updateStatusDisplay("Configuration loaded")
            
        } catch {
            showAlert(message: "Error loading configuration: \(error.localizedDescription)")
        }
    }
    
    @objc private func toggleMonitoring() {
        if isMonitoring {
            stopMonitoring()
        } else {
            startMonitoring()
        }
    }
    
    private func startMonitoring() {
        guard slackToken != nil else {
            showAlert(message: "Please configure the Slack token first.")
            return
        }
        
        isMonitoring = true
        updateMenuItems()
        updateStatusDisplay("Starting monitoring...")
        
        monitoringTask = Task {
            do {
                // Get initial Slack status
                initialStatus = try await getCurrentSlackStatus()

                await MainActor.run {
                    updateStatusDisplay("Monitoring active")
                }
                
                // Reset state
                lastUpdateWasMusic = false
                lastPlayedTrack = nil
                
                // Start monitoring loop
                while !Task.isCancelled {
                    await monitorMusicAndUpdateSlack()
                    
                    try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                }
            } catch {
                // If the user cancels the task or an error occurs, handle it gracefully.
                stopMonitoring()

                if Task.isCancelled {
                    appLogger.info("Monitoring task was cancelled.")

                    return
                } 

                await MainActor.run {
                    showAlert(message: "Monitoring error: \(error.localizedDescription)")

                    appLogger.error("Monitoring task encountered: \(error.localizedDescription)", metadata: ["error": "\(error)"])
                }
            }
        }
    }
    
    private func stopMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
        isMonitoring = false
        updateMenuItems()
        updateStatusDisplay("Monitoring stopped")
    }
    
    private func updateMenuItems() {
        if let statusMenuItem = menu.item(withTag: 1) {
            statusMenuItem.title = isMonitoring ? "Status: Monitoring" : "Status: Not monitoring"
        }
        
        if let startStopMenuItem = menu.item(withTag: 2) {
            startStopMenuItem.title = isMonitoring ? "Stop Monitoring" : "Start Monitoring"
        }
        
        statusItem.button?.image = isMonitoring ? playingIcon : stoppedIcon
    }
    
    private func updateStatusDisplay(_ status: String) {
        if let statusMenuItem = menu.item(withTag: 1) {
            if status.count <= 50 {
                statusMenuItem.title = "Status: \(status)"

                return
            }

            // Truncate status text to 50 characters and append ellipsis
            let statusText = String(status[status.startIndex..<status.index(status.startIndex, offsetBy: 50 - 1)]) + "…"
            statusMenuItem.title = "Status: \(statusText)"
        }
    }
    
    private func monitorMusicAndUpdateSlack() async {
        do {
            let currentTrackInfo = try CurrentTrackInfo.get(logger: appLogger)
            appLogger.debug("Grabbed music info.", metadata: ["info": "\(currentTrackInfo)"])
            
            var content: ProfileUpdateContent? = nil
            
            if case let .playing(songInfo) = currentTrackInfo {
                // Check if the song has changed
                let songHasChanged = lastPlayedTrack != songInfo
                
                if songHasChanged {
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
                    lastPlayedTrack = songInfo
                    
                    await MainActor.run {
                        updateStatusDisplay("▶ \(songInfo.artist) - \(songInfo.name)")
                    }
                    
                    appLogger.info("Song changed; updating Slack status.", metadata: ["info": "\(currentTrackInfo)"])
                } else {
                    appLogger.debug("Same song still playing; skipping Slack update.", metadata: ["info": "\(currentTrackInfo)"])
                }
            } else if clearWhenNotPlaying {
                if lastUpdateWasMusic {
                    appLogger.info("Paused/Stopped; restoring original Slack status.")
                    
                    lastUpdateWasMusic = false
                    lastPlayedTrack = nil
                    
                    if let initialStatus = initialStatus {
                        content = ProfileUpdateContent(
                            statusText: initialStatus.statusText,
                            statusEmoji: initialStatus.statusEmoji,
                            statusExpiration: initialStatus.statusExpiration
                        )
                    }
                    
                    await MainActor.run {
                        updateStatusDisplay("Music stopped - status restored")
                    }
                } else {
                    appLogger.debug("We do not have music playing and previous status was not music; skipping update.")
                    
                    // Retrieve the current Slack status to ensure we have the latest one.
                    initialStatus = try await getCurrentSlackStatus()
                    
                    await MainActor.run {
                        updateStatusDisplay("No music playing")
                    }
                    
                    appLogger.debug("Retrieved current Slack status.", metadata: ["current-status": "\(String(describing: initialStatus))"])
                }
            } else {
                appLogger.debug("No music playing; skipping Slack profile update.", metadata: ["current-track-info": "\(currentTrackInfo)"])
                
                lastUpdateWasMusic = false
                lastPlayedTrack = nil
                
                await MainActor.run {
                    updateStatusDisplay("No music playing")
                }
                
                // Retrieve the current Slack status to ensure we have the latest one.
                initialStatus = try await getCurrentSlackStatus()
            }
            
            // Send update to Slack if we have content
            if let content = content {
                try await updateSlackProfile(with: content)
            }
            
        } catch {
            appLogger.error("Error in monitoring loop: \(error)")
            
            await MainActor.run {
                updateStatusDisplay("Error: \(error.localizedDescription)")
            }
        }
    }
    
    private func getCurrentSlackStatus() async throws -> SlackStatus {
        var urlRequest = URLRequest(url: URL(string: "https://slack.com/api/users.profile.get")!)
        urlRequest.httpMethod = "GET"
        urlRequest.addValue("Bearer \(slackToken!)", forHTTPHeaderField: "Authorization")
        
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
    
    private func updateSlackProfile(with content: ProfileUpdateContent) async throws {
        var urlRequest = URLRequest(url: URL(string: "https://slack.com/api/users.profile.set")!)
        urlRequest.httpMethod = "POST"
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.addValue("Bearer \(slackToken!)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(content)
        
        let (data, urlResponse) = try await URLSession.shared.data(for: urlRequest)
        guard let httpResponse = urlResponse as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw SimpleError(message: "Cannot send the profile update to Slack.")
        }
        
        let response = try JSONDecoder().decode(ProfileUpdateResponse.self, from: data)
        guard response.ok else {
            throw SimpleError(message: "Error sending profile update to Slack. Error message: \(response.error ?? "<No Error in Response>")")
        }
        
        appLogger.debug("Successfully updated Slack profile.")
    }
    
    @objc private func showPreferences() {
        let alert = NSAlert()
        alert.messageText = "Preferences"
        alert.informativeText = """
        Current Settings:
        • Include Album Name: \(includeAlbumName ? "Yes" : "No")
        • Use Random Emoji: \(useRandomEmoji ? "Yes" : "No")
        • Clear When Not Playing: \(clearWhenNotPlaying ? "Yes" : "No")
        
        To modify settings, edit the settings.toml file in your config directory.
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(self)
    }
    
    private func showAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "Apple Music to Slack"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// MARK: - Data Structures

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

private struct ProfileUpdateContent: Encodable {
    var statusText: String
    var statusEmoji: String
    var statusExpiration: Date?
    
    init(statusText: String, statusEmoji: String, statusExpiration: Date? = nil) {
        let maxStatusLength: Int = 100
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
    
    enum RootCodingKey: String, CodingKey {
        case profile
    }
    
    enum StatusCodingKeys: String, CodingKey {
        case statusText = "status_text"
        case statusEmoji = "status_emoji"
        case statusExpiration = "status_expiration"
    }
}

private struct ProfileUpdateResponse: Decodable {
    var ok: Bool
    var error: String?
}
