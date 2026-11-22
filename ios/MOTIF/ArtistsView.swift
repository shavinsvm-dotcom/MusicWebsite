import SwiftUI
import UIKit

struct LibraryArtistCard: View {
    let artist: LibraryArtistGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ArtworkView(url: artist.artworkURL, seed: artist.name)
                .frame(width: 112, height: 112)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.20), radius: 14, y: 7)

            Text(artist.name)
                .font(.system(size: 14, weight: .semibold))
                .tracking(-0.15)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(artist.count == 1 ? "1 song" : "\(artist.count) songs")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 112, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct LibraryArtistGridCard: View {
    let artist: LibraryArtistGroup

    var body: some View {
        VStack(spacing: 8) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    ArtworkView(url: artist.artworkURL, seed: artist.name)
                }
                .clipShape(Circle())

            Text(artist.name)
                .font(.system(size: 13, weight: .semibold))
                .tracking(-0.1)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(artist.count == 1 ? "1 song" : "\(artist.count) songs")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
    }
}

struct LibraryArtistDetailView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerManager

    let artistName: String
    @Binding var showNowPlaying: Bool

    private var tracks: [Track] {
        library.tracks.filter {
            $0.artist.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(artistName) == .orderedSame
        }
    }

    private var artworkURL: URL? {
        tracks.compactMap(\.artworkURL).first
    }

    private var cloudCount: Int {
        tracks.filter(\.isCloud).count
    }

    private var albums: [LibraryAlbumGroup] {
        LibraryAlbumBuilder.albums(from: tracks)
    }

    var body: some View {
        ZStack {
            DetailBackdrop(artworkURL: artworkURL)

            ScrollView {
                VStack(spacing: 0) {
                    header

                    if tracks.isEmpty {
                        Text("No songs by this artist.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                    } else {
                        if !albums.isEmpty {
                            albumSection
                        }

                        HStack(alignment: .firstTextBaseline) {
                            SectionTitle(title: "All songs")
                            Spacer()
                            Text("\(tracks.count)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)

                        LazyVStack(spacing: 0) {
                            ForEach(tracks) { track in
                                TrackRow(track: track, queue: tracks, showNowPlaying: $showNowPlaying)

                                if track.id != tracks.last?.id {
                                    Divider().opacity(0.35)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    Spacer(minLength: 120)
                }
            }
            .scrollIndicators(.hidden)
            .background(Color.clear)
        }
        .navigationTitle(artistName)
        .navigationBarTitleDisplayMode(.large)
        .nativeScrollHeader()
        .toolbar(.visible, for: .navigationBar)
    }

    private var header: some View {
        VStack(spacing: 16) {
            ArtworkView(url: artworkURL, seed: artistName)
                .frame(width: 184, height: 184)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.28), radius: 28, y: 14)

            Text(metadataText)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            if !tracks.isEmpty {
                HStack(spacing: 10) {
                    GlassActionButton(
                        title: "Play",
                        prominent: true,
                        accessibilityLabel: "Play artist"
                    ) {
                        play(shuffled: false)
                    }

                    GlassIconButton(
                        systemImage: "shuffle",
                        label: "Shuffle artist",
                        size: 42
                    ) {
                        play(shuffled: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 28)
    }

    private var albumSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Albums")

            CarouselScroll {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(albums) { album in
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
                .padding(.bottom, 4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    private var metadataText: String {
        let countText = tracks.count == 1 ? "1 song" : "\(tracks.count) songs"
        let duration = Int(tracks.reduce(0) { $0 + $1.duration }.rounded())
        let minutes = max(1, duration / 60)
        var parts = [countText, "\(minutes) min"]
        if cloudCount > 0 {
            parts.append("\(cloudCount) in cloud")
        }
        return parts.joined(separator: " · ")
    }

    private func play(shuffled: Bool) {
        guard let first = tracks.first else { return }
        if player.isShuffled != shuffled {
            player.toggleShuffle()
        }
        player.play(first, queue: tracks)
        showNowPlaying = true
    }
}

struct LibraryArtistGroup: Identifiable {
    let id: String
    let name: String
    let artworkURL: URL?
    let count: Int
}

enum LibraryArtistBuilder {
    static func artists(from tracks: [Track]) -> [LibraryArtistGroup] {
        var order: [String] = []
        var names: [String: String] = [:]
        var counts: [String: Int] = [:]
        var artwork: [String: URL] = [:]

        for track in tracks {
            let name = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty,
                  name != "Imported",
                  name.caseInsensitiveCompare("Unknown artist") != .orderedSame
            else { continue }

            let key = name.lowercased()
            if counts[key] == nil {
                order.append(key)
                names[key] = name
            }
            counts[key, default: 0] += 1
            if artwork[key] == nil, let url = track.artworkURL {
                artwork[key] = url
            }
        }

        return order
            .map { key in
                LibraryArtistGroup(
                    id: key,
                    name: names[key] ?? key,
                    artworkURL: artwork[key],
                    count: counts[key] ?? 0
                )
            }
            .sorted {
                if $0.count == $1.count {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return $0.count > $1.count
            }
    }
}

struct LibraryAlbumGroup: Identifiable {
    let id: String
    let title: String
    let artist: String
    let year: Int?
    let artworkURL: URL?
    let tracks: [Track]
}

enum LibraryAlbumBuilder {
    static func albums(from tracks: [Track]) -> [LibraryAlbumGroup] {
        var order: [String] = []
        var titles: [String: String] = [:]
        var artists: [String: String] = [:]
        var years: [String: Int] = [:]
        var artwork: [String: URL] = [:]
        var grouped: [String: [Track]] = [:]

        for track in tracks {
            let title = track.album.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            let artist = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = "\(title.lowercased())|\(artist.lowercased())"

            if grouped[key] == nil {
                order.append(key)
                titles[key] = title
                artists[key] = artist
            }
            if years[key] == nil, let year = track.releaseYear {
                years[key] = year
            }
            if artwork[key] == nil, let url = track.artworkURL {
                artwork[key] = url
            }
            grouped[key, default: []].append(track)
        }

        return order
            .map { key in
                LibraryAlbumGroup(
                    id: key,
                    title: titles[key] ?? "Album",
                    artist: artists[key] ?? "",
                    year: years[key],
                    artworkURL: artwork[key],
                    tracks: grouped[key] ?? []
                )
            }
            .sorted {
                if $0.year != $1.year {
                    return ($0.year ?? 0) > ($1.year ?? 0)
                }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
    }
}

struct LibraryAlbumCard: View {
    let album: LibraryAlbumGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ArtworkView(url: album.artworkURL, seed: album.title + album.artist)
                .frame(width: 132, height: 132)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.7)
                }
                .shadow(color: .black.opacity(0.16), radius: 12, y: 6)

            Text(album.title)
                .font(.system(size: 14, weight: .semibold))
                .tracking(-0.15)
                .lineLimit(1)

            Text(albumSubtitle)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 132, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var albumSubtitle: String {
        let count = album.tracks.count
        let trackText = count == 1 ? "1 song" : "\(count) songs"
        if let year = album.year {
            return "\(year) · \(trackText)"
        }
        return trackText
    }
}

struct LibraryAlbumGridCard: View {
    let album: LibraryAlbumGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    ArtworkView(url: album.artworkURL, seed: album.title + album.artist)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text(album.title)
                .font(.system(size: 13, weight: .semibold))
                .tracking(-0.1)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(album.artist)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
    }
}

struct LibraryAlbumDetailView: View {
    @EnvironmentObject private var player: PlayerManager
    let album: LibraryAlbumGroup
    @Binding var showNowPlaying: Bool

    private var tracks: [Track] { album.tracks }

    var body: some View {
        ZStack {
            DetailBackdrop(artworkURL: album.artworkURL)

            ScrollView {
                VStack(spacing: 0) {
                    header

                    LazyVStack(spacing: 0) {
                        ForEach(tracks) { track in
                            TrackRow(track: track, queue: tracks, showNowPlaying: $showNowPlaying)

                            if track.id != tracks.last?.id {
                                Divider().opacity(0.35)
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    Spacer(minLength: 120)
                }
            }
            .scrollIndicators(.hidden)
            .background(Color.clear)
        }
        .navigationTitle(album.title)
        .navigationBarTitleDisplayMode(.large)
        .nativeScrollHeader()
        .toolbar(.visible, for: .navigationBar)
    }

    private var header: some View {
        VStack(spacing: 16) {
            ArtworkView(
                url: album.artworkURL,
                seed: album.title + album.artist
            )
                .frame(width: 220, height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
                }
                .shadow(color: .black.opacity(0.24), radius: 24, y: 12)

            Text(albumSubtitle)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            if !tracks.isEmpty {
                GlassActionButton(
                    title: "Play",
                    prominent: true,
                    accessibilityLabel: "Play album"
                ) {
                    play(shuffled: false)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 28)
    }

    private var albumSubtitle: String {
        let count = tracks.count
        let countText = count == 1 ? "1 song" : "\(count) songs"
        var parts = [album.artist, countText]
        if let year = album.year { parts.insert(String(year), at: 1) }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func play(shuffled: Bool) {
        guard let first = tracks.first else { return }
        if player.isShuffled != shuffled {
            player.toggleShuffle()
        }
        player.play(first, queue: tracks)
        showNowPlaying = true
    }
}
