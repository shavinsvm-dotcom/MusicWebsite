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
        .environmentObject(library)
        .environmentObject(player)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomChrome(
                selectedTab: $selectedTab,
                showNowPlaying: $showNowPlaying,
                showSearch: $showSearch
            )
        }
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

    var body: some View {
        VStack(spacing: 8) {
            MiniPlayer(showNowPlaying: $showNowPlaying)

            HStack(spacing: 8) {
                HStack(spacing: 2) {
                    ForEach(AppTab.allCases) { tab in
                        tabButton(tab)
                    }
                }
                .padding(5)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.20), radius: 18, x: 0, y: 8)

                Button {
                    showSearch = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 56, height: 56)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle().strokeBorder(Color.white.opacity(0.13), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.20), radius: 18, x: 0, y: 8)
                .accessibilityLabel("Search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            withAnimation(.easeOut(duration: 0.18)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: tab.icon(selected: isSelected))
                    .font(.system(size: 17, weight: .semibold))
                    .frame(height: 20)

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
                    Capsule().fill(Color.primary.opacity(0.10))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
    }
}
