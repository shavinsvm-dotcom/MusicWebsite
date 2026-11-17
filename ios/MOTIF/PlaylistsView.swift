import PhotosUI
import SwiftUI
import UIKit

enum SmartPlaylist: String, CaseIterable, Identifiable, Hashable {
    case recentlyPlayed
    case favorites
    case downloaded
    case cloud
    case recentlyAdded
    case mostPlayed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recentlyPlayed: return "Recently Played"
        case .favorites: return "Favorites"
        case .downloaded: return "Downloaded"
        case .cloud: return "Cloud Library"
        case .recentlyAdded: return "Recently Added"
        case .mostPlayed: return "Most Played"
        }
    }

    var icon: String {
        switch self {
        case .recentlyPlayed: return "clock.arrow.circlepath"
        case .favorites: return "heart.fill"
        case .downloaded: return "arrow.down.circle.fill"
        case .cloud: return "cloud.fill"
        case .recentlyAdded: return "sparkles"
        case .mostPlayed: return "chart.bar.fill"
        }
    }

    var tint: Color {
        switch self {
        case .recentlyPlayed:
            return Color(red: 0.29, green: 0.43, blue: 0.62)
        case .favorites:
            return Color(red: 0.61, green: 0.25, blue: 0.33)
        case .downloaded:
            return Color(red: 0.20, green: 0.45, blue: 0.37)
        case .cloud:
            return Color(red: 0.22, green: 0.38, blue: 0.62)
        case .recentlyAdded:
            return Color(red: 0.42, green: 0.32, blue: 0.58)
        case .mostPlayed:
            return Color(red: 0.57, green: 0.39, blue: 0.20)
        }
    }

    var emptyTitle: String {
        switch self {
        case .recentlyPlayed: return "Nothing played yet"
        case .favorites: return "No favorites yet"
        case .downloaded: return "Nothing downloaded"
        case .cloud: return "No cloud tracks"
        case .recentlyAdded: return "No songs yet"
        case .mostPlayed: return "No play history yet"
        }
    }

    var emptyMessage: String {
        switch self {
        case .recentlyPlayed:
            return "Songs you play will appear here automatically."
        case .favorites:
            return "Tap the heart on any song and it will live here."
        case .downloaded:
            return "Download a cloud song and it will show up here."
        case .cloud:
            return "Sync your Tigris library and your cloud songs will appear here."
        case .recentlyAdded:
            return "Import files or add previews and they will appear here."
        case .mostPlayed:
            return "Play a song and your most played tracks will rise to the top."
        }
    }

    @MainActor
    func tracks(in library: LibraryStore) -> [Track] {
        switch self {
        case .recentlyPlayed:
            return library.recentTracks
        case .favorites:
            return library.favorites
        case .downloaded:
            return library.tracks.filter { library.isDownloaded($0) }
        case .cloud:
            return library.tracks.filter { $0.isCloud }
        case .recentlyAdded:
            return library.tracks.sorted { lhs, rhs in
                if lhs.addedAt != rhs.addedAt { return lhs.addedAt > rhs.addedAt }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        case .mostPlayed:
            return library.mostPlayed
        }
    }
}

