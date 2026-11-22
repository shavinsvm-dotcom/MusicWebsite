import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct LibraryView: View {
    private enum LibrarySection: String, CaseIterable, Identifiable {
        case songs
        case albums
        case artists
        case downloads
        case cloud

        var id: String { rawValue }

        var title: String {
            switch self {
            case .songs: return "Songs"
            case .albums: return "Albums"
            case .artists: return "Artists"
            case .downloads: return "Downloads"
            case .cloud: return "Cloud"
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

    private var downloadedTracks: [Track] {
        library.tracks.filter { library.isDownloaded($0) }
    }

    private var cloudTracks: [Track] {
        library.tracks.filter(\.isCloud)
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
                LazyVStack(alignment: .leading, spacing: 22) {
                    header

                    if !library.tracks.isEmpty {
                        sectionPicker
                    }

                    activityRow

                    if library.tracks.isEmpty {
                        emptyState
                    } else {
                        switch section {
                        case .songs:
                            songs
                        case .albums:
                            albumsGrid
                        case .artists:
                            artistsGrid
                        case .downloads:
                            downloads
                        case .cloud:
                            cloudSection
                        }
                    }
                }
                .screenEntrance()
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .toolbar(.hidden, for: .navigationBar)
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

    private var header: some View {
        ScreenHeader(title: "Your Library", subtitle: summaryLine) {
            GlassIconButton(
                systemImage: "gearshape",
                label: "Settings",
                size: 36
            ) {
                showSettings = true
            }

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
                GlassMenuLabel(systemImage: "plus", size: 36)
            }
            .accessibilityLabel("Add music")
        }
    }

    private var summaryLine: String {
        let songCount = library.tracks.count
        guard songCount > 0 else { return "Nothing saved yet" }

        let songText = songCount == 1 ? "1 song" : "\(songCount) songs"
        let albumCount = albums.count
        guard albumCount > 0 else { return songText }
        let albumText = albumCount == 1 ? "1 album" : "\(albumCount) albums"
        return "\(songText) · \(albumText)"
    }

    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LibrarySection.allCases) { option in
                    let isSelected = section == option

                    Button {
                        MotifHaptics.play(.light)
                        withAnimation(.easeOut(duration: 0.18)) {
                            sectionRaw = option.rawValue
                        }
                    } label: {
                        sectionChip(option, isSelected: isSelected)
                    }
                    .buttonStyle(MotifPressStyle(scale: 0.95))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func sectionChip(_ option: LibrarySection, isSelected: Bool) -> some View {
        let label = Text(option.title)
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)

        if isSelected {
            label
                .foregroundStyle(Color(uiColor: .systemBackground))
                .background(Color.primary, in: Capsule())
        } else {
            label
                .foregroundStyle(.primary)
                .nativeGlass(Capsule(), interactive: true)
        }
    }

    @ViewBuilder
    private var activityRow: some View {
        if let message = activityMessage {
            HStack(spacing: 8) {
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.secondary)
                } else {
                    Image(systemName: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

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
        return library.cloudMessage
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
            HStack(alignment: .center, spacing: 12) {
                SectionTitle(title: "Songs")

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

                Text("\(sortedTracks.count)")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.tertiary)
            }

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

    private var albumsGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle(title: "Albums")
                Spacer()
                Text("\(albums.count)")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.tertiary)
            }

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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle(title: "Artists")
                Spacer()
                Text("\(artists.count)")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.tertiary)
            }

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

    private var downloads: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                SectionTitle(title: "Downloads")

                Spacer(minLength: 8)

                GlassActionButton(
                    title: "Manage",
                    systemImage: "arrow.down.circle",
                    accessibilityLabel: "Open download manager"
                ) {
                    showDownloads = true
                }
            }

            if downloadedTracks.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(.tertiary)

                    Text("No downloads yet")
                        .font(.subheadline.weight(.semibold))

                    Text("Download a cloud song and it will stay on this iPhone, ready without a connection.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 18)
            } else {
                HStack(spacing: 10) {
                    GlassActionButton(
                        title: "Play",
                        prominent: true,
                        accessibilityLabel: "Play downloaded songs"
                    ) {
                        play(downloadedTracks)
                    }

                    Text("Available without a connection")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                LazyVStack(spacing: 0) {
                    ForEach(downloadedTracks) { track in
                        TrackRow(
                            track: track,
                            queue: downloadedTracks,
                            showNowPlaying: $showNowPlaying
                        )

                        if track.id != downloadedTracks.last?.id {
                            Divider().opacity(0.35)
                        }
                    }
                }
            }
        }
    }

    private var cloudSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle(title: "Cloud")
                Spacer()
                Text("\(cloudTracks.count)")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.tertiary)
            }

            if cloudTracks.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    Image(systemName: "cloud")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(.tertiary)

                    Text("No cloud tracks yet")
                        .font(.subheadline.weight(.semibold))

                    Text("Sync your cloud library to stream songs here, or download them for offline listening.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    GlassActionButton(
                        title: "Sync cloud library",
                        systemImage: "arrow.clockwise",
                        prominent: true
                    ) {
                        Task { await library.refreshCloud() }
                    }
                    .disabled(library.isRefreshingCloud)
                    .padding(.top, 2)
                }
                .padding(.vertical, 18)
            } else {
                HStack(spacing: 10) {
                    GlassActionButton(
                        title: "Play",
                        prominent: true,
                        accessibilityLabel: "Play cloud tracks"
                    ) {
                        play(cloudTracks)
                    }

                    GlassActionButton(
                        title: "Download all",
                        systemImage: "arrow.down.circle",
                        accessibilityLabel: "Download all cloud tracks"
                    ) {
                        let pending = cloudTracks.filter { !library.isDownloaded($0) }
                        Task { await library.downloadAll(pending) }
                    }
                    .disabled(cloudTracks.allSatisfy { library.isDownloaded($0) })

                    Spacer(minLength: 8)
                }

                Text("Stream from your cloud library, or download songs for offline listening.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                LazyVStack(spacing: 0) {
                    ForEach(cloudTracks) { track in
                        TrackRow(
                            track: track,
                            queue: cloudTracks,
                            showNowPlaying: $showNowPlaying
                        )

                        if track.id != cloudTracks.last?.id {
                            Divider().opacity(0.35)
                        }
                    }
                }
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
