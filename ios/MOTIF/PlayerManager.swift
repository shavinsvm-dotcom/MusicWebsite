import AVFoundation
import Combine
import Foundation
import MediaPlayer
import UIKit
import WidgetKit

@MainActor
final class PlaybackProgress: ObservableObject {
    @Published var elapsed: Double = 0
}

/// The only playback facts a song row draws from. Rows observe this small
/// object instead of `PlayerManager`, so queue edits, duration updates, sleep
/// timer changes and playback errors never invalidate a long list.
@MainActor
final class NowPlayingMarker: ObservableObject {
    @Published fileprivate(set) var trackID: UUID?
    @Published fileprivate(set) var remoteID: String?
    @Published fileprivate(set) var isPlaying = false
}

/// How much bandwidth and buffering streaming playback may spend. Cloud songs
/// are stored once at their uploaded quality, so these modes change network
/// behaviour rather than the fidelity of the stored file.
enum PlaybackQuality: String, CaseIterable, Identifiable {
    case dataSaver
    case balanced
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dataSaver: return "Data Saver"
        case .balanced: return "Balanced"
        case .high: return "High Quality"
        }
    }

    /// Adaptive streams honour this cap; progressive files play as stored.
    var peakBitRate: Double {
        switch self {
        case .dataSaver: return 128_000
        case .balanced: return 256_000
        case .high: return 0
        }
    }

    var forwardBufferDuration: TimeInterval {
        switch self {
        case .dataSaver: return 2
        case .balanced: return 6
        case .high: return 15
        }
    }

    var waitsToMinimizeStalling: Bool {
        self != .dataSaver
    }
}

@MainActor
final class PlayerManager: ObservableObject {
    enum RepeatMode {
        case off
        case all
        case one
    }

    @Published private(set) var current: Track? {
        didSet { syncMarker() }
    }
    @Published private(set) var queue: [Track] = []
    @Published private(set) var isPlaying = false {
        didSet { syncMarker() }
    }
    @Published private(set) var duration: Double = 0
    /// True once the current item reports its own duration, rather than the
    /// metadata duration copied from the track when loading began.
    @Published private(set) var isDurationLoaded = false
    @Published private(set) var isShuffled = false
    @Published private(set) var repeatMode: RepeatMode = .off
    @Published private(set) var crossfadeDuration: TimeInterval = UserDefaults.standard.double(forKey: "motif.crossfadeDuration")
    @Published private(set) var playbackQuality: PlaybackQuality = PlaybackQuality(
        rawValue: UserDefaults.standard.string(forKey: "motif.playbackQuality") ?? ""
    ) ?? .balanced
    @Published private(set) var automixEnabled = UserDefaults.standard.bool(forKey: "motif.automixEnabled")
    @Published private(set) var sleepTimerEnd: Date?
    @Published private(set) var playbackError: String?

    var onTrackStarted: ((Track) -> Void)?
    var automixContinuationProvider: ((Track, Set<UUID>) -> Track?)?

    let progress = PlaybackProgress()
    let nowPlaying = NowPlayingMarker()

    var elapsed: Double { progress.elapsed }

    private func syncMarker() {
        if nowPlaying.trackID != current?.id {
            nowPlaying.trackID = current?.id
        }
        if nowPlaying.remoteID != current?.remoteID {
            nowPlaying.remoteID = current?.remoteID
        }
        if nowPlaying.isPlaying != isPlaying {
            nowPlaying.isPlaying = isPlaying
        }
    }

    var upNext: Track? { upNextTracks.first }

    var upNextTracks: [Track] {
        guard let current,
              let index = queue.firstIndex(where: { $0.id == current.id })
        else { return [] }
        return Array(queue.dropFirst(index + 1))
    }

    var isSleepTimerActive: Bool { sleepTimerEnd != nil }

    var automixBPM: Int? {
        guard automixEnabled, let current,
              let grid = automixAnalysis.grid(for: current),
              grid.confidence >= 0.18
        else { return nil }
        return Int(grid.bpm.rounded())
    }

    var sleepTimerRemainingText: String? {
        guard let sleepTimerEnd else { return nil }
        let remaining = max(0, sleepTimerEnd.timeIntervalSinceNow)
        let minutes = max(1, Int(ceil(remaining / 60)))
        return "\(minutes) min"
    }

