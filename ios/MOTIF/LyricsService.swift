import Foundation

enum LyricsSyncLevel: Int, Comparable {
    case none = 0
    case plain = 1
    case lineSynced = 2
    case wordSynced = 3

    static func < (lhs: LyricsSyncLevel, rhs: LyricsSyncLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

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
        if let lyricsfile,
           let plain = LyricsFileParser.plainText(from: lyricsfile),
           !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return plain
        }
        return nil
    }

    var isWordSynced: Bool {
        guard instrumental != true,
              let lyricsfile,
              !lyricsfile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let document = LyricsFileParser.parse(lyricsfile)
        else { return false }
        return document.isWordSynced
    }

    var hasUsableLyrics: Bool {
        instrumental != true && (lyricsText != nil || isWordSynced)
    }

    var isSynced: Bool {
        if isWordSynced { return true }
        if let lyricsfile,
           let document = LyricsFileParser.parse(lyricsfile),
           document.isSynced {
            return true
        }
        guard let syncedLyrics else { return false }
        return !syncedLyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var syncLevel: LyricsSyncLevel {
        if isWordSynced { return .wordSynced }
        if isSynced { return .lineSynced }
        if lyricsText != nil { return .plain }
        return .none
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
    private static let userAgent = "Lilt/1.0 (https://github.com/shavinsvm-dotcom/MusicWebsite)"

    /// Finds the best available lyrics record for a library track.
    ///
    /// The exact endpoint is only one candidate. Search results are merged in
    /// so a word-synced file can beat an exact plain-text match. Every timed
    /// candidate must fit the actual audio duration before it is considered.
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

        var candidates: [LyricsRecord] = []
        var exactError: Error?

        do {
            if let exact = try await fetchRecord(path: "/api/get", queryItems: exactItems),
               exact.hasUsableLyrics {
                if exact.syncLevel == .wordSynced,
                   isAcceptable(exact, for: track, duration: duration) {
                    return exact
                }
                candidates.append(exact)
            }
        } catch {
            exactError = error
        }

        do {
            candidates.append(contentsOf: try await search(title: title, artist: artist))
        } catch {
            guard !candidates.isEmpty else {
                throw exactError ?? error
            }
        }

        var unique: [Int: LyricsRecord] = [:]
        for candidate in candidates where candidate.hasUsableLyrics {
            if let existing = unique[candidate.id], existing.syncLevel >= candidate.syncLevel {
                continue
            }
            unique[candidate.id] = candidate
        }

        let eligible = unique.values.filter {
            isAcceptable($0, for: track, duration: duration)
        }
        guard !eligible.isEmpty else { return nil }

        if let wordSynced = best(in: eligible.filter { $0.syncLevel == .wordSynced }, for: track, duration: duration) {
            return wordSynced
        }
        if let lineSynced = best(in: eligible.filter { $0.syncLevel == .lineSynced }, for: track, duration: duration) {
            return lineSynced
        }
        return best(in: eligible, for: track, duration: duration)
    }

    /// The quality currently stored on a library track.
    static func syncLevel(for track: Track) -> LyricsSyncLevel {
        var level: LyricsSyncLevel = .none

        if let lyricsFile = track.lyricsFile,
           let document = LyricsFileParser.parse(lyricsFile) {
            if document.isWordSynced { return .wordSynced }
            if document.isSynced { level = .lineSynced }
        }

        if let lyrics = track.lyrics, !lyrics.isEmpty {
            let document = LyricsParser.parse(lyrics)
            if document.isWordSynced { return .wordSynced }
            if document.isSynced, level < .lineSynced { level = .lineSynced }
            if level == .none { level = .plain }
        }

        return level
    }

    private static func best(
        in candidates: [LyricsRecord],
        for track: Track,
        duration: TimeInterval?
    ) -> LyricsRecord? {
        candidates.max {
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
        guard matchesTrackMetadata(record, track: track) else { return false }
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

    private static func matchesTrackMetadata(_ record: LyricsRecord, track: Track) -> Bool {
        let recordTitle = normalize(record.trackName)
        let trackTitle = normalize(track.title)
        guard !recordTitle.isEmpty, !trackTitle.isEmpty else { return false }
        guard recordTitle == trackTitle
            || recordTitle.contains(trackTitle)
            || trackTitle.contains(recordTitle)
        else { return false }

        let recordArtist = normalize(record.artistName)
        let trackArtist = normalize(track.artist)
        if !recordArtist.isEmpty, !trackArtist.isEmpty {
            guard recordArtist == trackArtist
                || recordArtist.contains(trackArtist)
                || trackArtist.contains(recordArtist)
            else { return false }
        }

        return true
    }

    private static func timestampsFit(_ record: LyricsRecord, duration: TimeInterval) -> Bool {
        guard let document = lyricsDocument(for: record) else {
            return record.syncLevel < .lineSynced
        }
        guard document.isSynced else { return true }

        let timedLines = document.lines.filter { $0.timestamp != nil }
        guard timedLines.count >= 2,
              let first = timedLines.first?.timestamp,
              let last = timedLines.last?.timestamp
        else { return false }

        // A word-synced file should start near the top of the song and cover
        // most of it. This rejects partial files and wildly offset timestamps.
        let introTolerance = max(12, duration * 0.35)
        guard first >= -1,
              first <= introTolerance,
              last >= duration * 0.35,
              last <= duration + 2
        else { return false }

        var previousStart = -Double.infinity
        for line in timedLines {
            guard let start = line.timestamp,
                  start >= -1,
                  start >= previousStart - 0.05
            else { return false }

            if let end = line.end,
               end < start - 0.05 || end > duration + 2 {
                return false
            }

            var previousWordStart = -Double.infinity
            for word in line.words {
                guard word.start >= -0.5,
                      word.start <= duration + 2,
                      word.start >= start - 1.5,
                      word.start >= previousWordStart - 0.05
                else { return false }

                if let end = word.end,
                   end < word.start - 0.05 || end > duration + 3 {
                    return false
                }
                previousWordStart = word.start
            }

            previousStart = start
        }

        return true
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

        switch record.syncLevel {
        case .wordSynced:
            score += 400
        case .lineSynced:
            score += 80
        case .plain, .none:
            break
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
        if let lyricsfile = record.lyricsfile,
           let document = LyricsFileParser.parse(lyricsfile) {
            return document
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
