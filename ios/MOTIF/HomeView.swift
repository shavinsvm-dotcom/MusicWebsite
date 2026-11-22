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
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 30) {
                    header

                    if let current = player.current {
                        listeningNow(current)
                    }

                    if let featured = library.tracks.first, player.current == nil {
                        featuredCard(featured)
                    }

                    if library.tracks.isEmpty {
                        emptyCard
                    } else {
                        if !library.recentTracks.isEmpty {
                            recentlyPlayed
                        }

                        recentlyAdded

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
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(library)
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

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Good morning."
        case 12..<17: return "Good afternoon."
        case 17..<22: return "Good evening."
        default: return "Good night."
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(.system(size: 34, weight: .bold))
                    .tracking(-1.1)
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.82)
                    .lineLimit(1)

                Text("Your music, all in one place.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .background(Color.primary.opacity(0.06), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(MotifPressStyle(scale: 0.92))
                .accessibilityLabel("Settings")

                Button {
                    showImporter = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .background(Color.primary.opacity(0.06), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(MotifPressStyle(scale: 0.92))
                .accessibilityLabel("Import music")
            }
            .padding(.top, 4)
        }
    }

    private func listeningNow(_ track: Track) -> some View {
        Button {
            showNowPlaying = true
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    ArtworkView(url: track.artworkURL, seed: track.title + track.artist)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .overlay {
                            ArtworkProgressRing(
                                size: 52,
                                cornerRadius: 15.5,
                                tint: Color.primary
                            )
                        }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            PlayingWaveform(isPlaying: player.isPlaying)
                                .frame(width: 12, height: 9)

                            Text(player.isPlaying ? "LISTENING NOW" : "PAUSED")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(1.6)
                                .foregroundStyle(.secondary)
                        }

                        Text(track.title)
                            .font(.system(size: 16, weight: .semibold))
                            .tracking(-0.2)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(track.artist.isEmpty ? "Unknown artist" : track.artist)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                PlaybackProgressLine(tint: .primary, height: 1.5)
            }
            .padding(.top, 2)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(MotifPressStyle(scale: 0.99, opacity: 0.94))
        .accessibilityLabel(
            "\(player.isPlaying ? "Listening now" : "Paused"): \(track.title) by \(track.artist.isEmpty ? "Unknown artist" : track.artist). Open player"
        )
        .accessibilityHint("Opens the player")
    }

    private func featuredCard(_ track: Track) -> some View {
        Button {
            player.play(track, queue: library.tracks)
            showNowPlaying = true
        } label: {
            ZStack(alignment: .bottomLeading) {
                ArtworkView(url: track.artworkURL, seed: track.title + track.artist)
                    .frame(height: 238)
                    .frame(maxWidth: .infinity)

                ProgressiveArtworkBlur(url: track.artworkURL)

                LinearGradient(
                    colors: [.clear, .black.opacity(0.72)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 5) {
                    Text("START HERE")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.7)
                        .foregroundStyle(.white.opacity(0.64))

                    Text(track.title)
                        .font(.system(size: 26, weight: .bold))
                        .tracking(-0.6)
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Text(track.artist)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                }
                .padding(18)

                Image(systemName: "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 46, height: 46)
                    .background(Color.white.opacity(0.94), in: Circle())
                    .shadow(color: .black.opacity(0.18), radius: 9, y: 4)
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(MotifPressStyle(scale: 0.985))
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)

            Text("Your library is empty.")
                .font(.system(size: 23, weight: .semibold))
                .tracking(-0.4)

            Text("Import audio from Files, or search the catalog for a preview.")
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
        .glassSurface(radius: 26)
    }

    private var recentlyPlayed: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "Recently played")

            CarouselScroll {
                LazyHStack(spacing: 14) {
                    ForEach(library.recentTracks.prefix(10)) { track in
                        Button {
                            player.play(track, queue: library.recentTracks)
                        } label: {
                            trackTile(track)
                        }
                        .buttonStyle(MotifPressStyle(scale: 0.96))
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
                    }
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 4)
            }
        }
    }

    private func trackTile(_ track: Track) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ArtworkView(url: track.artworkURL, seed: track.title + track.artist)
                .frame(width: 132, height: 132)
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
                ForEach(library.favorites) { track in
                    TrackRow(track: track, queue: library.favorites, showNowPlaying: $showNowPlaying)
                    if track.id != library.favorites.last?.id {
                        Divider().opacity(0.4)
                    }
                }
            }
        }
    }
}
