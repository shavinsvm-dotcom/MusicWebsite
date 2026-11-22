import AVKit
import Foundation
import SwiftUI
import UIKit

struct MiniPlayer: View {
    @EnvironmentObject private var player: PlayerManager
    @Binding var showNowPlaying: Bool
    let transitionSourceID: String
    let transitionNamespace: Namespace.ID
    @State private var simplifySurface = false

    var body: some View {
        if let track = player.current {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Button {
                        simplifySurface = true
                        showNowPlaying = true
                    } label: {
                        HStack(spacing: 9) {
                            ArtworkView(
                                url: track.artworkURL,
                                seed: track.title + track.artist,
                                thumbnail: true
                            )
                            .id(track.id)
                            .frame(width: 34, height: 34)
                                .clipShape(RoundedRectangle(cornerRadius: 10.5, style: .continuous))
                                .overlay {
                                    ArtworkProgressRing(size: 36, cornerRadius: 11.5)
                                }
                                .transition(.opacity)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(track.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .contentTransition(.opacity)
                                Text(track.artist)
                                    .font(.system(size: 10, weight: .regular))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .contentTransition(.opacity)
                            }

                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(MotifPressStyle(scale: 0.98, opacity: 0.9))
                    .layoutPriority(1)

                    GlassGroup(spacing: 8) {
                        HStack(spacing: 8) {
                            Button {
                                withAnimation(MotifMotion.control) {
                                    player.previous()
                                }
                            } label: {
                                Image(systemName: "backward.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .frame(width: 30, height: 30)
                                    .contentShape(Circle())
                                    .rowControl(Circle())
                            }
                            .buttonStyle(PlayerControlPressStyle())
                            .accessibilityLabel("Previous")

                            Button {
                                withAnimation(MotifMotion.control) {
                                    player.toggle()
                                }
                            } label: {
                                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .frame(width: 34, height: 34)
                                    .contentShape(Circle())
                                    .motifReplace()
                                    .rowControl(Circle())
                            }
                            .buttonStyle(PlayerControlPressStyle(haptic: .medium))
                            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

                            Button {
                                withAnimation(MotifMotion.control) {
                                    player.next()
                                }
                            } label: {
                                Image(systemName: "forward.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .frame(width: 30, height: 30)
                                    .contentShape(Circle())
                                    .rowControl(Circle())
                            }
                            .buttonStyle(PlayerControlPressStyle())
                            .accessibilityLabel("Next")
                        }
                    }
                }
                .animation(MotifMotion.artwork, value: track.id)
                .padding(.leading, 8)
                .padding(.trailing, 8)
                .frame(height: 46)
            }
            .background(miniPlayerSurface)
            .contentShape(Capsule())
            .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 7)
            .modifier(
                MiniPlayerTransitionSource(
                    sourceID: transitionSourceID,
                    namespace: transitionNamespace
                )
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 6)
            .transition(
                .move(edge: .bottom)
                    .combined(with: .opacity)
            )
            .onChange(of: showNowPlaying) { presented in
                guard !presented else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    simplifySurface = false
                }
            }
        }
    }

    private var miniPlayerSurface: some View {
        ZStack {
            if simplifySurface {
                Capsule()
                    .fill(Color(uiColor: .secondarySystemBackground).opacity(0.96))
                    .overlay {
                        Capsule()
                            .stroke(Color.primary.opacity(0.07), lineWidth: 0.8)
                    }
                    .transition(.opacity)
            } else {
                Color.clear
                    .playerGlass(Capsule())
                    .transition(.opacity)
            }
        }
        .animation(MotifMotion.settle, value: simplifySurface)
    }

}


private struct PlayerBackdrop: View {
    let artworkURL: URL?
    let cachedImage: UIImage?

    @State private var image: UIImage?
    @State private var gradient = PlayerGradient.fallback

    private var displayImage: UIImage? {
        image ?? cachedImage
    }

