import AVFoundation
import Combine
import Foundation
import UIKit

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var tracks: [Track] = []
    @Published private(set) var favoriteIDs: Set<UUID> = []
    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var recentTrackIDs: [UUID] = []
    @Published private(set) var isRefreshingCloud = false
    @Published private(set) var downloadingIDs: Set<UUID> = []
    @Published private(set) var cloudMessage: String?
    @Published var errorMessage: String?

    private let fileManager: FileManager
    private let documentsURL: URL
    private let importsURL: URL
    private let downloadsURL: URL
    private let artworkDirectory: URL
    private let libraryURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.importsURL = documentsURL.appendingPathComponent("Imported", isDirectory: true)
        self.downloadsURL = documentsURL.appendingPathComponent("Offline", isDirectory: true)
        self.artworkDirectory = documentsURL.appendingPathComponent("Artwork", isDirectory: true)
        self.libraryURL = documentsURL.appendingPathComponent("library.json")
        try? fileManager.createDirectory(at: importsURL, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: downloadsURL, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: artworkDirectory, withIntermediateDirectories: true)
        load()
    }

    var favorites: [Track] {
        tracks.filter { favoriteIDs.contains($0.id) }
    }

    var recentTracks: [Track] {
        recentTrackIDs.compactMap { id in tracks.first(where: { $0.id == id }) }
    }

    func recordPlay(_ track: Track) {
        guard let existing = canonicalTrack(for: track) else { return }
        recentTrackIDs.removeAll { $0 == existing.id }
        recentTrackIDs.insert(existing.id, at: 0)
        if recentTrackIDs.count > 20 {
            recentTrackIDs = Array(recentTrackIDs.prefix(20))
        }
        save()
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

    func refreshLocalMetadata() async {
        var changed = false

        for index in tracks.indices where tracks[index].source == .local {
            let track = tracks[index]
            let asset = AVURLAsset(url: track.mediaURL)
            let items = (try? await asset.load(.commonMetadata)) ?? []
            let allItems = (try? await asset.load(.metadata)) ?? items
            var updated = track

            if let title = await metadataString(in: items, key: .commonKeyTitle) {
                updated.title = title
            }
            if let artist = await metadataString(in: items, key: .commonKeyArtist) {
                updated.artist = artist
            }
            if let album = await metadataString(in: items, key: .commonKeyAlbumName) {
                updated.album = album
            }
            if updated.artist == "Imported", updated.title.contains(" - ") {
                let fallback = fallbackMetadata(from: updated.title)
                updated.title = fallback.title
                if let artist = fallback.artist { updated.artist = artist }
            }
            if updated.artworkURL == nil, let artwork = await artworkURL(in: items) {
                updated.artworkURL = artwork
            }
            if updated.lyrics == nil, let lyrics = await lyrics(in: allItems) {
                updated.lyrics = lyrics
            }

            if updated != track {
                tracks[index] = updated
                changed = true
            }
        }

        if changed { save() }
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

            var localArtwork: URL?
            if let remoteArtwork = existing.artworkURL, !remoteArtwork.isFileURL,
               let (artworkData, _) = try? await URLSession.shared.data(from: remoteArtwork) {
                let artworkDestination = artworkDirectory
                    .appendingPathComponent(filename + "-cover")
                if (try? artworkData.write(to: artworkDestination, options: .atomic)) != nil {
                    localArtwork = artworkDestination
                }
            }

            let downloadedAsset = AVURLAsset(url: destination)
            let downloadedItems = (try? await downloadedAsset.load(.metadata)) ?? []
            let downloadedLyrics = await lyrics(in: downloadedItems)

            if let index = tracks.firstIndex(where: { $0.id == existing.id }) {
                tracks[index].mediaURL = destination
                if let localArtwork {
                    tracks[index].artworkURL = localArtwork
                }
                if let downloadedLyrics, tracks[index].lyrics == nil {
                    tracks[index].lyrics = downloadedLyrics
                }
            }
            save()

            // Keep lyrics with the offline copy. Embedded lyrics win; when the
            // file has none, ask LRCLIB and persist the result in the library.
            if downloadedLyrics == nil,
               let record = try? await LyricsService.findLyrics(for: existing),
               let onlineLyrics = record.lyricsText {
                setLyrics(onlineLyrics, for: existing)
            }
        } catch {
            errorMessage = "Couldn’t download \(existing.title): \(error.localizedDescription)"
        }
    }

    func downloadAll(_ candidates: [Track]) async {
        for track in candidates where track.isCloud {
            await download(track)
        }
    }

    func removeDownload(_ track: Track) {
        guard
            let existing = canonicalTrack(for: track),
            isDownloaded(existing),
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

    func setLyrics(_ lyrics: String, for track: Track) {
        guard let existing = canonicalTrack(for: track),
              let index = tracks.firstIndex(where: { $0.id == existing.id })
        else { return }

        let trimmed = lyrics.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        tracks[index].lyrics = lyrics
        save()
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
        recentTrackIDs.removeAll { $0 == existing.id }
        for index in playlists.indices {
            playlists[index].trackIDs.removeAll { $0 == existing.id }
        }
        if existing.mediaURL.isFileURL {
            try? fileManager.removeItem(at: existing.mediaURL)
        }
        if let artworkURL = existing.artworkURL, artworkURL.isFileURL {
            try? fileManager.removeItem(at: artworkURL)
        }
        save()
    }

    @discardableResult
    func createPlaylist(
        named name: String,
        description: String = "",
        coverData: Data? = nil
    ) -> Playlist? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var playlist = Playlist(
            name: trimmed,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        playlist.customCoverURL = storePlaylistCover(coverData, for: playlist.id)
        playlists.insert(playlist, at: 0)
        save()
        return playlist
    }

    func updatePlaylistDetails(
        _ playlistID: UUID,
        name: String,
        description: String,
        coverData: Data?,
        removeCover: Bool
    ) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        playlists[index].name = trimmed
        playlists[index].description = description.trimmingCharacters(in: .whitespacesAndNewlines)

        if removeCover {
            removePlaylistCover(at: playlists[index].customCoverURL)
            playlists[index].customCoverURL = nil
        } else if let coverData {
            removePlaylistCover(at: playlists[index].customCoverURL)
            playlists[index].customCoverURL = storePlaylistCover(coverData, for: playlistID)
        }
        save()
    }

    @discardableResult
    func duplicatePlaylist(_ playlist: Playlist) -> Playlist? {
        var copy = Playlist(
            name: playlist.name + " Copy",
            description: playlist.description,
            trackIDs: playlist.trackIDs
        )
        if let cover = playlist.customCoverURL,
           let data = try? Data(contentsOf: cover) {
            copy.customCoverURL = storePlaylistCover(data, for: copy.id)
        }
        playlists.insert(copy, at: 0)
        save()
        return copy
    }

    func moveTracks(in playlistID: UUID, from source: IndexSet, to destination: Int) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[index].trackIDs.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func setTrackOrder(_ trackIDs: [UUID], in playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[index].trackIDs = trackIDs
        save()
    }

    func deletePlaylist(_ playlist: Playlist) {
        removePlaylistCover(at: playlist.customCoverURL)
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
                let items = (try? await asset.load(.commonMetadata)) ?? []
                let fallbackTitle = url.deletingPathExtension().lastPathComponent
                    .replacingOccurrences(of: "_", with: " ")
                let metaTitle = await metadataString(in: items, key: .commonKeyTitle)
                let metaArtist = await metadataString(in: items, key: .commonKeyArtist)
                let metaAlbum = await metadataString(in: items, key: .commonKeyAlbumName)
                let metaArtwork = await artworkURL(in: items)
                let fallback = fallbackMetadata(from: fallbackTitle)

                imported.append(Track(
                    title: cleaned(metaTitle) ?? fallback.title,
                    artist: cleaned(metaArtist) ?? fallback.artist ?? "Imported",
                    album: cleaned(metaAlbum) ?? "Files",
                    artworkURL: metaArtwork,
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

    private func cleaned(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private func fallbackMetadata(from name: String) -> (title: String, artist: String?) {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = cleanedName.components(separatedBy: " - ")
        guard parts.count > 1, let artist = parts.last, !artist.isEmpty else {
            return (cleanedName.isEmpty ? "Untitled track" : cleanedName, nil)
        }
        let title = parts.dropLast().joined(separator: " - ")
        return (title.isEmpty ? cleanedName : title, artist)
    }

    private func metadataString(in items: [AVMetadataItem], key: AVMetadataKey) async -> String? {
        guard let item = items.first(where: { $0.commonKey == key }) else { return nil }
        return cleaned(try? await item.load(.stringValue))
    }

    private func artworkURL(in items: [AVMetadataItem]) async -> URL? {
        guard
            let item = items.first(where: { $0.commonKey == .commonKeyArtwork }),
            let data = try? await item.load(.dataValue),
            let image = UIImage(data: data),
            let jpeg = image.jpegData(compressionQuality: 0.9)
        else { return nil }

        let destination = artworkDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        do {
            try jpeg.write(to: destination, options: .atomic)
            return destination
        } catch {
            return nil
        }
    }

    private func storePlaylistCover(_ data: Data?, for playlistID: UUID) -> URL? {
        guard
            let data,
            let image = UIImage(data: data),
            let jpeg = image.jpegData(compressionQuality: 0.9)
        else { return nil }

        let destination = artworkDirectory
            .appendingPathComponent("playlist-\(playlistID.uuidString).jpg")
        do {
            try jpeg.write(to: destination, options: .atomic)
            return destination
        } catch {
            return nil
        }
    }

    private func removePlaylistCover(at url: URL?) {
        guard let url, url.isFileURL else { return }
        try? fileManager.removeItem(at: url)
    }

    private func lyrics(in items: [AVMetadataItem]) async -> String? {
        for item in items {
            let identifier = item.identifier?.rawValue.lowercased() ?? ""
            let key = String(describing: item.key).lowercased()
            let commonKey = item.commonKey?.rawValue.lowercased() ?? ""
            let isLyrics = identifier.contains("uslt")
                || identifier.contains("lyr")
                || key.contains("lyric")
                || commonKey.contains("lyric")
            guard isLyrics else { continue }

            if let value = try? await item.load(.stringValue) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return value }
            }
        }
        return nil
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
        recentTrackIDs = snapshot.recentTrackIDs.filter { id in
            tracks.contains { $0.id == id }
        }
    }

    private func save() {
        let snapshot = LibrarySnapshot(
            tracks: tracks,
            favoriteIDs: Array(favoriteIDs),
            playlists: playlists,
            recentTrackIDs: recentTrackIDs
        )
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: libraryURL, options: .atomic)
        } catch {
            errorMessage = "Couldn’t save your library: \(error.localizedDescription)"
        }
    }
}
