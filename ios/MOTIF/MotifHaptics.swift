import UIKit

enum MotifHaptics {
    enum Event {
        case light
        case medium
        case soft
        case selection
        case success
        case warning
    }

    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let selection = UISelectionFeedbackGenerator()
    private static let notification = UINotificationFeedbackGenerator()

    static func prepare() {
        light.prepare()
        medium.prepare()
        soft.prepare()
        selection.prepare()
        notification.prepare()
    }

    static func play(_ event: Event) {
        switch event {
        case .light:
            light.impactOccurred(intensity: 0.62)
            light.prepare()
        case .medium:
            medium.impactOccurred(intensity: 0.78)
            medium.prepare()
        case .soft:
            soft.impactOccurred(intensity: 0.55)
            soft.prepare()
        case .selection:
            selection.selectionChanged()
            selection.prepare()
        case .success:
            notification.notificationOccurred(.success)
            notification.prepare()
        case .warning:
            notification.notificationOccurred(.warning)
            notification.prepare()
        }
    }
}
