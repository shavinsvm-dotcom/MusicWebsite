import SwiftUI
import UIKit

struct AirPodsMomentOverlay: View {
    @ObservedObject var monitor: AudioRouteMonitor

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var snapshot: UIImage?
    @State private var revealed = false
    @State private var cardIn = false
    @State private var settled = false
    @State private var statusShown = false
    @State private var dismissing = false
    @State private var warp: CGFloat = 0
    @State private var sweep: CGFloat = -1.3
    @State private var announced = false

    private let blue = Color(red: 0.33, green: 0.71, blue: 1.0)
    private let cyan = Color(red: 0.55, green: 0.93, blue: 1.0)
    private let mint = Color(red: 0.49, green: 0.96, blue: 0.78)
    private let slate = Color(red: 0.64, green: 0.70, blue: 0.82)

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 46, style: .continuous)
    }

    var body: some View {
        ZStack {
            if let moment = monitor.moment {
                GeometryReader { proxy in
                    let size = proxy.size
                    let cardWidth = min(size.width * 0.70, 300)
                    let cardHeight = cardWidth * 1.06
                    let center = CGPoint(x: size.width / 2, y: size.height * 0.40)
                    let isConnected = moment.kind == .connected

                    ZStack {
                        background(moment: moment, size: size)

                        if revealed {
                            AirPodsRings(
                                center: center,
                                radius: cardWidth * 0.58,
                                blue: blue,
                                cyan: cyan,
                                collapsing: !isConnected
                            )
                            .frame(width: size.width, height: size.height)
                            .allowsHitTesting(false)

                            AirPodsParticles(
                                center: center,
                                radius: cardWidth * 0.9,
                                blue: blue,
                                cyan: cyan
                            )
                            .frame(width: size.width, height: size.height)
                            .allowsHitTesting(false)
                        }

                        hero(
                            moment: moment,
                            center: center,
                            width: cardWidth,
                            height: cardHeight
                        )

                        footer(
                            moment: moment,
                            center: center,
                            cardHeight: cardHeight
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
        cardIn = false
        settled = false
        statusShown = false
        dismissing = false
        warp = 0
        sweep = -1.3
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
                    .init(color: .black.opacity(0.30), location: 0),
                    .init(color: .black.opacity(0.44), location: 0.40),
                    .init(color: .black.opacity(0.70), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [
                    blue.opacity(isConnected ? 0.30 : 0.16),
                    Color(red: 0.42, green: 0.48, blue: 1.0)
                        .opacity(isConnected ? 0.12 : 0.06),
                    .clear
                ],
                center: UnitPoint(x: 0.5, y: 0.40),
                startRadius: 10,
                endRadius: size.height * 0.46
            )
        }
        .opacity(revealed ? 1 : 0)
    }

    private var warpBlur: CGFloat {
        guard !reduceMotion else { return 0 }
        return CGFloat(sin(Double(warp) * .pi)) * 3.5
    }

    private func hero(
        moment: AirPodsMoment,
        center: CGPoint,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        let isConnected = moment.kind == .connected
        let accent = isConnected ? cyan : slate

        return ZStack {
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            accent.opacity(isConnected ? 0.40 : 0.22),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: width * 0.55
                    )
                )
                .frame(width: width * 1.5, height: height * 0.30)
                .blur(radius: 26)
                .offset(y: height * 0.52)
                .opacity(cardIn ? 1 : 0)

            card(moment: moment, width: width, height: height)
                .overlay(alignment: .bottomTrailing) {
                    badge(moment: moment)
                        .padding(10)
                }

            Image(systemName: moment.symbolName)
                .font(.system(size: width * 0.44, weight: .regular))
                .foregroundStyle(
                    LinearGradient(
                        stops: [
                            .init(color: .white, location: 0),
                            .init(color: .white.opacity(0.82), location: 0.62),
                            .init(color: .white.opacity(0.96), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: accent.opacity(isConnected ? 0.55 : 0.18), radius: 30, y: 6)
                .shadow(color: .black.opacity(0.35), radius: 10, y: 8)
                .opacity(isConnected ? 1 : 0.52)
                .saturation(isConnected ? 1 : 0.2)
                .scaleEffect(settled ? 1.04 : 1)
                .rotation3DEffect(
                    .degrees(settled ? 0 : -16),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.55
                )
                .offset(y: -10)
        }
        .frame(width: width, height: height)
        .position(center)
        .rotation3DEffect(
            .degrees(cardIn ? 0 : -24),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.55
        )
        .rotation3DEffect(
            .degrees(cardIn ? 0 : 9),
            axis: (x: 1, y: 0, z: 0),
            perspective: 0.55
        )
        .scaleEffect(cardIn ? 1 : 0.80)
        .offset(y: cardIn ? 0 : 80)
        .opacity(cardIn ? 1 : 0)
    }

    private func card(
        moment: AirPodsMoment,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        let isConnected = moment.kind == .connected
        let accent = isConnected ? cyan : slate

        return cardShape
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.10),
                        accent.opacity(0.05),
                        Color.black.opacity(0.10)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .nativeGlass(cardShape)
            .overlay {
                cardShape
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.62), location: 0),
                                .init(color: .white.opacity(0.10), location: 0.32),
                                .init(color: .white.opacity(0.16), location: 0.68),
                                .init(color: accent.opacity(0.40), location: 1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
            }
            .overlay {
                cardShape
                    .inset(by: 7)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8)
            }
            .overlay {
                ZStack {
                    Ellipse()
                        .fill(
                            RadialGradient(
                                colors: [
                                    .white.opacity(0.30),
                                    .white.opacity(0.06),
                                    .clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: width * 0.55
                            )
                        )
                        .frame(width: width * 1.1, height: height * 0.60)
                        .offset(x: -width * 0.16, y: -height * 0.26)
                        .blur(radius: 10)
                }
                .frame(width: width, height: height)
                .clipShape(cardShape)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
            }
            .overlay {
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    .clear,
                                    .white.opacity(0.30),
                                    .clear
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: width * 0.35)
                        .rotationEffect(.degrees(18))
                        .offset(x: sweep * width)
                        .blur(radius: 5)
                }
                .frame(width: width, height: height)
                .mask(cardShape)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
            }
            .frame(width: width, height: height)
    }

    private func badge(moment: AirPodsMoment) -> some View {
        let isConnected = moment.kind == .connected
        let accent = isConnected ? mint : slate

        return ZStack {
            Circle()
                .fill(Color.white.opacity(0.06))
                .nativeGlass(Circle())
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(0.28), lineWidth: 0.8)
                }

            Image(systemName: isConnected ? "checkmark" : "xmark")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(isConnected ? accent : .white.opacity(0.72))
        }
        .frame(width: 54, height: 54)
        .shadow(color: accent.opacity(isConnected ? 0.5 : 0.2), radius: 18, y: 6)
        .scaleEffect(settled ? 1 : 0.30)
        .opacity(settled ? 1 : 0)
    }

    private func footer(
        moment: AirPodsMoment,
        center: CGPoint,
        cardHeight: CGFloat
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
        .position(x: center.x, y: center.y + cardHeight / 2 + 66)
        .opacity(statusShown ? 1 : 0)
        .offset(y: statusShown ? 0 : 12)
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
            // Disconnect enters on the same settled product card, then dims.
            settled = true
        }

        if reduceMotion {
            cardIn = true
            settled = true
            statusShown = true
            revealed = true
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

        withAnimation(.spring(response: 0.62, dampingFraction: 0.78)) {
            cardIn = true
        }

        if moment.kind == .connected {
            MotifHaptics.play(.soft)

            try? await Task.sleep(nanoseconds: 560_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.40, dampingFraction: 0.74)) {
                settled = true
                statusShown = true
            }
            withAnimation(.easeInOut(duration: 0.80)) {
                sweep = 1.35
            }
            MotifHaptics.play(.success)
            announce(moment)

            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }

        } else {
            MotifHaptics.play(.soft)

            try? await Task.sleep(nanoseconds: 620_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.35)) {
                statusShown = true
            }
            announce(moment)

            try? await Task.sleep(nanoseconds: 1_500_000_000)
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

