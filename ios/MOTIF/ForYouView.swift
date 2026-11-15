import SwiftUI
import UIKit

struct ForYouView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerManager
    @Binding var showNowPlaying: Bool
    var openSearch: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 30) {
                    header

                    if library.tracks.isEmpty {
                        emptyState
                    } else {
                        if !mixTracks.isEmpty {
                            dailyMix
                        }

                        if let artist = topArtist, topArtistTracks.count > 1 {
                            becauseYouLike(artist)
                        }

                        onRepeat

                        if artistSummaries.count > 1 {
                            topArtists
                        }
                    }
                }
                .screenEntrance()
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            LiltWordmark()
                .opacity(0.92)

            Text("For you.")
                .font(.system(size: 33, weight: .semibold))
                .tracking(-1.2)
                .foregroundStyle(.primary)
        }
    }

    private var dailyMix: some View {
        Button {
            guard let first = mixTracks.first else { return }
            player.play(first, queue: mixTracks)
            showNowPlaying = true
        } label: {
            ZStack(alignment: .bottomLeading) {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 0),
                        GridItem(.flexible(), spacing: 0)
                    ],
                    spacing: 0
                ) {
                    ForEach(0..<4, id: \.self) { index in
                        mixArtwork(index)
                    }
                }
                .frame(height: 244)

                LinearGradient(
                    colors: [.clear, .black.opacity(0.20), .black.opacity(0.86)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text("MADE FOR YOU")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.8)
                        .foregroundStyle(.white.opacity(0.72))
                        .padding(.bottom, 2)

                    Text("Daily Mix 1")
                        .font(.system(size: 28, weight: .bold))
                        .tracking(-0.8)
                        .foregroundStyle(.white)

                    Text(mixSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                }
                .padding(18)

                Image(systemName: "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 46, height: 46)
                    .background(.white, in: Circle())
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.13), lineWidth: 1)
            }
        }
        .buttonStyle(MotifPressStyle(scale: 0.985))
    }

    private func mixArtwork(_ index: Int) -> some View {
        let track = mixTracks[index % max(mixTracks.count, 1)]
        return ArtworkView(url: track.artworkURL, seed: track.title + track.artist)
            .frame(maxWidth: .infinity)
            .frame(height: 122)
            .clipped()
    }

    private func becauseYouLike(_ artist: ArtistSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "Because you like \(artist.name)")

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(topArtistTracks) { track in
                        Button {
                            player.play(track, queue: topArtistTracks)
                            showNowPlaying = true
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                ArtworkView(url: track.artworkURL, seed: track.title + track.artist)
                                    .frame(width: 140, height: 140)
                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                                Text(track.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(track.artist)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 140, alignment: .leading)
                        }
                        .buttonStyle(MotifPressStyle(scale: 0.94))
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private var onRepeat: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(title: "On repeat")
                Spacer()
                Button {
                    guard let first = repeatTracks.first else { return }
                    player.play(first, queue: repeatTracks)
                    showNowPlaying = true
                } label: {
                    Label("Play all", systemImage: "play.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(MotifPressStyle(scale: 0.92))
                .foregroundStyle(.secondary)
            }

            LazyVStack(spacing: 0) {
                ForEach(repeatTracks) { track in
                    TrackRow(track: track, queue: repeatTracks)
                    if track.id != repeatTracks.last?.id {
                        Divider().opacity(0.35)
                    }
                }
            }
        }
    }

    private var topArtists: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "Your artists")

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 20) {
                    ForEach(artistSummaries.prefix(8)) { artist in
                        NavigationLink {
                            ArtistTracksView(
                                artistName: artist.name,
                                showNowPlaying: $showNowPlaying
                            )
                        } label: {
                            VStack(spacing: 8) {
                                ArtworkView(url: artist.artworkURL, seed: artist.name)
                                    .frame(width: 82, height: 82)
                                    .clipShape(Circle())

                                Text(artist.name)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .frame(width: 88)
                            }
                        }
                        .buttonStyle(MotifPressStyle(scale: 0.92))
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)

            Text("Your mixes start here.")
                .font(.system(size: 24, weight: .semibold))
                .tracking(-0.5)

            Text("Add music to your library and For You will shape a daily mix, artist picks and the songs you keep coming back to.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                openSearch()
            } label: {
                Label("Find music", systemImage: "magnifyingglass")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(Color.primary, in: Capsule())
                    .foregroundStyle(Color(uiColor: .systemBackground))
            }
            .buttonStyle(MotifPressStyle(scale: 0.94))
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(radius: 26)
    }

    private var mixTracks: [Track] {
        let all = library.tracks
        guard !all.isEmpty else { return [] }
        let count = min(8, all.count)
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        return (0..<count).map { all[(day + $0 * 7) % all.count] }
    }

    private var mixSubtitle: String {
        var seen = Set<String>()
        let names = mixTracks.compactMap { track -> String? in
            guard seen.insert(track.artist).inserted else { return nil }
            return track.artist
        }
        return names.prefix(3).joined(separator: ", ")
    }

    private var topArtistTracks: [Track] {
        guard let topArtist else { return [] }
        return Array(library.tracks.filter { $0.artist == topArtist.name }.prefix(6))
    }

    private var repeatTracks: [Track] {
        var picked: [Track] = []
        var seen = Set<UUID>()
        for track in library.favorites + library.tracks {
            guard seen.insert(track.id).inserted else { continue }
            picked.append(track)
            if picked.count == 6 { break }
        }
        return picked
    }

    private var artistSummaries: [ArtistSummary] {
        var counts: [String: Int] = [:]
        var artwork: [String: URL] = [:]
        var order: [String] = []

        for track in library.tracks {
            let name = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name != "Imported" else { continue }
            if counts[name] == nil {
                order.append(name)
                if let url = track.artworkURL { artwork[name] = url }
            }
            counts[name, default: 0] += 1
        }

        return order
            .map {
                ArtistSummary(
                    name: $0,
                    artworkURL: artwork[$0],
                    count: counts[$0] ?? 0
                )
            }
            .sorted {
                if $0.count == $1.count { return $0.name < $1.name }
                return $0.count > $1.count
            }
    }

    private var topArtist: ArtistSummary? {
        artistSummaries.first
    }
}

struct ArtistTracksView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerManager
    let artistName: String
    @Binding var showNowPlaying: Bool

    private var tracks: [Track] {
        library.tracks.filter { $0.artist == artistName }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Button {
                    guard let first = tracks.first else { return }
                    player.play(first, queue: tracks)
                    showNowPlaying = true
                } label: {
                    Label("Play all", systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Color.primary, in: Capsule())
                        .foregroundStyle(Color(uiColor: .systemBackground))
                }
                .buttonStyle(MotifPressStyle(scale: 0.94))

                LazyVStack(spacing: 0) {
                    ForEach(tracks) { track in
                        TrackRow(track: track, queue: tracks)
                        if track.id != tracks.last?.id {
                            Divider().opacity(0.35)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .navigationTitle(artistName)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

private struct ArtistSummary: Identifiable {
    var id: String { name }
    let name: String
    let artworkURL: URL?
    let count: Int
}
