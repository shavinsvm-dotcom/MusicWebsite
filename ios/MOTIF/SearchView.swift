import SwiftUI
import UIKit

private enum SearchScope: String, CaseIterable, Identifiable, Hashable {
    case all
    case songs
    case artists
    case albums
    case playlists

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .songs: return "Songs"
        case .artists: return "Artists"
        case .albums: return "Albums"
        case .playlists: return "Playlists"
        }
    }
}

/// Everything the search surface shows, resolved in one pass so a body read
/// never filters and ranks the library more than once.
private struct SearchResults {
    var tracks: [Track] = []
    var artists: [LibraryArtistGroup] = []
    var albums: [LibraryAlbumGroup] = []
    var playlists: [Playlist] = []

    var isEmpty: Bool {
        tracks.isEmpty && artists.isEmpty && albums.isEmpty && playlists.isEmpty
    }
}

struct SearchView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerManager
    @Binding var showNowPlaying: Bool

    @State private var query = ""
    @State private var scope: SearchScope = .all
    @State private var recentSearches: [String] = UserDefaults.standard.stringArray(forKey: "motif.recentSearches") ?? []
    @State private var results = SearchResults()
    @State private var searchTask: Task<Void, Never>?

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// One pass over the library per settled query. Every section reads this
    /// same value, so a body pass can no longer filter, rank and sort the whole
    /// song list once per section.
    private func buildResults(for rawQuery: String) -> SearchResults {
        let text = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return SearchResults() }

        // Split the query once instead of once per candidate row.
        let tokens = LibrarySearch.tokens(in: text)

        let tracks = library.tracks
            .compactMap { track -> (track: Track, rank: Int)? in
                guard LibrarySearch.matches(tokens, in: [track.title, track.artist, track.album]) else {
                    return nil
                }
                return (track, trackRank(track, query: text))
            }
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
                return lhs.track.title.localizedCaseInsensitiveCompare(rhs.track.title) == .orderedAscending
            }
            .map { $0.track }

        // Artist and album groups are already built and cached per library
        // revision. Rebuilding them here made every keystroke walk the whole
        // song list again.
        let artists = library.artistGroups
            .compactMap { group -> (group: LibraryArtistGroup, rank: Int)? in
                guard LibrarySearch.matches(tokens, in: [group.name]) else { return nil }
                return (group, LibrarySearch.rank(title: group.name, query: text))
            }
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
                if lhs.group.count != rhs.group.count { return lhs.group.count > rhs.group.count }
                return lhs.group.name.localizedCaseInsensitiveCompare(rhs.group.name) == .orderedAscending
            }
            .map { $0.group }

        let albums = library.albumGroups
            .compactMap { group -> (group: LibraryAlbumGroup, rank: Int)? in
                guard LibrarySearch.matches(tokens, in: [group.title, group.artist]) else { return nil }
                return (group, LibrarySearch.rank(title: group.title, query: text))
            }
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
                return lhs.group.title.localizedCaseInsensitiveCompare(rhs.group.title) == .orderedAscending
            }
            .map { $0.group }

        let playlists = library.playlists
            .compactMap { playlist -> (playlist: Playlist, rank: Int)? in
                guard LibrarySearch.matches(tokens, in: [playlist.name, playlist.description]) else {
                    return nil
                }
                return (playlist, LibrarySearch.rank(title: playlist.name, query: text))
            }
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
                return lhs.playlist.name.localizedCaseInsensitiveCompare(rhs.playlist.name) == .orderedAscending
            }
            .map { $0.playlist }

        return SearchResults(tracks: tracks, artists: artists, albums: albums, playlists: playlists)
    }

    private func trackRank(_ track: Track, query: String) -> Int {
        let titleRank = LibrarySearch.rank(title: track.title, query: query)
        if titleRank < 3 { return titleRank }
        if track.artist.localizedStandardContains(query) { return 3 }
        if track.album.localizedStandardContains(query) { return 4 }
        return 5
    }

    /// Wait for a short pause in typing, then search once. Previously every
    /// keystroke ran a full scan and sort before the next character arrived.
    private func scheduleSearch(_ rawQuery: String) {
        searchTask?.cancel()

        guard !rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            results = SearchResults()
            return
        }

        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            results = buildResults(for: rawQuery)
        }
    }

    private func refreshResultsNow() {
        searchTask?.cancel()
        results = buildResults(for: query)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if trimmedQuery.isEmpty {
                        if !recentSearches.isEmpty {
                            recentSearchesSection
                        }

                        browseHint

                        if !library.tracks.isEmpty {
                            resultSection(
                                title: "Your library",
                                subtitle: "\(library.tracks.count) tracks",
                                tracks: Array(library.tracks.prefix(12))
                            )
                        }
                    } else {
                        Group {
                            switch scope {
                        case .all:
                            if !results.artists.isEmpty {
                                artistSection
                            }
                            if !results.albums.isEmpty {
                                albumSection
                            }
                            if !results.playlists.isEmpty {
                                playlistSection
                            }
                            if !results.tracks.isEmpty {
                                resultSection(
                                    title: "Songs",
                                    subtitle: nil,
                                    tracks: results.tracks
                                )
                            }
                        case .songs:
                            resultSection(
                                title: "Songs",
                                subtitle: nil,
                                tracks: results.tracks
                            )
                        case .artists:
                            artistSection
                        case .albums:
                            albumSection
                        case .playlists:
                            playlistSection
                        }
                        }
                        .id(scope)
                        .transition(.opacity)

                        if results.isEmpty {
                            emptyResults
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .background(AppBackground())
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.large)
            .nativeScrollHeader()
            .searchable(
                text: $query,
                prompt: "Songs, artists, albums, playlists"
            )
            .minimizedSearch()
            .searchScopes($scope) {
                Text("All").tag(SearchScope.all)
                Text("Songs").tag(SearchScope.songs)
                Text("Artists").tag(SearchScope.artists)
                Text("Albums").tag(SearchScope.albums)
                Text("Playlists").tag(SearchScope.playlists)
            }
            .onSubmit(of: .search) {
                remember(trimmedQuery)
            }
            .onChange(of: query) { newValue in
                scheduleSearch(newValue)
            }
            .onChange(of: library.tracks.count) { _ in
                guard !trimmedQuery.isEmpty else { return }
                refreshResultsNow()
            }
            .onChange(of: library.playlists.count) { _ in
                guard !trimmedQuery.isEmpty else { return }
                refreshResultsNow()
            }
            .onDisappear {
                searchTask?.cancel()
            }
        }
    }

    private var recentSearchesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Recent searches") {
                GlassActionButton(
                    title: "Clear",
                    systemImage: "xmark",
                    accessibilityLabel: "Clear recent searches"
                ) {
                    recentSearches = []
                    UserDefaults.standard.removeObject(forKey: "motif.recentSearches")
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(recentSearches, id: \.self) { term in
                        Button {
                            query = term
                        } label: {
                            Text(term)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .nativeGlass(Capsule(), interactive: true)
                        }
                        .buttonStyle(MotifPressStyle(scale: 0.95))
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var artistSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Artists") {
                Text("\(results.artists.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if results.artists.isEmpty {
                emptyScope("No artists match this search.")
            } else {
                CarouselScroll {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(results.artists) { artist in
                            NavigationLink {
                                LibraryArtistDetailView(
                                    artistName: artist.name,
                                    showNowPlaying: $showNowPlaying
                                )
                            } label: {
                                LibraryArtistCard(artist: artist)
                            }
                            .buttonStyle(MotifPressStyle(scale: 0.96, opacity: 0.92))
                            .carouselItemTransition()
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
    }

    private var albumSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Albums") {
                Text("\(results.albums.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if results.albums.isEmpty {
                emptyScope("No albums match this search.")
            } else {
                CarouselScroll {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(results.albums) { album in
                            NavigationLink {
                                LibraryAlbumDetailView(
                                    album: album,
                                    showNowPlaying: $showNowPlaying
                                )
                            } label: {
                                LibraryAlbumCard(album: album)
                            }
                            .buttonStyle(MotifPressStyle(scale: 0.96, opacity: 0.92))
                            .carouselItemTransition()
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
    }

    private var playlistSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Playlists") {
                Text("\(results.playlists.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if results.playlists.isEmpty {
                emptyScope("No playlists match this search.")
            } else {
                CarouselScroll {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(results.playlists) { playlist in
                            NavigationLink {
                                PlaylistDetailView(
                                    playlistID: playlist.id,
                                    showNowPlaying: $showNowPlaying
                                )
                            } label: {
                                PlaylistTile(
                                    playlist: playlist,
                                    tracks: library.tracks(in: playlist)
                                )
                                .frame(width: 146)
                            }
                            .buttonStyle(MotifPressStyle(scale: 0.97, opacity: 0.92))
                            .carouselItemTransition()
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
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
                if !tracks.isEmpty {
                    Text("\(tracks.count)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            if tracks.isEmpty {
                emptyScope("No \(title.lowercased()) match this search.")
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(tracks) { track in
                        TrackRow(track: track, queue: tracks, player: player, showNowPlaying: $showNowPlaying)
                        if track.id != tracks.last?.id {
                            Divider().opacity(0.35)
                        }
                    }
                }
            }
        }
    }

    private var browseHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Find anything.")
                .font(.system(size: 24, weight: .semibold))
                .tracking(-0.5)

            Text("Search your songs, albums, artists, and playlists.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyResults: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No matches for “\(trimmedQuery)”.")
                .font(.subheadline.weight(.semibold))

            Text("Try a shorter title, artist, album or playlist name.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private func emptyScope(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.vertical, 6)
    }

    private func remember(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return }

        var next = recentSearches.filter {
            $0.caseInsensitiveCompare(trimmed) != .orderedSame
        }
        next.insert(trimmed, at: 0)
        recentSearches = Array(next.prefix(8))
        UserDefaults.standard.set(recentSearches, forKey: "motif.recentSearches")
    }

}
