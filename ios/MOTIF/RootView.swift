import SwiftUI

struct RootView: View {
    @StateObject private var library = LibraryStore()
    @StateObject private var player = PlayerManager()
    @State private var showNowPlaying = false
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(showNowPlaying: $showNowPlaying)
                .tabItem { Label("Home", systemImage: "house") }
                .tag(0)

            SearchView(showNowPlaying: $showNowPlaying)
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(1)

            LibraryView(showNowPlaying: $showNowPlaying)
                .tabItem { Label("Library", systemImage: "square.stack") }
                .tag(2)
        }
        .tint(.primary)
        .environmentObject(library)
        .environmentObject(player)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            MiniPlayer(showNowPlaying: $showNowPlaying)
                .environmentObject(player)
        }
        .fullScreenCover(isPresented: $showNowPlaying) {
            NowPlayingView()
                .environmentObject(library)
                .environmentObject(player)
        }
        .task {
            await library.refreshCloud()
        }
    }
}
