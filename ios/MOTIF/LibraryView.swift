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

    private var sectionBinding: Binding<LibrarySection> {
        Binding(
            get: { section },
            set: { next in
                guard next != section else { return }
                withAnimation(MotifMotion.control) {
                    sectionRaw = next.rawValue
                }
            }
        )
    }

    private var sort: SongSort {
        SongSort(rawValue: sortRaw) ?? .recentlyAdded
    }

    private var hasContent: Bool {
        !library.tracks.isEmpty
    }

    private var sortedTracks: [Track] {
        library.sortedTracks(by: sort)
    }

    private var albums: [LibraryAlbumGroup] {
        library.albumGroups
    }

    private var artists: [LibraryArtistGroup] {
        library.artistGroups
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if hasContent {
                        Picker("Library section", selection: sectionBinding) {
                            ForEach(LibrarySection.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel("Library section")
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
                .padding(.top, 8)
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

            Text("Import audio from your iPhone to start your library.")
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
        let rows = sortedTracks
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                GlassActionButton(
                    title: "Play",
                    prominent: true,
                    accessibilityLabel: "Play all songs"
                ) {
                    play(rows)
                }

                GlassActionButton(
                    title: "Shuffle",
                    systemImage: "shuffle",
                    accessibilityLabel: "Shuffle all songs"
                ) {
                    play(rows, shuffled: true)
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

            if rows.isEmpty {
                emptyScope("Songs will appear here once you import or add music.")
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, track in
                        TrackRow(
                            track: track,
                            queue: rows,
                            showNowPlaying: $showNowPlaying
                        )

                        if index < rows.count - 1 {
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
