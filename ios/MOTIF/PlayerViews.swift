import SwiftUI
import UIKit

struct MiniPlayer: View {
    @EnvironmentObject private var player: PlayerManager
    @Binding var showNowPlaying: Bool
    let transitionSourceID: String
    let transitionNamespace: Namespace.ID
    @State private var playPulse = 0
    @State private var skipPulse = 0

    var body: some View {
        if let track = player.current {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Button {
                        showNowPlaying = true
                    } label: {
                        HStack(spacing: 8) {
                            ArtworkView(url: track.artworkURL, seed: track.title + track.artist)
                                .frame(width: 24, height: 24)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .modifier(
                                    MiniArtworkTransitionSource(
                                        sourceID: transitionSourceID,
                                        namespace: transitionNamespace
                                    )
                                )

                            VStack(alignment: .leading, spacing: 1) {
                                Text(track.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(track.artist)
                                    .font(.system(size: 10, weight: .regular))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(MotifPressStyle(scale: 0.98, opacity: 0.9))
                    .layoutPriority(1)

                    Button {
                        skipPulse += 1
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
                            player.previous()
                        }
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 30, height: 30)
                            .motifBounce(tick: skipPulse)
                            .contentShape(Circle())
                    }
                    .buttonStyle(MotifPressStyle(scale: 0.8))
                    .nativeGlass(Circle(), interactive: true)
                    .accessibilityLabel("Previous")

                    Button {
                        playPulse += 1
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.70)) {
                            player.toggle()
                        }
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 34, height: 34)
                            .contentShape(Circle())
                            .motifReplace()
                            .motifBounce(tick: playPulse)
                    }
                    .buttonStyle(MotifPressStyle(scale: 0.8))
                    .nativeGlass(Circle(), interactive: true)
                    .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

                    Button {
                        skipPulse += 1
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
                            player.next()
                        }
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 30, height: 30)
                            .motifBounce(tick: skipPulse)
                            .contentShape(Circle())
                    }
                    .buttonStyle(MotifPressStyle(scale: 0.8))
                    .nativeGlass(Circle(), interactive: true)
                    .accessibilityLabel("Next")
                }
                .padding(.leading, 6)
                .padding(.trailing, 6)
                .frame(height: 42)

                MiniPlayerProgress()
            }
            .nativeGlass(Capsule())
            .contentShape(Capsule())
            .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 7)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .transition(
                .move(edge: .bottom)
                    .combined(with: .opacity)
            )
        }
    }

}

