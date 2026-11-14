import SwiftUI
import UIKit

struct PlaylistsView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerManager
    @Binding var showNowPlaying: Bool

    @State private var showNewPlaylist = false
    @State private var newPlaylistName = ""

    private let columns = [
        GridItem(.flexible(), spacing: 18),
        GridItem(.flexible(), spacing: 18)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                if library.playlists.isEmpty {
                    emptyState
                        .padding(.horizontal, 24)
                        .padding(.top, 72)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                        ForEach(library.playlists) { playlist in
                            let tracks = library.tracks(in: playlist)

                            NavigationLink {
                                PlaylistDetailView(
                                    playlistID: playlist.id,
                                    showNowPlaying: $showNowPlaying
                                )
                            } label: {
                                PlaylistTile(playlist: playlist, tracks: tracks)
                            }
                            .buttonStyle(MotifPressStyle(scale: 0.975, opacity: 0.92))
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
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 120)
                }
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .navigationTitle("Playlists")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        beginNewPlaylist()
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel("New playlist")
                }
            }
            .alert("New playlist", isPresented: $showNewPlaylist) {
                TextField("Playlist name", text: $newPlaylistName)
                Button("Create") {
                    _ = library.createPlaylist(named: newPlaylistName)
                    newPlaylistName = ""
                }
                Button("Cancel", role: .cancel) {
                    newPlaylistName = ""
                }
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
                beginNewPlaylist()
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

    private func beginNewPlaylist() {
        newPlaylistName = ""
        showNewPlaylist = true
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
            PlaylistMosaic(tracks: tracks)
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
            VStack(alignment: .leading, spacing: 24) {
                header

                if tracks.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(tracks) { track in
                            TrackRow(track: track, queue: tracks)
                            if track.id != tracks.last?.id {
                                Divider().opacity(0.35)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 120)
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
                        play(shuffled: true)
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                    }
                    .disabled(tracks.isEmpty)

                    if tracks.contains(where: { $0.isCloud }) {
                        Button {
                            Task { await library.downloadAll(downloadable) }
                        } label: {
                            Label(
                                downloadable.isEmpty ? "Downloaded" : "Download playlist",
                                systemImage: downloadable.isEmpty ? "checkmark.circle" : "arrow.down.circle"
                            )
                        }
                        .disabled(downloadable.isEmpty || isDownloading)
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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom, spacing: 16) {
                PlaylistMosaic(tracks: tracks)
                    .frame(width: 126, height: 126)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.22), radius: 18, y: 10)

                VStack(alignment: .leading, spacing: 6) {
                    Text("PLAYLIST")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)

                    Text(playlist?.name ?? "Playlist")
                        .font(.system(size: 27, weight: .bold))
                        .tracking(-0.8)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)

                    Text(subtitle)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.bottom, 2)
            }

            if !tracks.isEmpty {
                HStack(spacing: 10) {
                    Button {
                        play(shuffled: false)
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 20)
                            .frame(height: 40)
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
                            .frame(width: 40, height: 40)
                            .contentShape(Circle())
                            .nativeGlass(Circle(), interactive: true)
                    }
                    .buttonStyle(MotifPressStyle(scale: 0.9))
                    .accessibilityLabel("Shuffle playlist")

                    Spacer(minLength: 4)

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
                            .frame(width: 40, height: 40)
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
