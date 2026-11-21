import AVFoundation
import Combine
import Foundation
import UIKit

enum AirPodsMomentKind: Equatable {
    case connected
    case disconnected
}

struct AirPodsMoment: Identifiable, Equatable {
    let id = UUID()
    let kind: AirPodsMomentKind
    let name: String
    let symbolName: String
}

@MainActor
final class AudioRouteMonitor: ObservableObject {
    @Published private(set) var moment: AirPodsMoment?

    private struct Device {
        let name: String
        let symbolName: String
    }

    private var observer: NSObjectProtocol?
    private var dismissTask: Task<Void, Never>?
    private var lastConnectedAt = Date.distantPast
    private var knownAirPods: Device?

    init() {
        // Seed the last known route so removing AirPods that were already
        // connected when the app launched still gets a disconnect moment.
        if let output = currentAirPodsOutput() {
            knownAirPods = device(for: output)
        }

        observer = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleRouteChange(notification)
            }
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        dismissTask?.cancel()
    }

    func dismiss() {
        dismissTask?.cancel()
        moment = nil
    }

    /// Plays a moment without a real route change. Used by the debug control
    /// so the motion can be replayed without unplugging anything.
    func playPreview(_ kind: AirPodsMomentKind) {
        let device = knownAirPods
            ?? Device(name: "AirPods Pro", symbolName: "airpodspro")
        let next = AirPodsMoment(
            kind: kind,
            name: device.name,
            symbolName: device.symbolName
        )
        moment = next
        scheduleDismiss(for: next)
    }

    private func handleRouteChange(_ notification: Notification) {
        guard
            let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason)
        else { return }

        switch reason {
        case .oldDeviceUnavailable:
            // The notification arrives after the device has left the route,
            // so the name comes from the last AirPods route we saw.
            guard let previous = knownAirPods, currentAirPodsOutput() == nil else {
                return
            }
            knownAirPods = nil
            show(.disconnected, device: previous, debounced: false)

        case .newDeviceAvailable:
            guard let output = currentAirPodsOutput() else { return }
            let next = device(for: output)
            let wasKnown = knownAirPods != nil
            knownAirPods = next
            guard !wasKnown else { return }
            show(.connected, device: next, debounced: true)

        default:
            break
        }
    }

    private func show(
        _ kind: AirPodsMomentKind,
        device: Device,
        debounced: Bool
    ) {
        guard UIApplication.shared.applicationState == .active else { return }

        if debounced {
            let now = Date()
            guard now.timeIntervalSince(lastConnectedAt) > 3.0 else { return }
            lastConnectedAt = now
        }

        let next = AirPodsMoment(
            kind: kind,
            name: device.name,
            symbolName: device.symbolName
        )
        moment = next
        scheduleDismiss(for: next)
    }

    private func scheduleDismiss(for moment: AirPodsMoment) {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            guard self?.moment?.id == moment.id else { return }
            self?.moment = nil
        }
    }

    private func currentAirPodsOutput() -> AVAudioSessionPortDescription? {
        AVAudioSession.sharedInstance().currentRoute.outputs.first {
            isBluetoothOutput($0)
                && $0.portName.localizedCaseInsensitiveContains("airpods")
        }
    }

    private func device(for output: AVAudioSessionPortDescription) -> Device {
        let name = output.portName.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = name.lowercased()
        let symbol = lowercased.contains("max")
            ? "airpodsmax"
            : (lowercased.contains("pro") ? "airpodspro" : "airpods")

        return Device(
            name: name.isEmpty ? "AirPods" : name,
            symbolName: symbol
        )
    }

    private func isBluetoothOutput(_ output: AVAudioSessionPortDescription) -> Bool {
        switch output.portType {
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
            return true
        default:
            return false
        }
    }
}