    var body: some View {
        GeometryReader { geometry in
            let screen = geometry.size

            ZStack {
                Color.black

                // The wash only shows while the pre-blurred cover is still
                // being prepared. Once it arrives the gradient is dropped
                // entirely, so no full-screen mesh sits under an opaque image.
                if displayImage == nil {
                    PlayerGradientView(gradient: gradient)
                }

                // The cache image is already blurred and colour-graded, so it
                // is drawn as a plain fill instead of paying for another live
                // full-surface blur on every frame.
                if let displayImage {
                    Image(uiImage: displayImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: screen.width, height: screen.height)
                        .clipped()
                        .opacity(0.78)
                        .transition(.opacity)
                }

                // The backdrop already mirrors the bottom's blurred
                // refraction band above the cover, so the top only needs a
                // light scrim to keep the bar readable. The bottom falloff
                // stays exactly as it was.
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.38), location: 0),
                        .init(color: .black.opacity(0.15), location: 0.12),
                        .init(color: .black.opacity(0.00), location: 0.30),
                        .init(color: .black.opacity(0.22), location: 0.50),
                        .init(color: .black.opacity(0.34), location: 0.66),
                        .init(color: .black.opacity(0.72), location: 0.88),
                        .init(color: .black, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            // Pin the backdrop to the screen. Without a definite height the
            // resizable image reports its own aspect-derived height, which
            // stretches the player's root ZStack and clips its chrome.
            .frame(width: screen.width, height: screen.height)
            .clipped()
            .animation(MotifMotion.artwork, value: artworkURL)
            .animation(MotifMotion.settle, value: displayImage != nil)
        }
        .ignoresSafeArea()
        .task(id: artworkURL) {
            await load()
        }
    }

    private func load() async {
        guard let artworkURL else {
            image = nil
            gradient = .fallback
            return
        }

        image = PlaybackBackdropCache.shared.image(for: artworkURL)
        gradient = PlaybackBackdropCache.shared.gradient(for: artworkURL) ?? .fallback

        async let gradientTask = PlaybackBackdropCache.shared.prepareGradient(for: artworkURL)
        async let imageTask = PlaybackBackdropCache.shared.prepare(for: artworkURL)

        let nextGradient = await gradientTask
        guard !Task.isCancelled else { return }
        gradient = nextGradient

        if let prepared = await imageTask {
            guard !Task.isCancelled else { return }
            image = prepared
        }
    }
}

