import SwiftUI
import UIKit

struct AirPodsMomentOverlay: View {
    @ObservedObject var monitor: AudioRouteMonitor

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var snapshot: UIImage?
    @State private var revealed = false
    @State private var settled = false
    @State private var ripple: CGFloat = 0
    @State private var dismissing = false
    @State private var announced = false

    var body: some View {
        ZStack {
            if let moment = monitor.moment {
                GeometryReader { proxy in
                    let size = proxy.size
                    let isConnected = moment.kind == .connected

                    ZStack {
                        backdrop(size: size)

                        VStack(spacing: 0) {
                            statusTile
                                .padding(.bottom, 22)

                            VStack(spacing: 0) {
                                Text(moment.name)
                                    .font(.system(size: 22, weight: .semibold))
                                    .tracking(-0.3)
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.8)
                                    .padding(.bottom, 7)

                                HStack(spacing: 5) {
                                    Image(systemName: isConnected ? "checkmark" : "xmark")
                                        .font(.system(size: 11, weight: .semibold))

                                    Text(isConnected ? "Connected" : "Disconnected")
                                        .font(.footnote)
                                }
                                .foregroundStyle(.white.opacity(0.60))
                            }
                            .opacity(settled ? 1 : 0)
                            .offset(y: settled ? 0 : 6)
                        }
                        .frame(maxWidth: 300)
                        .position(x: size.width / 2, y: size.height * 0.47)
                    }
                    .frame(width: size.width, height: size.height)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        monitor.dismiss()
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        isConnected
                            ? "\(moment.name) connected"
                            : "\(moment.name) disconnected"
                    )
                    .accessibilityHint("Double tap to dismiss")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction {
                        monitor.dismiss()
                    }
                }
                .ignoresSafeArea()
                .environment(\.colorScheme, .dark)
                .task(id: moment.id) {
                    await run(moment)
                }
                .opacity(dismissing ? 0 : 1)
            }
        }
        .ignoresSafeArea()
        .onChange(of: monitor.moment) { moment in
            if moment == nil {
                reset()
            }
        }
    }

    private func reset() {
        snapshot = nil
        revealed = false
        settled = false
        ripple = 0
        dismissing = false
        announced = false
    }

    @ViewBuilder
    private func backdrop(size: CGSize) -> some View {
        ZStack {
            Color.black

            if let snapshot {
                Image(uiImage: snapshot)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .blur(radius: 24)
                    .overlay(Color.black.opacity(0.46))
            } else {
                Color.black.opacity(0.94)
            }
        }
        .opacity(revealed ? 1 : 0)
    }

    private var statusTile: some View {
        ZStack {
            if !reduceMotion {
                Circle()
                    .strokeBorder(.white, lineWidth: 0.8)
                    .frame(width: 96, height: 96)
                    .scaleEffect(1 + ripple * 1.65)
                    .opacity(Double(sin(Double(ripple) * .pi)) * 0.22)
            }

            SingleAirPodGlyph()
                .frame(width: 28, height: 42)
                .scaleEffect(1.30)
                .shadow(color: .black.opacity(0.30), radius: 4, y: 1)
                .frame(width: 96, height: 96)
                .nativeGlass(Circle())
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
                }
        }
        .frame(width: 96, height: 96)
        .scaleEffect(revealed ? 1 : 0.92)
        .opacity(revealed ? 1 : 0)
    }

    @MainActor
    private func run(_ moment: AirPodsMoment) async {
        // A second moment can arrive while the first is still on screen (for
        // example connect, then unplugging straight away). Start the new one
        // from a clean slate instead of freezing the old frame.
        if revealed {
            reset()
            await Task.yield()
        }

        if snapshot == nil {
            await Task.yield()
            snapshot = WindowSnapshot.capture()
        }

        if reduceMotion {
            revealed = true
            settled = true
            MotifHaptics.play(moment.kind == .connected ? .success : .soft)
            announce(moment)

            try? await Task.sleep(nanoseconds: 1_900_000_000)
            guard !Task.isCancelled else { return }
            monitor.dismiss()
            return
        }

        withAnimation(.spring(response: 0.48, dampingFraction: 0.82)) {
            revealed = true
        }
        MotifHaptics.play(.soft)

        if moment.kind == .connected {
            withAnimation(.easeOut(duration: 1.35)) {
                ripple = 1
            }
        } else {
            // Collapse the ring inward for the negative beat.
            ripple = 1
            withAnimation(.easeOut(duration: 1.10)) {
                ripple = 0
            }
        }

        try? await Task.sleep(nanoseconds: 180_000_000)
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.30)) {
            settled = true
        }
        MotifHaptics.play(moment.kind == .connected ? .success : .soft)
        announce(moment)

        try? await Task.sleep(nanoseconds: 1_700_000_000)
        guard !Task.isCancelled else { return }

        withAnimation(.easeIn(duration: 0.30)) {
            dismissing = true
        }

        try? await Task.sleep(nanoseconds: 340_000_000)
        guard !Task.isCancelled else { return }
        monitor.dismiss()
    }

    private func announce(_ moment: AirPodsMoment) {
        guard !announced else { return }
        announced = true
        UIAccessibility.post(
            notification: .announcement,
            argument: moment.kind == .connected
                ? "\(moment.name) connected"
                : "\(moment.name) disconnected"
        )
    }
}

/// The status glyph: one white AirPod with a speaker slot and vent cut out,
/// traced from the flat single-pod reference.
private struct SingleAirPodGlyph: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3.4, style: .continuous)
                .fill(.white)
                .frame(width: 9, height: 24)
                .offset(x: 2, y: 11)

            head
                .offset(y: -8)
        }
        .frame(width: 28, height: 42)
    }

    private var head: some View {
        Ellipse()
            .fill(.white)
            .frame(width: 27, height: 22)
            .overlay {
                ZStack {
                    Capsule()
                        .fill(.black)
                        .frame(width: 6, height: 4.5)
                        .rotationEffect(.degrees(-20))
                        .offset(x: -4, y: 1)

                    Capsule()
                        .fill(.black)
                        .frame(width: 3.5, height: 3)
                        .rotationEffect(.degrees(-20))
                        .offset(x: 5, y: -2)
                }
                .blendMode(.destinationOut)
            }
            .compositingGroup()
            .rotationEffect(.degrees(-16))
    }
}

/// A small floating control for replaying either moment without changing the
/// audio route. It is intentionally tiny and out of the way; delete this view
/// and its two call sites once the motion has been signed off.
struct AirPodsMomentDebugButton: View {
    @ObservedObject var monitor: AudioRouteMonitor

    var body: some View {
        Menu {
            Button {
                monitor.playPreview(.connected)
            } label: {
                Label("Replay connect", systemImage: "airpodspro")
            }

            Button {
                monitor.playPreview(.disconnected)
            } label: {
                Label("Play disconnect", systemImage: "airpods")
            }
        } label: {
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 30, height: 30)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(0.16), lineWidth: 0.7)
                }
        }
        .accessibilityLabel("AirPods animation debug")
    }
}

@MainActor
private enum WindowSnapshot {
    static func capture() -> UIImage? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.activationState == .foregroundActive })
            ?? scenes.first

        guard let scene else { return nil }

        let windows = scene.windows.filter { !$0.isHidden && $0.alpha > 0.01 }
        guard let window = windows.first(where: { $0.isKeyWindow }) ?? windows.first else {
            return nil
        }

        let bounds = window.bounds
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        return renderer.image { _ in
            window.drawHierarchy(in: bounds, afterScreenUpdates: false)
        }
    }
}
