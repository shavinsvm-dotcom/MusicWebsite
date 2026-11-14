import PhotosUI
import SwiftUI
import UIKit

private enum PlaylistsLayout: String {
    case grid
    case list
}

private enum PlaylistSort: String, CaseIterable, Identifiable {
    case recent
    case name
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: return "Recently Added"
        case .name: return "Name"
        case .manual: return "Manual"
        }
    }
}

struct PlaylistsView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerManager
    @Binding var showNowPlaying: Bool

    @State private var showCreatePlaylist = false
    @State private var layout: PlaylistsLayout = .grid
    @State private var sort: PlaylistSort = .recent

    private let gridColumns = [
        GridItem(.flexible(), spacing: 18),
        GridItem(.flexible(), spacing: 18)
    ]

    private var sortedPlaylists: [Playlist] {
        switch sort {
        case .recent:
            return library.playlists.sorted { $0.createdAt > $1.createdAt }
        case .name:
            return library.playlists.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .manual:
            return library.playlists
        }
    }

    private var recentTracks: [Track] {
        Array(library.recentTracks.prefix(10))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    if !recentTracks.isEmpty {
                        recentlyPlayed
                    }

                    if library.playlists.isEmpty {
                        emptyState
                            .padding(.top, 54)
                    } else {
                        sectionHeader

                        if layout == .grid {
                            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 24) {
                                ForEach(sortedPlaylists) { playlist in
                                    playlistLink(playlist) {
                                        PlaylistTile(
                                            playlist: playlist,
                                            tracks: library.tracks(in: playlist)
                                        )
                                    }
                                }
                            }
                        } else {
                            LazyVStack(spacing: 0) {
                                ForEach(sortedPlaylists) { playlist in
                                    playlistLink(playlist) {
                                        PlaylistListRow(
                                            playlist: playlist,
                                            tracks: library.tracks(in: playlist)
                                        )
                                    }

                                    if playlist.id != sortedPlaylists.last?.id {
                                        Divider().opacity(0.35)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .navigationTitle("Playlists")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 14) {
                        Menu {
                            Section("View") {
                                Button {
                                    layout = .grid
                                } label: {
                                    Label("Grid", systemImage: layout == .grid ? "checkmark" : "square.grid.2x2")
                                }
                                Button {
                                    layout = .list
                                } label: {
                                    Label("List", systemImage: layout == .list ? "checkmark" : "list.bullet")
                                }
                            }

                            Section("Sort") {
                                ForEach(PlaylistSort.allCases) { option in
                                    Button {
                                        sort = option
                                    } label: {
                                        Label(
                                            option.title,
                                            systemImage: sort == option ? "checkmark" : "arrow.up.arrow.down"
                                        )
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.body.weight(.semibold))
                        }
                        .accessibilityLabel("Playlist options")

                        Button {
                            showCreatePlaylist = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.body.weight(.semibold))
                        }
                        .accessibilityLabel("New playlist")
                    }
                }
            }
            .sheet(isPresented: $showCreatePlaylist) {
                PlaylistEditorView()
            }
        }
    }

    private var sectionHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            SectionTitle(title: "Your Playlists")
            Spacer()
            Text("\(library.playlists.count)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private var recentlyPlayed: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Recently Played")

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(recentTracks) { track in
                        Button {
                            player.play(track, queue: recentTracks)
                            showNowPlaying = true
                        } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                ArtworkView(url: track.artworkURL, seed: track.title + track.artist)
                                    .frame(width: 128, height: 128)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                                    }

                                Text(track.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                Text(track.artist)
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 128, alignment: .leading)
                        }
                        .buttonStyle(MotifPressStyle(scale: 0.975, opacity: 0.9))
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "music.note.list")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)

            Text("No playlists yet")
                .font(.system(size: 23, weight: .semibold))
                .tracking(-0.4)

            Text("Build a playlist from your library and it will live here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                showCreatePlaylist = true
            } label: {
                Label("New playlist", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(Color.primary, in: Capsule())
                    .foregroundStyle(Color(uiColor: .systemBackground))
            }
            .buttonStyle(MotifPressStyle(scale: 0.94))
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func playlistLink<Content: View>(
        _ playlist: Playlist,
        @ViewBuilder content: () -> Content
    ) -> some View {
        NavigationLink {
            PlaylistDetailView(
                playlistID: playlist.id,
                showNowPlaying: $showNowPlaying
            )
        } label: {
            content()
        }
        .buttonStyle(MotifPressStyle(scale: 0.975, opacity: 0.92))
        .contextMenu {
            Button {
                play(playlist)
            } label: {
                Label("Play", systemImage: "play.fill")
            }

            let tracks = library.tracks(in: playlist)
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

    private func play(_ playlist: Playlist) {
        let tracks = library.tracks(in: playlist)
        guard let first = tracks.first else { return }
        player.play(first, queue: tracks)
        showNowPlaying = true
    }
}

struct PlaylistTile: View {
    let playlist: Playlist
    let tracks: [Track]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            PlaylistArtwork(playlist: playlist, tracks: tracks)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                }

            Text(playlist.name)
                .font(.system(size: 15, weight: .semibold))
                .tracking(-0.15)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(trackCountText)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
    }

    private var trackCountText: String {
        let count = tracks.count
        return count == 1 ? "1 track" : "\(count) tracks"
    }
}

