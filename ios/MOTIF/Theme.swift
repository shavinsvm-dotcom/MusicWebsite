import SwiftUI
import UIKit

struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if colorScheme == .dark {
                Color(red: 0.047, green: 0.047, blue: 0.055)
                RadialGradient(
                    colors: [Color.white.opacity(0.045), Color.clear],
                    center: .top,
                    startRadius: 0,
                    endRadius: 520
                )
            } else {
                Color.white
                RadialGradient(
                    colors: [Color.black.opacity(0.028), Color.clear],
                    center: .top,
                    startRadius: 0,
                    endRadius: 520
                )
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

extension View {
    /// Uses Apple's Liquid Glass on iOS 26 and falls back to a thin system
    /// material on earlier versions. The only hand-built glass in MOTIF is
    /// the closed mini player, which needs its own compact pill treatment.
    @ViewBuilder
    func nativeGlass<S: Shape>(_ shape: S, interactive: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            if interactive {
                glassEffect(.regular.interactive(), in: shape)
            } else {
                glassEffect(.regular, in: shape)
            }
        } else {
            glassFallback(shape)
        }
        #else
        glassFallback(shape)
        #endif
    }

    @ViewBuilder
    private func glassFallback<S: Shape>(_ shape: S) -> some View {
        background(.ultraThinMaterial, in: shape)
    }
}

extension View {
    @ViewBuilder
    func motifBounce(_ trigger: Bool) -> some View {
        if #available(iOS 17.0, *) {
            symbolEffect(.bounce, value: trigger)
        } else {
            self
        }
    }

    @ViewBuilder
    func motifBounce(tick: Int) -> some View {
        if #available(iOS 17.0, *) {
            symbolEffect(.bounce, options: .speed(1.6), value: tick)
        } else {
            self
        }
    }

    func screenEntrance() -> some View {
        modifier(ScreenEntrance())
    }

    @ViewBuilder
    func motifReplace() -> some View {
        if #available(iOS 17.0, *) {
            contentTransition(.symbolEffect(.replace))
        } else {
            self
        }
    }
}

private struct ScreenEntrance: ViewModifier {
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 7)
            .onAppear {
                withAnimation(.easeOut(duration: 0.14)) {
                    appeared = true
                }
            }
            .onDisappear {
                appeared = false
            }
    }
}

struct MotifPressStyle: ButtonStyle {
    var scale: CGFloat = 0.94
    var opacity: Double = 0.86

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? opacity : 1)
            .animation(
                .spring(response: 0.16, dampingFraction: 0.70),
                value: configuration.isPressed
            )
    }
}

private struct GlassSurface: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        content.nativeGlass(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
        )
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

    @State private var image: UIImage?
    @State private var failed = false

    private var resolvedImage: UIImage? {
        if let image { return image }
        guard let url else { return nil }
        return ArtworkImageCache.shared.image(for: url)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: palette,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let image = resolvedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if url != nil, !failed {
                ProgressView()
                    .tint(.white)
            } else {
                fallback
            }
        }
        .clipped()
        .task(id: url) {
            await loadImage()
        }
    }

    @MainActor
    private func loadImage() async {
        guard let url else {
            image = nil
            failed = false
            return
        }

        if let cached = ArtworkImageCache.shared.image(for: url) {
            image = cached
            failed = false
            return
        }

        image = nil
        failed = false

        if url.isFileURL {
            if let local = UIImage(contentsOfFile: url.path) {
                ArtworkImageCache.shared.store(local, for: url)
                image = local
            } else {
                failed = true
            }
            return
        }

        guard let (data, _) = try? await URLSession.shared.data(from: url),
              !Task.isCancelled,
              let remote = UIImage(data: data)
        else {
            if !Task.isCancelled { failed = true }
            return
        }

        ArtworkImageCache.shared.store(remote, for: url)
        image = remote
    }

    private var fallback: some View {
        Text(String(seed.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased())
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(.white.opacity(0.88))
    }

    private var palette: [Color] {
        let lift = 0.10 + stableHue * 0.10
        return [
            Color(white: 0.18 + lift),
            Color(white: 0.10 + lift * 0.45)
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

final class ArtworkImageCache {
    static let shared = ArtworkImageCache()

    private let cache = NSCache<NSURL, UIImage>()

    private init() {
        cache.countLimit = 160
        cache.totalCostLimit = 96 * 1024 * 1024
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func store(_ image: UIImage, for url: URL) {
        let cost = Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: url as NSURL, cost: cost)
    }
}

struct SectionTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 19, weight: .semibold))
            .tracking(-0.3)
    }
}

struct TrackRow: View {
    let track: Track
    var queue: [Track]? = nil

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerManager

    var body: some View {
        let isDownloaded = track.isCloud && library.isDownloaded(track)
        let isDownloading = track.isCloud && library.isDownloading(track)
        let isFavorite = library.isFavorite(track)

        HStack(spacing: 12) {
            Button {
                player.play(track, queue: queue ?? [track])
            } label: {
                HStack(spacing: 12) {
                    ArtworkView(url: track.artworkURL, seed: track.title + track.artist)
                        .frame(width: 54, height: 54)
                        .clipShape(Circle())

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

                    if isFavorite {
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
            .buttonStyle(MotifPressStyle(scale: 0.99, opacity: 0.9))

            if track.isCloud {
                Button {
                    guard !isDownloaded, !isDownloading else { return }
                    Task { await library.download(track) }
                } label: {
                    Group {
                        if isDownloading {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.secondary)
                        } else {
                            Image(systemName: isDownloaded ? "checkmark.circle.fill" : "arrow.down.circle")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 32, height: 42)
                    .contentShape(Rectangle())
                }
                .buttonStyle(MotifPressStyle(scale: 0.86))
                .disabled(isDownloaded || isDownloading)
                .accessibilityLabel(isDownloaded ? "Available offline" : "Download for offline")
            }

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
