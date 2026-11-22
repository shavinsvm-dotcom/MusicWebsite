import Foundation

struct SmartPlaylistResult {
    let name: String
    let description: String
    let tracks: [Track]
    let model: String?
}

enum SmartPlaylistService {
    private struct RequestBody: Encodable {
        let prompt: String
        let tracks: [Candidate]
    }

    private struct Candidate: Encodable {
        let id: String
        let title: String
        let artist: String
        let album: String
        let year: Int?
        let duration: Int
        let plays: Int
        let favorite: Bool
        let recent: Int?
    }

    private struct ResponseBody: Decodable {
        let name: String
        let description: String?
        let trackIDs: [String]
        let model: String?
    }

    private struct ErrorBody: Decodable {
        let error: String?
    }

    enum ServiceError: LocalizedError {
        case invalidResponse
        case server(String)
        case emptySelection

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "The playlist service returned an unreadable response."
            case .server(let message):
                return message
            case .emptySelection:
                return "No matching songs were found. Try a different description."
            }
        }
    }

    static func generate(
        prompt: String,
        library: [Track],
        playCounts: [UUID: Int],
        favoriteIDs: Set<UUID>,
        recentIDs: [UUID]
    ) async throws -> SmartPlaylistResult {
        guard !library.isEmpty else {
            throw ServiceError.server("Add some songs to your library first.")
        }
        guard let url = URL(
            string: "/api/tigris/smart-playlist",
            relativeTo: TigrisAPI.baseURL
        )?.absoluteURL else {
            throw ServiceError.invalidResponse
        }

        var recentRanks: [UUID: Int] = [:]
        for (index, id) in recentIDs.prefix(20).enumerated() {
            recentRanks[id] = index
        }

        // Keep the request compact enough for a free model while still giving
        // it the whole library for normal-sized collections.
        let candidates = library.prefix(600).map { track in
            Candidate(
                id: track.id.uuidString,
                title: track.title,
                artist: track.artist,
                album: track.album,
                year: track.releaseYear,
                duration: track.duration.isFinite
                    ? max(0, Int(track.duration.rounded()))
                    : 0,
                plays: playCounts[track.id] ?? 0,
                favorite: favoriteIDs.contains(track.id),
                recent: recentRanks[track.id]
            )
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 70
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(
            RequestBody(prompt: prompt, tracks: Array(candidates))
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error
            if http.statusCode == 429 {
                throw ServiceError.server(
                    message ?? "The free model is busy right now. Try again in a minute."
                )
            }
            throw ServiceError.server(
                message ?? "The playlist service is unavailable right now."
            )
        }

        let decoded: ResponseBody
        do {
            decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        } catch {
            throw ServiceError.invalidResponse
        }

        let byID: [String: Track] = Dictionary(
            uniqueKeysWithValues: library.map { ($0.id.uuidString, $0) }
        )
        var seen = Set<String>()
        let selected = decoded.trackIDs.compactMap { raw -> Track? in
            guard let track = byID[raw], seen.insert(raw).inserted else {
                return nil
            }
            return track
        }
        guard !selected.isEmpty else { throw ServiceError.emptySelection }

        let rawName = decoded.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = String((rawName.isEmpty ? "Smart Playlist" : rawName).prefix(60))
        let description = (decoded.description ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return SmartPlaylistResult(
            name: name,
            description: String(description.prefix(180)),
            tracks: selected,
            model: decoded.model
        )
    }
}
