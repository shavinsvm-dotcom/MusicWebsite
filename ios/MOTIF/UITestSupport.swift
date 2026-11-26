import Foundation

/// Launch-argument switches used by the UI test bundle. Inert in normal use.
enum UITestSupport {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("--motif-ui-testing")
    }
}
