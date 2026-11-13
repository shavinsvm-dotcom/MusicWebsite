import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerManager
    @Binding var showNowPlaying: Bool

    @State private var query = ""
    @State private var results: [Track] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var localMatches: [Track] {
        guard !trimmedQuery.isEmpty else { return [] }
        let needle = trimmedQuery.lowercased()
        return library.tracks
            .filter {
                $0.title.lowercased().contains(needle)
                    || $0.artist.lowercased().contains(needle)
                    || $0.album.lowercased().contains(needle)
            }
            .prefix(8)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if trimmedQuery.isEmpty {
                        browseHint
                    }

                    if !localMatches.isEmpty {
                        resultSection(
                            title: "In your library",
                            subtitle: nil,
                            tracks: localMatches
                        )
                    }

                    if isLoading {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Searching the catalog…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    }

                    if !results.isEmpty {
                        resultSection(
                            title: "Catalog",
                            subtitle: "Apple Music previews · 30 seconds",
                            tracks: results
                        )
                    }

                    if !trimmedQuery.isEmpty,
                       !isLoading,
                       results.isEmpty,
                       localMatches.isEmpty,
                       errorMessage == nil {
                        Text("No matches for “\(trimmedQuery)”.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Songs, artists, albums"
            )
            .task(id: query) {
                await runSearch()
            }
        }
    }

    private var browseHint: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)

            Text("Find something new.")
                .font(.system(size: 26, weight: .semibold, design: .serif))
                .tracking(-0.6)

            Text("Search the iTunes catalog for songs and artists. Previews play instantly and can be saved to your library.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(radius: 26)
    }

    private func resultSection(title: String, subtitle: String?, tracks: [Track]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle(title: title)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }

            VStack(spacing: 0) {
                ForEach(tracks) { track in
                    TrackRow(track: track, queue: tracks)
                    if track.id != tracks.last?.id {
                        Divider().opacity(0.35)
                    }
                }
            }
        }
    }

    @MainActor
    private func runSearch() async {
        let term = trimmedQuery
        guard term.count >= 2 else {
            results = []
            errorMessage = nil
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil

        try? await Task.sleep(nanoseconds: 350_000_000)
        guard !Task.isCancelled else { return }

        do {
            results = try await MusicAPI.search(term)
        } catch {
            if !Task.isCancelled {
                results = []
                errorMessage = error.localizedDescription
            }
        }

        isLoading = false
    }
}
