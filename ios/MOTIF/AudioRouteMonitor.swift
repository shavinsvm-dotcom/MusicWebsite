import AVFoundation
import Combine
import Foundation
import UIKit

struct AirPodsConnection: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let symbolName: String
}

@MainActor
final class AudioRouteMonitor: ObservableObject {
    @Published private(set) var connection: AirPodsConnection?

    private var observer: NSObjectProtocol?
    private var dismissTask: Task<Void, Never>?
    private var lastShownAt = Date.distantPast

    init() {
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
        connection = nil
    }

    private func handleRouteChange(_ notification: Notification) {
        guard
            let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason)
        else { return }

        if reason == .oldDeviceUnavailable {
            if !currentAirPodsOutputExists() {
                dismiss()
            }
            return
        }

        guard reason == .newDeviceAvailable else { return }

        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        guard let output = outputs.first(where: isBluetoothOutput),
              output.portName.localizedCaseInsensitiveContains("airpods")
        else { return }

        let now = Date()
        guard now.timeIntervalSince(lastShownAt) > 1.5 else { return }

        let name = output.portName.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = name.lowercased()
        let symbol = lowercased.contains("max")
            ? "airpodsmax"
            : (lowercased.contains("pro") ? "airpodspro" : "airpods")

        lastShownAt = now
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        let next = AirPodsConnection(name: name, symbolName: symbol)
        connection = next
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled else { return }
            guard self?.connection?.id == next.id else { return }
            self?.connection = nil
        }
    }

    private func currentAirPodsOutputExists() -> Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains {
            isBluetoothOutput($0) && $0.portName.localizedCaseInsensitiveContains("airpods")
        }
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
