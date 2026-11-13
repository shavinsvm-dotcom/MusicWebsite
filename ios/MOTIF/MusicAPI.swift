import Foundation

enum MusicAPI {
    struct SearchResponse: Decodable {
        let results: [Song]
    }

    struct Song: Decodable {
        let trackId: Int?
        let trackName: String?
        let artistName: String?
        let collectionName: String?
        let artworkUrl100: String?
        let previewUrl: String?
        let trackTimeMillis: Int?
    }

    enum APIError: LocalizedError {
        case invalidResponse
        case server(Int)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "The music catalog returned an unreadable response."
            case .server(let status):
                return "The music catalog is unavailable right now (HTTP \(status))."
            }
        }
    }

    static func search(_ term: String) async throws -> [Track] {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "30")
        ]

        guard let url = components?.url else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.server(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        var seen = Set<String>()
        var tracks: [Track] = []

        for song in decoded.results {
            guard
                let trackID = song.trackId,
                let title = song.trackName,
                let preview = song.previewUrl,
                let mediaURL = URL(string: preview),
                mediaURL.scheme?.lowercased() == "https"
            else { continue }

            let remoteID = String(trackID)
            guard !seen.contains(remoteID) else { continue }
            seen.insert(remoteID)

            let artwork: URL?
            if let rawArtwork = song.artworkUrl100 {
                let artworkString = rawArtwork.replacingOccurrences(
                    of: "100x100bb",
                    with: "600x600bb"
                )
                artwork = URL(string: artworkString)
            } else {
                artwork = nil
            }

            tracks.append(Track(
                title: title,
                artist: song.artistName ?? "Unknown artist",
                album: song.collectionName ?? "",
                artworkURL: artwork,
                mediaURL: mediaURL,
                duration: Double(song.trackTimeMillis ?? 0) / 1000,
                source: .preview,
                remoteID: remoteID
            ))
        }

        return tracks
    }
}
