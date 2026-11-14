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

    static func uploadAudio(fileURL: URL, key: String, contentType: String) async throws -> URL {
        guard let url = audioURL(key: key) else { throw APIError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.timeoutInterval = 300
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")

        let (_, response) = try await URLSession.shared.upload(for: request, fromFile: fileURL)
        try validate(response)
        return url
    }

    static func uploadObject(data: Data, key: String, contentType: String) async throws -> URL {
        guard let url = objectURL(key: key) else { throw APIError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.timeoutInterval = 120
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")

        let (_, response) = try await URLSession.shared.upload(for: request, from: data)
        try validate(response)
        return url
    }

    /// Adds one track to the shared library manifest without rebuilding the
    /// documents, so metadata written by other clients survives the upload.
    static func addLibraryDocument(_ document: [String: Any]) async throws {
        guard let id = document["id"] as? String else { throw APIError.invalidResponse }

        var documents = try await libraryDocuments()
        documents.removeAll { ($0["id"] as? String) == id }
        documents.insert(document, at: 0)

        let data = try JSONSerialization.data(withJSONObject: documents)
        try await put("/api/tigris/library", data: data, contentType: "application/json")
    }

    static func setCover(trackID: String, url: URL) async throws {
        var map = try await covers()
        map[trackID] = url.absoluteString
        let data = try JSONSerialization.data(withJSONObject: map)
        try await put("/api/tigris/covers", data: data, contentType: "application/json")
    }

    static func audioURL(key: String) -> URL? {
        objectURL(path: "/api/tigris/audio", key: key)
    }

    static func objectURL(key: String) -> URL? {
        objectURL(path: "/api/tigris/object", key: key)
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

    private static func libraryDocuments() async throws -> [[String: Any]] {
        let data = try await getData("/api/tigris/library")
        guard let raw = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }
        return raw as? [[String: Any]] ?? []
    }

    private static func objectURL(path: String, key: String) -> URL? {
        guard var components = URLComponents(
            string: baseURL.absoluteString + path
        ) else { return nil }
        components.queryItems = [URLQueryItem(name: "key", value: key)]
        return components.url
    }

    private static func get<T: Decodable>(_ path: String) async throws -> T {
        let data = try await getData(path)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func getData(_ path: String) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw APIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        return data
    }

    private static func put(_ path: String, data: Data, contentType: String) async throws {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw APIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.timeoutInterval = 120
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")

        let (_, response) = try await URLSession.shared.upload(for: request, from: data)
        try validate(response)
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.server(http.statusCode)
        }
    }
}
