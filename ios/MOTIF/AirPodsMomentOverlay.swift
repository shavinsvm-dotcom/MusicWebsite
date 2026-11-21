import SwiftUI
import UIKit

struct AirPodsMomentOverlay: View {
    @ObservedObject var monitor: AudioRouteMonitor

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var snapshot: UIImage?
    @State private var revealed = false
    @State private var settled = false
    @State private var burst: CGFloat = 0
    @State private var dismissing = false
    @State private var warp: CGFloat = 0
    @State private var announced = false

    private let mint = Color(red: 0.49, green: 0.96, blue: 0.78)
    private let silver = Color(white: 0.70)
    private let slate = Color(white: 0.55)

    var body: some View {
        ZStack {
            if let moment = monitor.moment {
                GeometryReader { proxy in
                    let size = proxy.size
                    let origin = CGPoint(
                        x: size.width - 46,
                        y: max(70, size.height * 0.08)
                    )
                    let isConnected = moment.kind == .connected
                    let labelWidth = min(300, size.width - 44)

                    ZStack {
                        background(
                            moment: moment,
                            size: size,
                            origin: origin
                        )

                        if revealed && !reduceMotion {
                            AirPodsRings(
                                center: origin,
                                radius: 26,
                                spread: sqrt(size.width * size.width + size.height * size.height),
                                bright: .white,
                                soft: silver,
                                collapsing: !isConnected
                            )
                            .frame(width: size.width, height: size.height)
                            .allowsHitTesting(false)

                            AirPodsParticles(
                                center: origin,
                                radius: 58,
                                bright: .white,
                                soft: silver
                            )
                            .frame(width: size.width, height: size.height)
                            .allowsHitTesting(false)
                        }

                        if burst > 0.001 {
                            Circle()
                                .strokeBorder(.white.opacity(0.55), lineWidth: 1.4)
                                .frame(width: 120, height: 120)
                                .scaleEffect(0.25 + burst * 2.6)
                                .opacity(Double(1 - burst) * 0.8)
                                .blur(radius: 1.5)
                                .position(origin)
                                .allowsHitTesting(false)
                        }

                        statusIcon(
                            isConnected: isConnected,
                            origin: origin
                        )

                        footer(
                            moment: moment,
                            centerX: size.width - 22 - labelWidth / 2,
                            y: origin.y + 76,
                            width: labelWidth
                        )
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
        burst = 0
        dismissing = false
        warp = 0
        announced = false
    }

    @ViewBuilder
    private func background(
        moment: AirPodsMoment,
        size: CGSize,
        origin: CGPoint
    ) -> some View {
        let isConnected = moment.kind == .connected

        ZStack {
            Color.black

            if let snapshot {
                Image(uiImage: snapshot)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .saturation(isConnected ? 1 : 0.30)
                    .modifier(
                        AirPodsRippleEffect(
                            progress: reduceMotion ? 0 : warp,
                            size: size,
                            origin: origin
                        )
                    )
                    .blur(radius: warpBlur)
            }

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.30), location: 0),
                    .init(color: .black.opacity(0.44), location: 0.44),
                    .init(color: .black.opacity(0.74), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [
                    .white.opacity(isConnected ? 0.16 : 0.05),
                    .clear
                ],
                center: UnitPoint(
                    x: origin.x / max(size.width, 1),
                    y: origin.y / max(size.height, 1)
                ),
                startRadius: 2,
                endRadius: size.height * 0.55
            )
        }
        .opacity(revealed ? 1 : 0)
    }

    private var warpBlur: CGFloat {
        guard !reduceMotion else { return 0 }
        return CGFloat(sin(Double(warp) * .pi)) * 1.6
    }

    private func statusIcon(
        isConnected: Bool,
        origin: CGPoint
    ) -> some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            .white.opacity(isConnected ? 0.30 : 0.10),
                            .clear
                        ],
                        center: .center,
                        startRadius: 6,
                        endRadius: 78
                    )
                )
                .frame(width: 156, height: 156)
                .blur(radius: 16)
                .opacity(revealed ? 1 : 0)

            ZStack {
                SingleAirPodGlyph()
                    .frame(width: 28, height: 42)
                    .shadow(color: .black.opacity(0.40), radius: 5, y: 2)
            }
            .frame(width: 56, height: 56)
            .nativeGlass(Circle())
            .overlay {
                Circle()
                    .strokeBorder(.white.opacity(0.26), lineWidth: 0.8)
            }
            .overlay(alignment: .bottomTrailing) {
                Circle()
                    .fill(isConnected ? mint : slate)
                    .frame(width: 11, height: 11)
                    .overlay {
                        Circle()
                            .strokeBorder(.black.opacity(0.45), lineWidth: 2)
                    }
                    .offset(x: 1, y: 1)
            }
            .shadow(color: .black.opacity(0.30), radius: 14, y: 8)
            .scaleEffect(revealed ? 1 : 0.55)
            .opacity(revealed ? 1 : 0)
        }
        .position(origin)
    }

    private func footer(
        moment: AirPodsMoment,
        centerX: CGFloat,
        y: CGFloat,
        width: CGFloat
    ) -> some View {
        let isConnected = moment.kind == .connected

        return VStack(alignment: .trailing, spacing: 8) {
            Text(moment.name)
                .font(.system(size: 22, weight: .semibold))
                .tracking(-0.3)
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .shadow(color: .black.opacity(0.40), radius: 8, y: 2)

            statusChip(isConnected: isConnected)
        }
        .frame(width: width, alignment: .trailing)
        .position(x: centerX, y: y)
        .opacity(settled ? 1 : 0)
        .offset(y: settled ? 0 : -8)
    }

    private func statusChip(isConnected: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: isConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isConnected ? mint : slate)

            Text(isConnected ? "Connected" : "Disconnected")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.82))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .nativeGlass(Capsule())
        .overlay {
            Capsule()
                .strokeBorder(.white.opacity(0.20), lineWidth: 0.8)
        }
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

            try? await Task.sleep(nanoseconds: 2_100_000_000)
            guard !Task.isCancelled else { return }
            monitor.dismiss()
            return
        }

        withAnimation(.spring(response: 0.46, dampingFraction: 0.74)) {
            revealed = true
        }
        MotifHaptics.play(.soft)

        if moment.kind == .connected {
            withAnimation(.linear(duration: 2.2)) {
                warp = 1
            }

            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.90)) {
                burst = 1
            }
            MotifHaptics.play(.light)

            try? await Task.sleep(nanoseconds: 560_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.36, dampingFraction: 0.80)) {
                settled = true
            }
            MotifHaptics.play(.success)
            announce(moment)

            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled else { return }

        } else {
            try? await Task.sleep(nanoseconds: 480_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.36, dampingFraction: 0.80)) {
                settled = true
            }
            MotifHaptics.play(.light)
            announce(moment)

            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
        }

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

