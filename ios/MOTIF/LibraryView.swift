import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct LibraryView: View {
    private enum LibraryFilter: CaseIterable, Hashable {
        case all
        case downloads
        case cloud

        var title: String {
            switch self {
            case .all: return "Songs"
            case .downloads: return "Downloads"
            case .cloud: return "Cloud"
            }
        }
    }

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerManager
    @Binding var showNowPlaying: Bool

    @State private var showImporter = false
    @State private var showNewPlaylist = false
    @State private var showDownloads = false
    @State private var importError: String?
    @State private var filter: LibraryFilter = .all

    private var downloadedTracks: [Track] {
        library.tracks.filter { library.isDownloaded($0) }
    }

    private var cloudTracks: [Track] {
        library.tracks.filter { $0.isCloud }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if !library.tracks.isEmpty {
                        filterBar
                    }

                    cloudStatus

                    if library.tracks.isEmpty {
                        emptyState
                    } else if filter == .downloads {
                        downloads
                    } else if filter == .cloud {
                        cloudLibrary
                    } else {
                        LibraryArtistsSection(showNowPlaying: $showNowPlaying)

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
                            showDownloads = true
                        } label: {
                            Label("Download manager", systemImage: "arrow.down.circle")
                        }

                        Button {
                            Task { await library.uploadAllLocal() }
                        } label: {
                            Label("Upload local songs", systemImage: "icloud.and.arrow.up")
                        }
                        .disabled(!library.uploadingIDs.isEmpty)

                        Button {
                            Task { await library.repairMissingCovers() }
                        } label: {
                            Label("Find missing covers", systemImage: "photo.badge.magnifyingglass")
                        }
                        .disabled(!library.enrichingIDs.isEmpty)
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
            .sheet(isPresented: $showDownloads) {
                DownloadManagerView()
                    .environmentObject(library)
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
                    : (!library.enrichingIDs.isEmpty
                        ? (library.enrichmentMessage ?? "Updating song details…")
                        : (!library.uploadingIDs.isEmpty
                            ? "Uploading \(library.uploadingIDs.count) \(library.uploadingIDs.count == 1 ? "song" : "songs")…"
                            : (library.cloudMessage ?? "Tigris library")))
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(2)

            Spacer(minLength: 4)

            GlassIconButton(
                systemImage: "arrow.clockwise",
                label: "Refresh Tigris library"
            ) {
                Task { await library.refreshCloud() }
            }
            .disabled(library.isRefreshingCloud)
        }
        .padding(.vertical, 2)
    }

    private var filterBar: some View {
        HStack(spacing: 2) {
            ForEach(LibraryFilter.allCases, id: \.self) { option in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        filter = option
                    }
                } label: {
                    Text(option.title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(filter == option
                            ? Color(uiColor: .systemBackground)
                            : Color.primary.opacity(0.65))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if filter == option {
                                Capsule()
                                    .fill(Color.primary)
                            }
                        }
                }
                .buttonStyle(MotifPressStyle(scale: 0.96))
                .accessibilityAddTraits(filter == option ? .isSelected : [])
            }
        }
        .padding(4)
        .nativeGlass(Capsule(), interactive: true)
        .glassOutline(Capsule())
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
            SectionHeader(title: "Songs") {
                HStack(spacing: 2) {
                    if !pendingDownloads.isEmpty {
                        Button {
                            Task { await library.downloadAll(pendingDownloads) }
                        } label: {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(MotifPressStyle(scale: 0.9))
                        .accessibilityLabel("Download all songs")

                        Divider().frame(height: 16)
                    }

                    Button {
                        guard let first = library.tracks.first else { return }
                        player.play(first, queue: library.tracks)
                        showNowPlaying = true
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 7)
                    }
                    .buttonStyle(MotifPressStyle(scale: 0.92))
                    .accessibilityLabel("Play all songs")
                }
                .glassTransport()
            }

            LazyVStack(spacing: 0) {
                ForEach(library.tracks) { track in
                    TrackRow(track: track, queue: library.tracks, showNowPlaying: $showNowPlaying)
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
            SectionHeader(title: "Downloaded") {
                if !tracks.isEmpty {
                    Text("\(tracks.count)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    GlassActionButton(
                        title: "Play",
                        accessibilityLabel: "Play downloaded songs"
                    ) {
                        guard let first = tracks.first else { return }
                        player.play(first, queue: tracks)
                        showNowPlaying = true
                    }
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

                    GlassActionButton(title: "Browse songs", systemImage: "square.stack") {
                        filter = .all
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                Text("Available without a connection")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                LazyVStack(spacing: 0) {
                    ForEach(tracks) { track in
                        TrackRow(track: track, queue: tracks, showNowPlaying: $showNowPlaying)
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
            SectionHeader(title: "Favorites") {
                GlassActionButton(
                    title: "Play",
                    accessibilityLabel: "Play favorite songs"
                ) {
                    guard let first = library.favorites.first else { return }
                    player.play(first, queue: library.favorites)
                    showNowPlaying = true
                }
            }

            LazyVStack(spacing: 0) {
                ForEach(library.favorites) { track in
                    TrackRow(track: track, queue: library.favorites, showNowPlaying: $showNowPlaying)
                    if track.id != library.favorites.last?.id {
                        Divider().opacity(0.35)
                    }
                }
            }
        }
    }

    private var cloudLibrary: some View {
        let tracks = cloudTracks
        let pendingDownloads = tracks.filter { !library.isDownloaded($0) }

        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Cloud tracks") {
                Text("\(tracks.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if tracks.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "cloud")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.tertiary)

                    Text("No cloud tracks yet")
                        .font(.system(size: 21, weight: .semibold))
                        .tracking(-0.3)

                    Text("Sync your Tigris library to bring your cloud songs into Lilt.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        Task { await library.refreshCloud() }
                    } label: {
                        Label("Sync cloud tracks", systemImage: "arrow.clockwise")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .background(Color.primary, in: Capsule())
                            .foregroundStyle(Color(uiColor: .systemBackground))
                    }
                    .buttonStyle(MotifPressStyle(scale: 0.94))
                    .disabled(library.isRefreshingCloud)
                    .padding(.top, 2)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassSurface(radius: 26)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Stream from your Tigris library, or download songs for offline listening.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Spacer(minLength: 0)

                        HStack(spacing: 2) {
                            Button {
                                showDownloads = true
                            } label: {
                                Image(systemName: "list.bullet")
                                    .font(.system(size: 13, weight: .semibold))
                                    .frame(width: 30, height: 30)
                            }
                            .buttonStyle(MotifPressStyle(scale: 0.9))
                            .accessibilityLabel("Open download manager")

                            Divider().frame(height: 16)

                            if !pendingDownloads.isEmpty {
                                Button {
                                    Task { await library.downloadAll(pendingDownloads) }
                                } label: {
                                    Image(systemName: "arrow.down.circle")
                                        .font(.system(size: 13, weight: .semibold))
                                        .frame(width: 30, height: 30)
                                }
                                .buttonStyle(MotifPressStyle(scale: 0.9))
                                .accessibilityLabel("Download all cloud tracks")

                                Divider().frame(height: 16)
                            }

                            Button {
                                guard let first = tracks.first else { return }
                                player.play(first, queue: tracks)
                                showNowPlaying = true
                            } label: {
                                Label("Play", systemImage: "play.fill")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 7)
                            }
                            .buttonStyle(MotifPressStyle(scale: 0.92))
                            .accessibilityLabel("Play cloud tracks")
                        }
                        .glassTransport()
                    }
                }

                LazyVStack(spacing: 0) {
                    ForEach(tracks) { track in
                        TrackRow(track: track, queue: tracks, showNowPlaying: $showNowPlaying)
                        if track.id != tracks.last?.id {
                            Divider().opacity(0.35)
                        }
                    }
                }
            }
        }
    }

    private var playlists: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Playlists") {
                GlassIconButton(systemImage: "plus", label: "New playlist") {
                    showNewPlaylist = true
                }
            }

            if library.playlists.isEmpty {
                Text("Playlists you create will appear here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    alignment: .leading,
                    spacing: 18
                ) {
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
                        .buttonStyle(MotifPressStyle(scale: 0.97, opacity: 0.92))
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }
}
