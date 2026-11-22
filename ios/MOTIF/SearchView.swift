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

struct SearchView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerManager
    @Binding var showNowPlaying: Bool

    @State private var query = ""
    @State private var scope: SearchScope = .all
    @State private var recentSearches: [String] = UserDefaults.standard.stringArray(forKey: "motif.recentSearches") ?? []

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var matchingTracks: [Track] {
        guard !trimmedQuery.isEmpty else { return [] }
        return library.tracks
            .filter {
                LibrarySearch.matches(
                    trimmedQuery,
                    in: [$0.title, $0.artist, $0.album]
                )
            }
            .sorted { lhs, rhs in
                let leftRank = trackRank(lhs)
                let rightRank = trackRank(rhs)
                if leftRank != rightRank { return leftRank < rightRank }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    private func trackRank(_ track: Track) -> Int {
        let titleRank = LibrarySearch.rank(title: track.title, query: trimmedQuery)
        if titleRank < 3 { return titleRank }
        if track.artist.localizedStandardContains(trimmedQuery) { return 3 }
        if track.album.localizedStandardContains(trimmedQuery) { return 4 }
        return 5
    }

    private var matchingArtists: [LibraryArtistGroup] {
        guard !trimmedQuery.isEmpty else { return [] }
        return LibraryArtistBuilder.artists(from: library.tracks)
            .filter { LibrarySearch.matches(trimmedQuery, in: [$0.name]) }
            .sorted { lhs, rhs in
                let leftRank = LibrarySearch.rank(title: lhs.name, query: trimmedQuery)
                let rightRank = LibrarySearch.rank(title: rhs.name, query: trimmedQuery)
                if leftRank != rightRank { return leftRank < rightRank }
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private var matchingAlbums: [LibraryAlbumGroup] {
        guard !trimmedQuery.isEmpty else { return [] }
        return LibraryAlbumBuilder.albums(from: library.tracks)
            .filter {
                LibrarySearch.matches(trimmedQuery, in: [$0.title, $0.artist])
            }
            .sorted { lhs, rhs in
                let leftRank = LibrarySearch.rank(title: lhs.title, query: trimmedQuery)
                let rightRank = LibrarySearch.rank(title: rhs.title, query: trimmedQuery)
                if leftRank != rightRank { return leftRank < rightRank }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    private var matchingPlaylists: [Playlist] {
        guard !trimmedQuery.isEmpty else { return [] }
        return library.playlists
            .filter {
                LibrarySearch.matches(trimmedQuery, in: [$0.name, $0.description])
            }
            .sorted { lhs, rhs in
                let leftRank = LibrarySearch.rank(title: lhs.name, query: trimmedQuery)
                let rightRank = LibrarySearch.rank(title: rhs.name, query: trimmedQuery)
                if leftRank != rightRank { return leftRank < rightRank }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private var hasAnyLocalMatch: Bool {
        !matchingTracks.isEmpty
            || !matchingArtists.isEmpty
            || !matchingAlbums.isEmpty
            || !matchingPlaylists.isEmpty
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
                            if !matchingArtists.isEmpty {
                                artistSection
                            }
                            if !matchingAlbums.isEmpty {
                                albumSection
                            }
                            if !matchingPlaylists.isEmpty {
                                playlistSection
                            }
                            if !matchingTracks.isEmpty {
                                resultSection(
                                    title: "Songs",
                                    subtitle: nil,
                                    tracks: matchingTracks
                                )
                            }
                        case .songs:
                            resultSection(
                                title: "Songs",
                                subtitle: nil,
                                tracks: matchingTracks
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

                        if !hasAnyLocalMatch {
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
                Text("\(matchingArtists.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if matchingArtists.isEmpty {
                emptyScope("No artists match this search.")
            } else {
                CarouselScroll {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(matchingArtists) { artist in
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
                Text("\(matchingAlbums.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if matchingAlbums.isEmpty {
                emptyScope("No albums match this search.")
            } else {
                CarouselScroll {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(matchingAlbums) { album in
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
                Text("\(matchingPlaylists.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if matchingPlaylists.isEmpty {
                emptyScope("No playlists match this search.")
            } else {
                CarouselScroll {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(matchingPlaylists) { playlist in
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
                        TrackRow(track: track, queue: tracks, showNowPlaying: $showNowPlaying)
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
