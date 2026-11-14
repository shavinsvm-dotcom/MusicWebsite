import SwiftUI

struct PlaylistsView: View {
    @EnvironmentObject private var library: LibraryStore
    @Binding var showNowPlaying: Bool

    @State private var showNewPlaylist = false
    @State private var newPlaylistName = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if library.playlists.isEmpty {
                        emptyState
                    } else {
                        ForEach(library.playlists) { playlist in
                            NavigationLink {
                                PlaylistDetailView(
                                    playlistID: playlist.id,
                                    showNowPlaying: $showNowPlaying
                                )
                            } label: {
                                playlistRow(playlist)
                            }
                            .buttonStyle(MotifPressStyle(scale: 0.97))
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 120)
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
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "music.note.list")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)

            Text("Make it yours.")
                .font(.system(size: 24, weight: .semibold))
                .tracking(-0.5)

            Text("Build playlists from your library and keep them next to your music.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                beginNewPlaylist()
            } label: {
                Label("New playlist", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(Color.primary, in: Capsule())
                    .foregroundStyle(Color(uiColor: .systemBackground))
            }
            .buttonStyle(MotifPressStyle(scale: 0.94))
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(radius: 26)
    }

    private func playlistRow(_ playlist: Playlist) -> some View {
        HStack(spacing: 12) {
            playlistArtwork(playlist)
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(playlist.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(trackCountText(playlist))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .contentShape(Rectangle())
        .glassSurface(radius: 18)
    }

    @ViewBuilder
    private func playlistArtwork(_ playlist: Playlist) -> some View {
        if let track = library.tracks(in: playlist).first {
            ArtworkView(url: track.artworkURL, seed: playlist.name)
        } else {
            ZStack {
                Color.secondary.opacity(0.12)
                Image(systemName: "music.note.list")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func trackCountText(_ playlist: Playlist) -> String {
        let count = playlist.trackIDs.count
        return count == 1 ? "1 track" : "\(count) tracks"
    }

    private func beginNewPlaylist() {
        newPlaylistName = ""
        showNewPlaylist = true
    }
}
