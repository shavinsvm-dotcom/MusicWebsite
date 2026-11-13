import AVFoundation
import Combine
import Foundation

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var tracks: [Track] = []
    @Published private(set) var favoriteIDs: Set<UUID> = []
    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var isRefreshingCloud = false
    @Published private(set) var downloadingIDs: Set<UUID> = []
    @Published private(set) var cloudMessage: String?
    @Published var errorMessage: String?

    private let fileManager: FileManager
    private let documentsURL: URL
    private let importsURL: URL
    private let downloadsURL: URL
    private let libraryURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.importsURL = documentsURL.appendingPathComponent("Imported", isDirectory: true)
        self.downloadsURL = documentsURL.appendingPathComponent("Offline", isDirectory: true)
        self.libraryURL = documentsURL.appendingPathComponent("library.json")
        try? fileManager.createDirectory(at: importsURL, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: downloadsURL, withIntermediateDirectories: true)
        load()
    }

    var favorites: [Track] {
        tracks.filter { favoriteIDs.contains($0.id) }
    }

    var artists: [String] {
        Array(Set(tracks.map(\.artist).filter { !$0.isEmpty })).sorted()
    }

    func isFavorite(_ track: Track) -> Bool {
        if favoriteIDs.contains(track.id) { return true }
        guard let remoteID = track.remoteID,
              let existing = tracks.first(where: { $0.remoteID == remoteID }) else {
            return false
        }
        return favoriteIDs.contains(existing.id)
    }

    func contains(_ track: Track) -> Bool {
        canonicalTrack(for: track) != nil
    }

    func tracks(in playlist: Playlist) -> [Track] {
        playlist.trackIDs.compactMap { id in tracks.first(where: { $0.id == id }) }
    }

    func isDownloaded(_ track: Track) -> Bool {
        track.mediaURL.isFileURL && fileManager.fileExists(atPath: track.mediaURL.path)
    }

    func isDownloading(_ track: Track) -> Bool {
        guard let existing = canonicalTrack(for: track) else { return false }
        return downloadingIDs.contains(existing.id)
    }

    func refreshCloud() async {
        guard !isRefreshingCloud else { return }
        isRefreshingCloud = true
        cloudMessage = nil
        defer { isRefreshingCloud = false }

        do {
            let remoteTracks = try await TigrisAPI.library()
            let covers = (try? await TigrisAPI.covers()) ?? [:]

            let incoming = remoteTracks.compactMap { remote -> Track? in
                guard
                    let title = remote.title,
                    let mediaString = remote.url,
                    let mediaURL = TigrisAPI.resolve(mediaString)
                else { return nil }

                let artworkURL = covers[remote.id].flatMap(TigrisAPI.resolve)

                return Track(
                    title: title,
                    artist: remote.artist ?? "Unknown artist",
                    album: remote.album ?? "",
                    releaseYear: remote.year,
                    artworkURL: artworkURL,
                    mediaURL: mediaURL,
                    duration: remote.duration ?? 0,
                    source: .cloud,
                    remoteID: remote.id,
                    streamURL: mediaURL
                )
            }

            add(incoming)
            cloudMessage = remoteTracks.isEmpty
                ? "No tracks in the Tigris library yet."
                : "\(remoteTracks.count) tracks in the Tigris library"
        } catch {
            cloudMessage = "Couldn’t reach the Tigris library. Tap refresh to retry."
        }
    }

    func download(_ track: Track) async {
        guard
            let existing = canonicalTrack(for: track),
            !isDownloaded(existing),
            !downloadingIDs.contains(existing.id),
            let remoteURL = existing.streamURL ?? (existing.isCloud ? existing.mediaURL : nil)
        else { return }

        downloadingIDs.insert(existing.id)
        defer { downloadingIDs.remove(existing.id) }

        do {
            let (temporaryURL, response) = try await URLSession.shared.download(from: remoteURL)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                throw TigrisAPI.APIError.invalidResponse
            }

            let filename = (existing.remoteID ?? existing.id.uuidString) + ".mp3"
            let destination = downloadsURL.appendingPathComponent(filename)
            if fileManager.fileExists(atPath: destination.path) {
                try? fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: temporaryURL, to: destination)

            if let index = tracks.firstIndex(where: { $0.id == existing.id }) {
                tracks[index].mediaURL = destination
            }
            save()
        } catch {
            errorMessage = "Couldn’t download \(existing.title): \(error.localizedDescription)"
        }
    }

    func removeDownload(_ track: Track) {
        guard
            let existing = canonicalTrack(for: track),
            existing.isDownloaded,
            let remoteURL = existing.streamURL
        else { return }

        try? fileManager.removeItem(at: existing.mediaURL)
        if let index = tracks.firstIndex(where: { $0.id == existing.id }) {
            tracks[index].mediaURL = remoteURL
        }
        save()
    }

    func add(_ incoming: [Track]) {
        var knownRemoteIDs = Set(tracks.compactMap(\.remoteID))
        var changed = false

        for var track in incoming {
            if let remoteID = track.remoteID, knownRemoteIDs.contains(remoteID) {
                continue
            }
            if tracks.contains(where: { $0.id == track.id }) {
                continue
            }
            track.addedAt = Date()
            tracks.insert(track, at: 0)
            if let remoteID = track.remoteID {
                knownRemoteIDs.insert(remoteID)
            }
            changed = true
        }

        if changed { save() }
    }

    func toggleFavorite(_ track: Track) {
        if let existing = canonicalTrack(for: track) {
            if favoriteIDs.contains(existing.id) {
                favoriteIDs.remove(existing.id)
            } else {
                favoriteIDs.insert(existing.id)
            }
        } else {
            add([track])
            favoriteIDs.insert(track.id)
        }
        save()
    }

    func delete(_ track: Track) {
        guard let existing = canonicalTrack(for: track) else { return }
        tracks.removeAll { $0.id == existing.id }
        favoriteIDs.remove(existing.id)
        for index in playlists.indices {
            playlists[index].trackIDs.removeAll { $0 == existing.id }
        }
        if existing.mediaURL.isFileURL {
            try? fileManager.removeItem(at: existing.mediaURL)
        }
        save()
    }

    @discardableResult
    func createPlaylist(named name: String) -> Playlist? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let playlist = Playlist(name: trimmed)
        playlists.insert(playlist, at: 0)
        save()
        return playlist
    }

    func deletePlaylist(_ playlist: Playlist) {
        playlists.removeAll { $0.id == playlist.id }
        save()
    }

    func add(_ track: Track, to playlistID: UUID) {
        if !contains(track) { add([track]) }
        guard let existing = canonicalTrack(for: track),
              let index = playlists.firstIndex(where: { $0.id == playlistID }) else {
            return
        }
        guard !playlists[index].trackIDs.contains(existing.id) else { return }
        playlists[index].trackIDs.append(existing.id)
        save()
    }

    func remove(_ track: Track, from playlistID: UUID) {
        guard let existing = canonicalTrack(for: track),
              let index = playlists.firstIndex(where: { $0.id == playlistID }) else {
            return
        }
        playlists[index].trackIDs.removeAll { $0 == existing.id }
        save()
    }

    func importFiles(_ urls: [URL]) async {
        var imported: [Track] = []

        for url in urls {
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }

            let extensionName = url.pathExtension.isEmpty ? "m4a" : url.pathExtension
            let destination = importsURL
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(extensionName)

            do {
                try fileManager.copyItem(at: url, to: destination)
                let asset = AVURLAsset(url: destination)
                let time = try? await asset.load(.duration)
                let seconds = time.map(CMTimeGetSeconds) ?? 0
                let title = url.deletingPathExtension().lastPathComponent
                    .replacingOccurrences(of: "_", with: " ")

                imported.append(Track(
                    title: title.isEmpty ? "Untitled track" : title,
                    artist: "Imported",
                    album: "Files",
                    artworkURL: nil,
                    mediaURL: destination,
                    duration: seconds.isFinite && seconds > 0 ? seconds : 0,
                    source: .local,
                    remoteID: nil
                ))
            } catch {
                errorMessage = "Couldn’t import \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }

        if !imported.isEmpty { add(imported) }
    }

    private func canonicalTrack(for track: Track) -> Track? {
        tracks.first { existing in
            if existing.id == track.id { return true }
            guard let remoteID = track.remoteID else { return false }
            return existing.remoteID == remoteID
        }
    }

    private func load() {
        guard
            let data = try? Data(contentsOf: libraryURL),
            let snapshot = try? JSONDecoder().decode(LibrarySnapshot.self, from: data)
        else { return }

        tracks = snapshot.tracks.compactMap { stored in
            var track = stored
            if track.source == .local {
                return fileManager.fileExists(atPath: track.mediaURL.path) ? track : nil
            }
            if track.source == .cloud,
               track.mediaURL.isFileURL,
               !fileManager.fileExists(atPath: track.mediaURL.path) {
                guard let streamURL = track.streamURL else { return nil }
                track.mediaURL = streamURL
            }
            return track
        }
        favoriteIDs = Set(snapshot.favoriteIDs)
        playlists = snapshot.playlists
    }

    private func save() {
        let snapshot = LibrarySnapshot(
            tracks: tracks,
            favoriteIDs: Array(favoriteIDs),
            playlists: playlists
        )
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: libraryURL, options: .atomic)
        } catch {
            errorMessage = "Couldn’t save your library: \(error.localizedDescription)"
        }
    }
}
