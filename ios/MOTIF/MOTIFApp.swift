import SwiftUI

@main
struct MOTIFApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .ignoresSafeArea()
                .preferredColorScheme(nil)
        }
    }
}

private struct RootView: View {
    private var startURL: URL? {
        guard
            let raw = Bundle.main.object(forInfoDictionaryKey: "MOTIFStartURL") as? String,
            let url = URL(string: raw),
            let scheme = url.scheme?.lowercased(),
            scheme == "https"
        else { return nil }
        return url
    }

    var body: some View {
        if let startURL {
            WebView(url: startURL)
        } else {
            VStack(spacing: 12) {
                Text("MOTIF")
                    .font(.title2.weight(.semibold))
                Text("Set MOTIFStartURL to a valid HTTPS URL in Support/Info.plist.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(28)
        }
    }
}
