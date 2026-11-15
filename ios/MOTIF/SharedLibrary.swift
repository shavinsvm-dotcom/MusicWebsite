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

    static let appGroup = "group.com.example.motif"
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
