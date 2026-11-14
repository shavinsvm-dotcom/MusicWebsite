import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case forYou
    case home
    case library

    var id: String { rawValue }

    var title: String {
        switch self {
        case .forYou: return "For You"
        case .home: return "Home"
        case .library: return "Library"
        }
    }

    func icon(selected: Bool) -> String {
        switch self {
        case .forYou: return "sparkles"
        case .home: return selected ? "house.fill" : "house"
        case .library: return selected ? "square.stack.fill" : "square.stack"
        }
    }
}

struct RootView: View {
    @StateObject private var library = LibraryStore()
    @StateObject private var player = PlayerManager()
    @State private var showNowPlaying = false
    @State private var showSearch = false
    @State private var selectedTab: AppTab = .forYou

    var body: some View {
        TabView(selection: $selectedTab) {
            ForYouView(
                showNowPlaying: $showNowPlaying,
                openSearch: { showSearch = true }
            )
            .tag(AppTab.forYou)
            .toolbar(.hidden, for: .tabBar)

            HomeView(showNowPlaying: $showNowPlaying)
                .tag(AppTab.home)
                .toolbar(.hidden, for: .tabBar)

            LibraryView(showNowPlaying: $showNowPlaying)
                .tag(AppTab.library)
                .toolbar(.hidden, for: .tabBar)
        }
        .toolbar(.hidden, for: .tabBar)
        .tint(.primary)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomChrome(
                selectedTab: $selectedTab,
                showNowPlaying: $showNowPlaying,
                showSearch: $showSearch
            )
        }
        .environmentObject(library)
        .environmentObject(player)
        .fullScreenCover(isPresented: $showNowPlaying) {
            NowPlayingView()
                .environmentObject(library)
                .environmentObject(player)
        }
        .fullScreenCover(isPresented: $showSearch) {
            SearchView(showNowPlaying: $showNowPlaying)
                .environmentObject(library)
                .environmentObject(player)
        }
        .task {
            await library.refreshLocalMetadata()
            await library.refreshCloud()
        }
    }
}

private struct BottomChrome: View {
    @EnvironmentObject private var player: PlayerManager
    @Binding var selectedTab: AppTab
    @Binding var showNowPlaying: Bool
    @Binding var showSearch: Bool
    @Namespace private var tabIndicator

    var body: some View {
        VStack(spacing: 8) {
            MiniPlayer(showNowPlaying: $showNowPlaying)
                .transition(
                    .move(edge: .bottom)
                        .combined(with: .opacity)
                )

            HStack(spacing: 8) {
                HStack(spacing: 2) {
                    ForEach(AppTab.allCases) { tab in
                        tabButton(tab)
                    }
                }
                .padding(5)
                .nativeGlass(Capsule())
                .animation(
                    .spring(response: 0.38, dampingFraction: 0.78),
                    value: selectedTab
                )

                Button {
                    showSearch = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 56, height: 56)
                        .contentShape(Circle())
                }
                .buttonStyle(MotifPressStyle(scale: 0.88))
                .nativeGlass(Circle())
                .accessibilityLabel("Search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .animation(
            .spring(response: 0.40, dampingFraction: 0.82),
            value: player.current?.id
        )
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.76)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: tab.icon(selected: isSelected))
                    .font(.system(size: 17, weight: .semibold))
                    .frame(height: 20)
                    .motifBounce(isSelected)

                Text(tab.title)
                    .font(.system(size: 9.5, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color.primary.opacity(0.10))
                        .matchedGeometryEffect(id: "tabIndicator", in: tabIndicator)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(MotifPressStyle(scale: 0.88))
        .accessibilityLabel(tab.title)
    }
}
