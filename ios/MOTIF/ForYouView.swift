import SwiftUI
import UIKit

struct ForYouView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerManager
    @Binding var showNowPlaying: Bool
    var openSearch: () -> Void

    var body: some View {
        let data = ForYouSnapshot(library: library)

        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 30) {
                    if data.tracks.isEmpty {
                        emptyState
                    } else {
                        if !data.mixTracks.isEmpty {
                            dailyMix(data)
                        }

                        if let artist = data.topArtist, data.topArtistTracks.count > 1 {
                            becauseYouLike(artist, tracks: data.topArtistTracks)
                        }

                        onRepeat(data)

                        if data.artists.count > 1 {
                            topArtists(data.artists)
                        }
                    }
                }
                .screenEntrance()
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .navigationTitle("For You")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private func dailyMix(_ data: ForYouSnapshot) -> some View {
        Button {
            guard let first = data.mixTracks.first else { return }
            player.play(first, queue: data.mixTracks)
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
                        mixArtwork(index, tracks: data.mixTracks)
                    }
                }
                .frame(height: 244)

                ProgressiveArtworkBlur(url: data.mixTracks.first?.artworkURL, strength: 0.88)

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

                    Text(data.mixSubtitle)
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

    private func mixArtwork(_ index: Int, tracks: [Track]) -> some View {
        let track = tracks[index % max(tracks.count, 1)]
        return ArtworkView(url: track.artworkURL, seed: track.title + track.artist)
            .frame(maxWidth: .infinity)
            .frame(height: 122)
            .clipped()
    }

    private func becauseYouLike(_ artist: ArtistSummary, tracks: [Track]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "Because you like \(artist.name)")

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(tracks) { track in
                        Button {
                            player.play(track, queue: tracks)
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

    private func onRepeat(_ data: ForYouSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(title: "On repeat")
                Spacer()
                Button {
                    guard let first = data.repeatTracks.first else { return }
                    player.play(first, queue: data.repeatTracks)
                    showNowPlaying = true
                } label: {
                    Label("Play all", systemImage: "play.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(MotifPressStyle(scale: 0.92))
                .foregroundStyle(.secondary)
            }

            LazyVStack(spacing: 0) {
                ForEach(data.repeatTracks) { track in
                    TrackRow(track: track, queue: data.repeatTracks)
                    if track.id != data.repeatTracks.last?.id {
                        Divider().opacity(0.35)
                    }
                }
            }
        }
    }

    private func topArtists(_ artists: [ArtistSummary]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "Your artists")

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 20) {
                    ForEach(artists.prefix(8)) { artist in
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

}

private struct ForYouSnapshot {
    let tracks: [Track]
    let mixTracks: [Track]
    let mixSubtitle: String
    let repeatTracks: [Track]
    let artists: [ArtistSummary]
    let topArtist: ArtistSummary?
    let topArtistTracks: [Track]

    @MainActor
    init(library: LibraryStore) {
        let all = library.tracks
        tracks = all

        if all.isEmpty {
            mixTracks = []
            mixSubtitle = ""
        } else {
            let count = min(8, all.count)
            let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
            let mix = (0..<count).map { all[(day + $0 * 7) % all.count] }
            mixTracks = mix

            var seen = Set<String>()
            mixSubtitle = mix
                .compactMap { track -> String? in
                    guard seen.insert(track.artist).inserted else { return nil }
                    return track.artist
                }
                .prefix(3)
                .joined(separator: ", ")
        }

        var picked: [Track] = []
        var pickedIDs = Set<UUID>()
        for track in library.favorites + all {
            guard pickedIDs.insert(track.id).inserted else { continue }
            picked.append(track)
            if picked.count == 6 { break }
        }
        repeatTracks = picked

        var counts: [String: Int] = [:]
        var artwork: [String: URL] = [:]
        var order: [String] = []

        for track in all {
            let name = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name != "Imported" else { continue }
            if counts[name] == nil {
                order.append(name)
                if let url = track.artworkURL { artwork[name] = url }
            }
            counts[name, default: 0] += 1
        }

        let summaries = order
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

        artists = summaries
        let top = summaries.first
        topArtist = top
        topArtistTracks = top.map { artist in
            Array(all.filter { $0.artist == artist.name }.prefix(6))
        } ?? []
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
