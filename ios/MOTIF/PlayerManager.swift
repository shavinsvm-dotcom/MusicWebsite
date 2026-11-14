import AVFoundation
import Combine
import Foundation
import MediaPlayer
import UIKit

@MainActor
final class PlaybackProgress: ObservableObject {
    @Published var elapsed: Double = 0
}

@MainActor
final class PlayerManager: ObservableObject {
    enum RepeatMode {
        case off
        case all
        case one
    }

    @Published private(set) var current: Track?
    @Published private(set) var queue: [Track] = []
    @Published private(set) var isPlaying = false
    @Published private(set) var duration: Double = 0
    @Published private(set) var isShuffled = false
    @Published private(set) var repeatMode: RepeatMode = .off

    let progress = PlaybackProgress()

    var elapsed: Double { progress.elapsed }

    var upNext: Track? {
        guard !isShuffled, repeatMode != .one,
              let current,
              let index = queue.firstIndex(where: { $0.id == current.id })
        else { return nil }

        if index + 1 < queue.count {
            return queue[index + 1]
        }
        return repeatMode == .all ? queue.first : nil
    }

    private let player = AVPlayer()
    private var currentIndex = 0
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var infoTick = 0

    init() {
        configureAudioSession()
        configureRemoteCommands()
        installTimeObserver()
    }

    func play(_ track: Track, queue newQueue: [Track]? = nil) {
        if current?.id == track.id {
            if !isPlaying { resume() }
            return
        }

        if let newQueue, !newQueue.isEmpty {
            queue = newQueue
        } else if !queue.contains(where: { $0.id == track.id }) {
            queue = [track]
        }

        currentIndex = queue.firstIndex(where: { $0.id == track.id }) ?? 0
        load(track)
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
        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
        isPlaying = true
        updateNowPlaying()
    }

    func pause() {
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
        } else {
            advance(by: -1)
        }
    }

    func toggleShuffle() {
        isShuffled.toggle()
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
    }

    func seek(to seconds: Double) {
        guard duration > 0 || seconds == 0 else { return }
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
        current = track
        progress.elapsed = 0
        duration = max(track.duration, 0)
        isPlaying = false

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }

        let item = AVPlayerItem(url: track.mediaURL)
        player.replaceCurrentItem(with: item)
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleTrackEnded() }
        }

        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
        isPlaying = true
        updateNowPlaying()
    }

    private func handleTrackEnded() {
        if repeatMode == .one {
            seek(to: 0)
            resume()
            return
        }
        advance(by: 1)
    }

    private func advance(by offset: Int) {
        guard !queue.isEmpty else { return }

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
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                let seconds = CMTimeGetSeconds(time)
                if seconds.isFinite {
                    let next = max(0, seconds)
                    if abs(next - self.progress.elapsed) > 0.01 {
                        self.progress.elapsed = next
                    }
                }

                if let itemDuration = self.player.currentItem?.duration {
                    let loadedDuration = CMTimeGetSeconds(itemDuration)
                    if loadedDuration.isFinite,
                       loadedDuration > 0,
                       abs(loadedDuration - self.duration) > 0.5 {
                        self.duration = loadedDuration
                    }
                }

                self.infoTick += 1
                if self.infoTick % 20 == 0 { self.updateNowPlaying() }
            }
        }
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
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
    }

    private func updateNowPlaying() {
        guard let track = current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        guard let artworkURL = track.artworkURL else { return }
        URLSession.shared.dataTask(with: artworkURL) { data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            }
        }.resume()
    }
}
