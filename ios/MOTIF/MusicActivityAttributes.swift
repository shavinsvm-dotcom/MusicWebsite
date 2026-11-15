import ActivityKit
import Foundation

@available(iOS 16.1, *)
struct MusicActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var artist: String
        var album: String
        var isPlaying: Bool
        var elapsed: Double
        var duration: Double
        var updatedAt: Date
    }

    var trackID: String
}
