import SwiftUI
import UIKit

struct AirPodsMomentOverlay: View {
    @ObservedObject var monitor: AudioRouteMonitor

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var snapshot: UIImage?
    @State private var revealed = false
    @State private var caseShown = false
    @State private var budsOut = false
    @State private var settled = false
    @State private var burst: CGFloat = 0
    @State private var dismissing = false
    @State private var warp: CGFloat = 0
    @State private var announced = false

    private let mint = Color(red: 0.49, green: 0.96, blue: 0.78)
    private let silver = Color(white: 0.70)
    private let slate = Color(white: 0.55)
    private let iconWhite = Color(white: 0.97)

    var body: some View {
        ZStack {
            if let moment = monitor.moment {
                GeometryReader { proxy in
                    let size = proxy.size
                    let heroWidth = min(size.width * 0.92, 360)
                    let iconScale = heroWidth / 340
                    let stage = CGPoint(x: size.width / 2, y: size.height * 0.39)
                    let isConnected = moment.kind == .connected

                    ZStack {
                        background(moment: moment, size: size)

                        if revealed {
                            AirPodsRings(
                                center: stage,
                                radius: heroWidth * 0.30,
                                bright: .white,
                                soft: silver,
                                collapsing: !isConnected
                            )
                            .frame(width: size.width, height: size.height)
                            .allowsHitTesting(false)

                            AirPodsParticles(
                                center: stage,
                                radius: heroWidth * 0.42,
                                bright: .white,
                                soft: silver
                            )
                            .frame(width: size.width, height: size.height)
                            .allowsHitTesting(false)
                        }

                        hero(
                            isConnected: isConnected,
                            stage: stage,
                            width: heroWidth
                        )

                        footer(
                            moment: moment,
                            centerX: stage.x,
                            y: stage.y + (budsOut ? 118.0 : 200.0) * iconScale
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
        caseShown = false
        budsOut = false
        settled = false
        burst = 0
        dismissing = false
        warp = 0
        announced = false
    }

    @ViewBuilder
    private func background(moment: AirPodsMoment, size: CGSize) -> some View {
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
                            size: size
                        )
                    )
                    .blur(radius: warpBlur)
            }

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.34), location: 0),
                    .init(color: .black.opacity(0.46), location: 0.40),
                    .init(color: .black.opacity(0.72), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [
                    .white.opacity(isConnected ? 0.10 : 0.04),
                    .clear
                ],
                center: UnitPoint(x: 0.5, y: 0.39),
                startRadius: 10,
                endRadius: size.height * 0.42
            )
        }
        .opacity(revealed ? 1 : 0)
    }

    private var warpBlur: CGFloat {
        guard !reduceMotion else { return 0 }
        return CGFloat(sin(Double(warp) * .pi)) * 3.0
    }

    private func hero(
        isConnected: Bool,
        stage: CGPoint,
        width: CGFloat
    ) -> some View {
        let scale = width / 340

        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            .white.opacity(isConnected ? 0.10 : 0.045),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 170
                    )
                )
                .frame(width: 300, height: 300)
                .blur(radius: 24)
                .position(x: 170, y: 180)

            if burst > 0.001 {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                .white.opacity(0.42),
                                .white.opacity(0.12),
                                .clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 90
                        )
                    )
                    .frame(width: 220, height: 220)
                    .scaleEffect(0.35 + burst * 1.4)
                    .opacity(Double(1 - burst))
                    .blur(radius: 14)
                    .position(x: 170, y: 180)
            }

            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.16), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 130
                    )
                )
                .frame(width: 260, height: 22)
                .blur(radius: 18)
                .position(x: 170, y: 300)
                .opacity(caseShown ? 1 : 0)

            ZStack {
                openCaseLid
                    .opacity(caseShown ? 1 : 0)
                    .scaleEffect(caseShown ? 1 : 0.95)
                    .offset(y: caseShown ? 0 : 16)
                    .position(x: 170, y: 150)

                bud(side: -1)
                bud(side: 1)

                openCaseBody
                    .opacity(caseShown ? 1 : 0)
                    .scaleEffect(caseShown ? 1 : 0.95)
                    .offset(y: caseShown ? 0 : 16)
                    .position(x: 170, y: 246)
            }
        }
        .frame(width: 340, height: 320)
        .opacity(revealed ? 1 : 0)
        .scaleEffect(scale)
        .position(stage)
    }

    private func bud(side: CGFloat) -> some View {
        AirPodsBudIcon(mirrored: side < 0)
            .scaleEffect(budsOut ? 1 : 0.55)
            .position(
                x: 170 + side * (budsOut ? 58 : 34),
                y: budsOut ? 120 : 172
            )
    }

    private var openCaseLid: some View {
        RoundedRectangle(cornerRadius: 42, style: .continuous)
            .fill(iconWhite)
            .frame(width: 190, height: 160)
            .overlay {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(.black)
                    .frame(width: 144, height: 118)
                    .offset(y: 20)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
            .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
            .shadow(color: .white.opacity(0.08), radius: 22)
    }

    private var openCaseBody: some View {
        RoundedRectangle(cornerRadius: 36, style: .continuous)
            .fill(iconWhite)
            .frame(width: 190, height: 112)
            .overlay {
                Capsule()
                    .fill(.black)
                    .frame(width: 22, height: 7)
                    .offset(y: -20)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
            .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
            .shadow(color: .white.opacity(0.08), radius: 22)
    }

    private func footer(
        moment: AirPodsMoment,
        centerX: CGFloat,
        y: CGFloat
    ) -> some View {
        let isConnected = moment.kind == .connected

        return VStack(spacing: 10) {
            Text(moment.name)
                .font(.system(size: 30, weight: .bold))
                .tracking(-0.7)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .shadow(color: .black.opacity(0.35), radius: 10, y: 2)

            statusChip(isConnected: isConnected)
        }
        .frame(maxWidth: 330)
        .position(x: centerX, y: y)
        .opacity(settled ? 1 : 0)
        .offset(y: settled ? 0 : 12)
    }

    private func statusChip(isConnected: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: isConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isConnected ? mint : slate)

            Text(isConnected ? "Connected" : "Disconnected")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.80))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
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

        if moment.kind == .disconnected {
            // Enter with the buds already out, then put them away.
            budsOut = true
        }

        if reduceMotion {
            revealed = true
            caseShown = false
            budsOut = moment.kind == .connected
            settled = true
            MotifHaptics.play(moment.kind == .connected ? .success : .soft)
            announce(moment)

            try? await Task.sleep(nanoseconds: 2_100_000_000)
            guard !Task.isCancelled else { return }
            monitor.dismiss()
            return
        }

        withAnimation(.easeOut(duration: 0.20)) {
            revealed = true
        }

        if moment.kind == .connected {
            withAnimation(.linear(duration: 2.2)) {
                warp = 1
            }
        }

        withAnimation(.spring(response: 0.58, dampingFraction: 0.80)) {
            caseShown = true
        }
        MotifHaptics.play(.soft)

        switch moment.kind {
        case .connected:
            try? await Task.sleep(nanoseconds: 420_000_000)
            guard !Task.isCancelled else { return }

            withAnimation(.spring(response: 0.72, dampingFraction: 0.68)) {
                budsOut = true
            }
            withAnimation(.easeInOut(duration: 0.50)) {
                caseShown = false
            }
            withAnimation(.easeOut(duration: 0.85)) {
                burst = 1
            }
            MotifHaptics.play(.light)

            try? await Task.sleep(nanoseconds: 560_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.40, dampingFraction: 0.74)) {
                settled = true
            }
            MotifHaptics.play(.success)
            announce(moment)

            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }

        case .disconnected:
            try? await Task.sleep(nanoseconds: 560_000_000)
            guard !Task.isCancelled else { return }

            withAnimation(.spring(response: 0.62, dampingFraction: 0.82)) {
                budsOut = false
            }
            MotifHaptics.play(.soft)

            try? await Task.sleep(nanoseconds: 560_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.28)) {
                settled = true
            }
            MotifHaptics.play(.light)
            announce(moment)

            try? await Task.sleep(nanoseconds: 1_300_000_000)
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