struct PlaylistsView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerManager
    @Binding var showNowPlaying: Bool

    @State private var showCreatePlaylist = false

    var body: some View {
        NavigationStack {
            List {
                Section("Smart Playlists") {
                    ForEach(SmartPlaylist.allCases) { smart in
                        NavigationLink {
                            SmartPlaylistDetailView(
                                smart: smart,
                                showNowPlaying: $showNowPlaying
                            )
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: smart.icon)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(smart.tint)
                                    .frame(width: 24)

                                Text(smart.title)
                            }
                        }
                    }
                }

                if library.playlists.isEmpty {
                    Section {
                        emptyState
                            .listRowBackground(Color.clear)
                    }
                } else {
                    Section("Your Playlists") {
                        ForEach(library.playlists) { playlist in
                            let tracks = library.tracks(in: playlist)
                            NavigationLink {
                                PlaylistDetailView(
                                    playlistID: playlist.id,
                                    showNowPlaying: $showNowPlaying
                                )
                            } label: {
                                PlaylistRow(playlist: playlist, tracks: tracks)
                            }
                            .contextMenu {
                                Button {
                                    play(playlist)
                                } label: {
                                    Label("Play", systemImage: "play.fill")
                                }

                                if tracks.contains(where: { $0.isCloud && !library.isDownloaded($0) }) {
                                    Button {
                                        Task {
                                            await library.downloadAll(
                                                tracks.filter { $0.isCloud && !library.isDownloaded($0) }
                                            )
                                        }
                                    } label: {
                                        Label("Download playlist", systemImage: "arrow.down.circle")
                                    }
                                }

                                Button(role: .destructive) {
                                    library.deletePlaylist(playlist)
                                } label: {
                                    Label("Delete playlist", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Playlists")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreatePlaylist = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New playlist")
                }
            }
            .sheet(isPresented: $showCreatePlaylist) {
                PlaylistEditorView()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note.list")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)

            Text("No playlists yet")
                .font(.headline)

            Text("Create a playlist and it will appear here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func play(_ playlist: Playlist) {
        let tracks = library.tracks(in: playlist)
        guard let first = tracks.first else { return }
        player.play(first, queue: tracks)
        showNowPlaying = true
    }
}

private struct PlaylistRow: View {
    let playlist: Playlist
    let tracks: [Track]

    var body: some View {
        HStack(spacing: 12) {
            PlaylistArtwork(playlist: playlist, tracks: tracks)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                Text(tracks.count == 1 ? "1 song" : "\(tracks.count) songs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

struct PlaylistArtwork: View {
    let playlist: Playlist
    let tracks: [Track]

    var body: some View {
        if let cover = playlist.customCoverURL {
            ArtworkView(url: cover, seed: playlist.name)
        } else {
            PlaylistMosaic(tracks: tracks)
        }
    }
}

struct PlaylistMosaic: View {
    let tracks: [Track]

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            if tracks.isEmpty {
                placeholder
            } else if tracks.count < 4 {
                // A two- or three-song playlist looks best as one strong cover.
                // Splitting a single square into thin strips crops artwork badly.
                let track = tracks.first(where: { $0.artworkURL != nil }) ?? tracks[0]
                ArtworkView(url: track.artworkURL, seed: track.title + track.artist)
                    .frame(width: width, height: height)
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        cell(0, width: width / 2, height: height / 2)
                        cell(1, width: width / 2, height: height / 2)
                    }
                    HStack(spacing: 0) {
                        cell(2, width: width / 2, height: height / 2)
                        cell(3, width: width / 2, height: height / 2)
                    }
                }
            }
        }
        .background(Color.secondary.opacity(0.10))
        .overlay {
            LinearGradient(
                colors: [.white.opacity(0.05), .clear, .black.opacity(0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .allowsHitTesting(false)
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.20), Color(white: 0.09)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: "music.note.list")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    @ViewBuilder
    private func cell(_ index: Int, width: CGFloat, height: CGFloat) -> some View {
        if index < tracks.count {
            let track = tracks[index]
            ArtworkView(url: track.artworkURL, seed: track.title + track.artist)
                .frame(width: width, height: height)
                .clipped()
        } else {
            Color(white: 0.12)
                .frame(width: width, height: height)
        }
    }
}

struct PlaylistTile: View {
    let playlist: Playlist
    let tracks: [Track]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PlaylistArtwork(playlist: playlist, tracks: tracks)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(playlist.name)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)

            Text(tracks.count == 1 ? "1 song" : "\(tracks.count) songs")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct PlaylistDetailView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerManager
    @Environment(\.dismiss) private var dismiss

    let playlistID: UUID
    @Binding var showNowPlaying: Bool

    @State private var showEditDetails = false
    @State private var showEditTracks = false

    private var playlist: Playlist? {
        library.playlists.first(where: { $0.id == playlistID })
    }

    private var tracks: [Track] {
        guard let playlist else { return [] }
        return library.tracks(in: playlist)
    }

    private var downloadable: [Track] {
        tracks.filter { $0.isCloud && !library.isDownloaded($0) }
    }

    private var isDownloading: Bool {
        tracks.contains { library.isDownloading($0) }
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 14) {
                    PlaylistArtwork(playlist: playlist ?? Playlist(name: "Playlist"), tracks: tracks)
                        .frame(width: 168, height: 168)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.16), radius: 12, y: 6)

                    if let description = playlist?.description, !description.isEmpty {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if !tracks.isEmpty {
                        HStack(spacing: 12) {
                            Button {
                                play(shuffled: false)
                            } label: {
                                Label("Play", systemImage: "play.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(minWidth: 84)
                            }
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.capsule)

                            Button {
                                play(shuffled: true)
                            } label: {
                                Image(systemName: "shuffle")
                                    .frame(width: 22)
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .accessibilityLabel("Shuffle playlist")

                            if tracks.contains(where: { $0.isCloud }) {
                                Button {
                                    Task { await library.downloadAll(downloadable) }
                                } label: {
                                    Group {
                                        if isDownloading {
                                            ProgressView()
                                                .controlSize(.small)
                                        } else {
                                            Image(systemName: downloadable.isEmpty ? "checkmark.circle.fill" : "arrow.down.circle")
                                                .frame(width: 22)
                                        }
                                    }
                                }
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                                .disabled(downloadable.isEmpty || isDownloading)
                                .accessibilityLabel(downloadable.isEmpty ? "Playlist downloaded" : "Download playlist")
                            }
                        }
                        .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if tracks.isEmpty {
                Section {
                    Text("No songs yet. Add songs from any song’s menu and they will appear here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                }
            } else {
                Section("Tracks") {
                    ForEach(tracks) { track in
                        PlaylistTrackRow(
                            track: track,
                            queue: tracks,
                            playlistID: playlistID,
                            showNowPlaying: $showNowPlaying
                        )
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(playlist?.name ?? "Playlist")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showEditDetails = true
                    } label: {
                        Label("Edit details", systemImage: "pencil")
                    }

                    Button {
                        showEditTracks = true
                    } label: {
                        Label("Edit tracks", systemImage: "arrow.up.arrow.down")
                    }

                    if let playlist {
                        Button {
                            library.duplicatePlaylist(playlist)
                        } label: {
                            Label("Duplicate", systemImage: "plus.square.on.square")
                        }

                        ShareLink(item: "\(playlist.name) — a playlist on Lilt") {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }

                    Divider()

                    Button(role: .destructive) {
                        if let playlist {
                            library.deletePlaylist(playlist)
                            dismiss()
                        }
                    } label: {
                        Label("Delete playlist", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showEditDetails) {
            if let playlist {
                PlaylistEditorView(playlist: playlist)
            }
        }
        .sheet(isPresented: $showEditTracks) {
            PlaylistTracksEditor(playlistID: playlistID)
        }
    }

    private var subtitle: String {
        let count = tracks.count
        let songText = count == 1 ? "1 song" : "\(count) songs"
        guard let durationText else { return songText }
        return "\(songText) · \(durationText)"
    }

    private var durationText: String? {
        let total = Int(tracks.reduce(0) { $0 + $1.duration }.rounded())
        guard total > 0 else { return nil }
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours) hr \(minutes) min"
        }
        return "\(minutes) min"
    }

    private func play(shuffled: Bool) {
        guard let first = tracks.first else { return }
        if player.isShuffled != shuffled {
            player.toggleShuffle()
        }
        player.play(first, queue: tracks)
        showNowPlaying = true
    }
}

private struct PlaylistTrackRow: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerManager

    let track: Track
    let queue: [Track]
    let playlistID: UUID
    @Binding var showNowPlaying: Bool

    private var isCurrent: Bool {
        player.current?.id == track.id
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                player.play(track, queue: queue)
                showNowPlaying = true
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        ArtworkView(url: track.artworkURL, seed: track.title + track.artist)
                            .frame(width: 46, height: 46)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                        if isCurrent {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(.black.opacity(0.42))
                            PlayingWaveform(color: .white)
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title)
                            .font(.system(size: 15, weight: isCurrent ? .semibold : .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(track.artist)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 6)

                    Text(track.durationText)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(MotifPressStyle(scale: 0.985, opacity: 0.9))

            Menu {
                Button {
                    player.play(track, queue: queue)
                    showNowPlaying = true
                } label: {
                    Label("Play", systemImage: "play.fill")
                }

                Button {
                    player.playNext(track)
                } label: {
                    Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                }

                Button {
                    player.addToQueue(track)
                } label: {
                    Label("Add to Queue", systemImage: "text.badge.plus")
                }

                Button {
                    library.toggleFavorite(track)
                } label: {
                    Label(
                        library.isFavorite(track) ? "Remove favorite" : "Favorite",
                        systemImage: library.isFavorite(track) ? "heart.slash" : "heart"
                    )
                }

                if track.isCloud {
                    if library.isDownloaded(track) {
                        Button(role: .destructive) {
                            library.removeDownload(track)
                        } label: {
                            Label("Remove download", systemImage: "icloud.slash")
                        }
                    } else {
                        Button {
                            Task { await library.download(track) }
                        } label: {
                            Label("Download for offline", systemImage: "arrow.down.circle")
                        }
                        .disabled(library.isDownloading(track))
                    }
                }

                if track.source == .local && track.mediaURL.isFileURL {
                    if track.isUploadedToCloud {
                        Button {} label: {
                            Label("Uploaded to cloud", systemImage: "checkmark.icloud")
                        }
                        .disabled(true)
                    } else if library.isUploading(track) {
                        Button {} label: {
                            Label("Uploading…", systemImage: "icloud.and.arrow.up")
                        }
                        .disabled(true)
                    } else {
                        Button {
                            Task { await library.uploadToCloud(track) }
                        } label: {
                            Label("Upload to cloud", systemImage: "icloud.and.arrow.up")
                        }
                    }
                }

                Divider()

                Button(role: .destructive) {
                    library.remove(track, from: playlistID)
                } label: {
                    Label("Remove from playlist", systemImage: "minus.circle")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 38)
                    .contentShape(Rectangle())
            }
        }
        .padding(.vertical, 7)
    }
}

struct PlaylistTracksEditor: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    let playlistID: UUID

    private var playlist: Playlist? {
        library.playlists.first(where: { $0.id == playlistID })
    }

    private var tracks: [Track] {
        guard let playlist else { return [] }
        return library.tracks(in: playlist)
    }

    var body: some View {
        NavigationStack {
            List {
                if tracks.isEmpty {
                    Text("This playlist is empty.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(tracks) { track in
                        HStack(spacing: 12) {
                            ArtworkView(url: track.artworkURL, seed: track.title + track.artist)
                                .frame(width: 42, height: 42)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                            VStack(alignment: .leading, spacing: 3) {
                                Text(track.title)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                Text(track.artist)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .onMove { source, destination in
                        library.moveTracks(in: playlistID, from: source, to: destination)
                    }
                    .onDelete { offsets in
                        for index in offsets where tracks.indices.contains(index) {
                            library.remove(tracks[index], from: playlistID)
                        }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Edit Tracks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct PlaylistEditorView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    let playlist: Playlist?

    @State private var name: String
    @State private var descriptionText: String
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var coverData: Data?
    @State private var removeCover = false

    init(playlist: Playlist? = nil) {
        self.playlist = playlist
        _name = State(initialValue: playlist?.name ?? "")
        _descriptionText = State(initialValue: playlist?.description ?? "")
    }

    private var tracks: [Track] {
        guard let playlist else { return [] }
        return library.tracks(in: playlist)
    }

    private var previewPlaylist: Playlist {
        playlist ?? Playlist(name: name.isEmpty ? "Playlist" : name)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        coverPreview
                            .frame(width: 138, height: 138)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                            }
                            .overlay(alignment: .bottomTrailing) {
                                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                    Image(systemName: "photo")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(.primary)
                                        .frame(width: 34, height: 34)
                                        .nativeGlass(Circle(), interactive: true)
                                }
                                .offset(x: 6, y: 6)
                            }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .padding(.vertical, 8)

                    if playlist?.customCoverURL != nil || coverData != nil {
                        Button("Remove Cover", role: .destructive) {
                            coverData = nil
                            selectedPhoto = nil
                            removeCover = true
                        }
                    }
                }

                Section("Details") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)

                    TextField("Description", text: $descriptionText, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle(playlist == nil ? "New Playlist" : "Edit Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task(id: selectedPhoto) {
                guard let selectedPhoto,
                      let data = try? await selectedPhoto.loadTransferable(type: Data.self)
                else { return }
                coverData = data
                removeCover = false
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var coverPreview: some View {
        if let coverData, let image = UIImage(data: coverData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else if !removeCover, let cover = playlist?.customCoverURL {
            ArtworkView(url: cover, seed: previewPlaylist.name)
        } else {
            PlaylistMosaic(tracks: tracks)
        }
    }

    private func save() {
        if let playlist {
            library.updatePlaylistDetails(
                playlist.id,
                name: name,
                description: descriptionText,
                coverData: coverData,
                removeCover: removeCover
            )
        } else {
            _ = library.createPlaylist(
                named: name,
                description: descriptionText,
                coverData: coverData
            )
        }
        dismiss()
    }
}

struct SmartPlaylistCover: View {
    let smart: SmartPlaylist
    let tracks: [Track]

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)

            ZStack {
                if tracks.isEmpty {
                    LinearGradient(
                        colors: [
                            smart.tint.opacity(0.95),
                            smart.tint.opacity(0.48),
                            Color(white: 0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    Image(systemName: smart.icon)
                        .font(.system(size: side * 0.30, weight: .light))
                        .foregroundStyle(.white.opacity(0.92))
                } else {
                    PlaylistMosaic(tracks: Array(tracks.prefix(4)))

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.16), .black.opacity(0.48)],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    VStack {
                        Spacer()
                        HStack {
                            Image(systemName: smart.icon)
                                .font(.system(size: max(10, side * 0.095), weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: side * 0.18, height: side * 0.18)
                                .background(.black.opacity(0.44), in: Circle())
                            Spacer()
                        }
                        .padding(side * 0.07)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(smart.tint.opacity(0.22))
    }
}

struct SmartPlaylistDetailView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerManager

    let smart: SmartPlaylist
    @Binding var showNowPlaying: Bool

    private var tracks: [Track] {
        smart.tracks(in: library)
    }

    private var downloadable: [Track] {
        tracks.filter { $0.isCloud && !library.isDownloaded($0) }
    }

    private var isDownloading: Bool {
        tracks.contains { library.isDownloading($0) }
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    SmartPlaylistCover(smart: smart, tracks: tracks)
                        .frame(width: 156, height: 156)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: .black.opacity(0.16), radius: 12, y: 6)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if !tracks.isEmpty {
                        HStack(spacing: 12) {
                            Button {
                                play(shuffled: false)
                            } label: {
                                Label("Play", systemImage: "play.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(minWidth: 84)
                            }
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.capsule)

                            Button {
                                play(shuffled: true)
                            } label: {
                                Image(systemName: "shuffle")
                                    .frame(width: 22)
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .accessibilityLabel("Shuffle \(smart.title)")

                            if !downloadable.isEmpty {
                                Button {
                                    Task { await library.downloadAll(downloadable) }
                                } label: {
                                    Group {
                                        if isDownloading {
                                            ProgressView()
                                                .controlSize(.small)
                                        } else {
                                            Image(systemName: "arrow.down.circle")
                                                .frame(width: 22)
                                        }
                                    }
                                }
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                                .disabled(isDownloading)
                                .accessibilityLabel("Download \(smart.title)")
                            }
                        }
                        .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if tracks.isEmpty {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: smart.icon)
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(.tertiary)

                        Text(smart.emptyTitle)
                            .font(.headline)

                        Text(smart.emptyMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .listRowBackground(Color.clear)
                }
            } else {
                Section("Tracks") {
                    ForEach(tracks) { track in
                        TrackRow(track: track, queue: tracks)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(smart.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var subtitle: String {
        let count = tracks.count
        let songText = count == 1 ? "1 song" : "\(count) songs"
        guard let duration = durationText else { return songText }
        return "\(songText) · \(duration)"
    }

    private var durationText: String? {
        let total = Int(tracks.reduce(0) { $0 + $1.duration }.rounded())
        guard total > 0 else { return nil }
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours) hr \(minutes) min"
        }
        return "\(minutes) min"
    }

    private func play(shuffled: Bool) {
        guard let first = tracks.first else { return }
        if player.isShuffled != shuffled {
            player.toggleShuffle()
        }
        player.play(first, queue: tracks)
        showNowPlaying = true
    }
}
