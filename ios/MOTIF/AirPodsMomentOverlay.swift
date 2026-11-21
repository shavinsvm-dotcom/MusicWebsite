import SwiftUI
import UIKit

struct AirPodsMomentOverlay: View {
    @ObservedObject var monitor: AudioRouteMonitor

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var snapshot: UIImage?
    @State private var revealed = false
    @State private var together = false
    @State private var settled = false
    @State private var statusShown = false
    @State private var departed = false
    @State private var dismissing = false
    @State private var warp: CGFloat = 0
    @State private var announced = false

    private let blue = Color(red: 0.33, green: 0.71, blue: 1.0)
    private let cyan = Color(red: 0.55, green: 0.93, blue: 1.0)
    private let mint = Color(red: 0.49, green: 0.96, blue: 0.78)
    private let slate = Color(red: 0.63, green: 0.69, blue: 0.80)

    var body: some View {
        ZStack {
            if let moment = monitor.moment {
                GeometryReader { proxy in
                    let size = proxy.size
                    let center = CGPoint(x: size.width / 2, y: size.height * 0.36)
                    let isConnected = moment.kind == .connected

                    ZStack {
                        background(moment: moment, size: size)

                        if revealed {
                            radar(moment: moment, center: center)
                        }

                        nodes(moment: moment, center: center, size: size)
                            .opacity(revealed ? 1 : 0)

                        status(moment: moment, center: center)
                            .opacity(statusShown ? 1 : 0)
                            .offset(y: statusShown ? 0 : 14)
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
        together = false
        settled = false
        statusShown = false
        departed = false
        dismissing = false
        warp = 0
        announced = false
    }

    @ViewBuilder
    private func background(moment: AirPodsMoment, size: CGSize) -> some View {
        let isConnected = moment.kind == .connected
        let accent = isConnected ? blue : slate

        ZStack {
            Color.black

            if let snapshot {
                Image(uiImage: snapshot)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .saturation(isConnected ? 1 : 0.35)
                    .modifier(
                        AirPodsRippleEffect(
                            progress: reduceMotion ? 0 : warp,
                            size: size
                        )
                    )
                    .blur(radius: warpBlur)
            }

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.28), location: 0),
                    .init(color: .black.opacity(0.44), location: 0.42),
                    .init(color: .black.opacity(0.66), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [
                    accent.opacity(isConnected ? 0.30 : 0.20),
                    Color(red: 0.45, green: 0.48, blue: 1.0)
                        .opacity(isConnected ? 0.12 : 0.08),
                    .clear
                ],
                center: UnitPoint(x: 0.5, y: 0.36),
                startRadius: 8,
                endRadius: size.height * 0.42
            )
        }
        .opacity(revealed ? 1 : 0)
    }

    private var warpBlur: CGFloat {
        guard !reduceMotion else { return 0 }
        return CGFloat(sin(Double(warp) * .pi)) * 3.5
    }

    private func radar(moment: AirPodsMoment, center: CGPoint) -> some View {
        AirPodsRadar(
            blue: blue,
            cyan: cyan,
            collapsing: moment.kind == .disconnected
        )
        .frame(width: 300, height: 300)
        .position(center)
        .allowsHitTesting(false)
    }

    private func nodes(
        moment: AirPodsMoment,
        center: CGPoint,
        size: CGSize
    ) -> some View {
        let separation: CGFloat = together ? 0 : 76
        let isConnected = moment.kind == .connected

        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            .white.opacity(0.85),
                            cyan.opacity(0.38),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 74
                    )
                )
                .frame(width: 148, height: 148)
                .position(center)
                .opacity(together ? (settled ? 0.30 : 0.72) : 0)
                .blur(radius: 12)
                .allowsHitTesting(false)

            deviceNode(symbol: "iphone", diameter: 86, accent: blue)
                .position(x: center.x - separation, y: center.y)
                .opacity(settled ? 0 : 1)
                .scaleEffect(settled ? 0.62 : 1)

            deviceNode(
                symbol: moment.symbolName,
                diameter: 108,
                accent: isConnected ? cyan : slate
            )
            .position(x: center.x + separation, y: center.y)
            .scaleEffect(settled ? 1.05 : 1)
            .offset(x: departed ? 44 : 0, y: departed ? -14 : 0)
            .opacity(departed ? 0 : 1)
            .zIndex(2)
        }
        .frame(width: size.width, height: size.height)
    }

    private func deviceNode(
        symbol: String,
        diameter: CGFloat,
        accent: Color
    ) -> some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.20), lineWidth: 1)
                }
                .overlay {
                    Circle()
                        .strokeBorder(accent.opacity(0.42), lineWidth: 1.5)
                        .blur(radius: 1.5)
                }
                .shadow(color: accent.opacity(0.36), radius: 24, y: 8)

            Image(systemName: symbol)
                .font(.system(size: diameter * 0.40, weight: .regular))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.28), radius: 6, y: 2)
        }
        .frame(width: diameter, height: diameter)
    }

    private func status(moment: AirPodsMoment, center: CGPoint) -> some View {
        let isConnected = moment.kind == .connected

        return VStack(spacing: 8) {
            Text(moment.name)
                .font(.system(size: 31, weight: .bold))
                .tracking(-0.8)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .shadow(color: .black.opacity(0.45), radius: 12, y: 2)

            HStack(spacing: 6) {
                Image(
                    systemName: isConnected
                        ? "checkmark.circle.fill"
                        : "xmark.circle.fill"
                )
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isConnected ? mint : slate)

                Text(isConnected ? "Connected" : "Disconnected")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.66))
            }
        }
        .frame(maxWidth: 330)
        .position(x: center.x, y: center.y + 148)
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

        if moment.kind == .disconnected {
            // The disconnect moment begins on the settled, connected frame.
            together = true
            settled = true
        }

        if reduceMotion {
            switch moment.kind {
            case .connected:
                together = true
                settled = true
            case .disconnected:
                together = false
                settled = false
                departed = true
            }

            statusShown = true
            revealed = true
            MotifHaptics.play(moment.kind == .connected ? .success : .soft)
            announce(moment)

            try? await Task.sleep(nanoseconds: 2_100_000_000)
            guard !Task.isCancelled else { return }
            monitor.dismiss()
            return
        }

        withAnimation(.easeOut(duration: 0.22)) {
            revealed = true
        }

        switch moment.kind {
        case .connected:
            withAnimation(.linear(duration: 2.2)) {
                warp = 1
            }
            MotifHaptics.play(.soft)

            try? await Task.sleep(nanoseconds: 520_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.76)) {
                together = true
            }

            try? await Task.sleep(nanoseconds: 360_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                settled = true
                statusShown = true
            }
            MotifHaptics.play(.success)
            announce(moment)

            try? await Task.sleep(nanoseconds: 1_550_000_000)
            guard !Task.isCancelled else { return }

        case .disconnected:
            MotifHaptics.play(.soft)

            try? await Task.sleep(nanoseconds: 380_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                together = false
                settled = false
            }
            withAnimation(.easeOut(duration: 0.28)) {
                statusShown = true
            }
            announce(moment)

            try? await Task.sleep(nanoseconds: 340_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.40)) {
                departed = true
            }

            try? await Task.sleep(nanoseconds: 1_250_000_000)
            guard !Task.isCancelled else { return }
        }

        withAnimation(.easeIn(duration: 0.32)) {
            dismissing = true
        }

        try? await Task.sleep(nanoseconds: 360_000_000)
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

