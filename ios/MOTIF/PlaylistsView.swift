import PhotosUI
import SwiftUI
import UIKit

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

private struct PlaylistRoute: Hashable {
    let id: UUID
}

struct PlaylistsView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerManager
    @Binding var showNowPlaying: Bool

    @State private var showCreatePlaylist = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    smartPlaylistsSection
                    yourPlaylistsSection
                }
                .screenEntrance()
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .navigationTitle("Playlists")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: PlaylistRoute.self) { route in
                PlaylistDetailView(
                    playlistID: route.id,
                    showNowPlaying: $showNowPlaying
                )
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreatePlaylist = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New playlist")
                }
            }
            .sheet(isPresented: $showCreatePlaylist) {
                PlaylistEditorView()
            }
        }
    }

    private var smartPlaylistsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle(title: "Smart Playlists")
                Spacer()
                Text("\(SmartPlaylist.allCases.count)")
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }

            SmartPlaylistShelf(showNowPlaying: $showNowPlaying)
                .padding(.vertical, 10)
                .nativeGlass(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                )
        }
    }

    private var yourPlaylistsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle(title: "Your Playlists")
                Spacer()
                Text("\(library.playlists.count)")
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }

            if library.playlists.isEmpty {
                emptyState
                    .padding(.horizontal, 18)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .nativeGlass(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                    )
            } else {
                playlistPanel
            }
        }
    }

    @ViewBuilder
    private func playlistRow(_ playlist: Playlist) -> some View {
        let tracks = library.tracks(in: playlist)

        NavigationLink(value: PlaylistRoute(id: playlist.id)) {
            PlaylistRow(playlist: playlist, tracks: tracks)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
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

    private var playlistPanel: some View {
        VStack(spacing: 0) {
            ForEach(library.playlists) { playlist in
                playlistRow(playlist)

                if playlist.id != library.playlists.last?.id {
                    Divider()
                        .padding(.leading, 84)
                        .padding(.trailing, 12)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .nativeGlass(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note.list")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)

            Text("No playlists yet")
                .font(.headline)

            Text("Create a playlist from your library and it will appear here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            GlassActionButton(
                title: "New Playlist",
                systemImage: "plus",
                prominent: true
            ) {
                showCreatePlaylist = true
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func play(_ playlist: Playlist) {
        let tracks = library.tracks(in: playlist)
        guard let first = tracks.first else { return }
        player.play(first, queue: tracks)
        showNowPlaying = true
    }
}

private struct SmartPlaylistShelf: View {
    @EnvironmentObject private var library: LibraryStore
    @Binding var showNowPlaying: Bool

    var body: some View {
        CarouselScroll {
            LazyHStack(alignment: .top, spacing: 14) {
                ForEach(SmartPlaylist.allCases) { smart in
                    NavigationLink {
                        SmartPlaylistDetailView(
                            smart: smart,
                            showNowPlaying: $showNowPlaying
                        )
                    } label: {
                        SmartPlaylistShelfItem(
                            smart: smart,
                            tracks: smart.tracks(in: library)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
        }
    }
}

private struct SmartPlaylistShelfItem: View {
    let smart: SmartPlaylist
    let tracks: [Track]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SmartPlaylistCover(smart: smart, tracks: tracks)
                .frame(width: 104, height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(smart.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(width: 104, alignment: .leading)

            Text(tracks.count == 1 ? "1 song" : "\(tracks.count) songs")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 104, alignment: .leading)
        }
        .frame(width: 104, alignment: .leading)
    }
}

private struct PlaylistRow: View {
    let playlist: Playlist
    let tracks: [Track]

    private var metadata: String {
        let countText = tracks.count == 1 ? "1 song" : "\(tracks.count) songs"
        let total = Int(tracks.reduce(0) { $0 + $1.duration }.rounded())
        guard total > 0 else { return countText }
        if total < 60 { return "\(countText) · <1 min" }

        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(countText) · \(hours) hr \(minutes) min"
        }
        return "\(countText) · \(minutes) min"
    }

    var body: some View {
        HStack(spacing: 14) {
            PlaylistArtwork(playlist: playlist, tracks: tracks)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(playlist.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(metadata)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
    }
}

struct PlaylistArtwork: View {
    let playlist: Playlist
    let tracks: [Track]

    var body: some View {
        if let cover = playlist.customCoverURL {
            ArtworkView(url: cover, seed: playlist.name)
                .id(cover)
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

struct PlaylistTile: View {
    let playlist: Playlist
    let tracks: [Track]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PlaylistArtwork(playlist: playlist, tracks: tracks)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(playlist.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(tracks.count == 1 ? "1 song" : "\(tracks.count) songs")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private var playlistArtworkURL: URL? {
        playlist?.customCoverURL ?? tracks.compactMap(\.artworkURL).first
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    PlaylistArtwork(playlist: playlist ?? Playlist(name: "Playlist"), tracks: tracks)
                        .frame(width: 240, height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.34),
                                            Color.white.opacity(0.06),
                                            Color.white.opacity(0.16)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.8
                                )
                        }
                        .shadow(color: .black.opacity(0.18), radius: 18, y: 9)
                        .padding(7)
                        .nativeGlass(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .overlay(alignment: .bottomTrailing) {
                            Button {
                                generateCover()
                            } label: {
                                Image(systemName: "wand.and.stars")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .frame(width: 40, height: 40)
                                    .nativeGlass(Circle(), interactive: true)
                            }
                            .buttonStyle(MotifPressStyle(scale: 0.9))
                            .offset(x: 10, y: 10)
                            .accessibilityLabel("Generate playlist cover")
                        }

                    if let description = playlist?.description, !description.isEmpty {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(subtitle)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)

                    if !tracks.isEmpty {
                        HStack(spacing: 2) {
                            Button {
                                play(shuffled: false)
                            } label: {
                                Label("Play", systemImage: "play.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(MotifPressStyle(scale: 0.90, opacity: 0.9))
                            .accessibilityLabel("Play playlist")

                            Divider()
                                .frame(height: 18)

                            Button {
                                play(shuffled: true)
                            } label: {
                                Image(systemName: "shuffle")
                                    .frame(width: 38, height: 36)
                            }
                            .buttonStyle(MotifPressStyle(scale: 0.90, opacity: 0.9))
                            .accessibilityLabel("Shuffle playlist")

                            if tracks.contains(where: { $0.isCloud }) {
                                Button {
                                    Task { await library.downloadAll(downloadable) }
                                } label: {
                                    Group {
                                        if isDownloading {
                                            ProgressView()
                                                .controlSize(.small)
                                        } else {
                                            Image(systemName: downloadable.isEmpty ? "checkmark.circle.fill" : "arrow.down.circle")
                                                .frame(width: 38, height: 36)
                                        }
                                    }
                                }
                                .buttonStyle(MotifPressStyle(scale: 0.90, opacity: 0.9))
                                .disabled(downloadable.isEmpty || isDownloading)
                                .accessibilityLabel(downloadable.isEmpty ? "Playlist downloaded" : "Download playlist")
                            }
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                        .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 20)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 18, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if tracks.isEmpty {
                Section {
                    Text("No songs yet. Add songs from any song’s menu and they will appear here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                        .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(tracks) { track in
                        PlaylistTrackRow(
                            track: track,
                            queue: tracks,
                            playlistID: playlistID,
                            showNowPlaying: $showNowPlaying
                        )
                        .listRowBackground(Color.clear)
                    }
                } header: {
                    Text("Tracks")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                        .padding(.leading, 4)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background {
            DetailBackdrop(artworkURL: playlistArtworkURL)
        }
        .navigationTitle(playlist?.name ?? "Playlist")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let playlist {
                        Section {
                            Button {
                                generateCover()
                            } label: {
                                Label(
                                    playlist.customCoverURL == nil ? "Generate cover" : "Generate new cover",
                                    systemImage: "wand.and.stars"
                                )
                            }

                            if playlist.customCoverURL != nil {
                                Button {
                                    library.clearPlaylistCover(playlist.id)
                                    MotifHaptics.play(.light)
                                } label: {
                                    Label("Use song artwork instead", systemImage: "square.grid.2x2")
                                }
                            }
                        }

                        Section {
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
                        }

                        Section {
                            Button {
                                library.duplicatePlaylist(playlist)
                                MotifHaptics.play(.light)
                            } label: {
                                Label("Duplicate", systemImage: "plus.square.on.square")
                            }

                            ShareLink(item: "\(playlist.name) — a playlist on Lilt") {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                        }

                        Section {
                            Button(role: .destructive) {
                                library.deletePlaylist(playlist)
                                dismiss()
                            } label: {
                                Label("Delete playlist", systemImage: "trash")
                            }
                        }
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

    private var subtitle: String {
        let count = tracks.count
        let songText = count == 1 ? "1 song" : "\(count) songs"
        guard let durationText else { return songText }
        return "\(songText) · \(durationText)"
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

    @MainActor
    private func generateCover() {
        guard let playlist else { return }
        Task {
            guard await library.generatePlaylistCover(playlist.id) else { return }
            MotifHaptics.play(.success)
        }
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
                    ZStack(alignment: .bottomTrailing) {
                        ArtworkView(url: track.artworkURL, seed: track.title + track.artist)
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                        if isCurrent {
                            PlayingWaveform(isPlaying: player.isPlaying, color: .white)
                                .frame(width: 20, height: 20)
                                .background(.black.opacity(0.52), in: Circle())
                                .padding(3)
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
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
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background {
            if isCurrent {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.clear)
                    .nativeGlass(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                    }
            }
        }
        .animation(.easeOut(duration: 0.22), value: isCurrent)
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
    @State private var coverVariant = 0

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
                            .frame(width: 156, height: 156)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                            }
                            .overlay(alignment: .bottomTrailing) {
                                Button {
                                    generateCover()
                                } label: {
                                    Image(systemName: "wand.and.stars")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(.primary)
                                        .frame(width: 36, height: 36)
                                        .nativeGlass(Circle(), interactive: true)
                                }
                                .buttonStyle(MotifPressStyle(scale: 0.9))
                                .offset(x: 8, y: 8)
                                .accessibilityLabel("Generate cover")
                            }
                            .shadow(color: .black.opacity(0.18), radius: 14, y: 7)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .padding(.vertical, 10)
                }

                Section("Cover") {
                    Button {
                        generateCover()
                    } label: {
                        Label("Generate artwork", systemImage: "wand.and.stars")
                    }

                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("Choose photo", systemImage: "photo")
                    }

                    if hasCover {
                        Button("Remove cover", role: .destructive) {
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

    private var hasCover: Bool {
        coverData != nil || (!removeCover && playlist?.customCoverURL != nil)
    }

    /// Renders the same on-device artwork used by the detail menu, but keeps
    /// it as pending data until the playlist is saved.
    @MainActor
    private func generateCover() {
        let variant = coverVariant
        coverVariant += 1
        let coverName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Playlist"
            : name

        Task {
            let data = await Task.detached(priority: .userInitiated) {
                PlaylistCoverGenerator.jpegData(name: coverName, variant: variant)
            }.value

            guard let data else { return }
            coverData = data
            selectedPhoto = nil
            removeCover = false
            MotifHaptics.play(.light)
        }
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

struct SmartPlaylistCover: View {
    let smart: SmartPlaylist
    let tracks: [Track]

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)

            ZStack(alignment: .bottomLeading) {
                if tracks.isEmpty {
                    LinearGradient(
                        colors: [
                            smart.tint.opacity(0.92),
                            smart.tint.opacity(0.40),
                            Color(white: 0.07)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    Image(systemName: smart.icon)
                        .font(.system(size: side * 0.28, weight: .light))
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    PlaylistMosaic(tracks: Array(tracks.prefix(4)))

                    Image(systemName: smart.icon)
                        .font(.system(size: max(10, side * 0.08), weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: side * 0.17, height: side * 0.17)
                        .background(.black.opacity(0.38), in: Circle())
                        .padding(side * 0.07)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(smart.tint.opacity(0.16))
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

    private var artworkURL: URL? {
        tracks.compactMap(\.artworkURL).first
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    SmartPlaylistCover(smart: smart, tracks: tracks)
                        .frame(width: 200, height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.32),
                                            Color.white.opacity(0.05),
                                            Color.white.opacity(0.14)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.8
                                )
                        }
                        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
                        .padding(7)
                        .nativeGlass(RoundedRectangle(cornerRadius: 26, style: .continuous))

                    Text(subtitle)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)

                    if !tracks.isEmpty {
                        HStack(spacing: 2) {
                            Button {
                                play(shuffled: false)
                            } label: {
                                Label("Play", systemImage: "play.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Play \(smart.title)")

                            Divider()
                                .frame(height: 18)

                            Button {
                                play(shuffled: true)
                            } label: {
                                Image(systemName: "shuffle")
                                    .frame(width: 38, height: 36)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Shuffle \(smart.title)")

                            if !downloadable.isEmpty {
                                Button {
                                    Task { await library.downloadAll(downloadable) }
                                } label: {
                                    Group {
                                        if isDownloading {
                                            ProgressView()
                                                .controlSize(.small)
                                        } else {
                                            Image(systemName: "arrow.down.circle")
                                                .frame(width: 38, height: 36)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .disabled(isDownloading)
                                .accessibilityLabel("Download \(smart.title)")
                            }
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                        .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 20)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 18, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if tracks.isEmpty {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: smart.icon)
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(.tertiary)

                        Text(smart.emptyTitle)
                            .font(.headline)

                        Text(smart.emptyMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(tracks) { track in
                        TrackRow(track: track, queue: tracks, showNowPlaying: $showNowPlaying)
                            .listRowBackground(Color.clear)
                    }
                } header: {
                    Text("Tracks")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                        .padding(.leading, 4)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background {
            DetailBackdrop(artworkURL: artworkURL)
        }
        .navigationTitle(smart.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
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