    private var player = AVPlayer()
    private var fadePlayer = AVPlayer()
    private var currentIndex = 0
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private var itemStatusObservation: NSKeyValueObservation?
    private var wasPlayingBeforeInterruption = false
    private var navigationHistory: [Int] = []
    private var lastWidgetSurfaceUpdate = Date.distantPast
    private var lastWidgetTrackID: UUID?
    private var lastWidgetIsPlaying: Bool?
    private var nowPlayingArtworkLoadingURL: URL?
    private var nowPlayingArtwork: MPMediaItemArtwork?
    private var nowPlayingArtworkImage: UIImage?
    private var nowPlayingArtworkURL: URL?
    private var nowPlayingAnimatedArtwork: [String: Any] = [:]
    private var nowPlayingAnimatedArtworkIDs: [String: String] = [:]
    private var artworkCacheObserver: NSObjectProtocol?
    private var artworkPrefetchTask: Task<Void, Never>?
    private var crossfadeTask: Task<Void, Never>?
    private var tempoRestoreTask: Task<Void, Never>?
    private var automixNextIndex: Int?
    private var preloadedNextID: UUID?
    private var preloadedItem: AVPlayerItem?
    private var isCrossfading = false
    private var sleepTask: Task<Void, Never>?
    private let automixAnalysis = AutomixAnalysisService.shared

