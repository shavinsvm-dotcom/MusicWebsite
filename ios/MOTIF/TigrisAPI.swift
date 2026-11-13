import Foundation

enum TigrisAPI {
    static let baseURL = URL(string: "https://site-6ac7ea8ef8c0420ba8de8cc93361c186.freebuff.page")!

    struct RemoteTrack: Decodable {
        let id: String
        let title: String?
        let artist: String?
        let album: String?
        let duration: Double?
        let url: String?
        let year: Int?
    }

    enum APIError: LocalizedError {
        case invalidResponse
        case server(Int)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Tigris returned an unreadable response."
            case .server(let status):
                return "Tigris is unavailable right now (HTTP \(status))."
            }
        }
    }

    static func library() async throws -> [RemoteTrack] {
        try await get("/api/tigris/library")
    }

    static func covers() async throws -> [String: String] {
        try await get("/api/tigris/covers")
    }

    static func resolve(_ value: String) -> URL? {
        let secure = value.hasPrefix("http://")
            ? "https://" + value.dropFirst("http://".count)
            : value

        if let url = URL(string: secure), url.scheme != nil {
            return url
        }
        return URL(string: secure, relativeTo: baseURL)?.absoluteURL
    }

    private static func get<T: Decodable>(_ path: String) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw APIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.server(http.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
