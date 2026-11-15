import SwiftUI
import UIKit

struct LibraryArtistsSection: View {
    @EnvironmentObject private var library: LibraryStore
    @Binding var showNowPlaying: Bool

    private var artists: [LibraryArtistGroup] {
        var order: [String] = []
        var names: [String: String] = [:]
        var counts: [String: Int] = [:]
        var artwork: [String: URL] = [:]

        for track in library.tracks {
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

    var body: some View {
        if !artists.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    SectionTitle(title: "Artists")
                    Spacer()
                    Text("\(artists.count)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 17) {
                        ForEach(artists) { artist in
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
                    .padding(.bottom, 4)
                }
            }
        }
    }
}

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

    var body: some View {
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
                    LazyVStack(spacing: 0) {
                        ForEach(tracks) { track in
                            TrackRow(track: track, queue: tracks)

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
        .background(AppBackground())
        .navigationTitle(artistName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
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

            VStack(spacing: 6) {
                Text("ARTIST")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(.secondary)

                Text(artistName)
                    .font(.system(size: 34, weight: .bold))
                    .tracking(-1.0)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                Text(metadataText)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)

            if !tracks.isEmpty {
                HStack(spacing: 10) {
                    Button {
                        play(shuffled: false)
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 22)
                            .frame(height: 42)
                            .background(Color.primary, in: Capsule())
                            .foregroundStyle(Color(uiColor: .systemBackground))
                    }
                    .buttonStyle(MotifPressStyle(scale: 0.94))

                    Button {
                        play(shuffled: true)
                    } label: {
                        Image(systemName: "shuffle")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 42, height: 42)
                            .contentShape(Circle())
                            .nativeGlass(Circle(), interactive: true)
                    }
                    .buttonStyle(MotifPressStyle(scale: 0.9))
                    .accessibilityLabel("Shuffle artist")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 28)
        .background(alignment: .top) {
            RadialGradient(
                colors: [
                    Color(red: 0.36, green: 0.42, blue: 0.58).opacity(0.24),
                    .clear
                ],
                center: .top,
                startRadius: 0,
                endRadius: 360
            )
            .frame(height: 460)
            .allowsHitTesting(false)
        }
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
