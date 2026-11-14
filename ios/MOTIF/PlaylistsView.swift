import SwiftUI

struct PlaylistsView: View {
    @EnvironmentObject private var library: LibraryStore
    @Binding var showNowPlaying: Bool

    @State private var showNewPlaylist = false
    @State private var newPlaylistName = ""

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                if library.playlists.isEmpty {
                    emptyState
                        .padding(.horizontal, 24)
                        .padding(.top, 72)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
                        ForEach(library.playlists) { playlist in
                            NavigationLink {
                                PlaylistDetailView(
                                    playlistID: playlist.id,
                                    showNowPlaying: $showNowPlaying
                                )
                            } label: {
                                PlaylistTile(
                                    playlist: playlist,
                                    tracks: library.tracks(in: playlist)
                                )
                            }
                            .buttonStyle(MotifPressStyle(scale: 0.975, opacity: 0.92))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
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
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(trackCountText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private var trackCountText: String {
        let count = playlist.trackIDs.count
        return count == 1 ? "1 track" : "\(count) tracks"
    }
}

struct PlaylistMosaic: View {
    let tracks: [Track]

    var body: some View {
        GeometryReader { geometry in
            if tracks.isEmpty {
                placeholder
            } else if tracks.count == 1, let track = tracks.first {
                ArtworkView(url: track.artworkURL, seed: track.title + track.artist)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            } else {
                let cellWidth = geometry.size.width / 2

                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        cell(0, width: cellWidth)
                        cell(1, width: cellWidth)
                    }
                    HStack(spacing: 0) {
                        cell(2, width: cellWidth)
                        cell(3, width: cellWidth)
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
    private func cell(_ index: Int, width: CGFloat) -> some View {
        if index < tracks.count {
            let track = tracks[index]
            ArtworkView(url: track.artworkURL, seed: track.title + track.artist)
                .frame(width: width, height: width)
                .clipped()
        } else {
            Color(white: 0.12)
                .frame(width: width, height: width)
        }
    }
}
