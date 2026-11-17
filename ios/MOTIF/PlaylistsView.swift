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

enum SmartPlaylist: String, CaseIterable, Identifiable, Hashable {
    case recentlyPlayed
    case favorites
    case downloaded
    case cloud
    case recentlyAdded
    case mostPlayed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recentlyPlayed: return "Recently Played"
        case .favorites: return "Favorites"
        case .downloaded: return "Downloaded"
        case .cloud: return "Cloud Library"
        case .recentlyAdded: return "Recently Added"
        case .mostPlayed: return "Most Played"
        }
    }

    var icon: String {
        switch self {
        case .recentlyPlayed: return "clock.arrow.circlepath"
        case .favorites: return "heart.fill"
        case .downloaded: return "arrow.down.circle.fill"
        case .cloud: return "cloud.fill"
        case .recentlyAdded: return "sparkles"
        case .mostPlayed: return "chart.bar.fill"
        }
    }

    var tint: Color {
        switch self {
        case .recentlyPlayed:
            return Color(red: 0.29, green: 0.43, blue: 0.62)
        case .favorites:
            return Color(red: 0.61, green: 0.25, blue: 0.33)
        case .downloaded:
            return Color(red: 0.20, green: 0.45, blue: 0.37)
        case .cloud:
            return Color(red: 0.22, green: 0.38, blue: 0.62)
        case .recentlyAdded:
            return Color(red: 0.42, green: 0.32, blue: 0.58)
        case .mostPlayed:
            return Color(red: 0.57, green: 0.39, blue: 0.20)
        }
    }

    var emptyTitle: String {
        switch self {
        case .recentlyPlayed: return "Nothing played yet"
        case .favorites: return "No favorites yet"
        case .downloaded: return "Nothing downloaded"
        case .cloud: return "No cloud tracks"
        case .recentlyAdded: return "No songs yet"
        case .mostPlayed: return "No play history yet"
        }
    }

    var emptyMessage: String {
        switch self {
        case .recentlyPlayed:
            return "Songs you play will appear here automatically."
        case .favorites:
            return "Tap the heart on any song and it will live here."
        case .downloaded:
            return "Download a cloud song and it will show up here."
        case .cloud:
            return "Sync your Tigris library and your cloud songs will appear here."
        case .recentlyAdded:
            return "Import files or add previews and they will appear here."
        case .mostPlayed:
            return "Play a song and your most played tracks will rise to the top."
        }
    }

    @MainActor
    func tracks(in library: LibraryStore) -> [Track] {
        switch self {
        case .recentlyPlayed:
            return library.recentTracks
        case .favorites:
            return library.favorites
        case .downloaded:
            return library.tracks.filter { library.isDownloaded($0) }
        case .cloud:
            return library.tracks.filter { $0.isCloud }
        case .recentlyAdded:
            return library.tracks.sorted { lhs, rhs in
                if lhs.addedAt != rhs.addedAt { return lhs.addedAt > rhs.addedAt }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        case .mostPlayed:
            return library.mostPlayed
        }
    }
}

private struct PlaylistsSnapshot {
    let playlists: [Playlist]
    let tracksByPlaylist: [UUID: [Track]]
    let smartTracks: [SmartPlaylist: [Track]]
    let totalSongs: Int

