import AudioToolbox
import AVFoundation
import CoreMedia
import Foundation
import UIKit

/// Finds an official cover for a track using the same artist/title gates as the
/// web app. The catalogue is the free iTunes Search API, so no key is needed.
enum ArtworkFinder {
    struct Match {
        let artworkURL: URL
        let trackName: String
        let artistName: String
        let albumName: String
    }

    private struct SearchResponse: Decodable {
        let results: [Item]
    }

    private struct Item: Decodable {
        let trackName: String?
        let artistName: String?
        let collectionName: String?
        let collectionArtistName: String?
        let artworkUrl100: String?
    }

    private static let minimumScore = 5
    private static let lookupUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    static func find(title: String, artist: String, album: String) async -> Match? {
        let cleanedTitle = cleanTitle(title)
        guard !cleanedTitle.isEmpty else { return nil }

        let rawArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let artistCore = primaryArtist(rawArtist)
        let cleanAlbum = album.trimmingCharacters(in: .whitespacesAndNewlines)
        let albumIsCompilation = isCompilation(cleanAlbum)

        var terms: [String] = []
        var base = cleanedTitle
        if !artistCore.isEmpty { base += " \(artistCore)" }

        if !cleanAlbum.isEmpty && !albumIsCompilation {
            terms.append("\(base) \(cleanAlbum)")
        }
        terms.append(base)
        if !artistCore.isEmpty {
            terms.append("\(artistCore) \(cleanedTitle)")
        }

        var seen = Set<String>()
        for term in terms {
            let key = norm(term)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            let items = await search(term: term)
            if let match = choose(items, title: cleanedTitle, artist: rawArtist, album: cleanAlbum) {
                return match
            }
        }
        return nil
    }

