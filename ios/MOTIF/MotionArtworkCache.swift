import CryptoKit
import Foundation

enum MotionArtworkCacheError: Error {
    case badResponse
    case invalidPlaylist
    case unsupported
}

/// Downloads the short fMP4 behind Apple's motion-artwork HLS playlist.
/// Everything stays inside the app sandbox; the file is never listed in the UI.
actor MotionArtworkCache {
    private static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 180
        configuration.httpAdditionalHeaders = ["Accept-Language": "en-US,en;q=0.9"]
        session = URLSession(configuration: configuration)
    }

    static func fileName(for albumKey: String) -> String {
        let digest = SHA256.hash(data: Data(albumKey.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".mp4"
    }

    func download(streamURL: URL, to destination: URL) async throws -> Int64 {
        let master = try await text(from: streamURL)
        let variants = Self.variants(in: master, relativeTo: streamURL)
        guard let variant = Self.bestVariant(in: variants) else {
            throw MotionArtworkCacheError.invalidPlaylist
        }

        let mediaPlaylist = try await text(from: variant.url)
        let mediaURL = try Self.mediaFileURL(in: mediaPlaylist, relativeTo: variant.url)

        let temporary = try await file(from: mediaURL)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Self.validateMP4(at: temporary)

        let folder = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporary, to: destination)

        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: destination.path
        )

        let values = try destination.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }

    // MARK: - Requests

    private func text(from url: URL) async throws -> String {
        let urlRequest = makeRequest(for: url, accept: "application/vnd.apple.mpegurl, application/x-mpegURL, */*")
        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let text = String(data: data, encoding: .utf8) else {
            throw MotionArtworkCacheError.badResponse
        }
        return text
    }

    private func file(from url: URL) async throws -> URL {
        let urlRequest = makeRequest(for: url, accept: "*/*")
        let (temporary, response) = try await session.download(for: urlRequest)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw MotionArtworkCacheError.badResponse
        }
        return temporary
    }

    private func makeRequest(for url: URL, accept: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://music.apple.com", forHTTPHeaderField: "Origin")
        request.setValue("https://music.apple.com/", forHTTPHeaderField: "Referer")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        return request
    }

    // MARK: - Playlists

    private struct Variant {
        var width: Int
        var bandwidth: Int
        var codec: String
        var url: URL
    }

    private static func variants(in playlist: String, relativeTo base: URL) -> [Variant] {
        var result: [Variant] = []
        var pending: [String: String]?

        for rawLine in playlist.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#EXT-X-STREAM-INF:") {
                pending = attributes(String(line.dropFirst("#EXT-X-STREAM-INF:".count)))
            } else if !line.isEmpty, !line.hasPrefix("#"), let values = pending {
                if let url = URL(string: line, relativeTo: base)?.absoluteURL {
                    let resolution = values["RESOLUTION"] ?? ""
                    let width = Int(resolution.split(separator: "x").first ?? "") ?? 0
                    let bandwidth = Int(values["BANDWIDTH"] ?? "") ?? 0
                    result.append(Variant(
                        width: width,
                        bandwidth: bandwidth,
                        codec: values["CODECS"] ?? "",
                        url: url
                    ))
                }
                pending = nil
            }
        }
        return result
    }

    private static func bestVariant(in variants: [Variant]) -> Variant? {
        guard !variants.isEmpty else { return nil }

        let h264 = variants.filter { $0.codec.lowercased().contains("avc1") }
        let pool = h264.isEmpty ? variants : h264
        let capped = pool.filter { $0.width > 0 && $0.width <= 1080 }

        if let width = capped.map(\.width).max() {
            return capped
                .filter { $0.width == width }
                .min { $0.bandwidth < $1.bandwidth }
        }

        let sized = pool.filter { $0.width > 0 }
        if let width = sized.map(\.width).min() {
            return sized
                .filter { $0.width == width }
                .min { $0.bandwidth < $1.bandwidth }
        }

        return pool.min { $0.bandwidth < $1.bandwidth }
    }

    /// Apple packages each motion cover as one fMP4 addressed with byte ranges.
    /// If that changes, streaming keeps working and only the offline copy is skipped.
    private static func mediaFileURL(in playlist: String, relativeTo base: URL) throws -> URL {
        var mapURI: String?
        var segmentURIs = Set<String>()

        for rawLine in playlist.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#EXT-X-KEY:") {
                let values = attributes(String(line.dropFirst("#EXT-X-KEY:".count)))
                if let method = values["METHOD"], method != "NONE" {
                    throw MotionArtworkCacheError.unsupported
                }
            } else if line.hasPrefix("#EXT-X-MAP:") {
                let values = attributes(String(line.dropFirst("#EXT-X-MAP:".count)))
                mapURI = values["URI"]
            } else if !line.isEmpty, !line.hasPrefix("#") {
                segmentURIs.insert(line)
            }
        }

        guard segmentURIs.count == 1, let onlySegment = segmentURIs.first else {
            throw MotionArtworkCacheError.unsupported
        }
        if let mapURI, mapURI != onlySegment {
            throw MotionArtworkCacheError.unsupported
        }
        guard let url = URL(string: mapURI ?? onlySegment, relativeTo: base)?.absoluteURL else {
            throw MotionArtworkCacheError.invalidPlaylist
        }
        return url
    }

    private static func attributes(_ text: String) -> [String: String] {
        guard let regex = try? NSRegularExpression(pattern: #"([A-Z0-9-]+)=("[^"]*"|[^,]*)"#) else {
            return [:]
        }
        let range = NSRange(text.startIndex..., in: text)
        var result: [String: String] = [:]
        for match in regex.matches(in: text, range: range) {
            guard let keyRange = Range(match.range(at: 1), in: text),
                  let valueRange = Range(match.range(at: 2), in: text) else { continue }
            var value = String(text[valueRange])
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value.removeFirst()
                value.removeLast()
            }
            result[String(text[keyRange])] = value
        }
        return result
    }

    // MARK: - Validation

    private static func validateMP4(at url: URL) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0 else { throw MotionArtworkCacheError.invalidPlaylist }

        var offset: Int64 = 0
        var boxes = 0
        var hasFileType = false
        var hasMovieHeader = false

        while offset + 8 <= size, boxes < 64 {
            try handle.seek(toOffset: UInt64(offset))
            guard let header = try handle.read(upToCount: 16), header.count >= 8 else { break }

            let shortSize = bigEndian32(header.prefix(4))
            var boxSize = Int64(shortSize)
            let type = String(data: header[4..<8], encoding: .ascii) ?? ""

            if shortSize == 1 {
                guard header.count >= 16 else { break }
                boxSize = Int64(bitPattern: bigEndian64(header[8..<16]))
            } else if shortSize == 0 {
                boxSize = size - offset
            }

            if type == "ftyp" { hasFileType = true }
            if type == "moov" { hasMovieHeader = true }
            guard boxSize >= 8 else { break }

            offset += boxSize
            boxes += 1
        }

        guard hasFileType, hasMovieHeader else {
            throw MotionArtworkCacheError.invalidPlaylist
        }
    }

    private static func bigEndian32<S: Sequence>(_ bytes: S) -> UInt32 where S.Element == UInt8 {
        bytes.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private static func bigEndian64<S: Sequence>(_ bytes: S) -> UInt64 where S.Element == UInt8 {
        bytes.reduce(0) { ($0 << 8) | UInt64($1) }
    }
}
