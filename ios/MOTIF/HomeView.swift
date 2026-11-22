import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerManager
    @Binding var showNowPlaying: Bool

    @State private var showImporter = false
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    if let current = player.current {
                        listeningNow(current)
                    }

                    if let featured = library.tracks.first {
                        featuredCard(featured)
                    } else {
                        emptyCard
                    }

                    if !library.tracks.isEmpty {
                        recentlyAdded
                    }

                    if !library.favorites.isEmpty {
                        favorites
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showImporter = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Import music")
                }
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

    private func listeningNow(_ track: Track) -> some View {
        Button {
            showNowPlaying = true
        } label: {
            HStack(spacing: 12) {
                ArtworkView(url: track.artworkURL, seed: track.title + track.artist)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        ArtworkProgressRing(
                            size: 46,
                            cornerRadius: 14,
                            tint: Color.primary
                        )
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text(player.isPlaying ? "LISTENING NOW" : "PAUSED")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.6)
                        .foregroundStyle(.secondary)

                    Text(track.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(track.artist.isEmpty ? "Unknown artist" : track.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    PlaybackProgressLine()
                        .padding(.top, 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 10)
            .padding(.trailing, 14)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .nativeGlass(Capsule(), interactive: true)
        }
        .buttonStyle(MotifPressStyle(scale: 0.985, opacity: 0.94))
        .accessibilityLabel(
            "\(player.isPlaying ? "Listening now" : "Paused"): \(track.title) by \(track.artist.isEmpty ? "Unknown artist" : track.artist). Open player"
        )
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

                VStack(alignment: .leading, spacing: 4) {
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
                    .foregroundStyle(.primary)
                    .frame(width: 46, height: 46)
                    .nativeGlass(Circle(), interactive: true)
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.13), lineWidth: 1)
            }
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
                            VStack(alignment: .leading, spacing: 9) {
                                ArtworkView(url: track.artworkURL, seed: track.title + track.artist)
                                    .frame(width: 146, height: 146)
                                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                                    }

                                Text(track.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(track.artist)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 146, alignment: .leading)
                        }
                        .buttonStyle(MotifPressStyle(scale: 0.94))
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
