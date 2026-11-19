import Foundation
import SwiftUI
import UIKit

struct MiniPlayer: View {
    @EnvironmentObject private var player: PlayerManager
    @Binding var showNowPlaying: Bool
    let transitionSourceID: String
    let transitionNamespace: Namespace.ID
    @State private var playPulse = 0
    @State private var skipPulse = 0
    private static let tapGenerator = UIImpactFeedbackGenerator(style: .soft)

    var body: some View {
        if let track = player.current {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Button {
                        showNowPlaying = true
                    } label: {
                        HStack(spacing: 9) {
                            ArtworkView(url: track.artworkURL, seed: track.title + track.artist)
                                .frame(width: 36, height: 36)
                                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                                .overlay {
                                    MiniArtworkProgressRing()
                                }

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

                    GlassGroup(spacing: 8) {
                        HStack(spacing: 8) {
                        Button {
                            tapFeedback()
                            skipPulse += 1
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
                                player.previous()
                            }
                        } label: {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 32, height: 32)
                                .motifBounce(tick: skipPulse)
                                .contentShape(Circle())
                        }
                        .buttonStyle(MotifPressStyle(scale: 0.8))
                        .playerGlass(Circle())
                        .accessibilityLabel("Previous")

                        Button {
                            tapFeedback()
                            playPulse += 1
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.70)) {
                                player.toggle()
                            }
                        } label: {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 36, height: 36)
                                .contentShape(Circle())
                                .motifReplace()
                                .motifBounce(tick: playPulse)
                        }
                        .buttonStyle(MotifPressStyle(scale: 0.8))
                        .playerGlass(Circle())
                        .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

                        Button {
                            tapFeedback()
                            skipPulse += 1
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
                                player.next()
                            }
                        } label: {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 32, height: 32)
                                .motifBounce(tick: skipPulse)
                                .contentShape(Circle())
                        }
                        .buttonStyle(MotifPressStyle(scale: 0.8))
                        .playerGlass(Circle())
                        .accessibilityLabel("Next")
                        }
                    }
                }
                .padding(.leading, 8)
                .padding(.trailing, 8)
                .frame(height: 50)
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
            .padding(.bottom, 8)
            .transition(
                .move(edge: .bottom)
                    .combined(with: .opacity)
            )
        }
    }

    private var miniPlayerSurface: some View {
        Color.clear
            .playerGlass(Capsule())
    }

    private func tapFeedback() {
        Self.tapGenerator.impactOccurred(intensity: 0.7)
    }
}

