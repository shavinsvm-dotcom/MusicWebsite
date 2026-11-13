import SwiftUI

struct MiniPlayer: View {
    @EnvironmentObject private var player: PlayerManager
    @Binding var showNowPlaying: Bool

    var body: some View {
        if let track = player.current {
            HStack(spacing: 10) {
                Button {
                    showNowPlaying = true
                } label: {
                    HStack(spacing: 10) {
                        ArtworkView(url: track.artworkURL, seed: track.title + track.artist)
                            .frame(width: 42, height: 42)
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(track.artist)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 4)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    player.toggle()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 38, height: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

                Button {
                    player.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 34, height: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Next")
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .glassSurface(radius: 20)
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
        }
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
                artworkBackground(track)

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.34),
                        Color.black.opacity(0.66),
                        Color.black.opacity(0.92)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

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

    private func artworkBackground(_ track: Track) -> some View {
        ArtworkView(url: track.artworkURL, seed: track.title + track.artist)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .blur(radius: 80)
            .opacity(0.46)
            .overlay(Color.black.opacity(0.18))
    }

    private func content(_ track: Track) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 42, height: 42)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close player")

                Spacer()

                Text("NOW PLAYING")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.6))

                Spacer()

                Button {
                    library.toggleFavorite(track)
                } label: {
                    Image(systemName: library.isFavorite(track) ? "heart.fill" : "heart")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 42, height: 42)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(library.isFavorite(track) ? "Remove favorite" : "Favorite")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.top, 8)

            Spacer(minLength: 18)

            ArtworkView(url: track.artworkURL, seed: track.title + track.artist)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 370)
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.46), radius: 40, x: 0, y: 26)
                .padding(.horizontal, 28)

            Spacer(minLength: 22)

            VStack(spacing: 8) {
                Text(track.title)
                    .font(.system(size: 27, weight: .semibold, design: .serif))
                    .tracking(-0.6)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text(track.artist)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.64))
                    .lineLimit(1)
            }
            .padding(.horizontal, 28)

            VStack(spacing: 6) {
                Slider(
                    value: Binding(
                        get: { isScrubbing ? scrubValue : player.elapsed },
                        set: { scrubValue = $0 }
                    ),
                    in: 0...max(player.duration, 1),
                    onEditingChanged: { editing in
                        if editing {
                            scrubValue = player.elapsed
                            isScrubbing = true
                        } else {
                            player.seek(to: scrubValue)
                            isScrubbing = false
                        }
                    }
                )
                .tint(.white)

                HStack {
                    Text(timeText(isScrubbing ? scrubValue : player.elapsed))
                    Spacer()
                    Text(timeText(max(player.duration - (isScrubbing ? scrubValue : player.elapsed), 0)))
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.52))
            }
            .padding(.horizontal, 26)
            .padding(.top, 18)

            HStack(spacing: 34) {
                Button {
                    player.previous()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 24, weight: .medium))
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Previous")

                Button {
                    player.toggle()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 76, height: 76)
                        .background(.white, in: Circle())
                        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 12)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

                Button {
                    player.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 24, weight: .medium))
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Next")
            }
            .foregroundStyle(.white)
            .padding(.top, 18)

            Spacer(minLength: 14)

            if track.isPreview {
                Label("Apple Music preview · 30 seconds", systemImage: "waveform")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.42))
                    .padding(.bottom, 10)
            }
        }
    }

    private func timeText(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
