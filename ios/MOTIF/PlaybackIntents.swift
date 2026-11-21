import AppIntents
import Foundation

enum PlaybackCommand: String, Sendable {
    case togglePlayback
    case nextTrack
    case previousTrack
}

enum PlaybackIntentBridge {
    static let notification = Notification.Name("motif.playbackCommand")

    static func send(_ command: PlaybackCommand) {
        NotificationCenter.default.post(name: notification, object: command.rawValue)
    }
}

@available(iOS 17.0, *)
struct MotifTogglePlaybackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Play or Pause"
    static var description = IntentDescription("Toggles playback in MOTIF.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        PlaybackIntentBridge.send(.togglePlayback)
        return .result()
    }
}

@available(iOS 17.0, *)
struct MotifNextTrackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Next Track"
    static var description = IntentDescription("Skips to the next track in MOTIF.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        PlaybackIntentBridge.send(.nextTrack)
        return .result()
    }
}

@available(iOS 17.0, *)
struct MotifPreviousTrackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Previous Track"
    static var description = IntentDescription("Returns to the previous track in MOTIF.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        PlaybackIntentBridge.send(.previousTrack)
        return .result()
    }
}
