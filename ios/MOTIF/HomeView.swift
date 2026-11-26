import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerManager
    @Binding var showNowPlaying: Bool

    @State private var showImporter = false
    @State private var showSettings = false
    @State private var importError: String?

    var body: some View {
        let data = library.homeSnapshot

        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    if library.tracks.isEmpty {
                        emptyCard
                    } else {
                        if !data.mixTracks.isEmpty {
                            dailyMix(data)
                        }

                        if !library.recentTracks.isEmpty {
                            recentlyPlayed
                        }

                        recentlyAdded

                        if let artist = data.topArtistName,
                           data.topArtistTracks.count > 1 {
                            becauseYouLike(artist, tracks: data.topArtistTracks)
                        }

                        if !library.favorites.isEmpty {
                            favorites
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
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.large)
            .nativeScrollHeader()
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")

                    Button {
                        showImporter = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Import music")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(player)
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    Task { await library.importFiles(urls) }
                case .failure(let error):
                    importError = error.localizedDescription
                }
            }
            .alert(
                "Import failed",
                isPresented: Binding(
                    get: { importError != nil },
                    set: { if !$0 { importError = nil } }
                )
            ) {
                Button("OK") { importError = nil }
            } message: {
                Text(importError ?? "")
            }
        }
    }

    private func dailyMix(_ data: HomeSnapshot) -> some View {
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
                        .lineLimit(1)

                    Text(data.mixSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                }
                .padding(18)

                Image(systemName: "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 46, height: 46)
                    .nativeGlass(Circle(), interactive: true)
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(MotifPressStyle(scale: 0.985))
        .accessibilityLabel("Play Daily Mix 1")
        .accessibilityHint("Plays a mix of songs from your library")
    }

    private func mixArtwork(_ index: Int, tracks: [Track]) -> some View {
        let track = tracks[index % max(tracks.count, 1)]
        return ArtworkView(url: track.artworkURL, seed: track.title + track.artist, card: true)
            .frame(maxWidth: .infinity)
            .frame(height: 122)
            .clipped()
    }

    private var recentlyPlayed: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Recently played") {
                GlassActionButton(
                    title: "Play",
                    accessibilityLabel: "Play recently played"
                ) {
                    guard let first = library.recentTracks.first else { return }
                    player.play(first, queue: library.recentTracks)
                    showNowPlaying = true
                }
            }

            CarouselScroll {
                LazyHStack(spacing: 14) {
                    ForEach(library.recentTracks.prefix(10)) { track in
                        Button {
                            player.play(track, queue: library.recentTracks)
                        } label: {
                            trackTile(track)
                        }
                        .buttonStyle(MotifPressStyle(scale: 0.96))
                        .carouselItemTransition()
                    }
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 4)
            }
        }
    }

    private var recentlyAdded: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Recently added") {
                GlassActionButton(
                    title: "Play",
                    accessibilityLabel: "Play recently added"
                ) {
                    guard let first = library.tracks.first else { return }
                    player.play(first, queue: Array(library.tracks.prefix(10)))
                    showNowPlaying = true
                }
            }

            CarouselScroll {
                LazyHStack(spacing: 14) {
                    ForEach(library.tracks.prefix(10)) { track in
                        Button {
                            player.play(track, queue: library.tracks)
                        } label: {
                            trackTile(track)
                        }
                        .buttonStyle(MotifPressStyle(scale: 0.96))
                        .carouselItemTransition()
                    }
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 4)
            }
        }
    }

    private func becauseYouLike(_ artist: String, tracks: [Track]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Because you like \(artist)") {
                GlassActionButton(
                    title: "Play",
                    accessibilityLabel: "Play songs by \(artist)"
                ) {
                    guard let first = tracks.first else { return }
                    player.play(first, queue: tracks)
                    showNowPlaying = true
                }
            }

            CarouselScroll {
                LazyHStack(spacing: 14) {
                    ForEach(tracks) { track in
                        Button {
                            player.play(track, queue: tracks)
                        } label: {
                            trackTile(track)
                        }
                        .buttonStyle(MotifPressStyle(scale: 0.96))
                        .carouselItemTransition()
                    }
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 4)
            }
        }
    }

    private var favorites: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Favorites") {
                GlassActionButton(
                    title: "Play",
                    accessibilityLabel: "Play favorites"
                ) {
                    guard let first = library.favorites.first else { return }
                    player.play(first, queue: library.favorites)
                    showNowPlaying = true
                }
            }

            LazyVStack(spacing: 0) {
                ForEach(Array(library.favorites.enumerated()), id: \.element.id) { index, track in
                    TrackRow(
                        track: track,
                        queue: library.favorites,
                        player: player,
                        showNowPlaying: $showNowPlaying
                    )

                    if index < library.favorites.count - 1 {
                        Divider().opacity(0.35)
                    }
                }
            }
        }
    }

    private func trackTile(_ track: Track) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                ArtworkView(url: track.artworkURL, seed: track.title + track.artist, card: true)
                    .frame(width: 132, height: 132)

                Image(systemName: "play.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 26, height: 26)
                    .rowControl(Circle(), dark: true)
                    .padding(7)
            }
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

            Text(track.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(track.artist.isEmpty ? "Unknown artist" : track.artist)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 132, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            track.artist.isEmpty
                ? track.title
                : "\(track.title), \(track.artist)"
        )
        .accessibilityHint("Plays this song")
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)

            Text("Your library is empty.")
                .font(.system(size: 23, weight: .semibold))
                .tracking(-0.4)

            Text("Import audio from Files to start listening.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            GlassActionButton(
                title: "Import music",
                systemImage: "square.and.arrow.down",
                prominent: true
            ) {
                showImporter = true
            }
            .padding(.top, 2)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nativeGlass(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