/// A single white AirPods bud, traced from the flat two-tone reference: an
/// oval head with a speaker slot and vent cut out, and a rounded stem.
private struct AirPodsBudIcon: View {
    var mirrored = false

    private let fill = Color(white: 0.97)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(fill)
                .frame(width: 20, height: 64)
                .offset(x: -7, y: 30)

            head
                .offset(y: -14)
        }
        .frame(width: 78, height: 132)
        .scaleEffect(x: mirrored ? -1 : 1, y: 1)
        .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
        .shadow(color: .white.opacity(0.10), radius: 18)
    }

    private var head: some View {
        Ellipse()
            .fill(fill)
            .frame(width: 70, height: 56)
            .overlay {
                ZStack {
                    Capsule()
                        .fill(.black)
                        .frame(width: 26, height: 11)
                        .rotationEffect(.degrees(-18))
                        .offset(x: 8, y: -6)

                    Capsule()
                        .fill(.black)
                        .frame(width: 15, height: 6)
                        .rotationEffect(.degrees(-18))
                        .offset(x: -13, y: 13)
                }
                .blendMode(.destinationOut)
            }
            .compositingGroup()
            .rotationEffect(.degrees(14))
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

        let maxRadius = min(size.width, size.height) * 0.52

        // Expanding (or collapsing) AirDrop-style rings.
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
                        bright.opacity(fade * 0.44),
                        soft.opacity(fade * 0.16),
                        .clear
                    ]),
                    startPoint: CGPoint(x: rect.minX, y: rect.minY),
                    endPoint: CGPoint(x: rect.maxX, y: rect.maxY)
                ),
                lineWidth: 1.3
            )
        }

        // A single rotating scan arc, like the AirDrop radar.
        let angle = elapsed * (collapsing ? -95 : 95)
        let arcRadius = radius + CGFloat(min(elapsed, 1.2)) * 70
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
                Gradient(colors: [.clear, bright.opacity(0.34), .clear]),
                startPoint: CGPoint(x: center.x - arcRadius, y: center.y),
                endPoint: CGPoint(x: center.x + arcRadius, y: center.y)
            ),
            lineWidth: 1.8
        )

        // A slow halo breathing behind the case.
        let pulse = 0.5 + 0.5 * sin(elapsed * 2.4)
        let halo = radius * 1.5
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
                Gradient(colors: [bright.opacity(0.10 * pulse), .clear]),
                center: center,
                startRadius: halo * 0.5,
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
        let life: Double = 2.6
        guard elapsed < life else { return }

        for index in 0..<30 {
            let seed = Double(index) * 0.6180339887
            let angle = seed * .pi * 2 + Double(index) * 0.37
            let orbit = Double(radius)
                * (0.75 + 0.65 * (seed * 7).truncatingRemainder(dividingBy: 1))
            let rise = elapsed
                * (10 + 14 * (seed * 3).truncatingRemainder(dividingBy: 1))
            let sway = sin(elapsed * 0.8 + seed * 6) * 9
            let x = Double(center.x) + cos(angle) * orbit * 0.55 + sway
            let y = Double(center.y) + sin(angle) * orbit * 0.85 - rise

            let appear = min(elapsed / 0.5, 1)
                * min(max((life - elapsed) / 0.7, 0), 1)
            let twinkle = 0.35 + 0.65 * (0.5 + 0.5 * sin(elapsed * 3 + seed * 9))
            let dot = 1.2 + 1.6 * (seed * 5).truncatingRemainder(dividingBy: 1)
            let tint = index % 3 == 0 ? bright : soft

            context.fill(
                Path(ellipseIn: CGRect(x: x, y: y, width: dot, height: dot)),
                with: .color(tint.opacity(0.45 * appear * twinkle))
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