private struct MiniPlayerProgress: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var progress: PlaybackProgress

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let fraction = player.duration > 0
                ? min(max(progress.elapsed / player.duration, 0), 1)
                : 0
            let headX = min(max(width * fraction, 2.5), max(width - 2.5, 2.5))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: width, height: 3)

                Capsule()
                    .fill(Color.white.opacity(0.88))
                    .frame(width: max(width * fraction, 3), height: 3)

                Circle()
                    .fill(Color.white)
                    .frame(width: 5, height: 5)
                    .position(x: headX, y: 1.5)
                    .shadow(color: .black.opacity(0.24), radius: 2, y: 1)
            }
            .frame(width: width, height: 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .animation(
                .linear(duration: player.isPlaying ? 0.90 : 0.20),
                value: fraction
            )
        }
        .frame(height: 3)
        .padding(.horizontal, 18)
        .padding(.bottom, 5)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct NowPlayingView: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @State private var playPulse = 0
    @State private var skipPulse = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let track = player.current {
                backdrop(track)
                content(track)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "music.note")
                        .font(.system(size: 34, weight: .light))
                    Text("Nothing playing")
                        .font(.headline)
                }
                .foregroundStyle(.white.opacity(0.8))
            }
        }
        .preferredColorScheme(.dark)
    }

    private func backdrop(_ track: Track) -> some View {
        GeometryReader { geometry in
            ZStack {
                Color.black

                Group {
                    if let image = track.artworkURL.flatMap({ ArtworkImageCache.shared.image(for: $0) }) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ArtworkView(
                            url: track.artworkURL,
                            seed: track.title + track.artist
                        )
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .scaleEffect(1.24)
                .blur(radius: 46)
                .saturation(1.45)
                .opacity(0.96)
                .drawingGroup()

                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.68), location: 0),
                        .init(color: .black.opacity(0.22), location: 0.30),
                        .init(color: .black.opacity(0.34), location: 0.62),
                        .init(color: .black.opacity(0.82), location: 0.90),
                        .init(color: .black, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
    }

    private func content(_ track: Track) -> some View {
        GeometryReader { geometry in
            let artHeight = min(
                geometry.size.height * 0.60,
                geometry.size.width * 1.28
            )
            let bottomHeight: CGFloat = 243
            let gap = max(
                42,
                min(
                    geometry.size.height * 0.28,
                    geometry.size.height - artHeight - bottomHeight - 6
                )
            )

            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    ArtworkView(url: track.artworkURL, seed: track.title + track.artist)
                        .frame(width: geometry.size.width, height: artHeight)
                        .mask(
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .black, location: 0.16),
                                    .init(color: .black, location: 0.64),
                                    .init(color: .black.opacity(0.5), location: 0.84),
                                    .init(color: .clear, location: 1)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .mask(
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .black, location: 0.11),
                                    .init(color: .black, location: 0.89),
                                    .init(color: .clear, location: 1)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .padding(.top, 4)

                    Spacer().frame(height: gap)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(track.title)
                            .font(.system(size: 44, weight: .heavy))
                            .tracking(-1.8)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.68)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(track.artist)
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(.white.opacity(0.66))
                            .lineLimit(1)

                        HStack(spacing: 8) {
                            Image(systemName: "opticaldisc")
                                .font(.system(size: 13, weight: .regular))
                            Text(metadataText(track))
                                .lineLimit(1)
                        }
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.white.opacity(0.52))
                        .padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)

                    NowPlayingScrubber()
                        .padding(.horizontal, 24)
                        .padding(.top, 10)

                    controls(track)
                        .padding(.horizontal, 22)
                        .padding(.top, 12)

                    Spacer(minLength: 0)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)

                topBar(track)
                    .padding(.top, 4)
            }
        }
    }

    private func topBar(_ track: Track) -> some View {
        ZStack {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .nativeGlass(Circle(), interactive: true)
                }
                .buttonStyle(MotifPressStyle(scale: 0.88))
                .accessibilityLabel("Close player")

                Spacer()

                Menu {
                    if !library.playlists.isEmpty {
                        Section("Add to playlist") {
                            ForEach(library.playlists) { playlist in
                                Button(playlist.name) {
                                    library.add(track, to: playlist.id)
                                }
                            }
                        }
                    }

                    Button {
                        library.toggleFavorite(track)
                    } label: {
                        Label(
                            library.isFavorite(track) ? "Remove favorite" : "Favorite",
                            systemImage: library.isFavorite(track) ? "heart.slash" : "heart"
                        )
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
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .nativeGlass(Circle(), interactive: true)
                }
                .buttonStyle(MotifPressStyle(scale: 0.88))
                .accessibilityLabel("More options")
            }

            Text("Now playing")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
        }
        .padding(.horizontal, 24)
        .frame(height: 44)
    }

    private func controls(_ track: Track) -> some View {
        HStack(spacing: 6) {
            circularButton(
                icon: library.isFavorite(track) ? "heart.fill" : "heart",
                active: library.isFavorite(track)
            ) {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.62)) {
                    library.toggleFavorite(track)
                }
            }
            .accessibilityLabel(library.isFavorite(track) ? "Remove favorite" : "Favorite")

            circularButton(icon: "shuffle", active: player.isShuffled) {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.62)) {
                    player.toggleShuffle()
                }
            }
            .accessibilityLabel(player.isShuffled ? "Turn shuffle off" : "Shuffle")

            repeatButton

            Spacer(minLength: 2)

            Button {
                skipPulse += 1
                withAnimation(.spring(response: 0.24, dampingFraction: 0.74)) {
                    player.previous()
                }
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .motifBounce(tick: skipPulse)
                    .nativeGlass(Circle(), interactive: true)
            }
            .buttonStyle(MotifPressStyle(scale: 0.82))
            .accessibilityLabel("Previous")

            Button {
                playPulse += 1
                withAnimation(.spring(response: 0.22, dampingFraction: 0.70)) {
                    player.toggle()
                }
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 68, height: 68)
                    .motifReplace()
                    .motifBounce(tick: playPulse)
                    .nativeGlass(Circle(), interactive: true)
            }
            .buttonStyle(MotifPressStyle(scale: 0.9))
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

            Button {
                skipPulse += 1
                withAnimation(.spring(response: 0.24, dampingFraction: 0.74)) {
                    player.next()
                }
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .motifBounce(tick: skipPulse)
                    .nativeGlass(Circle(), interactive: true)
            }
            .buttonStyle(MotifPressStyle(scale: 0.82))
            .accessibilityLabel("Next")
        }
    }

    private func circularButton(
        icon: String,
        active: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(active ? Color.white : Color.white.opacity(0.62))
                .frame(width: 42, height: 42)
                .motifReplace()
                .motifBounce(active)
                .nativeGlass(Circle(), interactive: true)
        }
        .buttonStyle(MotifPressStyle(scale: 0.88))
    }

    private var repeatButton: some View {
        Button {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.62)) {
                player.cycleRepeat()
            }
        } label: {
            ZStack(alignment: .bottom) {
                Image(systemName: "repeat")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(player.repeatMode == .off ? Color.white.opacity(0.62) : Color.white)
                    .motifBounce(player.repeatMode != .off)

                if player.repeatMode != .off {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 3.5, height: 3.5)
                        .offset(y: 2)
                }
            }
            .frame(width: 42, height: 42)
            .nativeGlass(Circle(), interactive: true)
        }
        .buttonStyle(MotifPressStyle(scale: 0.88))
        .accessibilityLabel("Repeat")
        .accessibilityValue(repeatLabel)
    }

    private var repeatLabel: String {
        switch player.repeatMode {
        case .off: return "Off"
        case .all: return "All"
        case .one: return "One"
        }
    }

    private func metadataText(_ track: Track) -> String {
        let album = track.album.isEmpty ? "Single" : track.album
        guard let year = track.releaseYear else { return album }
        return "\(album) · \(year)"
    }

}

