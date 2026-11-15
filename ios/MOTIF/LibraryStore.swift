import AVFoundation
import Combine
import Foundation
import UIKit
import UniformTypeIdentifiers

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var tracks: [Track] = []
    @Published private(set) var favoriteIDs: Set<UUID> = []
    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var recentTrackIDs: [UUID] = []
    @Published private(set) var playCounts: [UUID: Int] = [:]
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

            // `add` skips rows that already exist. Covers are written after the
            // manifest upload, so a track added before its cover was published
            // stayed blank forever. Merge those updates back into local rows.
            var merged = false
            for remote in incoming {
                guard
                    let remoteID = remote.remoteID,
                    let index = tracks.firstIndex(where: { $0.remoteID == remoteID })
                else { continue }

                var row = tracks[index]

                // A download can disappear after an app update or an OS cleanup.
                // Put the row back on its cloud stream instead of leaving it
                // pointing at a file that no longer exists.
                if isMissingLocalFile(row.mediaURL) {
                    row.mediaURL = remote.mediaURL
                    row.streamURL = remote.streamURL ?? row.streamURL
                }

                let missingArtwork = isMissingLocalFile(row.artworkURL)
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

                if row != tracks[index] {
                    tracks[index] = row
                    merged = true
                }
            }
            if merged { save() }

            await repairMissingCloudCovers()
            cloudMessage = remoteTracks.isEmpty
                ? "No tracks in the Tigris library yet."
                : "\(remoteTracks.count) tracks in the Tigris library"
        } catch {
            cloudMessage = "Couldn’t reach the Tigris library. Tap refresh to retry."
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
               tracks.first(where: { $0.id == existing.id })?.lyrics == nil,
               let record = try? await LyricsService.findLyrics(for: existing),
               let onlineLyrics = record.lyricsText {
                setLyrics(onlineLyrics, for: existing)
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

        var migrated = false

        tracks = snapshot.tracks.compactMap { stored in
            var track = stored

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

        if migrated { save() }
    }

    private func isMissingLocalFile(_ url: URL?) -> Bool {
        guard let url, url.isFileURL else { return false }
        return !fileManager.fileExists(atPath: url.path)
    }

    private func existingFile(named name: String, in directory: URL) -> URL? {
        guard !name.isEmpty else { return nil }
        let candidate = directory.appendingPathComponent(name)
        return fileManager.fileExists(atPath: candidate.path) ? candidate : nil
    }

    private func save() {
        let snapshot = LibrarySnapshot(
            tracks: tracks,
            favoriteIDs: Array(favoriteIDs),
            playlists: playlists,
            recentTrackIDs: recentTrackIDs,
            playCounts: playCounts
        )
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: libraryURL, options: .atomic)
        } catch {
            errorMessage = "Couldn’t save your library: \(error.localizedDescription)"
        }

        let recent = recentTracks.prefix(4).map { track in
            SharedLibrarySnapshot.Item(
                id: track.id.uuidString,
                title: track.title,
                artist: track.artist,
                artworkURL: track.artworkURL?.absoluteString
            )
        }
        let firstPlaylist = playlists.first
        SharedLibrarySnapshot.save(
            SharedLibrarySnapshot(
                trackCount: tracks.count,
                playlistCount: playlists.count,
                recent: Array(recent),
                playlistName: firstPlaylist?.name,
                playlistArtworkURL: firstPlaylist?.customCoverURL?.absoluteString
            )
        )
    }
}
