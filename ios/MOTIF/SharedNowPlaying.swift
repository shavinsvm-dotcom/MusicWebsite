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

    /// Derived from the running bundle so renaming the bundle identifier
    /// carries the widget's shared container with it. The widget bundle id is
    /// the app's id plus `.widgets`.
    static var appGroup: String {
        let identifier = Bundle.main.bundleIdentifier ?? "com.example.motif"
        let appIdentifier = identifier.hasSuffix(".widgets")
            ? String(identifier.dropLast(".widgets".count))
            : identifier
        return "group." + appIdentifier
    }
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
