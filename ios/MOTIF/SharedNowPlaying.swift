import Foundation

struct SharedNowPlaying: Codable, Equatable {
    var title: String
    var artist: String
    var album: String
    var artworkURL: String?
    var isPlaying: Bool
    var elapsed: Double
    var duration: Double
    var updatedAt: Date

    static let appGroup = "group.com.example.motif"
    private static let storageKey = "motif.nowPlaying"

    static func save(_ snapshot: SharedNowPlaying) {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = try? JSONEncoder().encode(snapshot)
        else { return }
        defaults.set(data, forKey: storageKey)
    }

    static func load() -> SharedNowPlaying? {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = defaults.data(forKey: storageKey)
        else { return nil }
        return try? JSONDecoder().decode(SharedNowPlaying.self, from: data)
    }

    static func clear() {
        UserDefaults(suiteName: appGroup)?.removeObject(forKey: storageKey)
    }
}
