import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct LibraryView: View {
    private enum LibrarySection: String, CaseIterable, Identifiable, Hashable {
        case songs
        case albums
        case artists

        var id: String { rawValue }

        var title: String {
            switch self {
            case .songs: return "Songs"
            case .albums: return "Albums"
            case .artists: return "Artists"
            }
        }
    }

    private enum SongSort: String, CaseIterable, Identifiable {
        case recentlyAdded
        case title
        case artist
        case album
        case mostPlayed

        var id: String { rawValue }

        var title: String {
            switch self {
            case .recentlyAdded: return "Recently added"
            case .title: return "Title"
            case .artist: return "Artist"
            case .album: return "Album"
            case .mostPlayed: return "Most played"
            }
        }
    }

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerManager
    @Binding var showNowPlaying: Bool

    @AppStorage("motif.library.section") private var sectionRaw = LibrarySection.songs.rawValue
    @AppStorage("motif.library.sort") private var sortRaw = SongSort.recentlyAdded.rawValue

    @State private var showImporter = false
    @State private var showDownloads = false
    @State private var showSettings = false
    @State private var importError: String?

    private var section: LibrarySection {
        LibrarySection(rawValue: sectionRaw) ?? .songs
    }

    private var sort: SongSort {
        SongSort(rawValue: sortRaw) ?? .recentlyAdded
    }

    private var hasContent: Bool {
        !library.tracks.isEmpty
    }

    private var sortedTracks: [Track] {
        switch sort {
        case .recentlyAdded:
            return library.tracks.sorted { $0.addedAt > $1.addedAt }
        case .title:
            return library.tracks.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        case .artist:
            return library.tracks.sorted {
                let artist = $0.artist.localizedCaseInsensitiveCompare($1.artist)
                if artist == .orderedSame {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return artist == .orderedAscending
            }
        case .album:
            return library.tracks.sorted {
                let album = $0.album.localizedCaseInsensitiveCompare($1.album)
                if album == .orderedSame {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return album == .orderedAscending
            }
        case .mostPlayed:
            return library.tracks.sorted {
                let left = library.playCounts[$0.id] ?? 0
                let right = library.playCounts[$1.id] ?? 0
                if left != right { return left > right }
                return $0.addedAt > $1.addedAt
            }
        }
    }

    private var albums: [LibraryAlbumGroup] {
        LibraryAlbumBuilder.albums(from: library.tracks)
    }

    private var artists: [LibraryArtistGroup] {
        LibraryArtistBuilder.artists(from: library.tracks)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if hasContent {
                        sectionBar
                    }

                    activityRow

                    if hasContent {
                        Group {
                            switch section {
                            case .songs:
                                songs
                            case .albums:
                                albumsGrid
                            case .artists:
                                artistsGrid
                            }
                        }
                        .id(section)
                        .transition(.opacity)
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .nativeScrollHeader()
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")

                    Menu {
                        Button {
                            showImporter = true
                        } label: {
                            Label("Import audio", systemImage: "square.and.arrow.down")
                        }

                        Divider()

                        Button {
                            Task { await library.refreshCloud() }
                        } label: {
                            Label("Sync cloud library", systemImage: "arrow.clockwise")
                        }
                        .disabled(library.isRefreshingCloud)

                        Button {
                            showDownloads = true
                        } label: {
                            Label("Download manager", systemImage: "arrow.down.circle")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add music")
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
            .sheet(isPresented: $showDownloads) {
                DownloadManagerView()
                    .environmentObject(library)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(player)
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

    private var sectionBar: some View {
        GeometryReader { proxy in
            let count = max(LibrarySection.allCases.count, 1)
            let segment = proxy.size.width / CGFloat(count)
            let index = CGFloat(LibrarySection.allCases.firstIndex(of: section) ?? 0)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary)
                    .frame(width: max(segment - 4, 0), height: 32)
                    .offset(x: index * segment + 2)
                    .animation(MotifMotion.control, value: section)
                    .allowsHitTesting(false)

                HStack(spacing: 0) {
                    ForEach(LibrarySection.allCases) { option in
                        sectionTab(option)
                    }
                }
            }
            .frame(width: proxy.size.width, height: 32)
        }
        .frame(height: 32)
        .padding(4)
        .nativeGlass(Capsule(), interactive: true)
        .padding(.bottom, 2)
    }

    private func sectionTab(_ option: LibrarySection) -> some View {
        let isSelected = section == option

        return Button {
            guard !isSelected else { return }
            MotifHaptics.play(.light)
            withAnimation(MotifMotion.settle) {
                sectionRaw = option.rawValue
            }
        } label: {
            Text(option.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? Color(uiColor: .systemBackground) : Color.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var activityRow: some View {
        if isWorking, let message = activityMessage {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(.secondary)

                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
        }
    }

    private var isWorking: Bool {
        library.isRefreshingCloud
            || !library.uploadingIDs.isEmpty
            || !library.enrichingIDs.isEmpty
    }

    private var activityMessage: String? {
        if library.isRefreshingCloud {
            return "Syncing your cloud library…"
        }
        if !library.uploadingIDs.isEmpty {
            let count = library.uploadingIDs.count
            return "Uploading \(count) \(count == 1 ? "song" : "songs")…"
        }
        if !library.enrichingIDs.isEmpty {
            return library.enrichmentMessage ?? "Updating song details…"
        }
        return nil
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

            GlassActionButton(
                title: "Import audio",
                systemImage: "square.and.arrow.down",
                prominent: true
            ) {
                showImporter = true
            }
            .padding(.top, 2)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nativeGlass(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var songs: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                GlassActionButton(
                    title: "Play",
                    prominent: true,
                    accessibilityLabel: "Play all songs"
                ) {
                    play(sortedTracks)
                }

                GlassActionButton(
                    title: "Shuffle",
                    systemImage: "shuffle",
                    accessibilityLabel: "Shuffle all songs"
                ) {
                    play(sortedTracks, shuffled: true)
                }

                Spacer(minLength: 8)

                Menu {
                    ForEach(SongSort.allCases) { option in
                        Button {
                            withAnimation(.easeOut(duration: 0.18)) {
                                sortRaw = option.rawValue
                            }
                        } label: {
                            if sort == option {
                                Label(option.title, systemImage: "checkmark")
                            } else {
                                Text(option.title)
                            }
                        }
                    }
                } label: {
                    GlassPillMenuLabel(
                        title: sort.title,
                        systemImage: "arrow.up.arrow.down"
                    )
                }
                .accessibilityLabel("Sort songs, \(sort.title)")
            }
            .padding(.bottom, 2)

            if sortedTracks.isEmpty {
                emptyScope("Songs will appear here once you import or add music.")
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(sortedTracks) { track in
                        TrackRow(
                            track: track,
                            queue: sortedTracks,
                            showNowPlaying: $showNowPlaying
                        )

                        if track.id != sortedTracks.last?.id {
                            Divider().opacity(0.35)
                        }
                    }
                }
            }
        }
    }

    private var albumsGrid: some View {
        Group {
            if albums.isEmpty {
                emptyScope("Albums will appear here once your songs have album details.")
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 14),
                        GridItem(.flexible(), spacing: 14)
                    ],
                    alignment: .leading,
                    spacing: 22
                ) {
                    ForEach(albums) { album in
                        NavigationLink {
                            LibraryAlbumDetailView(
                                album: album,
                                showNowPlaying: $showNowPlaying
                            )
                        } label: {
                            LibraryAlbumGridCard(album: album)
                        }
                        .buttonStyle(MotifPressStyle(scale: 0.97, opacity: 0.92))
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private var artistsGrid: some View {
        Group {
            if artists.isEmpty {
                emptyScope("Artists will appear here once your songs have artist details.")
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16)
                    ],
                    alignment: .leading,
                    spacing: 22
                ) {
                    ForEach(artists) { artist in
                        NavigationLink {
                            LibraryArtistDetailView(
                                artistName: artist.name,
                                showNowPlaying: $showNowPlaying
                            )
                        } label: {
                            LibraryArtistGridCard(artist: artist)
                        }
                        .buttonStyle(MotifPressStyle(scale: 0.95, opacity: 0.92))
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private func emptyScope(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.vertical, 6)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func play(_ tracks: [Track], shuffled: Bool = false) {
        guard !tracks.isEmpty else { return }

        if player.isShuffled != shuffled {
            player.toggleShuffle()
        }

        var queue = tracks
        if shuffled {
            queue.shuffle()
        }

        guard let first = queue.first else { return }
        player.play(first, queue: queue)
        showNowPlaying = true
    }
}
