import AVFoundation
import Combine
import Foundation
import UIKit
import UniformTypeIdentifiers

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var tracks: [Track] = [] {
        didSet {
            tracksRevision &+= 1
            invalidateDerivedCaches()
        }
    }
    @Published private(set) var favoriteIDs: Set<UUID> = [] {
        didSet { favoritesCache = nil }
    }
    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var recentTrackIDs: [UUID] = []
    @Published private(set) var playCounts: [UUID: Int] = [:] {
        didSet { sortedTracksCache.removeAll(keepingCapacity: true) }
    }
    @Published private(set) var isRefreshingCloud = false
    @Published private(set) var downloadingIDs: Set<UUID> = []
    @Published private(set) var downloadJobs: [DownloadJob] = []
    @Published private(set) var uploadingIDs: Set<UUID> = []
    @Published private(set) var enrichingIDs: Set<UUID> = []
    @Published private(set) var enrichmentMessage: String?
    @Published private(set) var cloudMessage: String?
    @Published var errorMessage: String?

    private let fileManager: FileManager
    private let documentsURL: URL
    private let importsURL: URL
    private let downloadsURL: URL
    private let artworkDirectory: URL
    private let libraryURL: URL
    private var downloadTasks: [UUID: Task<Void, Never>] = [:]
    private var activeDownloadCount = 0
    private var isPumpingDownloads = false
    private var trackIndex: [UUID: Track] = [:]
    private var trackByRemoteID: [String: Track] = [:]
    private var playlistTrackCache: [UUID: [Track]] = [:]
    /// False from the moment a mutation schedules a save until the deferred
    /// writer rebuilds the indexes off the main thread. Playlist resolution
    /// reads the live array while false so a just-added song never vanishes.
    private var indexesAreCurrent = true
    private var pendingSave: LibrarySnapshot?
    private var saveTask: Task<Void, Never>?

    /// Keeps consecutive generated covers from ever picking the same colour
    /// and pattern pair, even if the view's own counter starts over.
    private var coverGenerationCount = 0

    // Derived collections are read from SwiftUI bodies that run far more often
    // than the library changes. Each one is built once per library revision
    // instead of once per row, per scroll frame or per player state change.
    /// Bumped on every track-list change so a background merge can tell
    /// whether the library moved underneath it.
    private var tracksRevision = 0
    private var favoritesCache: [Track]?
    private var sortedTracksCache: [SongSort: [Track]] = [:]
    private var homeSnapshotCache: HomeSnapshot?
    private var albumGroupsCache: [LibraryAlbumGroup]?
    private var artistGroupsCache: [LibraryArtistGroup]?

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
#if DEBUG
        if UITestSupport.isEnabled {
            seedUITestLibraryIfNeeded()
        }
#endif
    }

#if DEBUG
    /// One local, silent, lyric-bearing track so the UI tests can exercise the
    /// song menu, player lyrics and timing control without network or imports.
    private func seedUITestLibraryIfNeeded() {
        let title = "UI Test Track"
        guard !tracks.contains(where: { $0.title == title }) else { return }

        let url = documentsURL.appendingPathComponent("ui-test-tone.wav")
        if !fileManager.fileExists(atPath: url.path) {
            Self.writeSilentWAV(to: url, seconds: 60)
        }

        let track = Track(
            title: title,
            artist: "Lilt Tests",
            album: "UI Tests",
            mediaURL: url,
            duration: 60,
            source: .local,
            lyrics: """
            [00:00.00]First line of the test
            [00:10.00]Second line of the test
            [00:20.00]Third line of the test
            [00:30.00]Fourth line of the test
            """,
            lyricsSource: .manual
        )

        tracks.insert(track, at: 0)
        save()
    }

    /// A plain PCM WAV is written directly, avoiding an encoder on launch.
    private static func writeSilentWAV(to url: URL, seconds: Int) {
        let sampleRate = 8_000
        let channels = 1
        let bitsPerSample = 16
        let bytesPerFrame = channels * bitsPerSample / 8
        let dataBytes = sampleRate * seconds * bytesPerFrame

        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }

        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + dataBytes))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(channels))
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * bytesPerFrame))
        append(UInt16(bytesPerFrame))
        append(UInt16(bitsPerSample))
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(dataBytes))
        data.append(Data(count: dataBytes))
        try? data.write(to: url)
    }
