import Foundation

struct SharedLibrarySnapshot: Codable, Equatable {
    struct Item: Codable, Equatable, Identifiable {
        let id: String
        let title: String
        let artist: String
        let artworkURL: String?
        var artworkFileName: String? = nil

        init(
            id: String,
            title: String,
            artist: String,
            artworkURL: String?,
            artworkFileName: String? = nil
        ) {
            self.id = id
            self.title = title
            self.artist = artist
            self.artworkURL = artworkURL
            self.artworkFileName = artworkFileName
        }
    }

    var trackCount: Int
    var playlistCount: Int
    var recent: [Item]
    var playlistName: String?
    var playlistArtworkURL: String?
    var favoriteCount: Int?
    var mostPlayed: [Item]?
    var updatedAt: Date?

    init(
        trackCount: Int,
        playlistCount: Int,
        recent: [Item],
        playlistName: String?,
        playlistArtworkURL: String?,
        favoriteCount: Int? = nil,
        mostPlayed: [Item]? = nil,
        updatedAt: Date? = nil
    ) {
        self.trackCount = trackCount
        self.playlistCount = playlistCount
        self.recent = recent
        self.playlistName = playlistName
        self.playlistArtworkURL = playlistArtworkURL
        self.favoriteCount = favoriteCount
        self.mostPlayed = mostPlayed
        self.updatedAt = updatedAt
    }

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