private struct MiniArtworkProgressRing: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var progress: PlaybackProgress

    private var fraction: CGFloat {
        guard player.duration > 0 else { return 0 }
        return CGFloat(min(max(progress.elapsed / player.duration, 0), 1))
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12.5, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1.5)

            RoundedRectangle(cornerRadius: 12.5, style: .continuous)
                .trim(from: 0, to: max(fraction, 0.001))
                .stroke(
                    Color.white.opacity(0.94),
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 38, height: 38)
        .animation(.linear(duration: 0.12), value: fraction)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct NowPlayingView: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var library: LibraryStore

    let backdropImage: UIImage?
    let onClose: () -> Void

    @StateObject private var spatialAudio = SpatialAudioMonitor()
    @ObservedObject private var equalizer = Equalizer.shared
    @State private var playPulse = 0
    @State private var skipPulse = 0
    @State private var showQueue = false
    @State private var showEqualizer = false
    @State private var lyricsTrack: Track?
    @State private var lyricsFinderTrack: Track?
    private static let controlHaptics = UIImpactFeedbackGenerator(style: .light)

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
        GeometryReader { geometry in
            ZStack {
                Color.black

                // The pre-rendered backdrop is the same cover, already blurred
                // off-main. It is what the masked artwork edges fade into.
                Group {
                    if let backdropImage {
                        Image(uiImage: backdropImage)
                            .resizable()
                            .scaledToFill()
                    } else if let image = track.artworkURL.flatMap({
                        ArtworkImageCache.shared.image(for: $0)
                    }) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .blur(radius: 55)
                            .opacity(0.55)
                    } else {
                        Color.black
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .scaleEffect(1.2)
                .blur(radius: 38)
                .clipped()
                .opacity(0.96)

                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.66), location: 0),
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
            .clipped()
        }
        .ignoresSafeArea()
    }

    private func content(_ track: Track) -> some View {
        GeometryReader { geometry in
            let artSide = min(
                geometry.size.width,
                geometry.size.height * 0.52
            )

            ZStack(alignment: .top) {
                ArtworkView(
                    url: track.artworkURL,
                    seed: track.title + track.artist
                )
                .id(track.id)
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
                .frame(width: artSide, height: artSide)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.24),
                            .init(color: .black, location: 0.58),
                            .init(color: .black.opacity(0.24), location: 0.86),
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
                .animation(
                    .spring(response: 0.46, dampingFraction: 0.86),
                    value: track.id
                )

                VStack(spacing: 0) {
                    Spacer(minLength: 0)

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

                        Menu {
                            lyricsOptions(track)
                        } label: {
                            Label(
                                track.lyrics?.isEmpty == false ? "Lyrics" : "Find Lyrics",
                                systemImage: "quote.bubble"
                            )
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.70))
                            .padding(.top, 3)
                        }
                        .buttonStyle(MotifPressStyle(scale: 0.94))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)

                    NowPlayingScrubber()
                        .padding(.horizontal, 24)
                        .padding(.top, 10)

                    controls(track)
                        .padding(.horizontal, 22)
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
                        haptic()
                        onClose()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .playerGlass(Circle())
                }
                .buttonStyle(MotifPressStyle(scale: 0.88))
                .accessibilityLabel("Close player")

                Spacer()

                HStack(spacing: 6) {
                    Button {
                        haptic()
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.72)) {
                            player.setAutomix(!player.automixEnabled)
                        }
                    } label: {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(
                                player.automixEnabled ? Color.white : Color.white.opacity(0.64)
                            )
                            .frame(width: 36, height: 36)
                            .motifBounce(player.automixEnabled)
                            .playerGlass(Circle())
                    }
                    .buttonStyle(MotifPressStyle(scale: 0.86))
                    .accessibilityLabel(player.automixEnabled ? "Turn Automix off" : "Turn Automix on")

                    Button {
                        haptic()
                        showEqualizer = true
                    } label: {
                        Image(systemName: "slider.vertical.3")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(
                                equalizer.isEnabled ? Color.white : Color.white.opacity(0.64)
                            )
                            .frame(width: 36, height: 36)
                            .playerGlass(Circle())
                    }
                    .buttonStyle(MotifPressStyle(scale: 0.86))
                    .accessibilityLabel("Equalizer")

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
                .buttonStyle(MotifPressStyle(scale: 0.88))
                .accessibilityLabel("More options")
                }
                }
            }

            VStack(spacing: 1) {
                Text("Now playing")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))

                if player.automixEnabled {
                    Text(player.automixBPM.map { "AUTOMIX · \($0) BPM" } ?? "AUTOMIX")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(.white.opacity(0.56))
                }

                if let badge = spatialAudio.badge {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform")
                        Text(badge)
                    }
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.68))
                    .transition(.opacity)
                }
            }
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
                haptic()
                withAnimation(.spring(response: 0.24, dampingFraction: 0.62)) {
                    library.toggleFavorite(track)
                }
            }
            .accessibilityLabel(library.isFavorite(track) ? "Remove favorite" : "Favorite")

            circularButton(icon: "shuffle", active: player.isShuffled) {
                haptic()
                withAnimation(.spring(response: 0.24, dampingFraction: 0.62)) {
                    player.toggleShuffle()
                }
            }
            .accessibilityLabel(player.isShuffled ? "Turn shuffle off" : "Shuffle")

            repeatButton

            Spacer(minLength: 2)

            Button {
                haptic()
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
                    .playerGlass(Circle())
            }
            .buttonStyle(MotifPressStyle(scale: 0.82))
            .accessibilityLabel("Previous")

            Button {
                haptic()
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
                    .playerGlass(Circle())
            }
            .buttonStyle(MotifPressStyle(scale: 0.9))
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

            Button {
                haptic()
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
                    .playerGlass(Circle())
            }
            .buttonStyle(MotifPressStyle(scale: 0.82))
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
                .motifBounce(active)
                .playerGlass(Circle())
        }
        .buttonStyle(MotifPressStyle(scale: 0.88))
    }

    private var repeatButton: some View {
        Button {
            haptic()
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
            .playerGlass(Circle())
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

    private func haptic() {
        Self.controlHaptics.impactOccurred(intensity: 0.62)
        Self.controlHaptics.prepare()
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
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(0.56))
            .padding(.horizontal, 2)
        }
        .onAppear {
            sliderValue = clamped(progress.elapsed)
        }
        .onChange(of: player.current?.id) { _ in
            sliderValue = 0
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
            content.matchedTransitionSource(id: sourceID, in: namespace)
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
                        QueueRow(track: current, isCurrent: true)
                    }
                }

                Section("Next Up") {
                    if player.upNextTracks.isEmpty {
                        Text("Nothing queued. Add songs from any song’s menu.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(player.upNextTracks.enumerated()), id: \.element.id) { index, track in
                            QueueRow(track: track, isCurrent: false)
                                .swipeActions {
                                    Button(role: .destructive) {
                                        player.removeFromUpNext(at: IndexSet(integer: index))
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.medium, .large])
    }
}

private struct QueueRow: View {
    let track: Track
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(url: track.artworkURL, seed: track.title + track.artist)
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
                Image(systemName: "waveform")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(track.durationText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