private struct AirPodsRings: View {
    let center: CGPoint
    let radius: CGFloat
    let spread: CGFloat
    let bright: Color
    let soft: Color
    let collapsing: Bool

    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                draw(
                    context: &context,
                    size: size,
                    elapsed: timeline.date.timeIntervalSince(start)
                )
            }
        }
    }

    private func draw(
        context: inout GraphicsContext,
        size: CGSize,
        elapsed: TimeInterval
    ) {
        guard size.width > 1, size.height > 1 else { return }

        let maxRadius = max(spread, radius)

        // Expanding (or collapsing) AirDrop-style rings from the status icon.
        for index in 0..<3 {
            let progress = (elapsed - Double(index) * 0.18) / 1.5
            guard progress > 0, progress < 1 else { continue }

            let p = CGFloat(progress)
            let current = collapsing
                ? maxRadius - p * (maxRadius - radius)
                : radius + p * (maxRadius - radius)
            let fade = Double(sin(p * .pi))

            let rect = CGRect(
                x: center.x - current,
                y: center.y - current,
                width: current * 2,
                height: current * 2
            )

            context.stroke(
                Path(ellipseIn: rect),
                with: .linearGradient(
                    Gradient(colors: [
                        .clear,
                        bright.opacity(fade * 0.40),
                        soft.opacity(fade * 0.14),
                        .clear
                    ]),
                    startPoint: CGPoint(x: rect.minX, y: rect.minY),
                    endPoint: CGPoint(x: rect.maxX, y: rect.maxY)
                ),
                lineWidth: 1.2
            )
        }

        // A single rotating scan arc, like the AirDrop radar.
        let angle = elapsed * (collapsing ? -95 : 95)
        let arcRadius = radius + CGFloat(min(elapsed, 1.2)) * 90
        var arc = Path()
        arc.addArc(
            center: center,
            radius: arcRadius,
            startAngle: .degrees(angle),
            endAngle: .degrees(angle + 52),
            clockwise: false
        )
        context.stroke(
            arc,
            with: .linearGradient(
                Gradient(colors: [.clear, bright.opacity(0.36), .clear]),
                startPoint: CGPoint(x: center.x - arcRadius, y: center.y),
                endPoint: CGPoint(x: center.x + arcRadius, y: center.y)
            ),
            lineWidth: 1.6
        )

        // A slow halo breathing behind the icon.
        let pulse = 0.5 + 0.5 * sin(elapsed * 2.4)
        let halo = max(90, spread * 0.10)
        context.fill(
            Path(
                ellipseIn: CGRect(
                    x: center.x - halo,
                    y: center.y - halo,
                    width: halo * 2,
                    height: halo * 2
                )
            ),
            with: .radialGradient(
                Gradient(colors: [bright.opacity(0.09 * pulse), .clear]),
                center: center,
                startRadius: 6,
                endRadius: halo
            )
        )
    }
}

private struct AirPodsParticles: View {
    let center: CGPoint
    let radius: CGFloat
    let bright: Color
    let soft: Color

    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            Canvas { context, _ in
                draw(
                    context: &context,
                    elapsed: timeline.date.timeIntervalSince(start)
                )
            }
        }
        .allowsHitTesting(false)
    }

    private func draw(context: inout GraphicsContext, elapsed: TimeInterval) {
        let life: Double = 2.4
        guard elapsed < life else { return }

        for index in 0..<24 {
            let seed = Double(index) * 0.6180339887
            let angle = seed * .pi * 2 + Double(index) * 0.37
            let orbit = Double(radius)
                * (0.55 + 0.65 * (seed * 7).truncatingRemainder(dividingBy: 1))
            let rise = elapsed
                * (6 + 10 * (seed * 3).truncatingRemainder(dividingBy: 1))
            let sway = sin(elapsed * 0.8 + seed * 6) * 6
            let x = Double(center.x) + cos(angle) * orbit + sway
            let y = Double(center.y) - rise + sin(angle) * orbit * 0.35

            let appear = min(elapsed / 0.4, 1)
                * min(max((life - elapsed) / 0.6, 0), 1)
            let twinkle = 0.35 + 0.65 * (0.5 + 0.5 * sin(elapsed * 3 + seed * 9))
            let dot = 1.0 + 1.4 * (seed * 5).truncatingRemainder(dividingBy: 1)
            let tint = index % 3 == 0 ? bright : soft

            context.fill(
                Path(ellipseIn: CGRect(x: x, y: y, width: dot, height: dot)),
                with: .color(tint.opacity(0.42 * appear * twinkle))
            )
        }
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
            // hand it the status icon's origin in that same flipped space.
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
