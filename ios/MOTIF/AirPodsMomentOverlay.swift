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
                            statusTile(isConnected: isConnected)
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

    private func statusTile(isConnected: Bool) -> some View {
        ZStack {
            if !reduceMotion {
                if isConnected {
                    NameDropRipple()
                } else {
                    let scale = 1 + ripple * 2.8

                    Circle()
                        .strokeBorder(.white, lineWidth: 0.8 / scale)
                        .frame(width: 96, height: 96)
                        .scaleEffect(scale)
                        .opacity(Double(sin(Double(ripple) * .pi)) * 0.30)
                }
            }

            SingleAirPodGlyph()
                .frame(width: 30, height: 46)
                .scaleEffect(1.28)
                .shadow(color: .black.opacity(0.28), radius: 3, y: 1)
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

        if moment.kind == .disconnected {
            // Collapse the ring inward for the negative beat; connect gets
            // the NameDrop ripple, which drives itself from the tile centre.
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
    /// Lightweight, geometrically built bud: a broad head, the ear tip folded
    /// in at the lower left, and a stem tucked under the back of the head.
    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(.white)
                .frame(width: 8.6, height: 24.5)
                .rotationEffect(.degrees(3))
                .offset(x: 5.2, y: 10.8)

            Capsule(style: .continuous)
                .fill(.white)
                .frame(width: 8.2, height: 7.0)
                .rotationEffect(.degrees(-44))
                .offset(x: -8.9, y: -2.2)

            head
                .offset(y: -8.6)
        }
        .frame(width: 30, height: 46)
    }

    private var head: some View {
        Ellipse()
            .fill(.white)
            .frame(width: 26, height: 20)
            .overlay {
                ZStack {
                    Capsule(style: .continuous)
                        .fill(.black)
                        .frame(width: 8.2, height: 2.0)
                        .offset(x: -3.2, y: -1.4)

                    Circle()
                        .fill(.black)
                        .frame(width: 2.1, height: 2.1)
                        .offset(x: 8.2, y: -4.1)
                }
                .blendMode(.destinationOut)
            }
            .compositingGroup()
            .rotationEffect(.degrees(-14))
    }
}

/// Three hairlines leaving the glass tile on a slow loop, the way NameDrop
/// pushes a pulse out from the devices it is connecting.
private struct NameDropRipple: View {
    @State private var start = Date()

    private let cycle: Double = 2.6
    private let ringCount = 3

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSince(start)
            let phase = elapsed.truncatingRemainder(dividingBy: cycle) / cycle

            ZStack {
                ForEach(0..<ringCount, id: \.self) { index in
                    let p = (phase + Double(index) / Double(ringCount))
                        .truncatingRemainder(dividingBy: 1)

                    let scale = 1 + CGFloat(p) * 4.2

                    Circle()
                        .strokeBorder(.white, lineWidth: 0.8 / scale)
                        .scaleEffect(scale)
                        .opacity(sin(p * .pi) * 0.30)
                }
            }
        }
        .frame(width: 96, height: 96)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