    @MainActor
    init(library: LibraryStore, sort: PlaylistSort) {
        switch sort {
        case .recent:
            playlists = library.playlists.sorted { $0.createdAt > $1.createdAt }
        case .name:
            playlists = library.playlists.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .manual:
            playlists = library.playlists
        }

        var resolved: [UUID: [Track]] = [:]
        for playlist in playlists {
            resolved[playlist.id] = library.tracks(in: playlist)
        }
        tracksByPlaylist = resolved

        var smart: [SmartPlaylist: [Track]] = [:]
        for item in SmartPlaylist.allCases {
            smart[item] = item.tracks(in: library)
        }
        smartTracks = smart
        totalSongs = Set(playlists.flatMap { $0.trackIDs }).count
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

    var body: some View {
        let data = PlaylistsSnapshot(library: library, sort: sort)

        NavigationStack {
            ScrollView {
                LazyVStack(
                    alignment: .leading,
                    spacing: 26,
                    pinnedViews: [.sectionHeaders]
                ) {
                    collectionSummary(data)
                    smartPlaylistsSection(data)

                    if data.playlists.isEmpty {
                        emptyState
                            .padding(.horizontal, 20)
                            .padding(.top, 18)
                    } else {
                        playlistsSection(data)
                    }
                }
                .padding(.top, 6)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .navigationTitle("Playlists")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $showCreatePlaylist) {
                PlaylistEditorView()
            }
        }
    }

    private func collectionSummary(_ data: PlaylistsSnapshot) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(data.playlists.count == 1 ? "1 playlist" : "\(data.playlists.count) playlists")
                    .font(.system(size: 20, weight: .semibold))
                    .tracking(-0.35)

                Text(data.totalSongs == 1 ? "1 song across your collection" : "\(data.totalSongs) songs across your collection")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button {
                showCreatePlaylist = true
            } label: {
                Label("New", systemImage: "plus")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
            }
            .buttonStyle(MotifPressStyle(scale: 0.94))
            .nativeGlass(Capsule(), interactive: true)
            .accessibilityLabel("New playlist")
        }
        .padding(.horizontal, 20)
    }

    private func smartPlaylistsSection(_ data: PlaylistsSnapshot) -> some View {
        Section {
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 18) {
                ForEach(Array(SmartPlaylist.allCases.enumerated()), id: \.offset) { index, smart in
                    NavigationLink {
                        SmartPlaylistDetailView(
                            smart: smart,
                            showNowPlaying: $showNowPlaying
                        )
                    } label: {
                        SmartPlaylistCard(
                            smart: smart,
                            tracks: data.smartTracks[smart] ?? []
                        )
                    }
                    .buttonStyle(MotifPressStyle(scale: 0.975, opacity: 0.92))
                    .liltEntrance(index: index)
                    .liltCardScrollTransition()
                }
            }
            .padding(.horizontal, 20)
        } header: {
            PinnedSectionHeader(title: "Smart Playlists") {
                Text("AUTOMATIC")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func playlistsSection(_ data: PlaylistsSnapshot) -> some View {
        Section {
            if layout == .grid {
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 24) {
                    ForEach(data.playlists) { playlist in
                        let tracks = data.tracksByPlaylist[playlist.id] ?? []
                        playlistLink(playlist, tracks: tracks) {
                            PlaylistTile(playlist: playlist, tracks: tracks)
                        }
                        .liltCardScrollTransition()
                    }
                }
                .padding(.horizontal, 20)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(data.playlists) { playlist in
                        let tracks = data.tracksByPlaylist[playlist.id] ?? []
                        playlistLink(playlist, tracks: tracks) {
                            PlaylistListRow(playlist: playlist, tracks: tracks)
                        }

                        if playlist.id != data.playlists.last?.id {
                            Divider().opacity(0.35)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        } header: {
            PinnedSectionHeader(title: "Your Playlists", count: data.playlists.count) {
                playlistControls
            }
        }
    }

    private var playlistControls: some View {
        HStack(spacing: 5) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { layout = .grid }
            } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(layout == .grid ? Color.primary : Color.secondary)
                    .frame(width: 27, height: 27)
                    .background(
                        layout == .grid ? Color.primary.opacity(0.08) : Color.clear,
                        in: Capsule()
                    )
            }
            .buttonStyle(MotifPressStyle(scale: 0.9))
            .accessibilityLabel("Grid layout")

            Button {
                withAnimation(.easeInOut(duration: 0.18)) { layout = .list }
            } label: {
                Image(systemName: "list.bullet")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(layout == .list ? Color.primary : Color.secondary)
                    .frame(width: 27, height: 27)
                    .background(
                        layout == .list ? Color.primary.opacity(0.08) : Color.clear,
                        in: Capsule()
                    )
            }
            .buttonStyle(MotifPressStyle(scale: 0.9))
            .accessibilityLabel("List layout")

            Menu {
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
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 27, height: 27)
            }
            .accessibilityLabel("Sort playlists")

            Button {
                showCreatePlaylist = true
            } label: {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 27, height: 27)
            }
            .buttonStyle(MotifPressStyle(scale: 0.9))
            .accessibilityLabel("New playlist")
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
        tracks: [Track],
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
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .bottomLeading) {
                PlaylistArtwork(playlist: playlist, tracks: tracks)
                    .aspectRatio(1, contentMode: .fit)

                LinearGradient(
                    colors: [.clear, .black.opacity(0.12), .black.opacity(0.62)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                HStack(alignment: .center) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(.black.opacity(0.42), in: Circle())

                    Spacer(minLength: 6)

                    Text(trackCountText)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.34), in: Capsule())
                }
                .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.7)
            }
            .shadow(color: .black.opacity(0.18), radius: 16, y: 8)

            Text(playlist.name)
                .font(.system(size: 15, weight: .semibold))
                .tracking(-0.15)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(playlist.description.isEmpty ? trackCountText : playlist.description)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        HStack(spacing: 14) {
            PlaylistArtwork(playlist: playlist, tracks: tracks)
                .frame(width: 68, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.6)
                }
                .shadow(color: .black.opacity(0.16), radius: 9, y: 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name)
                    .font(.system(size: 16, weight: .semibold))
                    .tracking(-0.2)
                    .lineLimit(1)

                Text(playlist.description.isEmpty ? trackText : playlist.description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text("\(tracks.count)")
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.06), in: Capsule())

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
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
            } else if tracks.count < 4 {
                // A two- or three-song playlist looks best as one strong cover.
                // Splitting a single square into thin strips crops artwork badly.
                let track = tracks.first(where: { $0.artworkURL != nil }) ?? tracks[0]
                ArtworkView(url: track.artworkURL, seed: track.title + track.artist)
                    .frame(width: width, height: height)
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
        .overlay {
            LinearGradient(
                colors: [.white.opacity(0.05), .clear, .black.opacity(0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .allowsHitTesting(false)
        }
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
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            ForEach(tracks) { track in
                                PlaylistTrackRow(
                                    track: track,
                                    queue: tracks,
                                    playlistID: playlistID,
                                    showNowPlaying: $showNowPlaying
                                )
                                .padding(.horizontal, 20)

                                if track.id != tracks.last?.id {
                                    Divider().opacity(0.3)
                                        .padding(.leading, 78)
                                        .padding(.trailing, 20)
                                }
                            }
                        } header: {
                            PinnedSectionHeader(title: "Tracks", count: tracks.count) {
                                EmptyView()
                            }
                        }
                    }
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

                        ShareLink(item: "\(playlist.name) — a playlist on Lilt") {
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
                .frame(width: 236, height: 236)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8)
                }
                .shadow(color: .black.opacity(0.30), radius: 30, y: 15)

            VStack(spacing: 6) {
                Text("PLAYLIST")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.3)
                    .foregroundStyle(.secondary)

                Text(playlist?.name ?? "Playlist")
                    .font(.system(size: 36, weight: .bold))
                    .tracking(-1.2)
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
                    .scaleEffect(1.12)
                    .blur(radius: 28)
                    .clipped()
                    .opacity(0.46)

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
        var parts = [songText]
        if let durationText {
            parts.append(durationText)
        }
        return parts.joined(separator: " · ")
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

    let track: Track
    let queue: [Track]
    let playlistID: UUID
    @Binding var showNowPlaying: Bool

    private var isCurrent: Bool {
        player.current?.id == track.id
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                player.play(track, queue: queue)
                showNowPlaying = true
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        ArtworkView(url: track.artworkURL, seed: track.title + track.artist)
                            .frame(width: 46, height: 46)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                        if isCurrent {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(.black.opacity(0.42))
                            PlayingWaveform(color: .white)
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title)
                            .font(.system(size: 15, weight: isCurrent ? .semibold : .medium))
                            .foregroundStyle(.primary)
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

struct SmartPlaylistCard: View {
    let smart: SmartPlaylist
    let tracks: [Track]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SmartPlaylistCover(smart: smart, tracks: tracks)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.11), lineWidth: 0.7)
                }
                .shadow(color: smart.tint.opacity(0.22), radius: 18, y: 9)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(smart.title)
                    .font(.system(size: 15, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text(countText)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Text(smart == .favorites ? "The songs you keep coming back to." : "A living collection from your library.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var countText: String {
        tracks.count == 1 ? "1 song" : "\(tracks.count) songs"
    }
}

struct SmartPlaylistTile: View {
    let smart: SmartPlaylist
    let tracks: [Track]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            SmartPlaylistCover(smart: smart, tracks: tracks)
                .frame(width: 132, height: 132)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.7)
                }
                .shadow(color: .black.opacity(0.16), radius: 12, y: 6)

            Text(smart.title)
                .font(.system(size: 14, weight: .semibold))
                .tracking(-0.15)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(countText)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 132, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var countText: String {
        tracks.count == 1 ? "1 song" : "\(tracks.count) songs"
    }
}

