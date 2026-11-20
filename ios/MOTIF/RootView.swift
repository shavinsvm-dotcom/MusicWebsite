import SwiftUI
import UIKit

enum AppTab: String, Hashable {
    case forYou
    case home
    case library
    case playlists
    case search

    var title: String {
        switch self {
        case .forYou: return "For You"
        case .home: return "Home"
        case .library: return "Library"
        case .playlists: return "Playlists"
        case .search: return "Search"
        }
    }
}

struct RootView: View {
    @StateObject private var library = LibraryStore()
    @StateObject private var player = PlayerManager()
    @StateObject private var routeMonitor = AudioRouteMonitor()
    @State private var showNowPlaying = false
    @State private var selectedTab: AppTab = .forYou
    @State private var attemptedLyricsIDs: Set<UUID> = []
    @State private var miniPlayerFrames: [String: CGRect] = [:]

    private var playerPresented: Binding<Bool> {
        Binding(
            get: { showNowPlaying },
            set: { showNowPlaying = $0 }
        )
    }

    var body: some View {
        ZStack {
            tabs
                .tint(.primary)
                .environmentObject(library)
                .environmentObject(player)
                .environmentObject(player.progress)
                .overlay(alignment: .top) {
                    if !showNowPlaying {
                        AirPodsConnectOverlay(monitor: routeMonitor)
                    }
                }
                .allowsHitTesting(!showNowPlaying)

            if showNowPlaying {
                PlayerMorphOverlay(
                    backdropImage: currentBackdrop,
                    sourceFrame: miniPlayerFrames[playerTransitionID] ?? .zero,
                    onClose: { showNowPlaying = false }
                )
                .environmentObject(library)
                .environmentObject(player)
                .environmentObject(player.progress)
                .zIndex(20)
            }
        }
        .onPreferenceChange(MiniPlayerFramePreferenceKey.self) { frames in
            miniPlayerFrames = frames
        }
        .onOpenURL { url in
                guard url.scheme == "motif" else { return }
                switch url.host {
                case "nowplaying":
                    playerPresented.wrappedValue = true
                case "library":
                    selectedTab = .library
                default:
                    break
                }
            }
            .alert(
                "Playback stopped",
                isPresented: Binding(
                    get: { player.playbackError != nil },
                    set: { if !$0 { player.clearPlaybackError() } }
                )
            ) {
                Button("OK") { player.clearPlaybackError() }
            } message: {
                Text(player.playbackError ?? "")
            }
            .task {
                player.onTrackStarted = { track in
                    library.recordPlay(track)
                }
                player.automixContinuationProvider = { [weak library] current, excluded in
                    guard let library else { return nil }
                    let candidates = library.tracks.filter { !excluded.contains($0.id) }
                    let sameAlbum = candidates.filter {
                        !$0.album.isEmpty && $0.album == current.album
                    }
                    let sameArtist = candidates.filter { $0.artist == current.artist }
                    return sameAlbum.randomElement()
                        ?? sameArtist.randomElement()
                        ?? candidates.randomElement()
                }
                await library.refreshLocalMetadata()
                await library.refreshCloud()
            }
            .task(id: player.current?.id) {
                guard let track = player.current else { return }

                if let url = track.artworkURL {
                    await PlaybackBackdropCache.shared.prepare(for: url)
                }

                // Auto-fetch lyrics for any track that is not already
                // word-synced. Manual picks are never replaced. The resolver
                // waits for the real playback duration, then prefers a valid
                // word-synced match over an exact-but-plain record.
                let libraryTrack = library.tracks.first { existing in
                    existing.id == track.id
                        || (track.remoteID != nil && existing.remoteID == track.remoteID)
                } ?? track
                let currentLevel = LyricsService.syncLevel(for: libraryTrack)
                guard libraryTrack.lyricsSource != .manual,
                      currentLevel < .wordSynced,
                      !attemptedLyricsIDs.contains(libraryTrack.id)
                else { return }

                let audioDuration = await audioDurationForLyrics(for: libraryTrack)
                guard !Task.isCancelled, player.current?.id == track.id else { return }
                attemptedLyricsIDs.insert(libraryTrack.id)

                if let record = try? await LyricsService.findLyrics(
                    for: libraryTrack,
                    audioDuration: audioDuration
                ),
                   record.hasUsableLyrics {
                    // A manual pick can land while the network lookup is in
                    // flight. Re-read the library before replacing anything.
                    let latest = library.tracks.first(where: { $0.id == libraryTrack.id }) ?? libraryTrack
                    guard latest.lyricsSource != .manual,
                          LyricsService.syncLevel(for: latest) < record.syncLevel
                    else { return }

                    library.setLyrics(
                        record.lyricsText,
                        lyricsFile: record.lyricsfile,
                        source: .automatic,
                        for: latest
                    )
                }
            }
    }

