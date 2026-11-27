import AVFoundation
import Foundation
import SwiftUI
import UIKit

// MARK: - Errors

enum MotionArtworkError: Error {
    case badResponse
    case unauthorized
    case rateLimited
    case status(Int)
}

// MARK: - Resolver

/// Finds the official Apple Music motion artwork for an album and returns its
/// HLS URL. The catalog *search* endpoint is currently the only place Apple
/// exposes `editorialVideo`; the album detail endpoint leaves it out.
actor MotionArtworkResolver {
    private static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    private let session: URLSession
    private var bearerToken: String?
    private var bearerFetchedAt: Date?
    private var backoffUntil: Date?
    private var lastSearchAt: Date?

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.httpAdditionalHeaders = ["Accept-Language": "en-US,en;q=0.9"]
        session = URLSession(configuration: configuration)
    }

    func resolve(track: Track) async throws -> URL? {
        if let backoffUntil, backoffUntil > Date() {
            throw MotionArtworkError.rateLimited
        }

        let storefront = Self.storefront
        let album = track.album.trimmingCharacters(in: .whitespacesAndNewlines)
        let searchAlbum = album.isEmpty ? track.title : album
        let term = [track.artist, searchAlbum]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " ")
        guard !term.isEmpty else { return nil }
        guard let token = try await token(storefront: storefront) else { return nil }

        do {
            let data = try await search(term: term, storefront: storefront, token: token)
            return Self.motionURL(in: data, track: track)
        } catch MotionArtworkError.unauthorized {
            // Web player tokens rotate; drop the cached one and retry once.
            bearerToken = nil
            bearerFetchedAt = nil
            guard let refreshed = try await token(storefront: storefront) else { return nil }
            let data = try await search(term: term, storefront: storefront, token: refreshed)
            return Self.motionURL(in: data, track: track)
        }
    }

    // MARK: Token

    private func token(storefront: String) async throws -> String? {
        if let bearerToken, let bearerFetchedAt,
           Date().timeIntervalSince(bearerFetchedAt) < 45 * 60 {
            return bearerToken
        }

        guard let pageURL = URL(string: "https://music.apple.com/\(storefront)/browse") else {
            return nil
        }
        var pageRequest = URLRequest(url: pageURL)
        pageRequest.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        pageRequest.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        let (pageData, pageResponse) = try await session.data(for: pageRequest)
        guard let pageHTTP = pageResponse as? HTTPURLResponse,
              pageHTTP.statusCode == 200,
              let html = String(data: pageData, encoding: .utf8) else {
            throw MotionArtworkError.badResponse
        }

        let assets = Self.matches(#"/assets/[^"']+\.js"#, in: html)
        for asset in assets.prefix(6) {
            guard let url = URL(string: "https://music.apple.com\(asset)") else { continue }
            let (jsData, _) = try await session.data(from: url)
            guard let js = String(data: jsData, encoding: .utf8) else { continue }
            if let found = Self.matches(
                #"["'](eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)["']"#,
                in: js
            ).first {
                bearerToken = found
                bearerFetchedAt = Date()
                return found
            }
        }
        return nil
    }

    // MARK: Search

    private func search(term: String, storefront: String, token: String) async throws -> Data {
        await throttle()

        var components = URLComponents(string: "https://amp-api.music.apple.com/v1/catalog/\(storefront)/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "types", value: "albums"),
            URLQueryItem(name: "limit", value: "10"),
            URLQueryItem(name: "extend", value: "editorialVideo"),
            URLQueryItem(name: "platform", value: "web")
        ]
        guard let url = components?.url else { throw MotionArtworkError.badResponse }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("https://music.apple.com", forHTTPHeaderField: "Origin")
        request.setValue("https://music.apple.com/", forHTTPHeaderField: "Referer")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MotionArtworkError.badResponse
        }
        switch http.statusCode {
        case 200..<300:
            return data
        case 401:
            throw MotionArtworkError.unauthorized
        case 403, 429:
            backoffUntil = Date().addingTimeInterval(90)
            throw MotionArtworkError.rateLimited
        default:
            throw MotionArtworkError.status(http.statusCode)
        }
    }

    private func throttle() async {
        if let lastSearchAt {
            let delay = 1.0 - Date().timeIntervalSince(lastSearchAt)
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        lastSearchAt = Date()
    }

    // MARK: Parsing

    private static func motionURL(in data: Data, track: Track) -> URL? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any],
              let results = root["results"] as? [String: Any],
              let albums = results["albums"] as? [String: Any],
              let items = albums["data"] as? [[String: Any]] else {
            return nil
        }

        let wantedArtist = normalized(track.artist)
        let wantedAlbum = normalized(track.album)
        let wantedBase = baseAlbum(wantedAlbum)
        var best: (score: Int, url: URL)?

        for item in items {
            guard let attributes = item["attributes"] as? [String: Any],
                  let name = attributes["name"] as? String,
                  let artist = attributes["artistName"] as? String,
                  let editorial = attributes["editorialVideo"] as? [String: Any],
                  let square = editorial["motionDetailSquare"] as? [String: Any],
                  let video = square["video"] as? String,
                  let url = URL(string: video) else { continue }

            let foundArtist = normalized(artist)
            let foundAlbum = normalized(name)
            let foundBase = baseAlbum(foundAlbum)

            var score = 0
            if foundArtist == wantedArtist {
                score += 4
            } else if !wantedArtist.isEmpty,
                      foundArtist.contains(wantedArtist) || wantedArtist.contains(foundArtist) {
                score += 2
            }
            if foundAlbum == wantedAlbum {
                score += 4
            } else if !wantedBase.isEmpty,
                      foundBase == wantedBase || foundAlbum.hasPrefix(wantedBase) {
                score += 2
            }

            // An artist-only match is too loose; require the album to line up.
            guard score >= 4 else { continue }
            if score > (best?.score ?? -1) {
                best = (score, url)
            }
        }

        return best?.url
    }

    private static func baseAlbum(_ value: String) -> String {
        value
            .replacingOccurrences(
                of: #"\b(deluxe|expanded|remaster(ed)?|anniversary|edition|version|bonus|special|explicit|clean)\b.*$"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespaces)
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(
                options: [.diacriticInsensitive, .caseInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            let matchRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
            return Range(matchRange, in: text).map { String(text[$0]) }
        }
    }

    private static var storefront: String {
        let code = Locale.current.region?.identifier.lowercased() ?? "us"
        return code.count == 2 ? code : "us"
    }
}

// MARK: - Store

struct MotionArtworkLink: Codable {
    var streamURL: URL
    var resolvedAt: Date
}

/// Keeps only the HLS URL, never the video. Resolving is on demand; the scan
/// only fills the same small index so the next play is instant.
@MainActor
final class MotionArtworkStore: ObservableObject {
    @MainActor static let shared = MotionArtworkStore()

    @Published private(set) var links: [String: MotionArtworkLink] = [:]
    @Published private(set) var isScanning = false
    @Published private(set) var scanDone = 0
    @Published private(set) var scanTotal = 0
    @Published private(set) var lastScanFound: Int?

    private var missing: [String: Date] = [:]
    private var inFlight: Set<String> = []
    private let resolver = MotionArtworkResolver()
    private let stateURL: URL
    private let missingLifetime: TimeInterval = 30 * 24 * 60 * 60

    private struct DiskState: Codable {
        var links: [String: MotionArtworkLink] = [:]
        var missing: [String: Date] = [:]
    }

    private init() {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let directory = support.appendingPathComponent("MotionArtwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        stateURL = directory.appendingPathComponent("index.json")
        load()
    }

    static func albumKey(for track: Track) -> String {
        let artist = normalized(track.artist)
        let album = normalized(track.album)
        if album.isEmpty {
            return "\(artist)|\(normalized(track.title))"
        }
        return "\(artist)|\(album)"
    }

    func streamURL(for track: Track) -> URL? {
        links[Self.albumKey(for: track)]?.streamURL
    }

    func hasStream(for track: Track) -> Bool {
        streamURL(for: track) != nil
    }

    /// Called when the player opens. A miss is cached for 30 days; a network
    /// failure is not, so a later play tries again.
    func prepareForPlayback(_ track: Track) async {
        let key = Self.albumKey(for: track)
        if links[key] != nil { return }
        if let missingAt = missing[key],
           Date().timeIntervalSince(missingAt) < missingLifetime { return }
        if inFlight.contains(key) { return }

        inFlight.insert(key)
        defer { inFlight.remove(key) }

        do {
            if let url = try await resolver.resolve(track: track) {
                links[key] = MotionArtworkLink(streamURL: url, resolvedAt: Date())
                missing[key] = nil
                save()
            } else {
                missing[key] = Date()
                save()
            }
        } catch {
            // Leave unresolved; playback keeps the static cover.
        }
    }

    @discardableResult
    func scan(tracks: [Track]) async -> Int {
        guard !isScanning else { return lastScanFound ?? 0 }

        var seen = Set<String>()
        var unique: [Track] = []
        for track in tracks {
            let key = Self.albumKey(for: track)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            unique.append(track)
        }
        guard !unique.isEmpty else {
            lastScanFound = 0
            return 0
        }

        isScanning = true
        scanDone = 0
        scanTotal = unique.count
        lastScanFound = nil
        var found = 0

        for track in unique {
            if Task.isCancelled { break }
            let key = Self.albumKey(for: track)

            if links[key] != nil {
                found += 1
                scanDone += 1
                continue
            }
            if let missingAt = missing[key],
               Date().timeIntervalSince(missingAt) < missingLifetime {
                scanDone += 1
                continue
            }
            if inFlight.contains(key) {
                scanDone += 1
                continue
            }

            inFlight.insert(key)
            var resolved: URL?
            var definitiveMiss = false
            do {
                resolved = try await resolver.resolve(track: track)
                definitiveMiss = resolved == nil
            } catch MotionArtworkError.rateLimited {
                inFlight.remove(key)
                break
            } catch {
                // Network failure: leave the album for a later scan.
            }
            inFlight.remove(key)

            if let resolved {
                links[key] = MotionArtworkLink(streamURL: resolved, resolvedAt: Date())
                found += 1
            } else if definitiveMiss {
                missing[key] = Date()
            }
            scanDone += 1
            save()
        }

        lastScanFound = found
        isScanning = false
        return found
    }

    private func load() {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(DiskState.self, from: data) else {
            return
        }
        links = state.links
        missing = state.missing
    }

    private func save() {
        let state = DiskState(links: links, missing: missing)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(
                options: [.diacriticInsensitive, .caseInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Streaming view

struct MotionArtworkView: View {
    let url: URL
    let isActive: Bool

    @State private var ready = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        LoopingVideo(
            url: url,
            isActive: isActive && !reduceMotion && scenePhase == .active,
            onReady: { ready = true }
        )
        .opacity(ready ? 1 : 0)
        .animation(.easeOut(duration: 0.55), value: ready)
        .allowsHitTesting(false)
        .background(Color.clear)
        .onChange(of: url) { _ in ready = false }
        .onDisappear { ready = false }
    }
}

private struct LoopingVideo: UIViewRepresentable {
    let url: URL
    let isActive: Bool
    let onReady: () -> Void

    func makeUIView(context: Context) -> LoopingVideoUIView {
        let view = LoopingVideoUIView()
        view.onReady = onReady
        view.load(url)
        return view
    }

    func updateUIView(_ view: LoopingVideoUIView, context: Context) {
        if view.loadedURL != url {
            view.load(url)
        }
        view.setActive(isActive)
    }
}

private final class LoopingVideoUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    private var player: AVPlayer?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var isReady = false
    private var notifiedReady = false
    private var active = false

    var onReady: (() -> Void)?
    private(set) var loadedURL: URL?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.backgroundColor = UIColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func load(_ url: URL) {
        teardown()
        loadedURL = url
        isReady = false
        notifiedReady = false

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.actionAtItemEnd = .none
        player.automaticallyWaitsToMinimizeStalling = true
        self.player = player
        playerLayer.player = player

        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .readyToPlay else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isReady = true
                if self.active { self.player?.play() }
                if !self.notifiedReady {
                    self.notifiedReady = true
                    self.onReady?()
                }
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self, let player = self.player else { return }
            player.seek(to: .zero)
            if self.active { player.play() }
        }

        if active { player.play() }
    }

    func setActive(_ active: Bool) {
        guard self.active != active else { return }
        self.active = active
        if active {
            player?.play()
        } else {
            player?.pause()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }

    private func teardown() {
        statusObservation?.invalidate()
        statusObservation = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        player?.pause()
        playerLayer.player = nil
        player = nil
    }

    deinit {
        teardown()
    }
}