private struct PlaylistListRow: View {
    let playlist: Playlist
    let tracks: [Track]

    var body: some View {
        HStack(spacing: 12) {
            PlaylistArtwork(playlist: playlist, tracks: tracks)
                .frame(width: 62, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(playlist.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)

                if playlist.description.isEmpty {
                    Text(trackText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(playlist.description)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text("\(tracks.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    private var trackText: String {
        tracks.count == 1 ? "1 track" : "\(tracks.count) tracks"
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
            } else if tracks.count == 1, let track = tracks.first {
                ArtworkView(url: track.artworkURL, seed: track.title + track.artist)
                    .frame(width: width, height: height)
            } else if tracks.count == 2 {
                VStack(spacing: 0) {
                    cell(0, width: width, height: height / 2)
                    cell(1, width: width, height: height / 2)
                }
            } else if tracks.count == 3 {
                let topHeight = height * 0.56
                VStack(spacing: 0) {
                    cell(0, width: width, height: topHeight)
                    HStack(spacing: 0) {
                        cell(1, width: width / 2, height: height - topHeight)
                        cell(2, width: width / 2, height: height - topHeight)
                    }
                }
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
        ScrollView {
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 26)
                    .frame(maxWidth: .infinity)
                    .background(alignment: .top) {
                        headerAmbience
                    }

                if tracks.isEmpty {
                    emptyState
                        .padding(.horizontal, 20)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                            PlaylistTrackRow(
                                index: index,
                                track: track,
                                queue: tracks,
                                playlistID: playlistID,
                                showNowPlaying: $showNowPlaying
                            )

                            if track.id != tracks.last?.id {
                                Divider().opacity(0.32)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }

                Spacer(minLength: 120)
            }
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .navigationTitle(playlist?.name ?? "Playlist")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
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

                        ShareLink(item: "\(playlist.name) — a playlist on MOTIF") {
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

    private var header: some View {
        VStack(spacing: 14) {
            PlaylistArtwork(playlist: playlist ?? Playlist(name: "Playlist"), tracks: tracks)
                .frame(width: 222, height: 222)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.28), radius: 24, y: 12)

            VStack(spacing: 6) {
                Text("PLAYLIST")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.3)
                    .foregroundStyle(.secondary)

                Text(playlist?.name ?? "Playlist")
                    .font(.system(size: 33, weight: .bold))
                    .tracking(-1.1)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                if let description = playlist?.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 1)
                }

                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 1)
            }
            .padding(.horizontal, 16)

            if !tracks.isEmpty {
                HStack(spacing: 10) {
                    Button {
                        play(shuffled: false)
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 22)
                            .frame(height: 42)
                            .background(Color.primary, in: Capsule())
                            .foregroundStyle(Color(uiColor: .systemBackground))
                    }
                    .buttonStyle(MotifPressStyle(scale: 0.94))

                    Button {
                        play(shuffled: true)
                    } label: {
                        Image(systemName: "shuffle")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 42, height: 42)
                            .contentShape(Circle())
                            .nativeGlass(Circle(), interactive: true)
                    }
                    .buttonStyle(MotifPressStyle(scale: 0.9))
                    .accessibilityLabel("Shuffle playlist")

                    if tracks.contains(where: { $0.isCloud }) {
                        Button {
                            Task { await library.downloadAll(downloadable) }
                        } label: {
                            Group {
                                if isDownloading {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(.secondary)
                                } else {
                                    Image(systemName: downloadable.isEmpty ? "checkmark.circle.fill" : "arrow.down.circle")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.primary)
                                }
                            }
                            .frame(width: 42, height: 42)
                            .contentShape(Circle())
                            .nativeGlass(Circle(), interactive: true)
                        }
                        .buttonStyle(MotifPressStyle(scale: 0.9))
                        .disabled(downloadable.isEmpty || isDownloading)
                        .accessibilityLabel(downloadable.isEmpty ? "Playlist downloaded" : "Download playlist")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var headerAmbience: some View {
        GeometryReader { geometry in
            ZStack {
                PlaylistArtwork(playlist: playlist ?? Playlist(name: "Playlist"), tracks: tracks)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .opacity(0.52)

                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.52), location: 0),
                        .init(color: .black.opacity(0.38), location: 0.45),
                        .init(color: Color(uiColor: .systemBackground).opacity(0.92), location: 0.82),
                        .init(color: Color(uiColor: .systemBackground), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .frame(height: 500)
        .allowsHitTesting(false)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No songs yet")
                .font(.system(size: 21, weight: .semibold))
                .tracking(-0.3)

            Text("Add songs from any song’s menu, then they’ll appear here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
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

private struct PlaylistTrackRow: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerManager

    let index: Int
    let track: Track
    let queue: [Track]
    let playlistID: UUID
    @Binding var showNowPlaying: Bool

    private var isCurrent: Bool {
        player.current?.id == track.id
    }

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if isCurrent {
                    Image(systemName: "waveform")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                } else {
                    Text("\(index + 1)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 20)

            Button {
                player.play(track, queue: queue)
                showNowPlaying = true
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title)
                            .font(.system(size: 15, weight: isCurrent ? .semibold : .medium))
                            .foregroundStyle(isCurrent ? .primary : .primary)
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
