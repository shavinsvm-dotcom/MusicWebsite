import SwiftUI

struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if colorScheme == .dark {
                Color(red: 0.035, green: 0.035, blue: 0.050)
                    .ignoresSafeArea()

                Circle()
                    .fill(Color(red: 0.20, green: 0.28, blue: 0.82))
                    .frame(width: 420, height: 420)
                    .blur(radius: 130)
                    .offset(x: -150, y: -310)
                    .opacity(0.50)

                Circle()
                    .fill(Color(red: 0.78, green: 0.20, blue: 0.48))
                    .frame(width: 360, height: 360)
                    .blur(radius: 140)
                    .offset(x: 180, y: 130)
                    .opacity(0.30)

                Circle()
                    .fill(Color(red: 0.10, green: 0.58, blue: 0.52))
                    .frame(width: 320, height: 320)
                    .blur(radius: 150)
                    .offset(x: -10, y: 380)
                    .opacity(0.22)
            } else {
                Color(red: 0.965, green: 0.968, blue: 0.985)
                    .ignoresSafeArea()

                Circle()
                    .fill(Color(red: 0.58, green: 0.72, blue: 1.00))
                    .frame(width: 430, height: 430)
                    .blur(radius: 120)
                    .offset(x: -160, y: -300)
                    .opacity(0.52)

                Circle()
                    .fill(Color(red: 1.00, green: 0.64, blue: 0.78))
                    .frame(width: 360, height: 360)
                    .blur(radius: 130)
                    .offset(x: 190, y: 120)
                    .opacity(0.40)

                Circle()
                    .fill(Color(red: 0.58, green: 0.92, blue: 0.84))
                    .frame(width: 330, height: 330)
                    .blur(radius: 140)
                    .offset(x: 0, y: 380)
                    .opacity(0.30)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private struct GlassSurface: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.46),
                                Color.white.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(0.16), radius: 22, x: 0, y: 12)
    }
}

extension View {
    func glassSurface(radius: CGFloat = 24) -> some View {
        modifier(GlassSurface(radius: radius))
    }
}

struct ArtworkView: View {
    let url: URL?
    let seed: String

    var body: some View {
        ZStack {
            LinearGradient(
                colors: palette,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else if phase.error != nil {
                        fallback
                    } else {
                        ProgressView()
                            .tint(.white)
                    }
                }
            } else {
                fallback
            }
        }
        .clipped()
    }

    private var fallback: some View {
        Image(systemName: "music.note")
            .font(.system(size: 28, weight: .medium))
            .foregroundStyle(.white.opacity(0.85))
    }

    private var palette: [Color] {
        let hue = stableHue
        return [
            Color(hue: hue, saturation: 0.52, brightness: 0.58),
            Color(hue: (hue + 0.09).truncatingRemainder(dividingBy: 1), saturation: 0.55, brightness: 0.24)
        ]
    }

    private var stableHue: Double {
        var hash: UInt64 = 5381
        for scalar in seed.unicodeScalars {
            hash = (hash &* 33) &+ UInt64(scalar.value)
        }
        return Double(hash % 360) / 360
    }
}

struct SectionTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 20, weight: .semibold, design: .serif))
            .tracking(-0.3)
    }
}

struct TrackRow: View {
    let track: Track
    var queue: [Track]? = nil

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerManager

    var body: some View {
        HStack(spacing: 12) {
            Button {
                player.play(track, queue: queue ?? [track])
            } label: {
                HStack(spacing: 12) {
                    ArtworkView(url: track.artworkURL, seed: track.title + track.artist)
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    if track.isCloud {
                        if library.isDownloading(track) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.secondary)
                        } else {
                            Image(systemName: library.isDownloaded(track) ? "arrow.down.circle.fill" : "icloud")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if library.isFavorite(track) {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(track.durationText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button {
                    player.play(track, queue: queue ?? [track])
                } label: {
                    Label("Play", systemImage: "play.fill")
                }

                Button {
                    library.toggleFavorite(track)
                } label: {
                    Label(
                        library.isFavorite(track) ? "Remove favorite" : "Favorite",
                        systemImage: library.isFavorite(track) ? "heart.slash" : "heart"
                    )
                }

                if !library.playlists.isEmpty {
                    Menu {
                        ForEach(library.playlists) { playlist in
                            Button(playlist.name) {
                                library.add(track, to: playlist.id)
                            }
                        }
                    } label: {
                        Label("Add to playlist", systemImage: "text.badge.plus")
                    }
                }

                if track.isCloud {
                    if library.isDownloaded(track) {
                        Button(role: .destructive) {
                            library.removeDownload(track)
                        } label: {
                            Label("Remove download", systemImage: "icloud.slash")
                        }
                    } else {
                        Button {
                            Task { await library.download(track) }
                        } label: {
                            Label("Download for offline", systemImage: "arrow.down.circle")
                        }
                        .disabled(library.isDownloading(track))
                    }
                }

                if library.contains(track) {
                    Button(role: .destructive) {
                        library.delete(track)
                    } label: {
                        Label("Delete from library", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 42)
                    .contentShape(Rectangle())
            }
        }
        .padding(.vertical, 6)
    }
}
