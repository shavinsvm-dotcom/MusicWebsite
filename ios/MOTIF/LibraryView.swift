import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerManager
    @Binding var showNowPlaying: Bool

    @State private var showImporter = false
    @State private var showNewPlaylist = false
    @State private var newPlaylistName = ""
    @State private var importError: String?

    private var downloadedCount: Int {
        library.tracks.filter { library.isDownloaded($0) }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    cloudStatus

                    if downloadedCount > 0 {
                        Label("\(downloadedCount) tracks available offline", systemImage: "arrow.down.circle")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    if library.tracks.isEmpty {
                        emptyState
                    } else {
                        songs
                    }

                    if !library.favorites.isEmpty {
                        favorites
                    }

                    playlists
                }
                .screenEntrance()
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .navigationTitle("Library")
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showImporter = true
                        } label: {
                            Label("Import audio", systemImage: "square.and.arrow.down")
                        }

                        Button {
                            newPlaylistName = ""
                            showNewPlaylist = true
                        } label: {
                            Label("New playlist", systemImage: "text.badge.plus")
                        }

                        Button {
                            Task { await library.refreshCloud() }
                        } label: {
                            Label("Refresh Tigris library", systemImage: "arrow.clockwise")
                        }
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.title3)
                    }
                    .accessibilityLabel("Add music or playlist")
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    Task { await library.importFiles(urls) }
                case .failure(let error):
                    importError = error.localizedDescription
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
            .alert(
                "Couldn’t add music",
                isPresented: Binding(
                    get: { importError != nil || library.errorMessage != nil },
                    set: {
                        if !$0 {
                            importError = nil
                            library.errorMessage = nil
                        }
                    }
                )
            ) {
                Button("OK") {
                    importError = nil
                    library.errorMessage = nil
                }
            } message: {
                Text(importError ?? library.errorMessage ?? "")
            }
        }
    }

    private var cloudStatus: some View {
        HStack(spacing: 10) {
            if library.isRefreshingCloud {
                ProgressView()
                    .controlSize(.small)
                    .tint(.secondary)
            } else {
                Image(systemName: "cloud")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Text(
                library.isRefreshingCloud
                    ? "Syncing the Tigris library…"
                    : (library.cloudMessage ?? "Tigris library")
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(2)

            Spacer(minLength: 4)

            Button {
                Task { await library.refreshCloud() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(MotifPressStyle(scale: 0.9))
            .foregroundStyle(.secondary)
            .disabled(library.isRefreshingCloud)
            .accessibilityLabel("Refresh Tigris library")
        }
        .padding(.vertical, 2)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "square.stack")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)

            Text("Nothing here yet.")
                .font(.system(size: 25, weight: .semibold))
                .tracking(-0.5)

            Text("Import files from your iPhone, or add previews from Search.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                showImporter = true
            } label: {
                Label("Import audio", systemImage: "square.and.arrow.down")
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

    private var songs: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(title: "Songs")
                Spacer()
                Button {
                    guard let first = library.tracks.first else { return }
                    player.play(first, queue: library.tracks)
                    showNowPlaying = true
                } label: {
                    Label("Play all", systemImage: "play.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(MotifPressStyle(scale: 0.92))
                .foregroundStyle(.secondary)
            }

            LazyVStack(spacing: 0) {
                ForEach(library.tracks) { track in
                    TrackRow(track: track, queue: library.tracks)
                    if track.id != library.tracks.last?.id {
                        Divider().opacity(0.35)
                    }
                }
            }
        }
    }

    private var favorites: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Favorites")
            LazyVStack(spacing: 0) {
                ForEach(library.favorites) { track in
                    TrackRow(track: track, queue: library.favorites)
                    if track.id != library.favorites.last?.id {
                        Divider().opacity(0.35)
                    }
                }
            }
        }
    }

    private var playlists: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle(title: "Playlists")
                Spacer()
                Button {
                    newPlaylistName = ""
                    showNewPlaylist = true
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.weight(.semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(MotifPressStyle(scale: 0.9))
                .glassSurface(radius: 14)
                .accessibilityLabel("New playlist")
            }

            if library.playlists.isEmpty {
                Text("Playlists you create will appear here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(library.playlists) { playlist in
                        NavigationLink {
                            PlaylistDetailView(
                                playlistID: playlist.id,
                                showNowPlaying: $showNowPlaying
                            )
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "music.note.list")
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 54, height: 54)
                                    .background(Color.secondary.opacity(0.12), in: Circle())

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(playlist.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text("\(playlist.trackIDs.count) tracks")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(10)
                            .contentShape(Rectangle())
                            .glassSurface(radius: 18)
                        }
                        .buttonStyle(MotifPressStyle(scale: 0.97))
                    }
                }
            }
        }
    }
}

struct PlaylistDetailView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerManager
    let playlistID: UUID
    @Binding var showNowPlaying: Bool

    private var playlist: Playlist? {
        library.playlists.first(where: { $0.id == playlistID })
    }

    private var tracks: [Track] {
        guard let playlist else { return [] }
        return library.tracks(in: playlist)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if tracks.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("This playlist is empty.")
                            .font(.system(size: 23, weight: .semibold))
                        Text("Use the menu next to any song to add it here.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassSurface(radius: 24)
                } else {
                    Button {
                        guard let first = tracks.first else { return }
                        player.play(first, queue: tracks)
                        showNowPlaying = true
                    } label: {
                        Label("Play playlist", systemImage: "play.fill")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(Color.primary, in: Capsule())
                            .foregroundStyle(Color(uiColor: .systemBackground))
                    }
                    .buttonStyle(MotifPressStyle(scale: 0.94))

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
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .navigationTitle(playlist?.name ?? "Playlist")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        if let playlist { library.deletePlaylist(playlist) }
                    } label: {
                        Label("Delete playlist", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }
}