    init() {
        configureAudioSession()
        configureRemoteCommands()
        installSystemObservers()
        installTimeObserver()
        player.automaticallyWaitsToMinimizeStalling = playbackQuality.waitsToMinimizeStalling

        artworkCacheObserver = NotificationCenter.default.addObserver(
            forName: .motionArtworkCacheChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateNowPlaying()
            }
        }
    }

    deinit {
        if let artworkCacheObserver {
            NotificationCenter.default.removeObserver(artworkCacheObserver)
        }
    }

    func setPlaybackQuality(_ quality: PlaybackQuality) {
        guard quality != playbackQuality else { return }
        playbackQuality = quality
        UserDefaults.standard.set(quality.rawValue, forKey: "motif.playbackQuality")
        applyPlaybackQuality()
    }

    /// Applies the streaming profile to the item already playing and drops the
    /// preloaded item, which was configured with the previous profile.
    private func applyPlaybackQuality() {
        player.automaticallyWaitsToMinimizeStalling = playbackQuality.waitsToMinimizeStalling
        if let item = player.currentItem {
            item.preferredForwardBufferDuration = playbackQuality.forwardBufferDuration
            if let mediaURL = current?.mediaURL, !mediaURL.isFileURL {
                item.preferredPeakBitRate = playbackQuality.peakBitRate
            }
        }
        preloadedNextID = nil
        preloadedItem = nil
    }

    func play(_ track: Track, queue newQueue: [Track]? = nil) {
        if let newQueue, !newQueue.isEmpty {
            queue = newQueue
            navigationHistory.removeAll()
            if !queue.contains(where: { $0.id == track.id }) {
                queue.insert(track, at: 0)
            }
        } else if !queue.contains(where: { $0.id == track.id }) {
            queue = [track]
            navigationHistory.removeAll()
        }

        // Re-selecting the current song from another playlist should still
        // adopt that playlist's queue instead of silently keeping the old one.
        if current?.id == track.id {
            currentIndex = queue.firstIndex(where: { $0.id == track.id }) ?? currentIndex
            prepareAutomixAnalysis()
            prepareNextTrack()
            if !isPlaying { resume() }
            return
        }

        currentIndex = queue.firstIndex(where: { $0.id == track.id }) ?? 0
        navigationHistory.removeAll()
        playbackError = nil
        load(track)
    }

    func playNext(_ track: Track) {
        if current == nil {
            play(track)
            return
        }
        guard let currentIndex = queue.firstIndex(where: { $0.id == current?.id }) else {
            queue.insert(track, at: 0)
            return
        }
        queue.removeAll { $0.id == track.id }
        let insertIndex = min(currentIndex + 1, queue.count)
        queue.insert(track, at: insertIndex)
        navigationHistory.removeAll()
        automixNextIndex = nil
        prepareAutomixAnalysis()
        prepareNextTrack()
    }

    func addToQueue(_ track: Track) {
        if current == nil {
            play(track)
            return
        }
        guard !queue.contains(where: { $0.id == track.id }) else { return }
        queue.append(track)
        navigationHistory.removeAll()
        automixNextIndex = nil
        prepareAutomixAnalysis()
        prepareNextTrack()
    }

    func removeFromUpNext(at offsets: IndexSet) {
        let upcoming = upNextTracks
        let ids = Set(offsets.compactMap { upcoming.indices.contains($0) ? upcoming[$0].id : nil })
        queue.removeAll { ids.contains($0.id) && $0.id != current?.id }
        navigationHistory.removeAll()
        automixNextIndex = nil
        prepareAutomixAnalysis()
        prepareNextTrack()
    }

    /// Plays a song that is already in the queue without disturbing the rest
    /// of the upcoming order.
    func jumpTo(_ track: Track) {
        guard let index = queue.firstIndex(where: { $0.id == track.id }),
              index != currentIndex
        else { return }

        navigationHistory.removeAll()
        currentIndex = index
        playbackError = nil
        load(track)
    }

    func clearUpNext() {
        guard let current,
              queue.contains(where: { $0.id == current.id })
        else { return }

        cancelCrossfade()
        queue = [current]
        currentIndex = 0
        navigationHistory.removeAll()
        automixNextIndex = nil
        prepareAutomixAnalysis()
        prepareNextTrack()
    }

    func moveUpNext(from source: IndexSet, to destination: Int) {
        guard let current,
              let currentIndex = queue.firstIndex(where: { $0.id == current.id }),
              currentIndex + 1 < queue.count
        else { return }
        var upcoming = Array(queue.dropFirst(currentIndex + 1))
        upcoming.move(fromOffsets: source, toOffset: destination)
        queue = Array(queue.prefix(currentIndex + 1)) + upcoming
        navigationHistory.removeAll()
        automixNextIndex = nil
        prepareAutomixAnalysis()
        prepareNextTrack()
    }

    func setCrossfade(_ seconds: TimeInterval) {
        let clamped = max(0, min(seconds, 12))
        crossfadeDuration = clamped
        UserDefaults.standard.set(clamped, forKey: "motif.crossfadeDuration")
        if clamped == 0 && !automixEnabled { cancelCrossfade() }
    }

    func setAutomix(_ enabled: Bool) {
        automixEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "motif.automixEnabled")
        if enabled {
            prepareAutomixAnalysis()
        } else {
            cancelCrossfade()
        }
    }

    private var effectiveTransitionDuration: TimeInterval {
        automixEnabled ? max(crossfadeDuration, 6) : crossfadeDuration
    }

    func setSleepTimer(minutes: Int) {
        sleepTask?.cancel()
        sleepTask = nil
        cancelCrossfade()
        player.volume = 1
        guard minutes > 0 else {
            sleepTimerEnd = nil
            return
        }

        let totalSeconds = Double(minutes * 60)
        let fadeSeconds = min(10, max(1, totalSeconds - 1))
        sleepTimerEnd = Date().addingTimeInterval(totalSeconds)
        sleepTask = Task { [weak self] in
            let fadeStart = max(0, totalSeconds - fadeSeconds)
            if fadeStart > 0 {
                try? await Task.sleep(nanoseconds: UInt64(fadeStart * 1_000_000_000))
            }
            guard !Task.isCancelled, let self else { return }

            let steps = 20
            for step in 1...steps {
                try? await Task.sleep(
                    nanoseconds: UInt64((fadeSeconds / Double(steps)) * 1_000_000_000)
                )
                guard !Task.isCancelled else { return }
                let progress = Double(step) / Double(steps)
                self.player.volume = Float(1 - progress)
            }

            guard !Task.isCancelled else { return }
            self.pause()
            self.player.volume = 1
            self.sleepTimerEnd = nil
            self.sleepTask = nil
        }
    }

    func cancelSleepTimer() {
        sleepTask?.cancel()
        sleepTask = nil
        sleepTimerEnd = nil
        player.volume = 1
    }

    func toggle() {
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    func resume() {
        guard current != nil else {
            if let first = queue.first { play(first) }
            return
        }
        playbackError = nil
        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
        isPlaying = true
        updateNowPlaying()
    }

    func clearPlaybackError() {
        playbackError = nil
    }

    func pause() {
        cancelCrossfade()
        player.pause()
        isPlaying = false
        updateNowPlaying()
    }

    func next() {
        advance(by: 1)
    }

    func previous() {
        if elapsed > 3 {
            seek(to: 0)
            return
        }

        if let previousIndex = navigationHistory.popLast(),
           queue.indices.contains(previousIndex),
           previousIndex != currentIndex {
            currentIndex = previousIndex
            load(queue[previousIndex])
            return
        }

        if currentIndex == 0 {
            if repeatMode == .all, queue.count > 1 {
                currentIndex = queue.count - 1
                load(queue[currentIndex])
            } else {
                seek(to: 0)
            }
            return
        }

        advance(by: -1)
    }

    func toggleShuffle() {
        isShuffled.toggle()
        navigationHistory.removeAll()
        automixNextIndex = nil
        prepareAutomixAnalysis()
        prepareNextTrack()
    }

    func cycleRepeat() {
        switch repeatMode {
        case .off:
            repeatMode = .all
        case .all:
            repeatMode = .one
        case .one:
            repeatMode = .off
        }
        automixNextIndex = nil
        prepareAutomixAnalysis()
        prepareNextTrack()
    }

    func seek(to seconds: Double) {
        guard duration > 0 || seconds == 0 else { return }
        cancelCrossfade()
        let clamped = max(0, min(seconds, duration > 0 ? duration : seconds))
        player.seek(
            to: CMTime(seconds: clamped, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        progress.elapsed = clamped
        updateNowPlaying()
    }

    private func load(_ track: Track) {
        cancelCrossfade()
        automixNextIndex = nil
        playbackError = nil
        current = track
        progress.elapsed = 0
        duration = max(track.duration, 0)
        isDurationLoaded = false
        isPlaying = false

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }

        let item = makePlayerItem(for: track)
        player.replaceCurrentItem(with: item)
        installEndObserver(for: item)
        observeItemStatus(item)

        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
        isPlaying = true
        onTrackStarted?(track)
        prepareAutomixAnalysis()
        prepareNextTrack()
        updateNowPlaying()
        prefetchMotionArtwork(for: track)
    }

    private func prefetchMotionArtwork(for track: Track) {
        let defaults = UserDefaults.standard
        let offline = defaults.object(forKey: "motif.offlineAnimatedCovers") as? Bool ?? true
        guard offline else { return }

        artworkPrefetchTask?.cancel()
        artworkPrefetchTask = Task {
            await MotionArtworkStore.shared.prepareForPlayback(track)
        }
    }

    private func handleTrackEnded() {
        if isCrossfading { return }
        if repeatMode == .one {
            seek(to: 0)
            resume()
            return
        }
        advance(by: 1)
    }

    private func advance(by offset: Int) {
        guard !queue.isEmpty else { return }
        cancelCrossfade()

        if offset > 0 {
            navigationHistory.append(currentIndex)
        }

        if isShuffled, queue.count > 1, offset > 0 {
            let choices = queue.indices.filter { $0 != currentIndex }
            if let randomIndex = choices.randomElement() {
                currentIndex = randomIndex
                load(queue[randomIndex])
                return
            }
        }

        let nextIndex = currentIndex + offset

        if nextIndex >= queue.count {
            if repeatMode == .all {
                currentIndex = 0
                load(queue[0])
            } else if automixEnabled,
                      let current,
                      let next = automixContinuationProvider?(
                          current,
                          Set(queue.map(\.id))
                      ) {
                queue.append(next)
                currentIndex = queue.count - 1
                load(next)
            } else {
                pause()
                seek(to: 0)
            }
            return
        }
        if nextIndex < 0 {
            seek(to: 0)
            return
        }

        currentIndex = nextIndex
        load(queue[nextIndex])
    }

    private func installTimeObserver() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                let seconds = CMTimeGetSeconds(time)
                if seconds.isFinite {
                    let next = max(0, seconds)
                    if abs(next - self.progress.elapsed) > 0.04 {
                        self.progress.elapsed = next
                    }
                }

                if let itemDuration = self.player.currentItem?.duration {
                    let loadedDuration = CMTimeGetSeconds(itemDuration)
                    if loadedDuration.isFinite, loadedDuration > 0 {
                        if abs(loadedDuration - self.duration) > 0.5 {
                            self.duration = loadedDuration
                        }
                        if !self.isDurationLoaded {
                            self.isDurationLoaded = true
                        }
                    }
                }

                self.maybeBeginCrossfade()
            }
        }
    }

    private func installEndObserver(for item: AVPlayerItem) {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleTrackEnded() }
        }
    }

    private func observeItemStatus(_ item: AVPlayerItem) {
        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self, weak item] _, _ in
            guard let self, let item else { return }
            Task { @MainActor in
                guard self.player.currentItem === item,
                      item.status == .failed
                else { return }
                self.handlePlaybackFailure(item.error)
            }
        }
    }

    private func handlePlaybackFailure(_ error: Error?) {
        cancelCrossfade()
        player.pause()
        isPlaying = false
        playbackError = error?.localizedDescription ?? "This track couldn’t be played."
        updateNowPlaying()
    }

    private func maybeBeginCrossfade() {
        guard isPlaying,
              !isCrossfading,
              sleepTimerEnd == nil,
              repeatMode != .one,
              duration > 0
        else { return }

        if automixEnabled,
           let plan = automixPlan() {
            if elapsed >= plan.outgoingStart,
               elapsed < plan.outgoingStart + 0.75 {
                beginAutomix(plan)
                return
            }
            if elapsed < plan.outgoingStart {
                return
            }
        }

        let transitionDuration = effectiveTransitionDuration
        guard transitionDuration > 0,
              let nextIndex = automixNextIndex ?? upcomingIndex()
        else { return }

        let remaining = duration - elapsed
        guard remaining > 0, remaining <= transitionDuration else { return }
        beginCrossfade(to: nextIndex)
    }

    private func automixPlan() -> AutomixPlan? {
        guard automixEnabled,
              let current,
              let currentGrid = automixAnalysis.grid(for: current),
              currentGrid.confidence >= 0.18,
              let nextIndex = automixNextIndex ?? upcomingIndex(),
              queue.indices.contains(nextIndex)
        else { return nil }

        let next = queue[nextIndex]
        guard next.id != current.id,
              next.mediaURL.isFileURL,
              current.mediaURL.isFileURL,
              let nextGrid = automixAnalysis.grid(for: next),
              nextGrid.confidence >= 0.18
        else { return nil }

        let rate = currentGrid.bpm / nextGrid.bpm
        guard rate.isFinite, rate >= 0.85, rate <= 1.18 else { return nil }

        let currentDuration = max(duration, currentGrid.duration)
        // Four bars is the shortest transition that still lands on a real
        // phrase boundary in most dance/pop arrangements.
        let beats = 16
        let transitionDuration = (60 / currentGrid.bpm) * Double(beats)
        guard currentDuration > transitionDuration + 1 else { return nil }

        let targetStart = currentDuration - transitionDuration
        let outgoingStart = currentGrid.phraseStart(atOrBefore: targetStart, bars: 4)
        guard outgoingStart > 0,
              currentDuration - outgoingStart > 0.5
        else { return nil }

        // Cue the incoming track on a phrase boundary too, so both sides of
        // the blend stay on the same musical grid.
        let incomingStart = nextGrid.phraseStart(atOrBefore: nextGrid.firstBeat, bars: 4)
        let nextDuration = max(next.duration, nextGrid.duration)
        let incomingAdvance = transitionDuration * Double(rate)
        guard incomingStart >= 0,
              nextDuration > incomingStart + incomingAdvance + 1
        else { return nil }

        return AutomixPlan(
            nextIndex: nextIndex,
            next: next,
            outgoingStart: outgoingStart,
            incomingStart: incomingStart,
            incomingRate: Float(rate),
            duration: transitionDuration
        )
    }

    private func prepareAutomixAnalysis() {
        guard automixEnabled, let current else { return }

        var tracks = [current]
        let nextIndex = automixNextIndex ?? upcomingIndex()
        automixNextIndex = nextIndex
        if let nextIndex, queue.indices.contains(nextIndex) {
            tracks.append(queue[nextIndex])
        }

        for track in tracks where track.mediaURL.isFileURL {
            Task {
                _ = await automixAnalysis.analyze(track)
            }
        }
    }

    private func prepareNextTrack() {
        guard !isCrossfading,
              let nextIndex = automixNextIndex ?? upcomingIndex(),
              queue.indices.contains(nextIndex)
        else {
            preloadedNextID = nil
            preloadedItem = nil
            return
        }

        let next = queue[nextIndex]
        guard next.id != current?.id else { return }

        if preloadedNextID != next.id {
            let item = makeFreshPlayerItem(for: next)
            preloadedNextID = next.id
            preloadedItem = item
        }

        if let artworkURL = next.artworkURL {
            Task {
                _ = await PlaybackBackdropCache.shared.prepare(for: artworkURL)
            }
        }
    }

    private func makePlayerItem(for track: Track) -> AVPlayerItem {
        if preloadedNextID == track.id, let preloadedItem {
            preloadedNextID = nil
            self.preloadedItem = nil
            return preloadedItem
        }

        return makeFreshPlayerItem(for: track)
    }

    private func makeFreshPlayerItem(for track: Track) -> AVPlayerItem {
        let item = AVPlayerItem(url: track.mediaURL)
        item.preferredForwardBufferDuration = playbackQuality.forwardBufferDuration
        if !track.mediaURL.isFileURL {
            item.preferredPeakBitRate = playbackQuality.peakBitRate
        }
        Equalizer.shared.attach(to: item)
        return item
    }

    private func upcomingIndex() -> Int? {
        guard !queue.isEmpty else { return nil }

        if isShuffled, queue.count > 1 {
            return queue.indices.filter { $0 != currentIndex }.randomElement()
        }

        let next = currentIndex + 1
        if next < queue.count { return next }
        if repeatMode == .all { return 0 }
        return nil
    }

    private func beginCrossfade(to nextIndex: Int) {
        guard nextIndex >= 0, nextIndex < queue.count else { return }
        let next = queue[nextIndex]
        guard next.id != current?.id else { return }

        resetPlaybackTempo()
        isCrossfading = true
        let item = makePlayerItem(for: next)
        fadePlayer.replaceCurrentItem(with: item)
        fadePlayer.volume = 0
        fadePlayer.play()

        let total = max(effectiveTransitionDuration, 0.5)
        let steps = max(Int(total * 12), 1)
        let stepSeconds = total / Double(steps)

        crossfadeTask = Task { [weak self] in
            for step in 1...steps {
                try? await Task.sleep(
                    nanoseconds: UInt64(stepSeconds * 1_000_000_000)
                )
                guard !Task.isCancelled, let self else { return }
                let progress = Float(step) / Float(steps)
                self.player.volume = 1 - progress
                self.fadePlayer.volume = progress
            }

            guard !Task.isCancelled, let self else { return }
            self.finishCrossfade(to: nextIndex)
        }
    }

    private func finishCrossfade(to nextIndex: Int) {
        guard nextIndex >= 0, nextIndex < queue.count else {
            cancelCrossfade()
            return
        }
        let next = queue[nextIndex]

        // Keep the already-playing fade player as the new main player. Pausing
        // it and copying the item to the old player was the source of the tiny
        // silence between songs.
        let time = fadePlayer.currentTime()
        let resumeAt = time.isValid ? max(0, CMTimeGetSeconds(time)) : 0
        fadePlayer.volume = 1
        promoteFadePlayer()

        navigationHistory.append(currentIndex)
        currentIndex = nextIndex
        current = next
        playbackError = nil
        duration = max(next.duration, 0)
        isDurationLoaded = false
        progress.elapsed = resumeAt
        isCrossfading = false
        isPlaying = true
        crossfadeTask = nil
        automixNextIndex = nil

        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
        player.rate = 1
        onTrackStarted?(next)
        prepareAutomixAnalysis()
        prepareNextTrack()
        updateNowPlaying()
    }

    private func beginAutomix(_ plan: AutomixPlan) {
        guard plan.nextIndex >= 0,
              plan.nextIndex < queue.count,
              queue[plan.nextIndex].id == plan.next.id
        else { return }

        resetPlaybackTempo()
        isCrossfading = true

        let item = makePlayerItem(for: plan.next)
        item.audioTimePitchAlgorithm = .spectral
        fadePlayer.replaceCurrentItem(with: item)
        fadePlayer.volume = 0

        let start = CMTime(seconds: plan.incomingStart, preferredTimescale: 600)
        fadePlayer.seek(
            to: start,
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] finished in
            Task { @MainActor in
                guard let self, self.isCrossfading else { return }
                guard finished else {
                    self.cancelCrossfade()
                    return
                }
                self.fadePlayer.play()
                self.fadePlayer.rate = plan.incomingRate
                self.startAutomixFade(plan)
            }
        }
    }

    private func startAutomixFade(_ plan: AutomixPlan) {
        let total = max(plan.duration, 0.5)
        let steps = max(Int(total * 20), 1)
        let stepSeconds = total / Double(steps)

        crossfadeTask = Task { [weak self] in
            for step in 1...steps {
                try? await Task.sleep(
                    nanoseconds: UInt64(stepSeconds * 1_000_000_000)
                )
                guard !Task.isCancelled, let self else { return }
                let progress = Double(step) / Double(steps)
                let angle = progress * .pi / 2
                self.player.volume = Float(cos(angle))
                self.fadePlayer.volume = Float(sin(angle))
            }

            guard !Task.isCancelled, let self else { return }
            self.finishAutomix(plan)
        }
    }

    private func finishAutomix(_ plan: AutomixPlan) {
        guard plan.nextIndex >= 0,
              plan.nextIndex < queue.count,
              queue[plan.nextIndex].id == plan.next.id
        else {
            cancelCrossfade()
            return
        }

        let next = queue[plan.nextIndex]
        let time = fadePlayer.currentTime()
        let fallbackResume = plan.incomingStart + plan.duration * Double(plan.incomingRate)
        let resumeAt = time.isValid ? max(0, CMTimeGetSeconds(time)) : fallbackResume

        fadePlayer.volume = 1
        promoteFadePlayer()

        navigationHistory.append(currentIndex)
        currentIndex = plan.nextIndex
        current = next
        playbackError = nil
        duration = max(next.duration, 0)
        isDurationLoaded = false
        progress.elapsed = resumeAt
        isCrossfading = false
        isPlaying = true
        crossfadeTask = nil
        automixNextIndex = nil

        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
        player.rate = plan.incomingRate
        scheduleTempoRestore()
        onTrackStarted?(next)
        prepareAutomixAnalysis()
        prepareNextTrack()
        updateNowPlaying()
    }

    /// The fade player is already at the right position and playing, so make
    /// it the main player instead of stopping and re-seeking a new item.
    private func promoteFadePlayer() {
        let oldPlayer = player
        if let timeObserver {
            oldPlayer.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        player = fadePlayer
        fadePlayer = oldPlayer

        oldPlayer.pause()
        oldPlayer.replaceCurrentItem(with: nil)
        oldPlayer.volume = 0

        if let item = player.currentItem {
            installEndObserver(for: item)
            observeItemStatus(item)
        }
        installTimeObserver()
    }

    private func scheduleTempoRestore() {
        tempoRestoreTask?.cancel()
        tempoRestoreTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled, let self,
                  self.isPlaying, !self.isCrossfading
            else { return }
            self.player.rate = 1
            self.tempoRestoreTask = nil
        }
    }

    private func resetPlaybackTempo() {
        tempoRestoreTask?.cancel()
        tempoRestoreTask = nil
        if isPlaying {
            player.rate = 1
        }
    }

    private func cancelCrossfade() {
        crossfadeTask?.cancel()
        crossfadeTask = nil
        tempoRestoreTask?.cancel()
        tempoRestoreTask = nil
        isCrossfading = false
        fadePlayer.pause()
        fadePlayer.replaceCurrentItem(with: nil)
        player.volume = 1
        if isPlaying {
            player.rate = 1
        }
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
    }

    private func installSystemObservers() {
        let session = AVAudioSession.sharedInstance()

        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleAudioInterruption(notification)
            }
        }

        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleAudioRouteChange(notification)
            }
        }
    }

    private func handleAudioInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType)
        else { return }

        switch type {
        case .began:
            wasPlayingBeforeInterruption = isPlaying
            pause()
        case .ended:
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            if wasPlayingBeforeInterruption, options.contains(.shouldResume) {
                resume()
            }
            wasPlayingBeforeInterruption = false
        @unknown default:
            break
        }
    }

    private func handleAudioRouteChange(_ notification: Notification) {
        guard let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason),
              reason == .oldDeviceUnavailable
        else { return }

        if isPlaying { pause() }
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.toggle() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }

        center.skipForwardCommand.preferredIntervals = [15]
        center.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.seek(to: self.elapsed + 15)
            }
            return .success
        }

        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.seek(to: max(0, self.elapsed - 15))
            }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let track = current else {
            nowPlayingArtwork = nil
            nowPlayingArtworkImage = nil
            nowPlayingArtworkURL = nil
            nowPlayingArtworkLoadingURL = nil
            nowPlayingAnimatedArtwork.removeAll()
            nowPlayingAnimatedArtworkIDs.removeAll()
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            SharedNowPlaying.clear()
            WidgetCenter.shared.reloadTimelines(ofKind: "MOTIFNowPlaying")
            return
        }

        defer { updatePlaybackSurfaces(for: track) }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyAlbumArtist: track.artist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyIsLiveStream: false,
            MPNowPlayingInfoPropertyExternalContentIdentifier: "motif:\(track.id.uuidString)",
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]

        if #available(iOS 26.0, *) {
            let previewSource: UIImage?
            if nowPlayingArtworkURL == track.artworkURL, let artwork = nowPlayingArtworkImage {
                previewSource = artwork
            } else if let artworkURL = track.artworkURL {
                previewSource = ArtworkImageCache.shared.heroImage(for: artworkURL)
                    ?? ArtworkImageCache.shared.image(for: artworkURL)
            } else {
                previewSource = nil
            }
            attachAnimatedArtwork(
                to: &info,
                track: track,
                previewSource: previewSource
            )
        }

        guard let artworkURL = track.artworkURL else {
            nowPlayingArtwork = nil
            nowPlayingArtworkImage = nil
            nowPlayingArtworkURL = nil
            nowPlayingArtworkLoadingURL = nil
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            return
        }

        if nowPlayingArtworkURL == artworkURL, let artwork = nowPlayingArtwork {
            info[MPMediaItemPropertyArtwork] = artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            return
        }

        nowPlayingArtworkURL = artworkURL
        nowPlayingArtwork = nil
        nowPlayingArtworkImage = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        if nowPlayingArtworkLoadingURL == artworkURL { return }
        nowPlayingArtworkLoadingURL = artworkURL

        URLSession.shared.dataTask(with: artworkURL) { [weak self] data, _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.nowPlayingArtworkLoadingURL == artworkURL {
                    self.nowPlayingArtworkLoadingURL = nil
                }
                guard let data,
                      let image = UIImage(data: data),
                      self.current?.artworkURL == artworkURL
                else { return }
                self.nowPlayingArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                self.nowPlayingArtworkImage = image
                self.updateNowPlaying()
            }
        }.resume()
    }

    @available(iOS 26.0, *)
    private func attachAnimatedArtwork(
        to info: inout [String: Any],
        track: Track,
        previewSource: UIImage?
    ) {
        let supported = MPNowPlayingInfoCenter.supportedAnimatedArtworkKeys
        let albumID = MotionArtworkStore.albumKey(for: track)
        let store = MotionArtworkStore.shared

        attachAnimatedVariant(
            key: MPNowPlayingInfoProperty1x1AnimatedArtwork,
            artworkID: "\(albumID)#1x1",
            fileURL: store.cachedArtworkFileURL(for: track),
            preview: {
                previewSource.flatMap { Self.animatedPreview(from: $0, aspectRatio: 1) }
            },
            supported: supported.contains(MPNowPlayingInfoProperty1x1AnimatedArtwork),
            info: &info
        )

        attachAnimatedVariant(
            key: MPNowPlayingInfoProperty3x4AnimatedArtwork,
            artworkID: "\(albumID)#3x4",
            fileURL: store.cachedTallArtworkFileURL(for: track),
            preview: {
                previewSource.flatMap {
                    Self.animatedPreview(from: $0, aspectRatio: 3.0 / 4.0)
                }
            },
            supported: supported.contains(MPNowPlayingInfoProperty3x4AnimatedArtwork),
            info: &info
        )
    }

    @available(iOS 26.0, *)
    private func attachAnimatedVariant(
        key: String,
        artworkID: String,
        fileURL: URL?,
        preview: () -> UIImage?,
        supported: Bool,
        info: inout [String: Any]
    ) {
        guard supported, let fileURL else {
            nowPlayingAnimatedArtwork[key] = nil
            nowPlayingAnimatedArtworkIDs[key] = nil
            return
        }

        if nowPlayingAnimatedArtworkIDs[key] == artworkID,
           let existing = nowPlayingAnimatedArtwork[key] {
            info[key] = existing
            return
        }

        guard let preview = preview() else {
            nowPlayingAnimatedArtwork[key] = nil
            nowPlayingAnimatedArtworkIDs[key] = nil
            return
        }

        let artwork = MPMediaItemAnimatedArtwork(
            artworkID: artworkID,
            previewImageRequestHandler: { _ in preview },
            videoAssetFileURLRequestHandler: { _ in
                FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
            }
        )
        nowPlayingAnimatedArtwork[key] = artwork
        nowPlayingAnimatedArtworkIDs[key] = artworkID
        info[key] = artwork
    }

    private static func animatedPreview(from image: UIImage, aspectRatio: CGFloat) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        guard width > 0, height > 0 else { return nil }

        var crop = CGRect(x: 0, y: 0, width: width, height: height)
        if width / height > aspectRatio {
            crop.size.width = height * aspectRatio
            crop.origin.x = (width - crop.size.width) / 2
        } else {
            crop.size.height = width / aspectRatio
            crop.origin.y = (height - crop.size.height) / 2
        }

        guard let cropped = cgImage.cropping(to: crop) else { return nil }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }

    private func updatePlaybackSurfaces(for track: Track) {
        let snapshot = SharedNowPlaying(
            title: track.title,
            artist: track.artist,
            album: track.album,
            artworkURL: track.artworkURL?.absoluteString,
            isPlaying: isPlaying,
            elapsed: elapsed,
            duration: duration,
            updatedAt: Date()
        )
        let now = Date()
        let trackChanged = lastWidgetTrackID != track.id
        let playbackChanged = lastWidgetIsPlaying != isPlaying
        let progressRefreshDue = now.timeIntervalSince(lastWidgetSurfaceUpdate) > 15

        if trackChanged || playbackChanged || progressRefreshDue {
            SharedNowPlaying.save(snapshot)
            WidgetCenter.shared.reloadTimelines(ofKind: "MOTIFNowPlaying")
            lastWidgetSurfaceUpdate = now
            lastWidgetTrackID = track.id
            lastWidgetIsPlaying = isPlaying
        }
    }
}
