import SwiftUI

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
    @Namespace private var playerHero

    var body: some View {
        ZStack {
            tabs
                .tint(.primary)
                .overlay(alignment: .top) {
                    if !showNowPlaying {
                        AirPodsConnectOverlay(monitor: routeMonitor)
                    }
                }

            if showNowPlaying {
                ZStack {
                    Color.black.ignoresSafeArea()

                    NowPlayingView(
                        heroNamespace: playerHero,
                        heroID: playerHeroID,
                        onClose: closePlayer
                    )
                    .overlay(alignment: .top) {
                        AirPodsConnectOverlay(monitor: routeMonitor, topPadding: 54)
                    }
                }
                .zIndex(20)
                .transition(.opacity)
            }
        }
        .environmentObject(library)
        .environmentObject(player)
        .environmentObject(player.progress)
        .animation(.spring(response: 0.46, dampingFraction: 0.90), value: showNowPlaying)
        .task {
            await library.refreshLocalMetadata()
            await library.refreshCloud()
        }
    }

    private func closePlayer() {
        showNowPlaying = false
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

    private var playerHeroID: String {
        "player-cover-\(selectedTab.rawValue)"
    }

    private var forYouTab: some View {
        ForYouView(
            showNowPlaying: $showNowPlaying,
            openSearch: { selectedTab = .search }
        )
        .modifier(MiniPlayerInset(
            showNowPlaying: $showNowPlaying,
            currentID: player.current?.id,
            heroID: "player-cover-\(AppTab.forYou.rawValue)",
            heroNamespace: playerHero
        ))
    }

    private var homeTab: some View {
        HomeView(showNowPlaying: $showNowPlaying)
            .modifier(MiniPlayerInset(
                showNowPlaying: $showNowPlaying,
                currentID: player.current?.id,
                heroID: "player-cover-\(AppTab.home.rawValue)",
                heroNamespace: playerHero
            ))
    }

    private var libraryTab: some View {
        LibraryView(showNowPlaying: $showNowPlaying)
            .modifier(MiniPlayerInset(
                showNowPlaying: $showNowPlaying,
                currentID: player.current?.id,
                heroID: "player-cover-\(AppTab.library.rawValue)",
                heroNamespace: playerHero
            ))
    }

    private var playlistsTab: some View {
        PlaylistsView(showNowPlaying: $showNowPlaying)
            .modifier(MiniPlayerInset(
                showNowPlaying: $showNowPlaying,
                currentID: player.current?.id,
                heroID: "player-cover-\(AppTab.playlists.rawValue)",
                heroNamespace: playerHero
            ))
    }

    private var searchTab: some View {
        SearchView(showNowPlaying: $showNowPlaying)
            .modifier(MiniPlayerInset(
                showNowPlaying: $showNowPlaying,
                currentID: player.current?.id,
                heroID: "player-cover-\(AppTab.search.rawValue)",
                heroNamespace: playerHero
            ))
    }
}

private struct MiniPlayerInset: ViewModifier {
    @Binding var showNowPlaying: Bool
    let currentID: UUID?
    let heroID: String
    let heroNamespace: Namespace.ID

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            MiniPlayer(
                showNowPlaying: $showNowPlaying,
                heroID: heroID,
                heroNamespace: heroNamespace
            )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(
                    .spring(response: 0.28, dampingFraction: 0.84),
                    value: currentID
                )
        }
    }
}