    private func audioDurationForLyrics(for track: Track) async -> TimeInterval? {
        for _ in 0..<20 {
            guard !Task.isCancelled else { return nil }
            if player.isDurationLoaded {
                guard player.duration.isFinite, player.duration >= 1 else { break }
                return player.duration
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        // The item may never report a duration (for example, an unavailable
        // stream). In that case the metadata duration is the best available.
        if player.duration.isFinite, player.duration >= 1 {
            return player.duration
        }
        guard track.duration.isFinite, track.duration >= 1 else { return nil }
        return track.duration
    }

    private var currentBackdrop: UIImage? {
        guard let url = player.current?.artworkURL else { return nil }
        // Cache-only: rendering the backdrop synchronously would stall the
        // unfold animation. The async preparation task fills this in ahead
        // of the tap, and the artwork view is the fallback when it is cold.
        return PlaybackBackdropCache.shared.image(for: url)
    }

    @ViewBuilder
    private var tabs: some View {
        if #available(iOS 18.0, *) {
            TabView(selection: $selectedTab) {
                Tab("For You", systemImage: "sparkles", value: AppTab.forYou) {
                    forYouTab
                }

                Tab("Home", systemImage: "house", value: AppTab.home) {
                    homeTab
                }

                Tab("Library", systemImage: "square.stack", value: AppTab.library) {
                    libraryTab
                }

                Tab("Playlists", systemImage: "music.note.list", value: AppTab.playlists) {
                    playlistsTab
                }

                Tab(
                    "Search",
                    systemImage: "magnifyingglass",
                    value: AppTab.search,
                    role: .search
                ) {
                    searchTab
                }
            }
        } else {
            TabView(selection: $selectedTab) {
                forYouTab
                    .tabItem { Label("For You", systemImage: "sparkles") }
                    .tag(AppTab.forYou)

                homeTab
                    .tabItem { Label("Home", systemImage: "house") }
                    .tag(AppTab.home)

                libraryTab
                    .tabItem { Label("Library", systemImage: "square.stack") }
                    .tag(AppTab.library)

                playlistsTab
                    .tabItem { Label("Playlists", systemImage: "music.note.list") }
                    .tag(AppTab.playlists)

                searchTab
                    .tabItem { Label("Search", systemImage: "magnifyingglass") }
                    .tag(AppTab.search)
            }
        }
    }

    private var playerTransitionID: String {
        "now-playing-\(selectedTab.rawValue)"
    }

    private var forYouTab: some View {
        ForYouView(
            showNowPlaying: playerPresented,
            openSearch: { selectedTab = .search }
        )
        .modifier(MiniPlayerInset(
            showNowPlaying: playerPresented,
            currentID: player.current?.id,
                            transitionSourceID: "now-playing-\(AppTab.forYou.rawValue)"
        ))
    }

    private var homeTab: some View {
        HomeView(showNowPlaying: playerPresented)
            .modifier(MiniPlayerInset(
                showNowPlaying: playerPresented,
                currentID: player.current?.id,
                transitionSourceID: "now-playing-\(AppTab.home.rawValue)"
            ))
    }

    private var libraryTab: some View {
        LibraryView(showNowPlaying: playerPresented)
            .modifier(MiniPlayerInset(
                showNowPlaying: playerPresented,
                currentID: player.current?.id,
                transitionSourceID: "now-playing-\(AppTab.library.rawValue)"
            ))
    }

    private var playlistsTab: some View {
        PlaylistsView(showNowPlaying: playerPresented)
            .modifier(MiniPlayerInset(
                showNowPlaying: playerPresented,
                currentID: player.current?.id,
                transitionSourceID: "now-playing-\(AppTab.playlists.rawValue)"
            ))
    }

    private var searchTab: some View {
        SearchView(showNowPlaying: playerPresented)
            .modifier(MiniPlayerInset(
                showNowPlaying: playerPresented,
                currentID: player.current?.id,
                transitionSourceID: "now-playing-\(AppTab.search.rawValue)"
            ))
    }
}

private struct PlayerMorphOverlay: View {
    let backdropImage: UIImage?
    let sourceFrame: CGRect
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var expanded = false
    @State private var contentVisible = false
    @State private var closing = false

    private var shellColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.78)
            : Color.white.opacity(0.82)
    }

    var body: some View {
        GeometryReader { geometry in
            let screen = CGRect(origin: .zero, size: geometry.size)
            let fallback = CGRect(
                x: (screen.width - 360) / 2,
                y: screen.height - 96,
                width: 360,
                height: 50
            )
            let frame = expanded
                ? screen
                : (sourceFrame.isEmpty ? fallback : sourceFrame)

            ZStack {
                RoundedRectangle(
                    cornerRadius: expanded ? 0 : 25,
                    style: .continuous
                )
                .fill(shellColor)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)

                if contentVisible {
                    NowPlayingView(
                        backdropImage: backdropImage,
                        onClose: dismiss
                    )
                    .transition(.opacity)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .onAppear(perform: open)
    }

    @MainActor
    private func open() {
        expanded = false
        contentVisible = false
        closing = false

        DispatchQueue.main.async {
            withAnimation(
                .spring(response: 0.46, dampingFraction: 0.80, blendDuration: 0.08)
            ) {
                expanded = true
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.46) {
            guard !closing else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                contentVisible = true
            }
        }
    }

    @MainActor
    private func dismiss() {
        guard !closing else { return }
        closing = true

        withAnimation(.easeOut(duration: 0.14)) {
            contentVisible = false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(
                .spring(response: 0.42, dampingFraction: 0.86, blendDuration: 0.08)
            ) {
                expanded = false
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.58) {
            onClose()
        }
    }
}

private struct MiniPlayerInset: ViewModifier {
    @Binding var showNowPlaying: Bool
    let currentID: UUID?
    let transitionSourceID: String

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            MiniPlayer(
                showNowPlaying: $showNowPlaying,
                transitionSourceID: transitionSourceID
            )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(
                    .spring(response: 0.28, dampingFraction: 0.84),
                    value: currentID
                )
        }
    }
}
