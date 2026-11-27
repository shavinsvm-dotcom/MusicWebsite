import Foundation

/// Launch switches used by the simulator screenshot job. Seeded content, the
/// skipped network refresh and the initial screen make captures deterministic;
/// normal launches are untouched.
enum DemoMode {
    enum Screen: String {
        case home
        case library
        case lyrics
        case player
        case settings
    }

    private static let screenPrefix = "--motif-screen="

    static var isEnabled: Bool {
        arguments.contains("--motif-screenshots")
    }

    static var screen: Screen? {
        guard let argument = arguments.first(where: { $0.hasPrefix(screenPrefix) }) else {
            return nil
        }
        return Screen(rawValue: String(argument.dropFirst(screenPrefix.count)))
    }

    private static var arguments: [String] {
        ProcessInfo.processInfo.arguments
    }
}