private struct AirPodsRings: View {
    let center: CGPoint
    let radius: CGFloat
    let blue: Color
    let cyan: Color
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
                        cyan.opacity(fade * 0.50),
                        blue.opacity(fade * 0.18),
                        .clear
                    ]),
                    startPoint: CGPoint(x: rect.minX, y: rect.minY),
                    endPoint: CGPoint(x: rect.maxX, y: rect.maxY)
                ),
                lineWidth: 1.4
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
                Gradient(colors: [.clear, cyan.opacity(0.42), .clear]),
                startPoint: CGPoint(x: center.x - arcRadius, y: center.y),
                endPoint: CGPoint(x: center.x + arcRadius, y: center.y)
            ),
            lineWidth: 2
        )

        // A slow halo breathing behind the glass.
        let pulse = 0.5 + 0.5 * sin(elapsed * 2.4)
        let halo = radius * 0.92
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
                Gradient(colors: [cyan.opacity(0.16 * pulse), .clear]),
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
    let blue: Color
    let cyan: Color

    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            Canvas { context, _ in
                draw(elapsed: timeline.date.timeIntervalSince(start))
            }
        }
        .allowsHitTesting(false)
    }

    private func draw(elapsed: TimeInterval) {
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
            let tint = index % 3 == 0 ? cyan : blue

            context.fill(
                Path(ellipseIn: CGRect(x: x, y: y, width: dot, height: dot)),
                with: .color(tint.opacity(0.50 * appear * twinkle))
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