private struct AirPodsRadar: View {
    let blue: Color
    let cyan: Color
    var collapsing: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var start = Date()
    @State private var running = true

    var body: some View {
        ZStack {
            Circle()
                .stroke(blue.opacity(0.22), lineWidth: 1)
                .frame(width: 116, height: 116)

            if !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !running)) { timeline in
                    Canvas { context, size in
                        draw(
                            context: &context,
                            size: size,
                            elapsed: timeline.date.timeIntervalSince(start)
                        )
                    }
                }
            }
        }
        .onAppear {
            start = Date()
        }
        .task {
            guard !reduceMotion else { return }
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            running = false
        }
    }

    private func draw(
        context: inout GraphicsContext,
        size: CGSize,
        elapsed: TimeInterval
    ) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let maxRadius = size.width * 0.48

        for index in 0..<3 {
            let progress = (elapsed - Double(index) * 0.16) / 1.15
            guard progress > 0, progress < 1 else { continue }

            let radius = collapsing
                ? maxRadius - CGFloat(progress) * (maxRadius - 44)
                : 44 + CGFloat(progress) * (maxRadius - 44)
            let opacity = sin(progress * .pi) * 0.52
            let rect = CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )

            context.stroke(
                Path(ellipseIn: rect),
                with: .color(blue.opacity(opacity)),
                lineWidth: 1.2
            )
        }

        let angle = elapsed * 105 * (collapsing ? -1 : 1)
        var arc = Path()
        arc.addArc(
            center: center,
            radius: size.width * 0.28,
            startAngle: .degrees(angle),
            endAngle: .degrees(angle + 34),
            clockwise: false
        )

        context.stroke(
            arc,
            with: .linearGradient(
                Gradient(colors: [.clear, cyan.opacity(0.34), .clear]),
                startPoint: CGPoint(x: 0, y: center.y),
                endPoint: CGPoint(x: size.width, y: center.y)
            ),
            lineWidth: 1.8
        )

        if !collapsing, elapsed > 1.55 {
            let settle = min((elapsed - 1.55) / 0.25, 1)
            context.stroke(
                Path(
                    ellipseIn: CGRect(
                        x: center.x - 58,
                        y: center.y - 58,
                        width: 116,
                        height: 116
                    )
                ),
                with: .color(cyan.opacity(0.28 * settle)),
                lineWidth: 1
            )
        }
    }
}

private struct AirPodsRippleEffect: ViewModifier, Animatable {
    var progress: CGFloat
    let size: CGSize

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            // layerEffect samples the layer in a vertically flipped space.
            // Pre-flip the snapshot so the shader's flip cancels it out.
            content
                .scaleEffect(x: 1, y: -1)
                .layerEffect(
                    Shader(
                        function: ShaderFunction(library: .default, name: "airPodsRipple"),
                        arguments: [
                            .float(Float(progress * 2.2)),
                            .float2(Float(size.width), Float(size.height))
                        ]
                    ),
                    maxSampleOffset: CGSize(width: 240, height: 240)
                )
        } else {
            content
        }
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
