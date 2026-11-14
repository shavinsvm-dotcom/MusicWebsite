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
                        if let url = track.artworkURL {
                            _ = PlaybackBackdropCache.shared.preparedImage(for: url)
                        }
                        showNowPlaying = true
                    } label: {
                        HStack(spacing: 9) {
                            ArtworkView(url: track.artworkURL, seed: track.title + track.artist)
                                .frame(width: 32, height: 32)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                        .nativeGlass(Circle(), interactive: true)
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
                                .frame(width: 32, height: 32)
                                .contentShape(Circle())
                                .motifReplace()
                                .motifBounce(tick: playPulse)
                        }
                        .buttonStyle(MotifPressStyle(scale: 0.8))
                        .nativeGlass(Circle(), interactive: true)
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
                        .nativeGlass(Circle(), interactive: true)
                        .accessibilityLabel("Next")
                    }
                }
                .padding(.leading, 8)
                .padding(.trailing, 8)
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

    private func tapFeedback() {
        Self.tapGenerator.impactOccurred(intensity: 0.7)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let backdropImage: UIImage?

    @StateObject private var spatialAudio = SpatialAudioMonitor()
    @State private var playPulse = 0
    @State private var skipPulse = 0
    @State private var showQueue = false
    @State private var lyricsTrack: Track?
    @State private var transitionSettled = false

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
        .task {
            if reduceMotion {
                transitionSettled = true
                return
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.28)) {
                transitionSettled = true
            }
        }
        .sheet(isPresented: $showQueue) {
            UpNextView()
                .environmentObject(player)
        }
        .sheet(item: $lyricsTrack) { track in
            LyricsView(track: track)
        }
    }

    private func backdrop(_ track: Track) -> some View {
        GeometryReader { geometry in
            ZStack {
                Color.black

                Group {
                    if let backdropImage {
                        Image(uiImage: backdropImage)
                            .resizable()
                            .scaledToFill()
                    } else if let image = track.artworkURL.flatMap({ ArtworkImageCache.shared.image(for: $0) }) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .opacity(0.42)
                    } else {
                        Color.black
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .opacity(0.96)

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

                        if let lyrics = track.lyrics, !lyrics.isEmpty {
                            Button {
                                lyricsTrack = track
                            } label: {
                                Label("Lyrics", systemImage: "quote.bubble")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.70))
                                    .padding(.top, 3)
                            }
                            .buttonStyle(MotifPressStyle(scale: 0.94))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .opacity(transitionSettled ? 1 : 0)
                    .allowsHitTesting(transitionSettled)

                    NowPlayingScrubber()
                        .padding(.horizontal, 24)
                        .padding(.top, 10)
                        .opacity(transitionSettled ? 1 : 0)
                        .allowsHitTesting(transitionSettled)

                    controls(track)
                        .padding(.horizontal, 22)
                        .padding(.top, 12)
                        .opacity(transitionSettled ? 1 : 0)
                        .allowsHitTesting(transitionSettled)

                    Spacer(minLength: 0)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)

                topBar(track)
                    .padding(.top, 4)
                    .opacity(transitionSettled ? 1 : 0)
                    .allowsHitTesting(transitionSettled)
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

                    Section {
                        Button {
                            showQueue = true
                        } label: {
                            Label("Up Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                        }

                        Button {
                            lyricsTrack = track
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
                        .nativeGlass(Circle(), interactive: true)
                }
                .buttonStyle(MotifPressStyle(scale: 0.88))
                .accessibilityLabel("More options")
            }

            VStack(spacing: 1) {
                Text("Now playing")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))

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

struct LyricsView: View {
    @Environment(\.dismiss) private var dismiss
    let track: Track

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 14) {
                        ArtworkView(url: track.artworkURL, seed: track.title + track.artist)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(track.title)
                                .font(.headline)
                                .lineLimit(2)
                            Text(track.artist)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let lyrics = displayLyrics {
                        Text(lyrics)
                            .font(.system(size: 24, weight: .semibold, design: .serif))
                            .lineSpacing(9)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "quote.bubble")
                                .font(.system(size: 30, weight: .light))
                                .foregroundStyle(.tertiary)
                            Text("Lyrics aren’t available for this track.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 48)
                    }
                }
                .padding(24)
            }
            .navigationTitle("Lyrics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
        .presentationDetents([.medium, .large])
    }

    private var displayLyrics: String? {
        guard let lyrics = track.lyrics else { return nil }
        let stripped = lyrics.replacingOccurrences(
            of: "\\[\\d{1,2}:\\d{2}(?:\\.\\d{1,2})?\\]",
            with: "",
            options: .regularExpression
        )
        let trimmed = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
