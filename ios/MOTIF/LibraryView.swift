import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct LibraryView: View {
    private enum LibraryFilter: Hashable {
        case all
        case downloads
    }

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerManager
    @Binding var showNowPlaying: Bool

    @State private var showImporter = false
    @State private var showNewPlaylist = false
    @State private var importError: String?
    @State private var filter: LibraryFilter = .all

    private var downloadedTracks: [Track] {
        library.tracks.filter { library.isDownloaded($0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    cloudStatus

                    if !library.tracks.isEmpty {
                        Picker("Library filter", selection: $filter) {
                            Text("Songs").tag(LibraryFilter.all)
                            Text("Downloaded").tag(LibraryFilter.downloads)
                        }
                        .pickerStyle(.segmented)
                    }

                    if library.tracks.isEmpty {
                        emptyState
                    } else if filter == .downloads {
                        downloads
                    } else {
                        songs

                        if !library.favorites.isEmpty {
                            favorites
                        }
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
                            showNewPlaylist = true
                        } label: {
                            Label("New playlist", systemImage: "text.badge.plus")
                        }

                        Button {
                            Task { await library.refreshCloud() }
                        } label: {
                            Label("Refresh Tigris library", systemImage: "arrow.clockwise")
                        }

                        Button {
                            Task { await library.uploadAllLocal() }
                        } label: {
                            Label("Upload local songs", systemImage: "icloud.and.arrow.up")
                        }
                        .disabled(!library.uploadingIDs.isEmpty)
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
            .sheet(isPresented: $showNewPlaylist) {
                PlaylistEditorView()
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
                    : (!library.uploadingIDs.isEmpty
                        ? "Uploading \(library.uploadingIDs.count) \(library.uploadingIDs.count == 1 ? "song" : "songs")…"
                        : (library.cloudMessage ?? "Tigris library"))
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
        let pendingDownloads = library.tracks.filter { $0.isCloud && !library.isDownloaded($0) }

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                SectionTitle(title: "Songs")
                Spacer()

                if !pendingDownloads.isEmpty {
                    Button {
                        Task { await library.downloadAll(pendingDownloads) }
                    } label: {
                        Image(systemName: "arrow.down.circle")
                            .font(.body.weight(.semibold))
                    }
                    .buttonStyle(MotifPressStyle(scale: 0.9))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Download all songs")
                }

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

    private var downloads: some View {
        let tracks = downloadedTracks

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle(title: "Downloaded")
                Spacer()
                if !tracks.isEmpty {
                    Button {
                        guard let first = tracks.first else { return }
                        player.play(first, queue: tracks)
                        showNowPlaying = true
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(MotifPressStyle(scale: 0.92))
                    .foregroundStyle(.secondary)

                    Text("\(tracks.count)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            if tracks.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.tertiary)

                    Text("No downloads yet")
                        .font(.subheadline.weight(.semibold))

                    Text("Download a cloud song and it will stay on this iPhone, ready without a connection.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Browse songs") {
                        filter = .all
                    }
                    .font(.footnote.weight(.semibold))
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                Text("Available without a connection")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

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
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
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
                                .frame(width: 146)
                            }
                            .buttonStyle(MotifPressStyle(scale: 0.97, opacity: 0.92))
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
    }
}
