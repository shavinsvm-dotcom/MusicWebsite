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
                VStack(alignment: .leading, spacing: 28) {
                    header

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
                .padding(.top, 10)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .toolbar(.hidden, for: .navigationBar)
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

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("MOTIF")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(2.4)
                    .foregroundStyle(.secondary)

                Text(greeting)
                    .font(.system(size: 33, weight: .semibold))
                    .tracking(-1.2)
                    .foregroundStyle(.primary)
            }

            Spacer()

            Button {
                showImporter = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .contentShape(Rectangle())
            }
            .buttonStyle(MotifPressStyle(scale: 0.9))
            .glassSurface(radius: 21)
            .accessibilityLabel("Import music")
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning."
        case 12..<18: return "Good afternoon."
        default: return "Good evening."
        }
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
                    .foregroundStyle(.black)
                    .frame(width: 46, height: 46)
                    .background(.white, in: Circle())
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

            Button {
                showImporter = true
            } label: {
                Label("Import music", systemImage: "square.and.arrow.down")
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

    private var recentlyAdded: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "Recently added")

            ScrollView(.horizontal, showsIndicators: false) {
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
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Favorites")

            VStack(spacing: 0) {
                ForEach(library.favorites) { track in
                    TrackRow(track: track, queue: library.favorites)
                    if track.id != library.favorites.last?.id {
                        Divider().opacity(0.4)
                    }
                }
            }
        }
    }
}
