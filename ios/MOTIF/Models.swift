import Foundation

struct Track: Identifiable, Codable, Hashable {
    enum Source: String, Codable {
        case local
        case preview
        case cloud
    }

    var id: UUID = UUID()
    var title: String
    var artist: String
    var album: String
    var releaseYear: Int? = nil
    var artworkURL: URL?
    var mediaURL: URL
    var duration: Double
    var source: Source
    var remoteID: String?
    var streamURL: URL? = nil
    var addedAt: Date = Date()
    var lyrics: String? = nil
    /// "tags", "filename", or "ai". Optional so older library.json files decode.
    var metadataSource: String? = nil

    var isPreview: Bool { source == .preview }
    var isCloud: Bool { source == .cloud }
    var isOffline: Bool { mediaURL.isFileURL }
    var isUploadedToCloud: Bool { source == .local && remoteID != nil }

    var needsRecognition: Bool {
        guard source == .local else { return false }
        if metadataSource == "ai" { return false }
        if metadataSource == "filename" { return true }

        let artistKey = artist
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if ["", "imported", "unknown", "unknown artist", "various", "various artists", "va"]
            .contains(artistKey) {
            return true
        }
        return false
    }

    var durationText: String {
        guard duration.isFinite, duration > 0 else { return "--:--" }
        let total = Int(duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct Playlist: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var description: String
    var trackIDs: [UUID]
    var customCoverURL: URL?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        trackIDs: [UUID] = [],
        customCoverURL: URL? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.trackIDs = trackIDs
        self.customCoverURL = customCoverURL
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case trackIDs
        case customCoverURL
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        trackIDs = try container.decodeIfPresent([UUID].self, forKey: .trackIDs) ?? []
        customCoverURL = try container.decodeIfPresent(URL.self, forKey: .customCoverURL)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

struct LibrarySnapshot: Codable {
    var tracks: [Track]
    var favoriteIDs: [UUID]
    var playlists: [Playlist]
    var recentTrackIDs: [UUID]

    init(
        tracks: [Track] = [],
        favoriteIDs: [UUID] = [],
        playlists: [Playlist] = [],
        recentTrackIDs: [UUID] = []
    ) {
        self.tracks = tracks
        self.favoriteIDs = favoriteIDs
        self.playlists = playlists
        self.recentTrackIDs = recentTrackIDs
    }

    private enum CodingKeys: String, CodingKey {
        case tracks
        case favoriteIDs
        case playlists
        case recentTrackIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tracks = try container.decodeIfPresent([Track].self, forKey: .tracks) ?? []
        favoriteIDs = try container.decodeIfPresent([UUID].self, forKey: .favoriteIDs) ?? []
        playlists = try container.decodeIfPresent([Playlist].self, forKey: .playlists) ?? []
        recentTrackIDs = try container.decodeIfPresent([UUID].self, forKey: .recentTrackIDs) ?? []
    }
}
