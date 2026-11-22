import SwiftUI
import UIKit

struct AirPodsMomentOverlay: View {
    @ObservedObject var monitor: AudioRouteMonitor

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var snapshot: UIImage?
    @State private var revealed = false
    @State private var settled = false
    @State private var warp: CGFloat = 0
    @State private var dismissing = false
    @State private var announced = false

    var body: some View {
        ZStack {
            if let moment = monitor.moment {
                GeometryReader { proxy in
                    let size = proxy.size
                    let isConnected = moment.kind == .connected
                    let origin = CGPoint(
                        x: size.width / 2,
                        y: size.height * 0.47 - 35.5
                    )
                    let warpProgress = isConnected ? warp : 1 - warp

                    ZStack {
                        backdrop(size: size, origin: origin, progress: warpProgress)

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
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        isConnected
                            ? "\(moment.name) connected"
                            : "\(moment.name) disconnected"
                    )
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
        warp = 0
        dismissing = false
        announced = false
    }

    @ViewBuilder
    private func backdrop(
        size: CGSize,
        origin: CGPoint,
        progress: CGFloat
    ) -> some View {
        ZStack {
            Color.black

            if let snapshot {
                Image(uiImage: snapshot)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .modifier(
                        AirPodsRippleEffect(
                            progress: reduceMotion ? 0 : progress,
                            size: size,
                            origin: origin
                        )
                    )
                    .blur(radius: 5)
                    .overlay(Color.black.opacity(0.46))
            } else {
                Color.black.opacity(0.94)
            }
        }
        .opacity(revealed ? 1 : 0)
    }

    private var statusTile: some View {
        Image(systemName: "airpods.gen3")
            .font(.system(size: 46, weight: .regular))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.28), radius: 3, y: 1)
            .frame(width: 96, height: 96)
            .nativeGlass(Circle())
            .overlay {
                Circle()
                    .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
            }
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
        withAnimation(.linear(duration: 2.2)) {
            warp = 1
        }
        MotifHaptics.play(.soft)

        try? await Task.sleep(nanoseconds: 180_000_000)
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.30)) {
            settled = true
        }
        MotifHaptics.play(moment.kind == .connected ? .success : .soft)
        announce(moment)

        try? await Task.sleep(nanoseconds: 1_900_000_000)
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

private struct AirPodsRippleEffect: ViewModifier, Animatable {
    var progress: CGFloat
    let size: CGSize
    let origin: CGPoint

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            // layerEffect samples the layer in a vertically flipped space.
            // Pre-flip the snapshot so the shader's flip cancels it out, and
            // hand it the tile's origin in that same flipped space.
            content
                .scaleEffect(x: 1, y: -1)
                .layerEffect(
                    Shader(
                        function: ShaderFunction(library: .default, name: "airPodsRipple"),
                        arguments: [
                            .float(Float(progress * 2.2)),
                            .float2(Float(size.width), Float(size.height)),
                            .float2(
                                Float(origin.x / max(size.width, 1)),
                                Float(1 - origin.y / max(size.height, 1))
                            )
                        ]
                    ),
                    maxSampleOffset: CGSize(width: 240, height: 240)
                )
        } else {
            content
        }
    }
}

/// A small floating control for replaying either moment without changing the
/// audio route. It is intentionally tiny and out of the way; delete this view
/// and its two call sites once the motion has been signed off.
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
