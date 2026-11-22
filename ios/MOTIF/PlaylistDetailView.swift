import SwiftUI

/// Reports where the large playlist title sits so the navigation bar can
/// reveal a compact title once the header scrolls away.
private struct PlaylistTitlePositionKey: PreferenceKey {
    static var defaultValue: CGFloat = .greatestFiniteMagnitude

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
    }
}

struct PlaylistDetailView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let playlistID: UUID
    @Binding var showNowPlaying: Bool

    @State private var showEditDetails = false
    @State private var showEditTracks = false
    @State private var showAddSongs = false
    @State private var showsInlineTitle = false

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
            headerSection

            if tracks.isEmpty {
                emptySection
            } else {
                tracksSection
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .coordinateSpace(name: "playlistDetail")
        .background {
            DetailBackdrop(artworkURL: playlistArtworkURL)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .nativeScrollHeader()
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(playlist?.name ?? "Playlist")
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                    .opacity(showsInlineTitle ? 1 : 0)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: showsInlineTitle)
                    .accessibilityHidden(!showsInlineTitle)
            }

            ToolbarItem(placement: .topBarTrailing) {
                menu
            }
        }
        .onPreferenceChange(PlaylistTitlePositionKey.self) { maxY in
            let shouldShow = maxY < 86
            guard shouldShow != showsInlineTitle else { return }
            withAnimation(reduceMotion ? nil : MotifMotion.control) {
                showsInlineTitle = shouldShow
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
        .sheet(isPresented: $showAddSongs) {
            AddSongsView(playlistID: playlistID)
                .environmentObject(library)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                artworkHero

                VStack(alignment: .leading, spacing: 7) {
                    Text("PLAYLIST")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.7)
                        .foregroundStyle(.secondary)

                    Text(playlist?.name ?? "Playlist")
                        .font(.system(size: 28, weight: .bold))
                        .tracking(-0.7)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .background {
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: PlaylistTitlePositionKey.self,
                                    value: proxy.frame(in: .named("playlistDetail")).maxY
                                )
                            }
                        }

                    if let description = playlist?.description, !description.isEmpty {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }

                if !tracks.isEmpty {
                    actions
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 12)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private var artworkHero: some View {
        PlaylistArtwork(
            playlist: playlist ?? Playlist(name: "Playlist"),
            tracks: tracks,
            card: false
        )
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.28),
                            Color.white.opacity(0.05),
                            Color.white.opacity(0.13)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.7
                )
        }
        .shadow(color: .black.opacity(0.20), radius: 20, y: 12)
        .overlay(alignment: .bottomTrailing) {
            Button {
                generateCover()
            } label: {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 38, height: 38)
                    .nativeGlass(Circle(), interactive: true)
            }
            .buttonStyle(MotifPressStyle(scale: 0.9))
            .padding(12)
            .accessibilityLabel("Generate playlist cover")
        }
    }

    private var actions: some View {
        GlassGroup(spacing: 8) {
            HStack(spacing: 8) {
                LiltPrimaryButton(
                    title: "Play",
                    systemImage: "play.fill",
                    height: 38,
                    expands: false,
                    accessibilityLabel: "Play playlist"
                ) {
                    play(shuffled: false)
                }

                circleButton("shuffle", label: "Shuffle playlist") {
                    play(shuffled: true)
                }

                circleButton("plus", label: "Add songs") {
                    showAddSongs = true
                }

                if tracks.contains(where: { $0.isCloud }) {
                    Button {
                        Task { await library.downloadAll(downloadable) }
                    } label: {
                        Group {
                            if isDownloading {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.primary)
                            } else {
                                Image(systemName: downloadable.isEmpty ? "checkmark.circle.fill" : "arrow.down.circle")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.primary)
                            }
                        }
                        .frame(width: 38, height: 38)
                        .nativeGlass(Circle(), interactive: true)
                    }
                    .buttonStyle(MotifPressStyle(scale: 0.9, opacity: 0.9))
                    .disabled(downloadable.isEmpty || isDownloading)
                    .accessibilityLabel(downloadable.isEmpty ? "Playlist downloaded" : "Download playlist")
                }

                Spacer(minLength: 0)
            }
        }
    }

    private func circleButton(
        _ systemImage: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 38, height: 38)
                .nativeGlass(Circle(), interactive: true)
        }
        .buttonStyle(MotifPressStyle(scale: 0.9, opacity: 0.9))
        .accessibilityLabel(label)
    }

    // MARK: - Tracks

    private var tracksSection: some View {
        Section {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                PlaylistTrackRow(
                    track: track,
                    index: index + 1,
                    queue: tracks,
                    playlistID: playlistID,
                    showNowPlaying: $showNowPlaying,
                    showsDivider: index < tracks.count - 1
                )
                .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        library.toggleFavorite(track)
                        MotifHaptics.play(.light)
                    } label: {
                        Label(
                            library.isFavorite(track) ? "Unfavorite" : "Favorite",
                            systemImage: library.isFavorite(track) ? "heart.slash" : "heart"
                        )
                    }
                    .tint(.gray)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        library.remove(track, from: playlistID)
                    } label: {
                        Label("Remove", systemImage: "minus.circle")
                    }
                    .tint(.gray)
                }
            }
        } header: {
            HStack(spacing: 8) {
                Text("Tracks")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("\(tracks.count)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 8)

                Button {
                    showEditTracks = true
                } label: {
                    HStack(spacing: 4) {
                        Text("Edit")
                            .font(.system(size: 12, weight: .semibold))
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .nativeGlass(Capsule(), interactive: true)
                }
                .buttonStyle(MotifPressStyle(scale: 0.94))
                .accessibilityLabel("Edit track order")
            }
            .textCase(nil)
            .listRowInsets(EdgeInsets())
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 4)
        }
    }

    // MARK: - Empty

    private var emptySection: some View {
        Section {
            VStack(spacing: 14) {
                EmptyPlaylistArtwork()

                Text("No songs yet")
                    .font(.system(size: 21, weight: .semibold))
                    .tracking(-0.3)

                Text("Add a few songs from your library and they'll line up here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)

                LiltPrimaryButton(
                    title: "Add Songs",
                    systemImage: "plus",
                    height: 42,
                    expands: false
                ) {
                    showAddSongs = true
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    // MARK: - Toolbar menu

    private var menu: some View {
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
                        showAddSongs = true
                    } label: {
                        Label("Add songs", systemImage: "plus")
                    }

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

    // MARK: - Data

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
    let index: Int
    let queue: [Track]
    let playlistID: UUID
    @Binding var showNowPlaying: Bool
    let showsDivider: Bool

    private var isCurrent: Bool {
        player.current?.id == track.id
    }

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if isCurrent {
                    PlayingWaveform(isPlaying: player.isPlaying, color: .primary)
                } else {
                    Text("\(index)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 18, alignment: .center)
            .accessibilityHidden(true)

            Button {
                player.play(track, queue: queue)
                showNowPlaying = true
            } label: {
                HStack(spacing: 11) {
                    ArtworkView(
                        url: track.artworkURL,
                        seed: track.title + track.artist,
                        thumbnail: true
                    )
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
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

            trackMenu
        }
        .padding(.leading, 4)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
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
        .overlay(alignment: .bottom) {
            if showsDivider, !isCurrent {
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 0.5)
                    .padding(.leading, 74)
            }
        }
        .animation(.easeOut(duration: 0.22), value: isCurrent)
    }

    private var trackMenu: some View {
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
                .foregroundStyle(.primary)
                .frame(width: 30, height: 30)
                .rowControl(Circle())
                .frame(width: 32, height: 38)
                .contentShape(Rectangle())
        }
    }
}

private struct EmptyPlaylistArtwork: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.045))
                .frame(width: 88, height: 88)
                .rotationEffect(.degrees(-9))
                .offset(x: -18, y: 3)

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.065))
                .frame(width: 88, height: 88)
                .rotationEffect(.degrees(7))
                .offset(x: 16, y: 4)

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.085))
                .frame(width: 92, height: 92)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.6)
                }
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.secondary)
                }
        }
        .frame(height: 118)
        .accessibilityHidden(true)
    }
}
