import SwiftUI

struct MiniPlayer: View {
    @EnvironmentObject private var player: PlayerManager
    @Binding var showNowPlaying: Bool

    var body: some View {
        if let track = player.current {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Button {
                        showNowPlaying = true
                    } label: {
                        HStack(spacing: 8) {
                            ArtworkView(url: track.artworkURL, seed: track.title + track.artist)
                                .frame(width: 24, height: 24)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

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
                    .buttonStyle(.plain)
                    .layoutPriority(1)

                    if let next = player.upNext {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(next.title)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(next.artist)
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: 112, alignment: .trailing)
                        .padding(.leading, 2)
                    }

                    Button {
                        player.toggle()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 28, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

                    Button {
                        player.next()
                    } label: {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 28, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Next")
                }
                .padding(.leading, 6)
                .padding(.trailing, 8)
                .frame(height: 46)
            }
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            }
            .overlay(alignment: .bottom) {
                progress
            }
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 8)
        }
    }

    private var progress: some View {
        GeometryReader { geometry in
            let fraction = player.duration > 0
                ? min(max(player.elapsed / player.duration, 0), 1)
                : 0

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.16))
                Capsule()
                    .fill(Color.white.opacity(0.72))
                    .frame(width: geometry.size.width * fraction)
            }
            .padding(.horizontal, 10)
        }
        .frame(height: 2)
        .padding(.bottom, 1)
        .allowsHitTesting(false)
    }
}

struct NowPlayingView: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @State private var isScrubbing = false
    @State private var scrubValue = 0.0

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
                ArtworkView(url: track.artworkURL, seed: track.title + track.artist)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .scaleEffect(1.08)
                    .saturation(1.18)
                    .blur(radius: 26)

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.08),
                        Color.black.opacity(0.14),
                        Color.black.opacity(0.70),
                        Color.black.opacity(0.95)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                RadialGradient(
                    colors: [Color.clear, Color.black.opacity(0.24)],
                    center: .center,
                    startRadius: geometry.size.width * 0.30,
                    endRadius: geometry.size.width * 0.86
                )
            }
            .ignoresSafeArea()
        }
    }

    private func content(_ track: Track) -> some View {
        GeometryReader { geometry in
            let artSide = min(geometry.size.width - 84, geometry.size.height * 0.40)
            let bottomHeight: CGFloat = 243
            let gap = max(
                42,
                min(
                    geometry.size.height * 0.28,
                    geometry.size.height - artSide - bottomHeight - 6
                )
            )

            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    ArtworkView(url: track.artworkURL, seed: track.title + track.artist)
                        .frame(width: artSide, height: artSide)
                        .clipShape(Rectangle())
                        .overlay(alignment: .bottom) {
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.16)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 52)
                        }
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
                    .padding(.horizontal, 30)

                    scrubber
                        .padding(.horizontal, 30)
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
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay {
                            Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
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
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("More options")
            }

            Text("Now playing")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
        }
        .padding(.horizontal, 24)
        .frame(height: 44)
    }

    private var scrubber: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let duration = max(player.duration, 0)
                let displayed = isScrubbing ? scrubValue : player.elapsed
                let progress = duration > 0 ? CGFloat(min(max(displayed / duration, 0), 1)) : 0

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.24))
                        .frame(height: 4)

                    Capsule()
                        .fill(Color.white)
                        .frame(width: width * progress, height: 4)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 9, height: 9)
                        .position(
                            x: min(max(width * progress, 4.5), max(width - 4.5, 4.5)),
                            y: geometry.size.height / 2
                        )
                }
                .frame(height: geometry.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard player.duration > 0 else { return }
                            if !isScrubbing {
                                scrubValue = player.elapsed
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
                Text(timeText(isScrubbing ? scrubValue : player.elapsed))
                Spacer()
                Text(timeText(max(player.duration - (isScrubbing ? scrubValue : player.elapsed), 0)))
            }
            .font(.system(size: 12, weight: .regular, design: .monospaced))
            .foregroundStyle(.white.opacity(0.54))
        }
    }

    private func controls(_ track: Track) -> some View {
        HStack(spacing: 8) {
            circularButton(
                icon: library.isFavorite(track) ? "heart.fill" : "heart",
                active: library.isFavorite(track)
            ) {
                library.toggleFavorite(track)
            }
            .accessibilityLabel(library.isFavorite(track) ? "Remove favorite" : "Favorite")

            circularButton(icon: "shuffle", active: player.isShuffled) {
                player.toggleShuffle()
            }
            .accessibilityLabel(player.isShuffled ? "Turn shuffle off" : "Shuffle")

            repeatButton

            Spacer(minLength: 4)

            Button {
                player.previous()
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous")

            Button {
                player.toggle()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 78, height: 78)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay {
                        Circle().strokeBorder(Color.white.opacity(0.20), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 10)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

            Button {
                player.next()
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(active ? Color.white : Color.white.opacity(0.62))
                .frame(width: 48, height: 48)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private var repeatButton: some View {
        Button {
            player.cycleRepeat()
        } label: {
            ZStack(alignment: .bottom) {
                Image(systemName: "repeat")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(player.repeatMode == .off ? Color.white.opacity(0.62) : Color.white)

                if player.repeatMode != .off {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 3.5, height: 3.5)
                        .offset(y: 2)
                }
            }
            .frame(width: 48, height: 48)
            .background(.ultraThinMaterial, in: Circle())
            .overlay {
                Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
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

    private func timeText(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