#endif

    var favorites: [Track] {
        if let favoritesCache { return favoritesCache }
        let resolved = tracks.filter { favoriteIDs.contains($0.id) }
        favoritesCache = resolved
        return resolved
    }

    func sortedTracks(by sort: SongSort) -> [Track] {
        if let cached = sortedTracksCache[sort] { return cached }

        let sorted: [Track]
        switch sort {
        case .recentlyAdded:
            sorted = tracks.sorted { $0.addedAt > $1.addedAt }
        case .title:
            sorted = tracks.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        case .artist:
            sorted = tracks.sorted {
                let artist = $0.artist.localizedCaseInsensitiveCompare($1.artist)
                if artist == .orderedSame {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return artist == .orderedAscending
            }
        case .album:
            sorted = tracks.sorted {
                let album = $0.album.localizedCaseInsensitiveCompare($1.album)
                if album == .orderedSame {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return album == .orderedAscending
            }
        case .mostPlayed:
            sorted = tracks.sorted {
                let left = playCounts[$0.id] ?? 0
                let right = playCounts[$1.id] ?? 0
                if left != right { return left > right }
                return $0.addedAt > $1.addedAt
            }
        }

        sortedTracksCache[sort] = sorted
        return sorted
    }

    var homeSnapshot: HomeSnapshot {
        if let homeSnapshotCache { return homeSnapshotCache }
        let snapshot = HomeSnapshot(library: self)
        homeSnapshotCache = snapshot
        return snapshot
    }

    var albumGroups: [LibraryAlbumGroup] {
        if let albumGroupsCache { return albumGroupsCache }
        let groups = LibraryAlbumBuilder.albums(from: tracks)
        albumGroupsCache = groups
        return groups
    }

    var artistGroups: [LibraryArtistGroup] {
        if let artistGroupsCache { return artistGroupsCache }
        let groups = LibraryArtistBuilder.artists(from: tracks)
        artistGroupsCache = groups
        return groups
    }

    /// Resolves a player copy of a track to the library's canonical row using
    /// the existing indexes, instead of scanning every song on each pass.
    func resolve(_ track: Track) -> Track {
        canonicalTrack(for: track) ?? track
    }

    private func invalidateDerivedCaches() {
        favoritesCache = nil
        sortedTracksCache.removeAll(keepingCapacity: true)
        homeSnapshotCache = nil
        albumGroupsCache = nil
        artistGroupsCache = nil
    }

    var recentTracks: [Track] {
        recentTrackIDs.compactMap { trackIndex[$0] }
    }

    var mostPlayed: [Track] {
        tracks
            .filter { (playCounts[$0.id] ?? 0) > 0 }
            .sorted { lhs, rhs in
                let left = playCounts[lhs.id] ?? 0
                let right = playCounts[rhs.id] ?? 0
                if left != right { return left > right }
                return lhs.addedAt > rhs.addedAt
            }
    }

    func recordPlay(_ track: Track) {
        guard let existing = canonicalTrack(for: track) else { return }
        playCounts[existing.id, default: 0] += 1
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
        guard track.remoteID != nil,
              let existing = canonicalTrack(for: track)
        else { return false }
        return favoriteIDs.contains(existing.id)
    }

    func contains(_ track: Track) -> Bool {
        canonicalTrack(for: track) != nil
    }

    func tracks(in playlist: Playlist) -> [Track] {
        if let cached = playlistTrackCache[playlist.id] {
            return cached
        }

        let resolved: [Track]
        if indexesAreCurrent {
            resolved = playlist.trackIDs.compactMap { trackIndex[$0] }
        } else {
            // The deferred writer has not rebuilt the indexes yet; resolve
            // against the live array so new rows are not silently dropped and
            // removed rows do not linger.
            var byID: [UUID: Track] = [:]
            byID.reserveCapacity(tracks.count)
            for track in tracks {
                byID[track.id] = track
            }
            resolved = playlist.trackIDs.compactMap { byID[$0] }
        }

        playlistTrackCache[playlist.id] = resolved
        return resolved
    }

    func isDownloaded(_ track: Track) -> Bool {
        track.mediaURL.isFileURL && fileManager.fileExists(atPath: track.mediaURL.path)
    }

    func isDownloading(_ track: Track) -> Bool {
        guard let existing = canonicalTrack(for: track) else { return false }
        return downloadingIDs.contains(existing.id)
    }

    func isUploading(_ track: Track) -> Bool {
        guard let existing = canonicalTrack(for: track) else { return false }
        return uploadingIDs.contains(existing.id)
    }

    func isEnriching(_ track: Track) -> Bool {
        guard let existing = canonicalTrack(for: track) else { return false }
        return enrichingIDs.contains(existing.id)
    }

    func refreshLocalMetadata() async {
        var changed = false

        for index in tracks.indices where tracks[index].source == .local {
            let track = tracks[index]

            // Re-reading every local file on every launch is expensive. Only
            // revisit files that still need tags or artwork.
            guard track.metadataSource == "filename" || track.artworkURL == nil else {
                continue
            }

            let asset = AVURLAsset(url: track.mediaURL)
            let items = (try? await asset.load(.commonMetadata)) ?? []
            let allItems = (try? await asset.load(.metadata)) ?? items
            var updated = track
            var sawTag = false

            if let title = await metadataString(in: items, key: .commonKeyTitle) {
                updated.title = title
                sawTag = true
            }
            if let artist = await metadataString(in: items, key: .commonKeyArtist) {
                updated.artist = artist
                sawTag = true
            }
            if let album = await metadataString(in: items, key: .commonKeyAlbumName) {
                updated.album = album
                sawTag = true
            }
            if sawTag, updated.metadataSource != "ai" {
                updated.metadataSource = "tags"
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
                updated.lyricsSource = .embedded
            }

            if updated != track {
                tracks[index] = updated
                changed = true
            }
        }

        if changed { save() }

        // Existing local imports should get the same cover treatment as new
        // ones. Untagged files need identification first, otherwise a strict
        // artwork lookup has no artist to match against.
        let missingArtwork = tracks.filter {
            $0.source == .local && $0.artworkURL == nil && !enrichingIDs.contains($0.id)
        }
        Task {
            for track in missingArtwork {
                _ = await enrich(track)
            }
        }
    }

    func refreshCloud() async {
        guard !isRefreshingCloud else { return }
        isRefreshingCloud = true
        cloudMessage = nil
        defer { isRefreshingCloud = false }

        do {
            let remoteTracks = try await TigrisAPI.library()
            let covers = (try? await TigrisAPI.covers()) ?? [:]

            let startRevision = tracksRevision
            let existing = tracks
            let fileManager = self.fileManager

            // Converting the manifest, deduplicating it and checking which
            // downloads are still on disk now happen off the main actor. The
            // merge indexes remote IDs once instead of scanning the library
            // for every incoming row.
            let merged = await Task.detached(priority: .utility) {
                let incoming = makeCloudTracks(from: remoteTracks, covers: covers)
                return mergeCloudLibrary(incoming, into: existing, fileManager: fileManager)
            }.value

            if tracksRevision == startRevision {
                if merged.changed {
                    tracks = merged.tracks
                    save()
                }
            } else {
                // A local edit landed while the merge ran, so redo it against
                // the current rows instead of clobbering newer state.
                let incoming = makeCloudTracks(from: remoteTracks, covers: covers)
                let retry = mergeCloudLibrary(incoming, into: tracks, fileManager: fileManager)
                if retry.changed {
                    tracks = retry.tracks
                    save()
                }
            }

            await repairMissingCloudCovers()
            cloudMessage = remoteTracks.isEmpty
                ? "No cloud tracks yet. Upload a song to get started."
                : "\(remoteTracks.count) tracks in your cloud library"
        } catch {
            cloudMessage = "Couldn’t reach your cloud library. Tap refresh to retry."
        }
    }

    func download(_ track: Track) async {
        enqueueDownload(track)
    }

    func enqueueDownload(_ track: Track) {
        guard let existing = canonicalTrack(for: track),
              existing.isCloud,
              !isDownloaded(existing),
              !downloadJobs.contains(where: {
                  $0.trackID == existing.id
                      && ($0.state == .queued || $0.state == .downloading)
              })
        else { return }

        if let index = downloadJobs.firstIndex(where: {
            $0.trackID == existing.id && ($0.state == .failed || $0.state == .cancelled)
        }) {
            downloadJobs.remove(at: index)
        }

        let job = DownloadJob(
            id: UUID(),
            trackID: existing.id,
            title: existing.title,
            artist: existing.artist,
            state: .queued,
            detail: nil,
            createdAt: Date()
        )
        downloadJobs.insert(job, at: 0)
        pumpDownloads()
    }

    func downloadAll(_ candidates: [Track]) async {
        for track in candidates where track.isCloud {
            enqueueDownload(track)
        }
    }

    func cancelDownload(_ jobID: UUID) {
        guard let index = downloadJobs.firstIndex(where: { $0.id == jobID }) else { return }
        if downloadJobs[index].state == .downloading {
            downloadTasks[jobID]?.cancel()
            downloadJobs[index].detail = "Stopping…"
        }
        downloadJobs[index].state = .cancelled
    }

    func retryDownload(_ job: DownloadJob) {
        guard tracks.contains(where: { $0.id == job.trackID }) else {
            removeDownloadJob(job.id)
            return
        }
        if let index = downloadJobs.firstIndex(where: { $0.id == job.id }) {
            downloadJobs[index].state = .queued
            downloadJobs[index].detail = nil
        }
        pumpDownloads()
    }

    func removeDownloadJob(_ jobID: UUID) {
        if downloadJobs.first(where: { $0.id == jobID })?.state == .downloading {
            downloadTasks[jobID]?.cancel()
        }
        downloadJobs.removeAll { $0.id == jobID }
    }

    func clearFinishedDownloads() {
        downloadJobs.removeAll {
            $0.state == .completed || $0.state == .cancelled
        }
    }

    private func pumpDownloads() {
        guard !isPumpingDownloads else { return }
        isPumpingDownloads = true

        while activeDownloadCount < 2,
              let index = downloadJobs.firstIndex(where: { $0.state == .queued }) {
            let job = downloadJobs[index]
            guard let track = tracks.first(where: { $0.id == job.trackID }) else {
                downloadJobs[index].state = .failed
                downloadJobs[index].detail = "Song is no longer in the library."
                continue
            }

            activeDownloadCount += 1
            downloadJobs[index].state = .downloading
            downloadJobs[index].detail = nil

            let task = Task { [weak self] in
                guard let self else { return }
                await self.performDownload(track, jobID: job.id)
                self.activeDownloadCount = max(0, self.activeDownloadCount - 1)
                self.downloadTasks[job.id] = nil
                self.isPumpingDownloads = false
                self.pumpDownloads()
            }
            downloadTasks[job.id] = task
        }

        isPumpingDownloads = false
    }

    private func updateDownloadJob(
        _ jobID: UUID,
        state: DownloadJobState,
        detail: String? = nil
    ) {
        guard let index = downloadJobs.firstIndex(where: { $0.id == jobID }) else { return }
        downloadJobs[index].state = state
        downloadJobs[index].detail = detail
    }

    private func performDownload(_ track: Track, jobID: UUID) async {
        guard let existing = canonicalTrack(for: track),
              let remoteURL = existing.streamURL ?? (existing.isCloud ? existing.mediaURL : nil)
        else {
            updateDownloadJob(jobID, state: .failed, detail: "The cloud file is unavailable.")
            return
        }

        downloadingIDs.insert(existing.id)
        defer { downloadingIDs.remove(existing.id) }

        do {
            let (temporaryURL, response) = try await URLSession.shared.download(from: remoteURL)
            guard !Task.isCancelled else { throw CancellationError() }
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

            guard !Task.isCancelled else { throw CancellationError() }

            let downloadedAsset = AVURLAsset(url: destination)
            let downloadedItems = (try? await downloadedAsset.load(.metadata)) ?? []
            let downloadedLyrics = await lyrics(in: downloadedItems)
            let loadedDuration = try? await downloadedAsset.load(.duration)
            let downloadedDuration: TimeInterval? = {
                guard let loadedDuration else { return nil }
                let seconds = CMTimeGetSeconds(loadedDuration)
                return seconds.isFinite && seconds > 0 ? seconds : nil
            }()

            if let index = tracks.firstIndex(where: { $0.id == existing.id }) {
                tracks[index].mediaURL = destination
                if let localArtwork {
                    tracks[index].artworkURL = localArtwork
                }
                if let downloadedLyrics, tracks[index].lyrics == nil {
                    tracks[index].lyrics = downloadedLyrics
                    tracks[index].lyricsSource = .embedded
                }
            }
            save()

            // Keep lyrics with the offline copy. Embedded lyrics win; when the
            // file has none, ask LRCLIB and upgrade only when the new match is
            // better than what is already stored.
            let stored = tracks.first(where: { $0.id == existing.id })
            let storedLevel = stored.map { LyricsService.syncLevel(for: $0) } ?? .none
            if downloadedLyrics == nil,
               stored?.lyricsSource != .manual,
               storedLevel < .wordSynced,
               let record = try? await LyricsService.findLyrics(
                   for: existing,
                   audioDuration: downloadedDuration
               ),
               record.hasUsableLyrics,
               record.syncLevel > storedLevel {
                setLyrics(
                    record.lyricsText,
                    lyricsFile: record.lyricsfile,
                    source: .automatic,
                    for: existing
                )
            }

            updateDownloadJob(jobID, state: .completed)
        } catch is CancellationError {
            updateDownloadJob(jobID, state: .cancelled)
        } catch {
            updateDownloadJob(jobID, state: .failed, detail: error.localizedDescription)
            errorMessage = "Couldn’t download \(existing.title): \(error.localizedDescription)"
        }
    }

    func uploadToCloud(_ track: Track) async {
        guard
            let existing = canonicalTrack(for: track),
            existing.source == .local,
            existing.mediaURL.isFileURL,
            !existing.isUploadedToCloud,
            !uploadingIDs.contains(existing.id)
        else { return }

        uploadingIDs.insert(existing.id)
        defer { uploadingIDs.remove(existing.id) }

        let prepared = await enrich(existing) ?? existing
        let fileURL = prepared.mediaURL
        guard fileManager.fileExists(atPath: fileURL.path) else { return }

        let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard fileSize > 0 else {
            errorMessage = "Couldn’t upload \(prepared.title): the audio file is empty."
            return
        }
        guard fileSize <= 100 * 1024 * 1024 else {
            errorMessage = "Couldn’t upload \(prepared.title): cloud songs are limited to 100 MB."
            return
        }

        let id = "c-\(String(Int(Date().timeIntervalSince1970), radix: 36))-\(UUID().uuidString.prefix(8).lowercased())"
        let rawExtension = fileURL.pathExtension.lowercased()
        let safeExtension = rawExtension.filter { $0.isLetter || $0.isNumber }
        let fileExtension = safeExtension.isEmpty ? "m4a" : String(safeExtension.prefix(8))
        let storageKey = "\(id).\(fileExtension)"
        let contentType = UTType(filenameExtension: fileExtension)?.preferredMIMEType
            ?? "audio/mpeg"

        do {
            let remoteURL = try await TigrisAPI.uploadAudio(
                fileURL: fileURL,
                key: storageKey,
                contentType: contentType
            )

            var document: [String: Any] = [
                "id": id,
                "name": fileURL.lastPathComponent,
                "title": prepared.title.isEmpty ? "Untitled" : prepared.title,
                "artist": prepared.artist.isEmpty ? "Unknown artist" : prepared.artist,
                "albumArtist": prepared.artist,
                "album": prepared.album,
                "duration": prepared.duration.isFinite ? max(0, prepared.duration) : 0,
                "url": remoteURL.absoluteString,
                "storagePath": storageKey,
                "uploadedAt": Int(Date().timeIntervalSince1970 * 1000),
                "size": fileSize,
                "mimeType": contentType
            ]
            if let year = prepared.releaseYear {
                document["year"] = year
            }

            try await TigrisAPI.addLibraryDocument(document)

            if let artworkURL = prepared.artworkURL,
               artworkURL.isFileURL,
               let artworkData = try? Data(contentsOf: artworkURL),
               let artwork = UIImage(data: artworkData),
               let jpeg = artwork.jpegData(compressionQuality: 0.82) {
                let coverKey = "songs/covers/\(id).jpg"
                if let coverURL = try? await TigrisAPI.uploadObject(
                    data: jpeg,
                    key: coverKey,
                    contentType: "image/jpeg"
                ) {
                    try? await TigrisAPI.setCover(trackID: id, url: coverURL)
                }
            }

            if let index = tracks.firstIndex(where: { $0.id == prepared.id }) {
                tracks[index].remoteID = id
                tracks[index].streamURL = remoteURL
                save()
            }

            cloudMessage = "Uploaded \(prepared.title) to the cloud"
        } catch {
            errorMessage = "Couldn’t upload \(prepared.title): \(error.localizedDescription)"
        }
    }

    func enrichTrack(_ track: Track) async {
        _ = await enrich(track, forceIdentification: true)
    }

    /// Fill every empty cover. Local untagged files are identified first;
    /// well-tagged files go straight to the iTunes lookup. Cloud rows also get
    /// their cover written back to Tigris so every device sees it.
    func repairMissingCovers() async {
        let local = tracks.filter {
            $0.source == .local
                && $0.mediaURL.isFileURL
                && $0.artworkURL == nil
                && !enrichingIDs.contains($0.id)
        }
        for track in local {
            _ = await enrich(track)
        }
        await repairMissingCloudCovers()
    }

    private func repairMissingCloudCovers() async {
        let missing = tracks.filter {
            $0.isCloud
                && $0.remoteID != nil
                && $0.artworkURL == nil
                && !enrichingIDs.contains($0.id)
        }
        for track in missing {
            await repairCloudCover(track)
        }
    }

    private func repairCloudCover(_ track: Track) async {
        guard
            let current = canonicalTrack(for: track),
            current.isCloud,
            let remoteID = current.remoteID,
            current.artworkURL == nil,
            !enrichingIDs.contains(current.id)
        else { return }

        enrichingIDs.insert(current.id)
        defer {
            enrichingIDs.remove(current.id)
            if enrichingIDs.isEmpty { enrichmentMessage = nil }
        }
        enrichmentMessage = "Finding artwork for \(current.title)…"

        guard
            let match = await ArtworkFinder.find(
                title: current.title,
                artist: current.artist,
                album: current.album
            ),
            let data = await ArtworkFinder.imageData(from: match.artworkURL),
            let image = UIImage(data: data),
            let jpeg = image.jpegData(compressionQuality: 0.85)
        else { return }

        let coverKey = "songs/covers/\(remoteID).jpg"
        guard let coverURL = try? await TigrisAPI.uploadObject(
            data: jpeg,
            key: coverKey,
            contentType: "image/jpeg"
        ) else { return }

        try? await TigrisAPI.setCover(trackID: remoteID, url: coverURL)
        if let index = tracks.firstIndex(where: { $0.remoteID == remoteID }) {
            tracks[index].artworkURL = coverURL
            save()
        }
    }

    /// Identify an untagged local file, then find an official cover. Both steps
    /// are best effort: a failed lookup never blocks an import or an upload.
    private func enrich(
        _ track: Track,
        allowIdentification: Bool = true,
        forceIdentification: Bool = false
    ) async -> Track? {
        guard
            var current = canonicalTrack(for: track),
            current.source == .local,
            current.mediaURL.isFileURL,
            !enrichingIDs.contains(current.id)
        else { return canonicalTrack(for: track) }

        enrichingIDs.insert(current.id)
        defer {
            enrichingIDs.remove(current.id)
            if enrichingIDs.isEmpty { enrichmentMessage = nil }
        }

        var changed = false
        var identifiedCoverURL: URL?

        if allowIdentification, forceIdentification || current.needsRecognition {
            enrichmentMessage = "Identifying \(current.title)…"
            do {
                if let match = try await MusicIdentifier.identify(fileURL: current.mediaURL) {
                    current.title = match.title
                    if !match.artist.isEmpty { current.artist = match.artist }
                    if !match.album.isEmpty { current.album = match.album }
                    if let year = match.year { current.releaseYear = year }
                    current.metadataSource = "ai"
                    identifiedCoverURL = match.coverURL
                    changed = true
                }
            } catch {
                // Auto-enrichment is best effort; the upload still proceeds
                // with whatever tags the file already has.
            }
        }

        if current.artworkURL == nil {
            enrichmentMessage = "Finding artwork for \(current.title)…"
            var artworkData: Data?

            if let match = await ArtworkFinder.find(
                title: current.title,
                artist: current.artist,
                album: current.album
            ) {
                artworkData = await ArtworkFinder.imageData(from: match.artworkURL)
            }

            // Shazam often supplies a usable cover even when the catalogue
            // match is ambiguous. Prefer the iTunes artwork above, but never
            // leave a newly identified track with an empty square.
            if artworkData == nil, let identifiedCoverURL {
                artworkData = await ArtworkFinder.imageData(from: identifiedCoverURL)
            }

            if let artworkData, let saved = storeArtwork(artworkData, for: current.id) {
                current.artworkURL = saved
                changed = true
            }
        }

        if changed, let index = tracks.firstIndex(where: { $0.id == current.id }) {
            tracks[index] = current
            save()
        }
        return current
    }

    private func storeArtwork(_ data: Data, for trackID: UUID) -> URL? {
        guard
            let image = UIImage(data: data),
            let jpeg = image.jpegData(compressionQuality: 0.9)
        else { return nil }

        let destination = artworkDirectory
            .appendingPathComponent("track-\(trackID.uuidString).jpg")
        do {
            try jpeg.write(to: destination, options: .atomic)
            return destination
        } catch {
            return nil
        }
    }

    func uploadAllLocal() async {
        let candidates = tracks.filter {
            $0.source == .local
                && $0.mediaURL.isFileURL
                && !$0.isUploadedToCloud
                && !uploadingIDs.contains($0.id)
        }

        guard !candidates.isEmpty else {
            cloudMessage = "Every local song is already in the cloud."
            return
        }

        for track in candidates {
            await uploadToCloud(track)
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

    func removeAllDownloads() {
        var changed = false

        for index in tracks.indices {
            guard
                tracks[index].isCloud,
                tracks[index].mediaURL.isFileURL,
                let remoteURL = tracks[index].streamURL
            else { continue }

            try? fileManager.removeItem(at: tracks[index].mediaURL)
            tracks[index].mediaURL = remoteURL
            changed = true
        }

        if changed { save() }
    }

    /// Imported audio and downloaded copies, measured off the main actor.
    func storageUsage() async -> (library: Int64, downloads: Int64) {
        let imports = importsURL
        let downloads = downloadsURL

        return await Task.detached(priority: .utility) {
            (Self.directoryBytes(at: imports), Self.directoryBytes(at: downloads))
        }.value
    }

    private nonisolated static func directoryBytes(at url: URL) -> Int64 {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            total += Int64(values?.fileSize ?? 0)
        }
        return total
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

    func setLyrics(
        _ lyrics: String?,
        lyricsFile: String? = nil,
        source: LyricsSource = .manual,
        for track: Track
    ) {
        guard let existing = canonicalTrack(for: track),
              let index = tracks.firstIndex(where: { $0.id == existing.id })
        else { return }

        let trimmedLyrics = lyrics?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedFile = lyricsFile?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedLyrics.isEmpty || !trimmedFile.isEmpty else { return }

        tracks[index].lyrics = trimmedLyrics.isEmpty ? nil : lyrics
        tracks[index].lyricsFile = trimmedFile.isEmpty ? nil : lyricsFile
        tracks[index].lyricsSource = source
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
        playCounts.removeValue(forKey: existing.id)
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

    /// Renders a prismatic ribbon cover off the main thread and points the
    /// playlist at a fresh file name, which also busts the artwork cache so
    /// the new cover appears immediately everywhere the playlist shows up.
    @discardableResult
    func generatePlaylistCover(_ playlistID: UUID) async -> Bool {
        guard let playlist = playlists.first(where: { $0.id == playlistID }) else { return false }
        let name = playlist.name
        coverGenerationCount += 1
        let seedVariant = coverGenerationCount

        let data = await Task.detached(priority: .userInitiated) {
            PlaylistCoverGenerator.jpegData(name: name, variant: seedVariant)
        }.value

        guard let data,
              let index = playlists.firstIndex(where: { $0.id == playlistID })
        else { return false }

        let destination = artworkDirectory
            .appendingPathComponent(
                "playlist-\(playlistID.uuidString)-\(UUID().uuidString.prefix(8)).jpg"
            )

        do {
            try data.write(to: destination, options: .atomic)
        } catch {
            return false
        }

        removePlaylistCover(at: playlists[index].customCoverURL)
        playlists[index].customCoverURL = destination
        save()
        return true
    }

    func clearPlaylistCover(_ playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        removePlaylistCover(at: playlists[index].customCoverURL)
        playlists[index].customCoverURL = nil
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
        add([track], to: playlistID)
    }

    func add(_ incoming: [Track], to playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }

        let missing = incoming.filter { !contains($0) }
        if !missing.isEmpty { add(missing) }

        var known = Set(playlists[index].trackIDs)
        var changed = false

        for track in incoming {
            guard let existing = canonicalTrack(for: track),
                  known.insert(existing.id).inserted else { continue }
            playlists[index].trackIDs.append(existing.id)
            changed = true
        }

        if changed { save() }
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
                    remoteID: nil,
                    metadataSource: (metaTitle != nil || metaArtist != nil || metaAlbum != nil)
                        ? "tags"
                        : "filename"
                ))
            } catch {
                errorMessage = "Couldn’t import \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }

        if !imported.isEmpty { add(imported) }

        // Imported files are usable immediately; metadata and artwork are
        // improved in the background of this import task for untagged files
        // and files that arrived without a cover.
        for track in imported where track.artworkURL == nil || track.needsRecognition {
            _ = await enrich(track)
        }
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
        if let exact = trackIndex[track.id] { return exact }
        // A remote-ID hit is a dictionary lookup; scanning the whole library
        // first made every cloud-row resolution walk thousands of songs.
        if let remoteID = track.remoteID,
           let indexed = trackByRemoteID[remoteID] {
            return indexed
        }
        // Last resort while a deferred save is rebuilding the indexes: a
        // just-added row is only present in the live array.
        if let scanned = tracks.first(where: { $0.id == track.id }) { return scanned }
        guard let remoteID = track.remoteID else { return nil }
        return tracks.first { $0.remoteID == remoteID }
    }

    private func rebuildIndexes() {
        trackIndex.removeAll(keepingCapacity: true)
        trackByRemoteID.removeAll(keepingCapacity: true)

        for track in tracks {
            trackIndex[track.id] = track
            if let remoteID = track.remoteID, trackByRemoteID[remoteID] == nil {
                trackByRemoteID[remoteID] = track
            }
        }

        playlistTrackCache.removeAll(keepingCapacity: true)
        indexesAreCurrent = true
    }

    private func load() {
        guard
            let data = try? Data(contentsOf: libraryURL),
            let snapshot = try? JSONDecoder().decode(LibrarySnapshot.self, from: data)
        else { return }

        var migrated = false

        tracks = snapshot.tracks.compactMap { stored in
            var track = stored

            // The iTunes preview catalog is gone. Drop any preview rows that
            // were saved by older builds while leaving local and cloud tracks
            // untouched.
            if track.source == .preview {
                migrated = true
                return nil
            }

            // iOS can change the app container path between installs. An
            // absolute file URL saved in library.json then points at the old
            // container even though the file moved with the app. Recover it
            // by filename from the current directory before giving up.
            if isMissingLocalFile(track.mediaURL) {
                let directory = track.source == .local ? importsURL : downloadsURL
                if let relocated = existingFile(
                    named: track.mediaURL.lastPathComponent,
                    in: directory
                ) {
                    track.mediaURL = relocated
                    migrated = true
                } else if track.source == .local {
                    migrated = true
                    return nil
                } else if let streamURL = track.streamURL {
                    track.mediaURL = streamURL
                    migrated = true
                } else {
                    migrated = true
                    return nil
                }
            }

            if isMissingLocalFile(track.artworkURL) {
                if let artworkURL = track.artworkURL,
                   let relocated = existingFile(
                    named: artworkURL.lastPathComponent,
                    in: artworkDirectory
                   ) {
                    track.artworkURL = relocated
                } else {
                    track.artworkURL = nil
                }
                migrated = true
            }

            return track
        }
        favoriteIDs = Set(snapshot.favoriteIDs)
        playlists = snapshot.playlists
        recentTrackIDs = snapshot.recentTrackIDs.filter { id in
            tracks.contains { $0.id == id }
        }
        let identifiers = Set(tracks.map(\.id))
        playCounts = snapshot.playCounts.filter { identifiers.contains($0.key) }

        rebuildIndexes()
        if migrated { save() }
    }

    private func isMissingLocalFile(_ url: URL?) -> Bool {
        cloudFileIsMissing(url, fileManager: fileManager)
    }

    private func existingFile(named name: String, in directory: URL) -> URL? {
        guard !name.isEmpty else { return nil }
        let candidate = directory.appendingPathComponent(name)
        return fileManager.fileExists(atPath: candidate.path) ? candidate : nil
    }

    private func save() {
        // Index rebuilding and the shared widget snapshot live in the
        // debounced writer now: a play, favorite or playlist edit should never
        // walk the whole library or block on cfprefsd.
        indexesAreCurrent = false
        playlistTrackCache.removeAll(keepingCapacity: true)

        pendingSave = LibrarySnapshot(
            tracks: tracks,
            favoriteIDs: Array(favoriteIDs),
            playlists: playlists,
            recentTrackIDs: recentTrackIDs,
            playCounts: playCounts
        )
        scheduleSave()
    }

    /// Coalesce library writes and move JSON encoding, index rebuilding and
    /// the shared snapshot off the main thread. Play counts and favorites can
    /// fire several save requests in a burst, and each one previously rebuilt
    /// every index and wrote the widget snapshot synchronously.
    private func scheduleSave() {
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard let self else { return }

            while let snapshot = self.pendingSave {
                self.pendingSave = nil
                let outcome = await self.write(snapshot)

                // A newer mutation already queued another write; let that one
                // publish its fresher indexes instead.
                if self.pendingSave == nil {
                    self.applyIndexes(outcome.indexes)
                }

                if let error = outcome.error {
                    self.errorMessage = "Couldn’t save your library: \(error)"
                }
            }
            self.saveTask = nil
        }
    }

    private func applyIndexes(_ indexes: LibraryIndexes) {
        trackIndex = indexes.byID
        trackByRemoteID = indexes.byRemoteID
        playlistTrackCache.removeAll(keepingCapacity: true)
        indexesAreCurrent = true
    }

    private nonisolated static func buildIndexes(_ tracks: [Track]) -> LibraryIndexes {
        var indexes = LibraryIndexes()
        indexes.byID.reserveCapacity(tracks.count)
        for track in tracks {
            indexes.byID[track.id] = track
            if let remoteID = track.remoteID, indexes.byRemoteID[remoteID] == nil {
                indexes.byRemoteID[remoteID] = track
            }
        }
        return indexes
    }

    /// The widget/app-group snapshot is built from the same indexes the write
    /// already needs, so it costs no extra pass over the library.
    private nonisolated static func sharedSnapshot(
        _ snapshot: LibrarySnapshot,
        indexes: LibraryIndexes
    ) -> SharedLibrarySnapshot {
        let recent = snapshot.recentTrackIDs.prefix(4).compactMap { indexes.byID[$0] }
        let firstPlaylist = snapshot.playlists.first

        return SharedLibrarySnapshot(
            trackCount: snapshot.tracks.count,
            playlistCount: snapshot.playlists.count,
            recent: recent.map {
                SharedLibrarySnapshot.Item(
                    id: $0.id.uuidString,
                    title: $0.title,
                    artist: $0.artist,
                    artworkURL: $0.artworkURL?.absoluteString
                )
            },
            playlistName: firstPlaylist?.name,
            playlistArtworkURL: firstPlaylist?.customCoverURL?.absoluteString
        )
    }

    private nonisolated func write(_ snapshot: LibrarySnapshot) async -> SaveOutcome {
        let indexes = Self.buildIndexes(snapshot.tracks)

        // UserDefaults.set waits on a cfprefsd round trip, so the shared
        // snapshot is written here rather than in save().
        SharedLibrarySnapshot.save(Self.sharedSnapshot(snapshot, indexes: indexes))

        let url = libraryURL
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: .atomic)
            return SaveOutcome(indexes: indexes, error: nil)
        } catch {
            return SaveOutcome(indexes: indexes, error: error.localizedDescription)
        }
    }
}