    static func imageData(from url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(lookupUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("image/*", forHTTPHeaderField: "Accept")

        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            let http = response as? HTTPURLResponse,
            (200..<300).contains(http.statusCode),
            !data.isEmpty,
            UIImage(data: data) != nil
        else { return nil }
        return data
    }

    private static func search(term: String) async -> [Item] {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "25")
        ]
        guard let url = components?.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Apple answers mobile User-Agents with a musics:// redirect. A desktop
        // User-Agent keeps the response as JSON.
        request.setValue(lookupUserAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard
                let http = response as? HTTPURLResponse,
                (200..<300).contains(http.statusCode)
            else { return [] }
            return try JSONDecoder().decode(SearchResponse.self, from: data).results
        } catch {
            return []
        }
    }

    private static func choose(
        _ items: [Item],
        title: String,
        artist: String,
        album: String
    ) -> Match? {
        var best: Item?
        var bestScore = Int.min

        for item in items {
            guard item.artworkUrl100 != nil else { continue }
            let score = artworkScore(item, title: title, artist: artist, album: album)
            if score > bestScore {
                bestScore = score
                best = item
            }
        }

        guard
            bestScore >= minimumScore,
            let best,
            let rawArtwork = best.artworkUrl100,
            let artworkURL = highResolutionArtworkURL(rawArtwork)
        else { return nil }

        return Match(
            artworkURL: artworkURL,
            trackName: best.trackName ?? title,
            artistName: best.artistName ?? artist,
            albumName: best.collectionName ?? album
        )
    }

    private static func artworkScore(
        _ item: Item,
        title: String,
        artist: String,
        album: String
    ) -> Int {
        let nTitle = norm(title)
        let artistCore = primaryArtist(artist)
        let nArtist = (isJunkArtist(artist) || artistCore.isEmpty) ? "" : norm(artistCore)
        let nAlbum = norm(album)

        let candidateTitle = norm(cleanTitle(item.trackName ?? ""))
        let candidateArtistRaw = item.artistName ?? ""
        let candidateArtist = norm(candidateArtistRaw)
        let candidateAlbum = norm(item.collectionName ?? "")

        let titleSimilarity = (nTitle.isEmpty || candidateTitle.isEmpty)
            ? 0
            : tokenOverlap(nameTokens(candidateTitle), nameTokens(title))
        let titleExact = !nTitle.isEmpty && candidateTitle == nTitle
        let albumExact = !nAlbum.isEmpty && candidateAlbum == nAlbum
        let albumSimilarity = (nAlbum.isEmpty || candidateAlbum.isEmpty)
            ? 0
            : tokenOverlap(nameTokens(candidateAlbum), nameTokens(album))

        let compilation = isCompilation(album)
        let candidateCredit = item.collectionArtistName ?? ""
        let candidateVA = compilationArtists.contains(norm(candidateCredit))
        let candidateArtistName = item.artistName ?? ""
        let candidateAlbumName = item.collectionName ?? ""

        if isBroadcastCredit(candidateArtistName)
            || isBroadcastCredit(candidateAlbumName)
            || isBroadcastCredit(candidateCredit)
            || isNonOfficialCredit(candidateArtistName)
            || isNonOfficialCredit(candidateAlbumName) {
            return -1_000_000_000
        }

        let sameCompilation = compilation && !nAlbum.isEmpty && candidateAlbum == nAlbum
        let artistOk = !nArtist.isEmpty
            && (candidateArtist == nArtist
                || norm(primaryArtist(candidateArtistRaw)) == norm(primaryArtist(artist)))

        var score = 0
        var pass = true

        if titleExact {
            score += 6
        } else if titleSimilarity >= 0.8 {
            score += 3
        } else if titleSimilarity >= 0.5 {
            score += 1
        }

        if !nArtist.isEmpty {
            if artistOk {
                score += 6
            } else {
                pass = false
            }
        } else {
            // Without a reliable artist tag, a title alone is not identity.
            if !titleExact || !albumExact { pass = false }
            if candidateVA || isJunkArtist(candidateArtistName) || isCompilation(candidateAlbumName) {
                pass = false
            }
        }

        if !(titleExact || titleSimilarity >= 0.5) && !(albumExact && artistOk) {
            pass = false
        }

        if !compilation || !sameCompilation {
            if albumExact {
                score += 3
            } else if albumSimilarity >= 0.7 {
                score += 2
            }
        }

        if compilation {
            if sameCompilation { score -= 6 }
            if candidateVA { score -= 3 }
        }

        return pass ? score : -1_000_000_000
    }

    private static func highResolutionArtworkURL(_ raw: String) -> URL? {
        let upgraded = raw
            .replacingOccurrences(of: "100x100bb", with: "600x600bb")
            .replacingOccurrences(of: "60x60bb", with: "600x600bb")
        return URL(string: upgraded)
    }

    private static func cleanTitle(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        result = replacing(result, pattern: #"\s*\[[^\]]+\]\s*$"#)
        result = replacing(
            result,
            pattern: #"\s*\([^)]*(?:official|lyrics|audio|video|mv|hd|4k)[^)]*\)\s*$"#
        )
        result = replacing(
            result,
            pattern: #"\s*[\(\[](?:[^\)\]]*(?:\b(?:remaster|remastered|re-?recorded|version|edit|mix|remix|deluxe|reissue|mono|stereo|slowed|sped\s*up|explicit|clean|bonus|anniversary|live|acoustic|unplugged|demo|instrumental|karaoke|extended|radio|album|single|feat|ft|with)\b|\b(?:19|20)\d{2}\b)[^\)\]]*)[\)\]]\s*$"#
        )
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func primaryArtist(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let pieces = trimmed.components(separatedBy: CharacterSet(charactersIn: ";,/&"))
        for piece in pieces {
            let withoutFeatures = replacing(
                piece,
                pattern: #"\s+(?:feat\.?|ft\.?|featuring|with)\s+.*$"#
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            if !withoutFeatures.isEmpty && !isJunkArtist(withoutFeatures) {
                return withoutFeatures
            }
        }
        return pieces.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? trimmed
    }

    private static func isJunkArtist(_ value: String) -> Bool {
        let trimmed = value
            .replacingOccurrences(of: "\u{0}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        if trimmed.caseInsensitiveCompare("Unknown") == .orderedSame { return true }
        if trimmed.caseInsensitiveCompare("Unknown artist") == .orderedSame { return true }
        if matches(
            trimmed,
            pattern: #"^(?:various|various\s*artists|va|uncredited|unknown|track|artist|soundtrack|composer|none|null|\?|mixed\s*by|dj)$"#
        ) { return true }
        if matches(
            trimmed,
            pattern: #"^(?:https?:|www\.)|youtube|youtu\.be|@|(?:feat\.?|ft\.?)\s*$|^\s*[-–—~|]\s*$"#
        ) { return true }
        if trimmed == trimmed.lowercased(),
           trimmed.count <= 40,
           !trimmed.contains(where: { $0.isUppercase }),
           trimmed.contains(" "),
           trimmed.split(separator: " ").count > 4 {
            return true
        }
        return false
    }

    private static func isCompilation(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return matches(
            trimmed,
            pattern: #"\b(?:hits?|top\s*\d+|top\s*songs?|charts?|greatest|best\s*of|essential|anthology|compilation|playlist|mixtape|various|va)\b"#
        ) || matches(trimmed, pattern: #"\bnow\s*(?:that'?s|\d)"#)
            || matches(trimmed, pattern: #"\b\d{2,4}s\b"#)
    }

    private static func isBroadcastCredit(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return matches(
            trimmed,
            pattern: #"\b(?:radio\s*(?:\d|one|two|1|2|fm|station|disney|bbc|live|session|mix|broadcast)|(?:bbc|npr)\b|iheart(?:radio)?\b|siriusxm?\b|(?:capital|kiss|nova|energy)\s+(?:fm|radio)\b|podcast|broadcast|live\s*lounge)\b"#
        )
    }

    private static func isNonOfficialCredit(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return matches(
            trimmed,
            pattern: #"\b(?:tribute|karaoke|in\s+the\s+style\s+of|made\s+famous|originally\s+performed|cover\s+band|session\s+band|playback)\b"#
        )
    }

    private static func nameTokens(_ value: String) -> [String] {
        let normalized = norm(value)
        guard !normalized.isEmpty else { return [] }
        return normalized.split(separator: " ").map(String.init).filter {
            $0.count > 1 || Int($0) != nil
        }
    }

    private static func tokenOverlap(_ lhs: [String], _ rhs: [String]) -> Double {
        let a = Set(lhs)
        let b = Set(rhs)
        let union = a.union(b)
        guard !union.isEmpty else { return 0 }
        return Double(a.intersection(b).count) / Double(union.count)
    }

    private static func norm(_ value: String) -> String {
        let folded = value
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
        let cleaned = folded.map { character -> Character in
            character.isLetter || character.isNumber ? character : " "
        }
        return String(cleaned)
            .split(whereSeparator: { $0 == " " })
            .joined(separator: " ")
    }

    private static func matches(_ value: String, pattern: String) -> Bool {
        value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func replacing(_ value: String, pattern: String) -> String {
        value.replacingOccurrences(
            of: pattern,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let compilationArtists: Set<String> = [
        "various artists",
        "various",
        "va",
        "v a",
        "unknown",
        "unknown artist",
        "soundtrack",
        "original soundtrack",
        "ost"
    ]
}

/// Sends a short raw-PCM clip to the Worker, which holds the RapidAPI key and
/// forwards it to Shazam's detect endpoint.
enum MusicIdentifier {
    struct Match {
        let title: String
        let artist: String
        let album: String
        let coverURL: URL?
        let shazamURL: URL?
        let year: Int?
    }

    enum IdentificationError: LocalizedError {
        case unavailable
        case quota
        case badResponse

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "Music identification is not configured."
            case .quota:
                return "The recognition service has reached its quota."
            case .badResponse:
                return "The recognition service returned an unreadable response."
            }
        }
    }

    private struct StatusResponse: Decodable {
        let enabled: Bool?
    }

    private struct Response: Decodable {
        let match: Payload?
        let error: String?
    }

    private struct Payload: Decodable {
        let title: String?
        let artist: String?
        let album: String?
        let coverURL: String?
        let shazamURL: String?
        let year: Int?
    }

    private actor Availability {
        static let shared = Availability()
        private var cached: Bool?

        func isEnabled() async -> Bool {
            if let cached { return cached }

            var request = URLRequest(url: MusicIdentifier.endpoint)
            request.timeoutInterval = 10
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard
                    let http = response as? HTTPURLResponse,
                    (200..<300).contains(http.statusCode),
                    let status = try? JSONDecoder().decode(MusicIdentifier.StatusResponse.self, from: data)
                else {
                    cached = false
                    return false
                }
                let enabled = status.enabled ?? false
                cached = enabled
                return enabled
            } catch {
                cached = false
                return false
            }
        }

        func invalidate() {
            cached = nil
        }
    }

    static func isAvailable() async -> Bool {
        await Availability.shared.isEnabled()
    }

    static func identify(fileURL: URL) async throws -> Match? {
        guard await isAvailable() else { return nil }
        guard let clip = await PCMClip.make(from: fileURL) else { return nil }

        var request = URLRequest(url: MusicIdentifier.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.upload(for: request, from: clip)
        } catch {
            throw IdentificationError.badResponse
        }

        guard let http = response as? HTTPURLResponse else {
            throw IdentificationError.badResponse
        }
        if http.statusCode == 503 {
            await Availability.shared.invalidate()
            throw IdentificationError.unavailable
        }
        if http.statusCode == 429 {
            throw IdentificationError.quota
        }
        guard (200..<300).contains(http.statusCode) else {
            throw IdentificationError.badResponse
        }

        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw IdentificationError.badResponse
        }
        if decoded.error != nil { return nil }
        guard let payload = decoded.match else { return nil }

                let title = payload.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let artist = payload.artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty else { return nil }

        return Match(
            title: title,
            artist: artist,
            album: payload.album?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            coverURL: secureURL(payload.coverURL),
            shazamURL: secureURL(payload.shazamURL),
            year: payload.year
        )
    }

    private static var endpoint: URL {
        TigrisAPI.baseURL.appendingPathComponent("api/tigris/identify")
    }

    private static func secureURL(_ value: String?) -> URL? {
        guard let value, !value.isEmpty else { return nil }
        let secure = value.hasPrefix("http://")
            ? "https://" + value.dropFirst("http://".count)
            : value
        return URL(string: secure)
    }
}

/// Decodes the first few seconds of a local file into the exact uncompressed
/// format Shazam's detect endpoint expects: 44.1 kHz, mono, signed 16-bit LE.
private enum PCMClip {
    private static let sampleRate = 44_100
    private static let maxBytes = 352_800

    static func make(from url: URL) async -> Data? {
        let asset = AVURLAsset(url: url)
        guard
            let duration = try? await asset.load(.duration),
            CMTimeGetSeconds(duration).isFinite,
            CMTimeGetSeconds(duration) > 1
        else { return nil }
        let tracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        guard let track = tracks.first else { return nil }

        let durationSeconds = CMTimeGetSeconds(duration)
        let start = min(max(durationSeconds * 0.2, 0), max(0, durationSeconds - 4))
        let length = min(4, max(1, durationSeconds - start))

        guard let reader = try? AVAssetReader(asset: asset) else { return nil }
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: Double(sampleRate),
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: length, preferredTimescale: 600)
        )
        guard reader.startReading() else { return nil }

        var pcm = Data()
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let byteCount = CMBlockBufferGetDataLength(block)
            guard byteCount > 0 else { continue }

            var chunk = Data(count: byteCount)
            chunk.withUnsafeMutableBytes { raw in
                guard let destination = raw.baseAddress else { return }
                _ = CMBlockBufferCopyDataBytes(
                    block,
                    atOffset: 0,
                    dataLength: byteCount,
                    destination: destination
                )
            }
            pcm.append(chunk)
            if pcm.count >= maxBytes { break }
        }
        reader.cancelReading()

        guard !pcm.isEmpty else { return nil }
        return Data(pcm.prefix(maxBytes))
    }
}