struct SmartPlaylistCover: View {
    let smart: SmartPlaylist
    let tracks: [Track]

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)

            ZStack {
                if tracks.isEmpty {
                    LinearGradient(
                        colors: [
                            smart.tint.opacity(0.95),
                            smart.tint.opacity(0.48),
                            Color(white: 0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    Image(systemName: smart.icon)
                        .font(.system(size: side * 0.30, weight: .light))
                        .foregroundStyle(.white.opacity(0.92))
                } else {
                    PlaylistMosaic(tracks: Array(tracks.prefix(4)))

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.16), .black.opacity(0.48)],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    VStack {
                        Spacer()
                        HStack {
                            Image(systemName: smart.icon)
                                .font(.system(size: max(10, side * 0.095), weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: side * 0.18, height: side * 0.18)
                                .background(.black.opacity(0.44), in: Circle())
                            Spacer()
                        }
                        .padding(side * 0.07)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(smart.tint.opacity(0.22))
    }
}

struct SmartPlaylistDetailView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerManager

    let smart: SmartPlaylist
    @Binding var showNowPlaying: Bool

    private var tracks: [Track] {
        smart.tracks(in: library)
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
                        RadialGradient(
                            colors: [smart.tint.opacity(0.22), .clear],
                            center: .top,
                            startRadius: 0,
                            endRadius: 340
                        )
                        .frame(height: 460)
                    }

                if tracks.isEmpty {
                    emptyState
                        .padding(.horizontal, 20)
                } else {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            ForEach(tracks) { track in
                                TrackRow(track: track, queue: tracks)
                                    .padding(.horizontal, 20)

                                if track.id != tracks.last?.id {
                                    Divider().opacity(0.32)
                                        .padding(.horizontal, 20)
                                }
                            }
                        } header: {
                            PinnedSectionHeader(title: "Tracks", count: tracks.count) {
                                EmptyView()
                            }
                        }
                    }
                }

                Spacer(minLength: 120)
            }
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .navigationTitle(smart.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var header: some View {
        VStack(spacing: 14) {
            SmartPlaylistCover(smart: smart, tracks: tracks)
                .frame(width: 222, height: 222)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.28), radius: 24, y: 12)

            VStack(spacing: 6) {
                Text("SMART PLAYLIST")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.3)
                    .foregroundStyle(.secondary)

                Text(smart.title)
                    .font(.system(size: 33, weight: .bold))
                    .tracking(-1.1)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

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
                    .accessibilityLabel("Shuffle \(smart.title)")

                    if !downloadable.isEmpty {
                        Button {
                            Task { await library.downloadAll(downloadable) }
                        } label: {
                            Group {
                                if isDownloading {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(.secondary)
                                } else {
                                    Image(systemName: "arrow.down.circle")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.primary)
                                }
                            }
                            .frame(width: 42, height: 42)
                            .contentShape(Circle())
                            .nativeGlass(Circle(), interactive: true)
                        }
                        .buttonStyle(MotifPressStyle(scale: 0.9))
                        .disabled(isDownloading)
                        .accessibilityLabel("Download \(smart.title)")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: smart.icon)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)

            Text(smart.emptyTitle)
                .font(.system(size: 21, weight: .semibold))
                .tracking(-0.3)

            Text(smart.emptyMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
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
