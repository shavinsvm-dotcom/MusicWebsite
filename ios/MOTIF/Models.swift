import Foundation

enum LyricsSource: String, Codable, Hashable {
    case automatic
    case embedded
    case manual
}

struct Track: Identifiable, Codable, Hashable {
    enum Source: String, Codable {
        case local
        /// Legacy iTunes preview row. New previews are no longer created, and
        /// saved rows are dropped when the library loads.
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
    /// Raw LRCLIB Lyricsfile YAML when the record has word-level timings.
    var lyricsFile: String? = nil
    /// Whether the current lyrics were picked automatically or by the user.
    /// Optional so older library.json files still decode.
    var lyricsSource: LyricsSource? = nil
    /// "tags", "filename", or "ai". Optional so older library.json files decode.
    var metadataSource: String? = nil

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
    var playCounts: [UUID: Int]

    init(
        tracks: [Track] = [],
        favoriteIDs: [UUID] = [],
        playlists: [Playlist] = [],
        recentTrackIDs: [UUID] = [],
        playCounts: [UUID: Int] = [:]
    ) {
        self.tracks = tracks
        self.favoriteIDs = favoriteIDs
        self.playlists = playlists
        self.recentTrackIDs = recentTrackIDs
        self.playCounts = playCounts
    }

    private enum CodingKeys: String, CodingKey {
        case tracks
        case favoriteIDs
        case playlists
        case recentTrackIDs
        case playCounts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tracks = try container.decodeIfPresent([Track].self, forKey: .tracks) ?? []
        favoriteIDs = try container.decodeIfPresent([UUID].self, forKey: .favoriteIDs) ?? []
        playlists = try container.decodeIfPresent([Playlist].self, forKey: .playlists) ?? []
        recentTrackIDs = try container.decodeIfPresent([UUID].self, forKey: .recentTrackIDs) ?? []
        playCounts = try container.decodeIfPresent([UUID: Int].self, forKey: .playCounts) ?? [:]
    }
}

enum LibrarySearch {
    static func tokens(in query: String) -> [String] {
        query
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
    }

    /// Every token has to match at least one field, so "bad ed" finds
    /// "Bad Habits" by Ed Sheeran instead of requiring the exact phrase.
    static func matches(_ query: String, in fields: [String]) -> Bool {
        matches(tokens(in: query), in: fields)
    }

    /// Tokenised form, so a search pass splits the query once instead of once
    /// per candidate row.
    static func matches(_ tokens: [String], in fields: [String]) -> Bool {
        guard !tokens.isEmpty else { return false }
        return tokens.allSatisfy { token in
            fields.contains { $0.localizedStandardContains(token) }
        }
    }

    /// Exact title matches come first, then title prefixes, then title
    /// substrings. Everything else falls back to the caller's ordering.
    static func rank(title: String, query: String) -> Int {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        let options: String.CompareOptions = [
            .caseInsensitive,
            .diacriticInsensitive,
            .widthInsensitive
        ]
        if title.compare(trimmed, options: options) == .orderedSame { return 0 }
        if title.range(of: trimmed, options: options.union(.anchored)) != nil { return 1 }
        if title.range(of: trimmed, options: options) != nil { return 2 }
        return 3
    }
}

/// Sort orders offered by the Library tab. Lives here so the store can cache
/// the sorted array instead of rebuilding it for every view pass.
enum SongSort: String, CaseIterable, Identifiable {
    case recentlyAdded
    case title
    case artist
    case album
    case mostPlayed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recentlyAdded: return "Recently added"
        case .title: return "Title"
        case .artist: return "Artist"
        case .album: return "Album"
        case .mostPlayed: return "Most played"
        }
    }
}