private struct NowPlayingScrubber: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var progress: PlaybackProgress

    @State private var isScrubbing = false
    @State private var scrubValue = 0.0

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let duration = max(player.duration, 0)
                let displayed = isScrubbing ? scrubValue : progress.elapsed
                let fraction = duration > 0
                    ? CGFloat(min(max(displayed / duration, 0), 1))
                    : 0

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.24))
                        .frame(height: 4)

                    Capsule()
                        .fill(Color.white)
                        .frame(width: width * fraction, height: 4)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 9, height: 9)
                        .position(
                            x: min(max(width * fraction, 4.5), max(width - 4.5, 4.5)),
                            y: geometry.size.height / 2
                        )
                }
                .frame(height: geometry.size.height)
                .animation(
                    isScrubbing ? nil : .linear(duration: 0.42),
                    value: fraction
                )
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard player.duration > 0 else { return }
                            if !isScrubbing {
                                scrubValue = progress.elapsed
                                isScrubbing = true
                            }
                            let fraction = min(max(value.location.x / width, 0), 1)
                            scrubValue = fraction * player.duration
                        }
                        .onEnded { _ in
                            guard player.duration > 0 else { return }
                            player.seek(to: scrubValue)
                            isScrubbing = false
                        }
                )
            }
            .frame(height: 18)

            HStack {
                Text(timeText(isScrubbing ? scrubValue : progress.elapsed))
                Spacer()
                Text(timeText(max(player.duration - (isScrubbing ? scrubValue : progress.elapsed), 0)))
            }
            .font(.system(size: 12, weight: .regular, design: .monospaced))
            .foregroundStyle(.white.opacity(0.54))
        }
    }

    private func timeText(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct MiniArtworkTransitionSource: ViewModifier {
    let sourceID: String
    let namespace: Namespace.ID

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.matchedTransitionSource(id: sourceID, in: namespace)
        } else {
            content
        }
    }
}
