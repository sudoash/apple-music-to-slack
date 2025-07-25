import Foundation

struct Conf : Decodable {
	var slackToken: String?
	var includeAlbumName: Bool?
	
	enum CodingKeys : String, CodingKey {
		case slackToken = "slack_token"
		case includeAlbumName = "include_album_name"
	}
}
