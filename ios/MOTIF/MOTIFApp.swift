import SwiftUI

@main
struct MOTIFApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        MotifHaptics.prepare()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
