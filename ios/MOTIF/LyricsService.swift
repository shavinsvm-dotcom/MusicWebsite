import Foundation

struct LyricsRecord: Identifiable, Codable, Hashable {
    let id: Int
    let name: String?
    let trackName: String
    let artistName: String
    let albumName: String?
    let duration: Double?
    let instrumental: Bool?
    let plainLyrics: String?
    let syncedLyrics: String?

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

    var isSynced: Bool {
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
    static func findLyrics(for track: Track) async throws -> LyricsRecord? {
        let title = track.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !artist.isEmpty else { return nil }

        var exactItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist)
        ]

        let album = track.album.trimmingCharacters(in: .whitespacesAndNewlines)
        if !album.isEmpty {
            exactItems.append(URLQueryItem(name: "album_name", value: album))
        }

        if track.duration.isFinite, track.duration >= 1, track.duration <= 3600 {
            exactItems.append(URLQueryItem(
                name: "duration",
                value: String(Int(track.duration.rounded()))
            ))
        }

        if let exact = try await fetchRecord(path: "/api/get", queryItems: exactItems),
           exact.lyricsText != nil {
            return exact
        }

        let candidates = try await search(title: title, artist: artist)
        return candidates
            .filter { $0.lyricsText != nil }
            .min { rank($0, for: track) < rank($1, for: track) }
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

    private static func rank(_ record: LyricsRecord, for track: Track) -> Double {
        var score = 0.0
        if let duration = record.duration, track.duration > 0 {
            score += abs(duration - track.duration)
        }
        if normalize(record.trackName) == normalize(track.title) {
            score -= 100
        }
        if normalize(record.artistName) == normalize(track.artist) {
            score -= 40
        }
        if record.isSynced {
            score -= 5
        }
        return score
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