struct NowPlayingView: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var library: LibraryStore

    let backdropImage: UIImage?
    let onClose: () -> Void

    @ObservedObject private var equalizer = Equalizer.shared
    @State private var showQueue = false
    @State private var showEqualizer = false
    @State private var lyricsTrack: Track?
    @State private var lyricsFinderTrack: Track?
    @State private var effectsReady = false
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 58
    @ScaledMetric(relativeTo: .body) private var artistSize: CGFloat = 14
    @ScaledMetric(relativeTo: .caption) private var metaSize: CGFloat = 11

    private var currentTrack: Track? {
        guard let current = player.current else { return nil }
        return library.tracks.first { existing in
            existing.id == current.id
                || (current.remoteID != nil && existing.remoteID == current.remoteID)
        } ?? current
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let track = currentTrack {
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
        .environment(\.colorScheme, .dark)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                withAnimation(MotifMotion.overlay) {
                    effectsReady = true
                }
            }
        }
        .sheet(isPresented: $showQueue) {
            UpNextView()
                .environmentObject(player)
        }
        .sheet(isPresented: $showEqualizer) {
            EqualizerView()
        }
        .sheet(item: $lyricsTrack) { track in
            LyricsView(track: track)
                .environmentObject(player)
                .environmentObject(player.progress)
        }
        .sheet(item: $lyricsFinderTrack) { track in
            LyricsFinderView(track: track)
                .environmentObject(library)
        }
        .alert(
            "Couldn’t complete that",
            isPresented: Binding(
                get: { library.errorMessage != nil },
                set: { if !$0 { library.errorMessage = nil } }
            )
        ) {
            Button("OK") { library.errorMessage = nil }
        } message: {
            Text(library.errorMessage ?? "")
        }
    }

    private func backdrop(_ track: Track) -> some View {
        PlayerBackdrop(
            artworkURL: track.artworkURL,
            cachedImage: backdropImage
        )
    }


    private func content(_ track: Track) -> some View {
        GeometryReader { geometry in
            // Slightly wider than the screen so the artwork never exposes a
            // side seam; the extra edge is clipped by the display.
            let artSide = min(
                geometry.size.width + 12,
                geometry.size.height * 0.53
            )

            ZStack(alignment: .top) {
                ZStack {
                    ArtworkView(
                        url: track.artworkURL,
                        seed: track.title + track.artist,
                        highResolution: true
                    )

                    // Carry the blurred backdrop a little way over the sharp
                    // artwork so the hand-off has no visible boundary.
                    if let backdropImage {
                        Image(uiImage: backdropImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: artSide, height: artSide)
                            .mask(
                                LinearGradient(
                                    stops: [
                                        .init(color: .black, location: 0),
                                        .init(color: .black.opacity(0.84), location: 0.09),
                                        .init(color: .black.opacity(0.36), location: 0.18),
                                        .init(color: .clear, location: 0.30),
                                        .init(color: .clear, location: 0.69),
                                        .init(color: .black.opacity(0.72), location: 0.91),
                                        .init(color: .black, location: 1)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .opacity(0.86)
                            .allowsHitTesting(false)
                    }

                    if effectsReady {
                        HeroEdgeBlurOverlay(
                            url: track.artworkURL,
                            intensity: 1,
                            isPlaying: player.isPlaying
                        )
                            .transition(.opacity)
                    }
                }
                .compositingGroup()
                .id(track.id)
                .transition(.opacity)
                .frame(width: artSide, height: artSide)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.55), location: 0.09),
                            .init(color: .black, location: 0.24),
                            .init(color: .black, location: 0.62),
                            .init(color: .black.opacity(0.40), location: 0.85),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .position(
                    x: geometry.size.width / 2,
                    y: geometry.size.height * 0.38
                )
                .animation(MotifMotion.artwork, value: track.id)

                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(track.title)
                            .font(
                                .system(
                                    size: min(titleSize, 68),
                                    weight: .black
                                )
                            )
                            .tracking(-1.6)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                            .minimumScaleFactor(0.55)
                            .allowsTightening(true)
                            .fixedSize(horizontal: false, vertical: true)
                            .contentTransition(.opacity)

                        Text(track.artist)
                            .font(
                                .system(
                                    size: min(artistSize, 17),
                                    weight: .medium
                                )
                            )
                            .foregroundStyle(.white.opacity(0.60))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .contentTransition(.opacity)

                        HStack(spacing: 7) {
                            Image(systemName: "opticaldisc")
                                .font(.system(size: 10, weight: .medium))
                            Text(metadataText(track))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .font(
                            .system(
                                size: min(metaSize, 13),
                                weight: .medium
                            )
                        )
                        .foregroundStyle(.white.opacity(0.48))
                        .padding(.top, 1)
                        .contentTransition(.opacity)

                        Menu {
                            lyricsOptions(track)
                        } label: {
                            Label(
                                track.lyrics?.isEmpty == false ? "Lyrics" : "Find Lyrics",
                                systemImage: "quote.bubble"
                            )
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.78))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .playerGlass(Capsule(), interactive: true)
                            .contentShape(Capsule())
                        }
                        .buttonStyle(MotifPressStyle(scale: 0.94))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .animation(MotifMotion.artwork, value: track.id)

                    NowPlayingScrubber()
                        .padding(.horizontal, 24)
                        .padding(.top, 10)

                    controls(track)
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                        .padding(.bottom, -14)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)

                VStack(spacing: 0) {
                    topBar(track)
                        .padding(.top, 4)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func topBar(_ track: Track) -> some View {
        ZStack {
            GlassGroup(spacing: 10) {
                HStack {
                    Button {
                        onClose()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .playerGlass(Circle())
                }
                .buttonStyle(PlayerControlPressStyle())
                .accessibilityLabel("Close player")

                Spacer()

                HStack(spacing: 6) {
                    AirPlayRoutePicker()
                        .frame(width: 40, height: 40)
                        .playerGlass(Circle())

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

                    if track.source == .local && track.mediaURL.isFileURL {
                        if track.isUploadedToCloud {
                            Button {} label: {
                                Label("Uploaded to cloud", systemImage: "checkmark.icloud")
                            }
                            .disabled(true)
                        } else if library.isUploading(track) {
                            Button {} label: {
                                Label("Uploading…", systemImage: "icloud.and.arrow.up")
                            }
                            .disabled(true)
                        } else {
                            Button {
                                Task { await library.uploadToCloud(track) }
                            } label: {
                                Label("Upload to cloud", systemImage: "icloud.and.arrow.up")
                            }
                        }
                    }

                    Section {
                        Button {
                            showQueue = true
                        } label: {
                            Label("Up Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                        }

                        Menu {
                            lyricsOptions(track)
                        } label: {
                            Label("Lyrics", systemImage: "quote.bubble")
                        }
                    }

                    Section("Playback") {
                        Button {
                            MotifHaptics.play(.light)
                            player.setAutomix(!player.automixEnabled)
                        } label: {
                            Label(
                                player.automixEnabled ? "Automix · On" : "Automix",
                                systemImage: "waveform.path.ecg"
                            )
                        }

                        Button {
                            MotifHaptics.play(.light)
                            showEqualizer = true
                        } label: {
                            Label(
                                equalizer.isEnabled ? "Equalizer · On" : "Equalizer",
                                systemImage: "slider.vertical.3"
                            )
                        }

                        Menu {
                            if player.isSleepTimerActive {
                                Button {
                                    player.cancelSleepTimer()
                                } label: {
                                    Label("Cancel Sleep Timer", systemImage: "xmark.circle")
                                }
                                Divider()
                            }

                            ForEach([5, 10, 15, 30, 45, 60], id: \.self) { minutes in
                                Button("\(minutes) minutes") {
                                    player.setSleepTimer(minutes: minutes)
                                }
                            }
                        } label: {
                            Label(
                                player.sleepTimerRemainingText.map { "Sleep Timer · \($0)" } ?? "Sleep Timer",
                                systemImage: "moon.zzz"
                            )
                        }

                        Menu {
                            ForEach([0, 2, 4, 6, 8, 12], id: \.self) { seconds in
                                Button {
                                    player.setCrossfade(Double(seconds))
                                } label: {
                                    HStack {
                                        Text(seconds == 0 ? "Off" : "\(seconds) seconds")
                                        if abs(player.crossfadeDuration - Double(seconds)) < 0.01 {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Label(
                                player.crossfadeDuration > 0
                                    ? "Crossfade · \(Int(player.crossfadeDuration))s"
                                    : "Crossfade",
                                systemImage: "arrow.left.arrow.right"
                            )
                        }
                    }

                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .playerGlass(Circle())
                }
                .buttonStyle(PlayerControlPressStyle())
                .accessibilityLabel("More options")
                }
                }
            }

            Text("Now playing")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.82))
                .shadow(color: .black.opacity(0.50), radius: 6, y: 1)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, 24)
        .frame(height: 44)
    }

    private func controls(_ track: Track) -> some View {
        GlassGroup(spacing: 6) {
            HStack(spacing: 6) {
            circularButton(
                icon: library.isFavorite(track) ? "heart.fill" : "heart",
                active: library.isFavorite(track)
            ) {
                withAnimation(MotifMotion.control) {
                    library.toggleFavorite(track)
                }
            }
            .accessibilityLabel(library.isFavorite(track) ? "Remove favorite" : "Favorite")

            circularButton(icon: "shuffle", active: player.isShuffled) {
                withAnimation(MotifMotion.control) {
                    player.toggleShuffle()
                }
            }
            .accessibilityLabel(player.isShuffled ? "Turn shuffle off" : "Shuffle")

            repeatButton

            Spacer(minLength: 2)

            Button {
                withAnimation(MotifMotion.control) {
                    player.previous()
                }
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .playerGlass(Circle())
            }
            .buttonStyle(PlayerControlPressStyle())
            .accessibilityLabel("Previous")

            Button {
                withAnimation(MotifMotion.control) {
                    player.toggle()
                }
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 68, height: 68)
                    .motifReplace()
                    .playerGlass(Circle())
            }
            .buttonStyle(PlayerControlPressStyle(haptic: .medium))
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

            Button {
                withAnimation(MotifMotion.control) {
                    player.next()
                }
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .playerGlass(Circle())
            }
            .buttonStyle(PlayerControlPressStyle())
            .accessibilityLabel("Next")
            }
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
                .playerGlass(Circle())
        }
        .buttonStyle(PlayerControlPressStyle())
    }

    private var repeatButton: some View {
        Button {
            player.cycleRepeat()
        } label: {
            ZStack(alignment: .bottom) {
                Image(systemName: "repeat")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(player.repeatMode == .off ? Color.white.opacity(0.62) : Color.white)

                if player.repeatMode != .off {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 3.5, height: 3.5)
                        .offset(y: 2)
                        .transition(.opacity)
                }
            }
            .animation(MotifMotion.control, value: player.repeatMode)
            .frame(width: 42, height: 42)
            .playerGlass(Circle())
        }
        .buttonStyle(PlayerControlPressStyle())
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

    @ViewBuilder
    private func lyricsOptions(_ track: Track) -> some View {
        if track.lyrics?.isEmpty == false {
            Button {
                lyricsTrack = track
            } label: {
                Label("View Lyrics", systemImage: "quote.bubble")
            }

            Divider()
        }

        Button {
            lyricsFinderTrack = track
        } label: {
            Label(
                track.lyrics?.isEmpty == false ? "Find Different Lyrics" : "Find Lyrics Online",
                systemImage: "globe"
            )
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
    @State private var sliderValue = 0.0
    @State private var lastSeekAt = Date.distantPast

    private var duration: Double {
        max(player.duration, 0)
    }

    private var range: ClosedRange<Double> {
        0...max(duration, 1)
    }

    var body: some View {
        VStack(spacing: 2) {
            Slider(
                value: $sliderValue,
                in: range,
                onEditingChanged: { editing in
                    if editing {
                        isScrubbing = true
                    } else {
                        player.seek(to: sliderValue)
                        lastSeekAt = Date()
                        isScrubbing = false
                    }
                }
            )
            .tint(.white)
            .disabled(duration <= 0)
            // Bridge the 4 Hz progress ticks without animating the thumb
            // while a finger is on it.
            .animation(
                isScrubbing ? nil : .linear(duration: 0.24),
                value: sliderValue
            )
            .accessibilityLabel("Playback position")
            .accessibilityValue("\(timeText(sliderValue)) of \(timeText(duration))")

            HStack {
                Text(timeText(sliderValue))
                Spacer()
                Text(timeText(max(duration - sliderValue, 0)))
            }
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(0.50))
            .padding(.horizontal, 2)
        }
        .onAppear {
            sliderValue = clamped(progress.elapsed)
        }
        .onChange(of: player.current?.id) { _ in
            // A new track starts at zero; never animate the old position
            // rewinding across the slider.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                sliderValue = 0
            }
            lastSeekAt = Date()
        }
        .onChange(of: progress.elapsed) { elapsed in
            guard !isScrubbing,
                  Date().timeIntervalSince(lastSeekAt) > 0.35
            else { return }
            let next = clamped(elapsed)
            guard abs(next - sliderValue) > 0.02 else { return }
            sliderValue = next
        }
        .onChange(of: duration) { _ in
            guard !isScrubbing,
                  Date().timeIntervalSince(lastSeekAt) > 0.35
            else { return }
            sliderValue = clamped(progress.elapsed)
        }
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, 0), duration)
    }

    private func timeText(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct MiniPlayerTransitionSource: ViewModifier {
    let sourceID: String
    let namespace: Namespace.ID

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.matchedTransitionSource(id: sourceID, in: namespace) { source in
                source.clipShape(
                    RoundedRectangle(cornerRadius: 23, style: .continuous)
                )
            }
        } else {
            content
        }
    }
}

struct UpNextView: View {
    @EnvironmentObject private var player: PlayerManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let current = player.current {
                    Section("Now Playing") {
                        QueueRow(
                            track: current,
                            isCurrent: true,
                            isPlaying: player.isPlaying
                        )
                    }
                }

                Section("Next Up") {
                    if player.upNextTracks.isEmpty {
                        Text("Nothing queued. Add songs from any song’s menu.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(player.upNextTracks.enumerated()), id: \.element.id) { index, track in
                            Button {
                                player.jumpTo(track)
                                dismiss()
                            } label: {
                                QueueRow(track: track, isCurrent: false)
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button(role: .destructive) {
                                    player.removeFromUpNext(at: IndexSet(integer: index))
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                            .accessibilityHint("Plays this song now")
                        }
                        .onMove { source, destination in
                            player.moveUpNext(from: source, to: destination)
                        }
                        .onDelete { offsets in
                            player.removeFromUpNext(at: offsets)
                        }
                    }
                }
            }
            .navigationTitle("Up Next")
            .navigationBarTitleDisplayMode(.large)
            .nativeScrollHeader()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 14) {
                        if !player.upNextTracks.isEmpty {
                            Button("Clear") {
                                player.clearUpNext()
                            }
                        }

                        Button("Done") { dismiss() }
                    }
                }
            }
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.medium, .large])
    }
}

private struct AirPlayRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = .white
        picker.activeTintColor = .white
        picker.prioritizesVideoDevices = false
        picker.backgroundColor = .clear
        return picker
    }

    func updateUIView(_ picker: AVRoutePickerView, context: Context) {}
}

private struct QueueRow: View {
    let track: Track
    let isCurrent: Bool
    var isPlaying = false

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(
                url: track.artworkURL,
                seed: track.title + track.artist,
                thumbnail: true
            )
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(track.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if isCurrent {
                PlayingWaveform(isPlaying: isPlaying)
                    .frame(width: 14, height: 12)
            }

            Text(track.durationText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
