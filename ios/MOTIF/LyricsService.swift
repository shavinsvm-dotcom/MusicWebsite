import Foundation

struct LyricsRecord: Identifiable, Codable, Hashable {
    let id: Int
    let name: String?
    let trackName: String
    let artistName: String
    let albumName: String?
    let duration: Double?
    let instrumental: Bool?
    let hasWordSync: Bool?
    let plainLyrics: String?
    let syncedLyrics: String?
    let lyricsfile: String?

    var lyricsText: String? {
        guard instrumental != true else { return nil }
        for candidate in [syncedLyrics, plainLyrics] {
            if let candidate,
               !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return candidate
            }
        }
        return nil
    }

    var isWordSynced: Bool {
        guard instrumental != true else { return false }
        guard hasWordSync == true else { return false }
        return !(lyricsfile ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasUsableLyrics: Bool {
        instrumental != true && (lyricsText != nil || isWordSynced)
    }

    var isSynced: Bool {
        if isWordSynced { return true }
        guard let syncedLyrics else { return false }
        return !syncedLyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var durationText: String {
        guard let duration, duration.isFinite, duration > 0 else { return "--:--" }
        let total = Int(duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

enum LyricsServiceError: LocalizedError {
    case emptyQuery
    case invalidURL
    case invalidResponse
    case rateLimited
    case serverUnavailable
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .emptyQuery:
            return "Enter a song title first."
        case .invalidURL:
            return "Couldn’t build the lyrics search request."
        case .invalidResponse:
            return "The lyrics service returned an unexpected response."
        case .rateLimited:
            return "The lyrics service is busy right now. Try again in a moment."
        case .serverUnavailable:
            return "The lyrics service is temporarily unavailable."
        case .requestFailed:
            return "Couldn’t reach the lyrics service. Check your connection and try again."
        }
    }
}

enum LyricsService {
    private static let baseURL = "https://lrclib.net"
    private static let userAgent = "MOTIF/1.0 (https://github.com/shavinsvm-dotcom/MusicWebsite)"

    /// Finds the best available lyrics record for a library track.
    ///
    /// When the audio duration is known, candidates that do not fit the track
    /// or whose lyric timestamps run past the audio are rejected. This prevents
    /// a live or remix version from winning just because it is the only result.
    static func findLyrics(
        for track: Track,
        audioDuration: TimeInterval? = nil
    ) async throws -> LyricsRecord? {
        let title = track.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !artist.isEmpty else { return nil }

        let duration = usableDuration(audioDuration) ?? usableDuration(track.duration)

        var exactItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist)
        ]

        let album = track.album.trimmingCharacters(in: .whitespacesAndNewlines)
        if !album.isEmpty {
            exactItems.append(URLQueryItem(name: "album_name", value: album))
        }

        if let duration {
            exactItems.append(URLQueryItem(
                name: "duration",
                value: String(Int(duration.rounded()))
            ))
        }

        if let exact = try await fetchRecord(path: "/api/get", queryItems: exactItems),
           exact.hasUsableLyrics,
           isAcceptable(exact, for: track, duration: duration) {
            return exact
        }

        let candidates = try await search(title: title, artist: artist)
        return candidates
            .filter {
                $0.hasUsableLyrics
                    && isAcceptable($0, for: track, duration: duration)
            }
            .max {
                score($0, for: track, duration: duration)
                    < score($1, for: track, duration: duration)
            }
    }

    /// Searches LRCLIB using editable title and artist fields.
    static func search(title: String, artist: String) async throws -> [LyricsRecord] {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw LyricsServiceError.emptyQuery }

        var items = [URLQueryItem(name: "track_name", value: title)]
        if !artist.isEmpty {
            items.append(URLQueryItem(name: "artist_name", value: artist))
        }

        var results: [LyricsRecord] = try await fetchRecords(
            path: "/api/search",
            queryItems: items
        )

        if results.isEmpty {
            var broad = [URLQueryItem(name: "q", value: title)]
            if !artist.isEmpty {
                broad[0] = URLQueryItem(name: "q", value: "\(title) \(artist)")
            }
            results = try await fetchRecords(path: "/api/search", queryItems: broad)
        }

        return results
    }

    private static func usableDuration(_ value: TimeInterval?) -> TimeInterval? {
        guard let value, value.isFinite, value >= 1, value <= 3600 else { return nil }
        return value
    }

    private static func isAcceptable(
        _ record: LyricsRecord,
        for track: Track,
        duration: TimeInterval?
    ) -> Bool {
        guard record.hasUsableLyrics else { return false }
        guard !hasAlternateVersionMismatch(record, track: track) else { return false }

        if let duration {
            if let recordDuration = record.duration,
               recordDuration.isFinite,
               recordDuration >= 1 {
                let tolerance = max(3.0, min(8.0, duration * 0.03))
                guard abs(recordDuration - duration) <= tolerance else { return false }
            }

            guard timestampsFit(record, duration: duration) else { return false }
        }

        return true
    }

    private static func timestampsFit(_ record: LyricsRecord, duration: TimeInterval) -> Bool {
        let document: LyricsDocument?
        if record.isWordSynced, let lyricsfile = record.lyricsfile {
            document = LyricsFileParser.parse(lyricsfile)
        } else if let syncedLyrics = record.syncedLyrics {
            document = LyricsParser.parse(syncedLyrics)
        } else {
            return true
        }

        guard let document, document.isSynced else { return true }
        guard let first = document.lines.first?.timestamp,
              let last = document.lines.last?.timestamp
        else { return true }

        guard first >= -1, first <= duration + 2, last <= duration + 2 else {
            return false
        }

        let wordEndsOutOfBounds = document.lines.contains { line in
            line.words.contains { word in
                word.start > duration + 2
                    || (word.end ?? word.start) > duration + 3
            }
        }
        return !wordEndsOutOfBounds
    }

    private static func score(
        _ record: LyricsRecord,
        for track: Track,
        duration: TimeInterval?
    ) -> Double {
        var score = 0.0

        if normalize(record.trackName) == normalize(track.title) {
            score += 1000
        } else if normalize(record.trackName).contains(normalize(track.title))
                    || normalize(track.title).contains(normalize(record.trackName)) {
            score += 250
        }

        if normalize(record.artistName) == normalize(track.artist) {
            score += 400
        }

        if let recordAlbum = record.albumName,
           !recordAlbum.isEmpty,
           normalize(recordAlbum) == normalize(track.album) {
            score += 60
        }

        if let duration, let recordDuration = record.duration, recordDuration.isFinite {
            score -= abs(recordDuration - duration) * 100
        }

        if record.isWordSynced {
            score += 35
        } else if record.isSynced {
            score += 12
        }

        if let duration {
            if let document = lyricsDocument(for: record),
               let last = document.lines.last?.timestamp {
                let coverage = last / duration
                if coverage < 0.45 {
                    score -= 30
                } else if coverage > 0.85 {
                    score += 15
                }
            }
        }

        return score
    }

    private static func lyricsDocument(for record: LyricsRecord) -> LyricsDocument? {
        if record.isWordSynced, let lyricsfile = record.lyricsfile {
            return LyricsFileParser.parse(lyricsfile)
        }
        if let syncedLyrics = record.syncedLyrics {
            return LyricsParser.parse(syncedLyrics)
        }
        return nil
    }

    private static func hasAlternateVersionMismatch(
        _ record: LyricsRecord,
        track: Track
    ) -> Bool {
        let markers = [
            "live", "remix", "acoustic", "instrumental", "karaoke",
            "cover", "sped", "nightcore", "demo", "reprise", "remaster"
        ]
        let recordTokens = Set(tokens(in: record.trackName))
        let trackTokens = Set(tokens(in: track.title))
        let recordMarkers = Set(markers.filter(recordTokens.contains))
        let trackMarkers = Set(markers.filter(trackTokens.contains))
        return !recordMarkers.subtracting(trackMarkers).isEmpty
    }

    private static func tokens(in value: String) -> [String] {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static func normalize(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    private static func fetchRecord(
        path: String,
        queryItems: [URLQueryItem]
    ) async throws -> LyricsRecord? {
        guard var components = URLComponents(string: baseURL + path) else {
            throw LyricsServiceError.invalidURL
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw LyricsServiceError.invalidURL }

        let (data, response) = try await request(url)
        guard let http = response as? HTTPURLResponse else {
            throw LyricsServiceError.invalidResponse
        }

        switch http.statusCode {
        case 200:
            return try JSONDecoder().decode(LyricsRecord.self, from: data)
        case 404:
            return nil
        case 429:
            throw LyricsServiceError.rateLimited
        case 500...599:
            throw LyricsServiceError.serverUnavailable
        default:
            throw LyricsServiceError.invalidResponse
        }
    }

    private static func fetchRecords(
        path: String,
        queryItems: [URLQueryItem]
    ) async throws -> [LyricsRecord] {
        guard var components = URLComponents(string: baseURL + path) else {
            throw LyricsServiceError.invalidURL
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw LyricsServiceError.invalidURL }

        let (data, response) = try await request(url)
        guard let http = response as? HTTPURLResponse else {
            throw LyricsServiceError.invalidResponse
        }

        switch http.statusCode {
        case 200:
            return try JSONDecoder().decode([LyricsRecord].self, from: data)
        case 429:
            throw LyricsServiceError.rateLimited
        case 500...599:
            throw LyricsServiceError.serverUnavailable
        default:
            throw LyricsServiceError.invalidResponse
        }
    }

    private static func request(_ url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        do {
            return try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw LyricsServiceError.requestFailed
        } catch {
            throw LyricsServiceError.requestFailed
        }
    }
}
