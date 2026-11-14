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
    @Namespace private var playerTransition

    var body: some View {
        tabs
            .tint(.primary)
            .environmentObject(library)
            .environmentObject(player)
            .environmentObject(player.progress)
            .overlay(alignment: .top) {
                AirPodsConnectOverlay(monitor: routeMonitor)
            }
            .fullScreenCover(isPresented: $showNowPlaying) {
                NowPlayingView()
                    .environmentObject(library)
                    .environmentObject(player)
                    .environmentObject(player.progress)
                    .overlay(alignment: .top) {
                        AirPodsConnectOverlay(monitor: routeMonitor, topPadding: 54)
                    }
                    .modifier(
                        PlayerZoomDestination(
                            sourceID: playerTransitionID,
                            namespace: playerTransition
                        )
                    )
            }
            .task {
                await library.refreshLocalMetadata()
                await library.refreshCloud()
            }
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
            showNowPlaying: $showNowPlaying,
            openSearch: { selectedTab = .search }
        )
        .modifier(MiniPlayerInset(
            showNowPlaying: $showNowPlaying,
            currentID: player.current?.id,
            transitionSourceID: "now-playing-\(AppTab.forYou.rawValue)",
            transitionNamespace: playerTransition
        ))
    }

    private var homeTab: some View {
        HomeView(showNowPlaying: $showNowPlaying)
            .modifier(MiniPlayerInset(
                showNowPlaying: $showNowPlaying,
                currentID: player.current?.id,
                transitionSourceID: "now-playing-\(AppTab.home.rawValue)",
                transitionNamespace: playerTransition
            ))
    }

    private var libraryTab: some View {
        LibraryView(showNowPlaying: $showNowPlaying)
            .modifier(MiniPlayerInset(
                showNowPlaying: $showNowPlaying,
                currentID: player.current?.id,
                transitionSourceID: "now-playing-\(AppTab.library.rawValue)",
                transitionNamespace: playerTransition
            ))
    }

    private var playlistsTab: some View {
        PlaylistsView(showNowPlaying: $showNowPlaying)
            .modifier(MiniPlayerInset(
                showNowPlaying: $showNowPlaying,
                currentID: player.current?.id,
                transitionSourceID: "now-playing-\(AppTab.playlists.rawValue)",
                transitionNamespace: playerTransition
            ))
    }

    private var searchTab: some View {
        SearchView(showNowPlaying: $showNowPlaying)
            .modifier(MiniPlayerInset(
                showNowPlaying: $showNowPlaying,
                currentID: player.current?.id,
                transitionSourceID: "now-playing-\(AppTab.search.rawValue)",
                transitionNamespace: playerTransition
            ))
    }
}

private struct MiniPlayerInset: ViewModifier {
    @Binding var showNowPlaying: Bool
    let currentID: UUID?
    let transitionSourceID: String
    let transitionNamespace: Namespace.ID

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            MiniPlayer(
                showNowPlaying: $showNowPlaying,
                transitionSourceID: transitionSourceID,
                transitionNamespace: transitionNamespace
            )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(
                    .spring(response: 0.28, dampingFraction: 0.84),
                    value: currentID
                )
        }
    }
}

private struct PlayerZoomDestination: ViewModifier {
    let sourceID: String
    let namespace: Namespace.ID

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            content
        }
    }
}
