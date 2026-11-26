import Foundation

/// Launch switch used by the simulator screenshot job. Seeded content and the
/// skipped network refresh make captures deterministic; normal launches are
/// untouched.
enum DemoMode {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("--motif-screenshots")
    }
}
