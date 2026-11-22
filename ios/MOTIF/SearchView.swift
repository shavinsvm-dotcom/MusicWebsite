import SwiftUI
import UIKit

private enum SearchScope: String, CaseIterable, Identifiable {
    case all
    case songs
    case artists
    case albums
    case playlists
    case downloads
    case cloud

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .songs: return "Songs"
        case .artists: return "Artists"
        case .albums: return "Albums"
        case .playlists: return "Playlists"
        case .downloads: return "Downloads"
        case .cloud: return "Cloud"
        }
    }
}

struct SearchView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerManager
    @Binding var showNowPlaying: Bool

    @State private var query = ""
    @State private var results: [Track] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var scope: SearchScope = .all
    @State private var recentSearches: [String] = UserDefaults.standard.stringArray(forKey: "motif.recentSearches") ?? []

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var needle: String {
        trimmedQuery.lowercased()
    }

    private var matchingTracks: [Track] {
        guard !trimmedQuery.isEmpty else { return [] }
        return library.tracks
            .filter {
                $0.title.lowercased().contains(needle)
                    || $0.artist.lowercased().contains(needle)
                    || $0.album.lowercased().contains(needle)
            }
            .sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
    }

    private var matchingArtists: [LibraryArtistGroup] {
        guard !trimmedQuery.isEmpty else { return [] }
        return LibraryArtistBuilder.artists(from: library.tracks)
            .filter { $0.name.lowercased().contains(needle) }
    }

    private var matchingAlbums: [LibraryAlbumGroup] {
        guard !trimmedQuery.isEmpty else { return [] }
        return LibraryAlbumBuilder.albums(from: library.tracks)
            .filter {
                $0.title.lowercased().contains(needle)
                    || $0.artist.lowercased().contains(needle)
            }
    }

    private var matchingPlaylists: [Playlist] {
        guard !trimmedQuery.isEmpty else { return [] }
        return library.playlists.filter {
            $0.name.lowercased().contains(needle)
                || $0.description.lowercased().contains(needle)
        }
    }

    private var downloadedMatches: [Track] {
        matchingTracks.filter { library.isDownloaded($0) }
    }

    private var cloudMatches: [Track] {
        matchingTracks.filter(\.isCloud)
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
                        scopePicker

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
                        case .downloads:
                            resultSection(
                                title: "Downloaded",
                                subtitle: nil,
                                tracks: downloadedMatches
                            )
                        case .cloud:
                            resultSection(
                                title: "Cloud tracks",
                                subtitle: nil,
                                tracks: cloudMatches
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

                        if (scope == .all || scope == .songs), !results.isEmpty {
                            resultSection(
                                title: "Catalog",
                                subtitle: "Apple Music previews · 30 seconds",
                                tracks: results
                            )
                        }

                        if !isLoading,
                           !hasAnyLocalMatch,
                           results.isEmpty,
                           errorMessage == nil {
                            emptyResults
                        }
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
                prompt: "Songs, artists, albums, playlists"
            )
            .onSubmit(of: .search) {
                remember(trimmedQuery)
            }
            .task(id: query) {
                await runSearch()
            }
        }
    }

    private var recentSearchesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle(title: "Recent searches")

                Spacer()

                Button("Clear") {
                    recentSearches = []
                    UserDefaults.standard.removeObject(forKey: "motif.recentSearches")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
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
                                .background(Color.primary.opacity(0.06), in: Capsule())
                        }
                        .buttonStyle(MotifPressStyle(scale: 0.95))
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var browseHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Find anything.")
                .font(.system(size: 24, weight: .semibold))
                .tracking(-0.5)

            Text("Search your songs, artists, albums, playlists, downloads and cloud library — or find something new in the iTunes catalog.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scopePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SearchScope.allCases) { option in
                    scopeChip(option)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func scopeChip(_ option: SearchScope) -> some View {
        let isSelected = scope == option

        return Button {
            withAnimation(.easeOut(duration: 0.16)) {
                scope = option
            }
        } label: {
            scopeLabel(option, isSelected: isSelected)
        }
        .buttonStyle(MotifPressStyle(scale: 0.94))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func scopeLabel(_ option: SearchScope, isSelected: Bool) -> some View {
        let label = Text(option.title)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)

        if isSelected {
            label
                .foregroundStyle(Color(uiColor: .systemBackground))
                .background(Color.primary, in: Capsule())
        } else {
            label
                .foregroundStyle(.primary)
                .background(Color.primary.opacity(0.06), in: Capsule())
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
