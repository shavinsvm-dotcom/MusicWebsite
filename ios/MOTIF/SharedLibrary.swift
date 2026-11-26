import Foundation

struct SharedLibrarySnapshot: Codable, Equatable {
    struct Item: Codable, Equatable, Identifiable {
        let id: String
        let title: String
        let artist: String
        let artworkURL: String?
    }

    var trackCount: Int
    var playlistCount: Int
    var recent: [Item]
    var playlistName: String?
    var playlistArtworkURL: String?

    /// Matches SharedNowPlaying.appGroup, including inside the widget.
    static var appGroup: String {
        let identifier = Bundle.main.bundleIdentifier ?? "com.example.motif"
        let appIdentifier = identifier.hasSuffix(".widgets")
            ? String(identifier.dropLast(".widgets".count))
            : identifier
        return "group." + appIdentifier
    }
    private static let storageKey = "motif.library"

    static func save(_ snapshot: SharedLibrarySnapshot) {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = try? JSONEncoder().encode(snapshot)
        else { return }
        defaults.set(data, forKey: storageKey)
    }

    static func load() -> SharedLibrarySnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = defaults.data(forKey: storageKey)
        else { return nil }
        return try? JSONDecoder().decode(SharedLibrarySnapshot.self, from: data)
    }
}