/// Built off the main thread by the deferred writer and applied back on the
/// main actor once the write finishes.
private struct LibraryIndexes {
    var byID: [UUID: Track] = [:]
    var byRemoteID: [String: Track] = [:]
}

private struct SaveOutcome {
    var indexes: LibraryIndexes
    var error: String?
}

private struct CloudMergeResult {
    var tracks: [Track]
    var changed: Bool
}

/// Builds cloud rows from the remote catalogue. Pure, so it can run off the
/// main actor while the request is still fresh.
private func makeCloudTracks(
    from remoteTracks: [TigrisAPI.RemoteTrack],
    covers: [String: String]
) -> [Track] {
    remoteTracks.compactMap { remote -> Track? in
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
}

/// Merges the remote catalogue into a track list. Runs off the main actor: new
/// rows are deduplicated against sets built once, and existing rows are found
/// through one remote-ID dictionary instead of a `firstIndex` scan per track.
private func mergeCloudLibrary(
    _ incoming: [Track],
    into existing: [Track],
    fileManager: FileManager
) -> CloudMergeResult {
    var mergedTracks = existing
    var changed = false

    var knownIDs = Set(mergedTracks.map(\.id))
    var knownRemoteIDs = Set(mergedTracks.compactMap(\.remoteID))
    let additionDate = Date()

    for track in incoming {
        if let remoteID = track.remoteID, knownRemoteIDs.contains(remoteID) {
            continue
        }
        if knownIDs.contains(track.id) {
            continue
        }

        var row = track
        row.addedAt = additionDate
        mergedTracks.insert(row, at: 0)
        knownIDs.insert(row.id)
        if let remoteID = row.remoteID {
            knownRemoteIDs.insert(remoteID)
        }
        changed = true
    }

    // Covers are written after the manifest upload, so a track that was added
    // before its cover was published needs its row merged on every refresh.
    var indexByRemoteID: [String: Int] = [:]
    indexByRemoteID.reserveCapacity(mergedTracks.count)
    for (index, track) in mergedTracks.enumerated() {
        if let remoteID = track.remoteID, indexByRemoteID[remoteID] == nil {
            indexByRemoteID[remoteID] = index
        }
    }

    for remote in incoming {
        guard
            let remoteID = remote.remoteID,
            let index = indexByRemoteID[remoteID]
        else { continue }

        var row = mergedTracks[index]

        // A download can disappear after an app update or an OS cleanup. Put
        // the row back on its cloud stream instead of leaving it pointing at a
        // file that no longer exists.
        if cloudFileIsMissing(row.mediaURL, fileManager: fileManager) {
            row.mediaURL = remote.mediaURL
            row.streamURL = remote.streamURL ?? row.streamURL
        }

        let missingArtwork = cloudFileIsMissing(row.artworkURL, fileManager: fileManager)
        if let artworkURL = remote.artworkURL,
           (row.artworkURL == nil
            || missingArtwork
            || (row.source == .cloud
                && row.artworkURL?.isFileURL == false
                && row.artworkURL != artworkURL)) {
            row.artworkURL = artworkURL
        } else if missingArtwork {
            row.artworkURL = nil
        }

        if row != mergedTracks[index] {
            mergedTracks[index] = row
            changed = true
        }
    }

    return CloudMergeResult(tracks: mergedTracks, changed: changed)
}

/// File presence check that does not touch actor state, so the cloud merge can
/// run on a background task.
private func cloudFileIsMissing(_ url: URL?, fileManager: FileManager) -> Bool {
    guard let url, url.isFileURL else { return false }
    return !fileManager.fileExists(atPath: url.path)
}

/// Everything the Home screen derives from the library. Building this used to
/// happen inside `HomeView.body`; caching it in the store means a play/pause
/// change no longer rescans and re-sorts every track.
struct HomeSnapshot {
    let mixTracks: [Track]
    let mixSubtitle: String
    let topArtistName: String?
    let topArtistTracks: [Track]

    @MainActor
    init(library: LibraryStore) {
        let all = library.tracks

        guard !all.isEmpty else {
            mixTracks = []
            mixSubtitle = ""
            topArtistName = nil
            topArtistTracks = []
            return
        }

        let count = min(8, all.count)
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        let mix = (0..<count).map { all[(day + $0 * 7) % all.count] }
        mixTracks = mix

        var seen = Set<String>()
        let artists = mix.compactMap { track -> String? in
            let name = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(name).inserted else { return nil }
            return name
        }
        mixSubtitle = artists.isEmpty
            ? "Songs picked for today"
            : artists.prefix(3).joined(separator: ", ")

        var counts: [String: Int] = [:]
        for track in all {
            let name = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty,
                  name != "Imported",
                  name.caseInsensitiveCompare("Unknown artist") != .orderedSame
            else { continue }
            counts[name, default: 0] += 1
        }

        let top = counts
            .sorted {
                if $0.value == $1.value {
                    return $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending
                }
                return $0.value > $1.value
            }
            .first?
            .key

        topArtistName = top
        if let top {
            topArtistTracks = Array(
                all.filter {
                    $0.artist.caseInsensitiveCompare(top) == .orderedSame
                }
                .prefix(6)
            )
        } else {
            topArtistTracks = []
        }
    }
}
