import SwiftUI

enum AppTab: String, Hashable {
    case forYou
    case home
    case library
    case search

    var title: String {
        switch self {
        case .forYou: return "For You"
        case .home: return "Home"
        case .library: return "Library"
        case .search: return "Search"
        }
    }
}

struct RootView: View {
    @StateObject private var library = LibraryStore()
    @StateObject private var player = PlayerManager()
    @State private var showNowPlaying = false
    @State private var selectedTab: AppTab = .forYou

    var body: some View {
        tabs
            .tint(.primary)
            .environmentObject(library)
            .environmentObject(player)
            .fullScreenCover(isPresented: $showNowPlaying) {
                NowPlayingView()
                    .environmentObject(library)
                    .environmentObject(player)
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

                searchTab
                    .tabItem { Label("Search", systemImage: "magnifyingglass") }
                    .tag(AppTab.search)
            }
        }
    }

    private var forYouTab: some View {
        ForYouView(
            showNowPlaying: $showNowPlaying,
            openSearch: { selectedTab = .search }
        )
        .modifier(MiniPlayerInset(
            showNowPlaying: $showNowPlaying,
            currentID: player.current?.id
        ))
    }

    private var homeTab: some View {
        HomeView(showNowPlaying: $showNowPlaying)
            .modifier(MiniPlayerInset(
                showNowPlaying: $showNowPlaying,
                currentID: player.current?.id
            ))
    }

    private var libraryTab: some View {
        LibraryView(showNowPlaying: $showNowPlaying)
            .modifier(MiniPlayerInset(
                showNowPlaying: $showNowPlaying,
                currentID: player.current?.id
            ))
    }

    private var searchTab: some View {
        SearchView(showNowPlaying: $showNowPlaying)
            .modifier(MiniPlayerInset(
                showNowPlaying: $showNowPlaying,
                currentID: player.current?.id
            ))
    }
}

private struct MiniPlayerInset: ViewModifier {
    @Binding var showNowPlaying: Bool
    let currentID: UUID?

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            MiniPlayer(showNowPlaying: $showNowPlaying)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(
                    .spring(response: 0.40, dampingFraction: 0.82),
                    value: currentID
                )
        }
    }
}
