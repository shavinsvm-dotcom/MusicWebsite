import SwiftUI
import UIKit

struct AirPodsMomentOverlay: View {
    @ObservedObject var monitor: AudioRouteMonitor

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var snapshot: UIImage?
    @State private var revealed = false
    @State private var caseIn = false
    @State private var lidOpen = false
    @State private var budsOut = false
    @State private var settled = false
    @State private var burst: CGFloat = 0
    @State private var dismissing = false
    @State private var warp: CGFloat = 0
    @State private var announced = false

    private let blue = Color(red: 0.33, green: 0.71, blue: 1.0)
    private let cyan = Color(red: 0.55, green: 0.93, blue: 1.0)
    private let mint = Color(red: 0.49, green: 0.96, blue: 0.78)
    private let slate = Color(red: 0.64, green: 0.70, blue: 0.82)

    var body: some View {
        ZStack {
            if let moment = monitor.moment {
                GeometryReader { proxy in
                    let size = proxy.size
                    let heroWidth = min(size.width * 0.88, 330)
                    let heroHeight = heroWidth * 0.98
                    let stage = CGPoint(x: size.width / 2, y: size.height * 0.40)
                    let caseWidth = heroWidth * 0.55
                    let caseHeight = caseWidth * 0.90
                    let caseCenter = CGPoint(
                        x: stage.x,
                        y: stage.y + heroHeight / 2 - 12 - caseHeight / 2
                    )
                    let isConnected = moment.kind == .connected

                    ZStack {
                        background(moment: moment, size: size)

                        if revealed {
                            AirPodsRings(
                                center: caseCenter,
                                radius: caseWidth * 0.72,
                                blue: blue,
                                cyan: cyan,
                                collapsing: !isConnected
                            )
                            .frame(width: size.width, height: size.height)
                            .allowsHitTesting(false)

                            AirPodsParticles(
                                center: caseCenter,
                                radius: caseWidth * 1.05,
                                blue: blue,
                                cyan: cyan
                            )
                            .frame(width: size.width, height: size.height)
                            .allowsHitTesting(false)
                        }

                        hero(
                            moment: moment,
                            stage: stage,
                            width: heroWidth,
                            height: heroHeight
                        )

                        footer(
                            moment: moment,
                            centerX: stage.x,
                            y: stage.y + heroHeight / 2 + 42
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
        caseIn = false
        lidOpen = false
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
        stage: CGPoint,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        let isConnected = moment.kind == .connected
        let accent = isConnected ? cyan : slate
        let caseW = width * 0.55
        let caseH = caseW * 0.90
        let caseTop = height - 12 - caseH
        let lidH = caseH * 0.36
        let openingY = caseTop + 8

        return ZStack {
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            accent.opacity(isConnected ? 0.42 : 0.20),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: caseW * 0.62
                    )
                )
                .frame(width: caseW * 1.6, height: caseH * 0.34)
                .blur(radius: 26)
                .position(x: width / 2, y: caseTop + caseH + 2)

            if burst > 0.001 {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                .white.opacity(0.45),
                                cyan.opacity(0.20),
                                .clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: caseW * 0.55
                        )
                    )
                    .frame(width: caseW * 1.2, height: caseW * 1.2)
                    .scaleEffect(0.35 + burst * 1.3)
                    .opacity(Double(1 - burst))
                    .blur(radius: 12)
                    .position(x: width / 2, y: openingY)
            }

            lid(width: caseW, height: lidH)
                .position(x: width / 2, y: caseTop + lidH / 2)

            budArea(width: width, openingY: openingY)
                .position(x: width / 2, y: openingY / 2)

            caseBody(
                isConnected: isConnected,
                width: caseW,
                height: caseH,
                lidHeight: lidH
            )
            .position(x: width / 2, y: caseTop + caseH / 2)

            badge(isConnected: isConnected)
                .position(
                    x: width / 2 + caseW / 2 - 6,
                    y: caseTop + caseH - 8
                )
        }
        .frame(width: width, height: height)
        .scaleEffect(caseIn ? 1 : 0.86, anchor: .bottom)
        .rotation3DEffect(
            .degrees(caseIn ? 0 : 10),
            axis: (x: 1, y: 0, z: 0),
            perspective: 0.6
        )
        .offset(y: caseIn ? 0 : 46)
        .opacity(caseIn ? 1 : 0)
        .position(stage)
    }

    private func lid(width: CGFloat, height: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: width * 0.21, style: .continuous)

        return shape
            .fill(plasticFill)
            .frame(width: width, height: height)
            .overlay {
                shape
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.48, green: 0.54, blue: 0.63)
                                    .opacity(0.55),
                                Color(red: 0.72, green: 0.77, blue: 0.84)
                                    .opacity(0.16)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .opacity(lidOpen ? 1 : 0)
            }
            .overlay {
                shape
                    .strokeBorder(.white.opacity(0.62), lineWidth: 1)
            }
            .scaleEffect(x: 1, y: lidOpen ? 0.52 : 1, anchor: .bottom)
            .offset(y: lidOpen ? -height : 0)
            .shadow(color: .black.opacity(lidOpen ? 0.26 : 0), radius: 10, y: 4)
    }

    private func caseBody(
        isConnected: Bool,
        width: CGFloat,
        height: CGFloat,
        lidHeight: CGFloat
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: width * 0.21, style: .continuous)
        let accent = isConnected ? cyan : slate

        return shape
            .fill(plasticFill)
            .frame(width: width, height: height)
            .overlay {
                ZStack {
                    Ellipse()
                        .fill(
                            RadialGradient(
                                colors: [.white.opacity(0.80), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: width * 0.55
                            )
                        )
                        .frame(width: width * 0.95, height: height * 0.50)
                        .offset(x: -width * 0.10, y: -height * 0.28)
                        .blur(radius: 9)
                }
                .frame(width: width, height: height)
                .clipShape(shape)
                .allowsHitTesting(false)
            }
            .overlay {
                Rectangle()
                    .fill(Color.black.opacity(0.14))
                    .frame(width: width * 0.90, height: 1)
                    .offset(y: -height / 2 + lidHeight)
                    .opacity(lidOpen ? 0 : 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.03, green: 0.05, blue: 0.09),
                                Color(red: 0.10, green: 0.17, blue: 0.26)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: width * 0.76, height: height * 0.11)
                    .offset(y: -height / 2 + 12)
                    .opacity(lidOpen ? 1 : 0)
            }
            .overlay {
                Capsule()
                    .fill(accent.opacity(0.60))
                    .frame(width: width * 0.62, height: 1.6)
                    .blur(radius: 3)
                    .offset(y: -height / 2 + 22)
                    .opacity(lidOpen ? 1 : 0)
            }
            .overlay {
                Circle()
                    .fill(isConnected ? mint : Color(white: 0.56))
                    .frame(width: 5, height: 5)
                    .shadow(
                        color: accent.opacity(isConnected ? 0.9 : 0.18),
                        radius: 4
                    )
                    .offset(y: height * 0.17)
            }
            .overlay {
                shape
                    .strokeBorder(.white.opacity(0.65), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.42), radius: 28, y: 16)
            .shadow(
                color: accent.opacity(isConnected ? 0.22 : 0.10),
                radius: 34,
                y: 4
            )
            .saturation(isConnected ? 1 : 0.72)
    }

    private func budArea(width: CGFloat, openingY: CGFloat) -> some View {
        ZStack {
            AirPodBud(mirrored: false)
                .frame(width: 44, height: 78)
                .rotationEffect(.degrees(-7))
                .offset(x: budsOut ? 0 : -14, y: budsOut ? 0 : 70)
                .scaleEffect(budsOut ? 1 : 0.62)
                .position(x: width / 2 - 38, y: openingY - 40)

            AirPodBud(mirrored: true)
                .frame(width: 44, height: 78)
                .rotationEffect(.degrees(7))
                .offset(x: budsOut ? 0 : 14, y: budsOut ? 0 : 70)
                .scaleEffect(budsOut ? 1 : 0.62)
                .position(x: width / 2 + 38, y: openingY - 40)
        }
        .frame(width: width, height: openingY)
        .clipped()
    }

    private func badge(isConnected: Bool) -> some View {
        let accent = isConnected ? mint : slate

        return ZStack {
            Circle()
                .fill(Color.white.opacity(0.06))
                .nativeGlass(Circle())
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(0.26), lineWidth: 0.8)
                }

            Image(systemName: isConnected ? "checkmark" : "xmark")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(isConnected ? accent : .white.opacity(0.70))
        }
        .frame(width: 46, height: 46)
        .shadow(color: accent.opacity(0.40), radius: 14, y: 5)
        .scaleEffect(settled ? 1 : 0.30)
        .opacity(settled ? 1 : 0)
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

    private var plasticFill: LinearGradient {
        LinearGradient(
            colors: [
                Color(white: 1.0),
                Color(white: 0.96),
                Color(white: 0.84)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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
            // The case enters open, with the buds still out, then puts them away.
            lidOpen = true
            budsOut = true
        }

        if reduceMotion {
            caseIn = true
            revealed = true
            switch moment.kind {
            case .connected:
                lidOpen = true
                budsOut = true
            case .disconnected:
                lidOpen = false
                budsOut = false
            }
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

        withAnimation(.spring(response: 0.60, dampingFraction: 0.78)) {
            caseIn = true
        }
        MotifHaptics.play(.soft)

        switch moment.kind {
        case .connected:
            try? await Task.sleep(nanoseconds: 360_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.52, dampingFraction: 0.80)) {
                lidOpen = true
            }
            MotifHaptics.play(.light)

            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.68)) {
                budsOut = true
            }
            withAnimation(.easeOut(duration: 0.85)) {
                burst = 1
            }
            MotifHaptics.play(.soft)

            try? await Task.sleep(nanoseconds: 430_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.40, dampingFraction: 0.74)) {
                settled = true
            }
            MotifHaptics.play(.success)
            announce(moment)

            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }

        case .disconnected:
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.80)) {
                budsOut = false
            }
            MotifHaptics.play(.soft)

            try? await Task.sleep(nanoseconds: 460_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.50, dampingFraction: 0.86)) {
                lidOpen = false
            }

            try? await Task.sleep(nanoseconds: 380_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.28)) {
                settled = true
            }
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

/// One stylised AirPod: a glossy white head with a short stem, mirrorable so
/// the pair faces each other.
private struct AirPodBud: View {
    let mirrored: Bool

    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(budFill)
                .frame(width: 15, height: 48)
                .offset(y: 15)

            Ellipse()
                .fill(budFill)
                .frame(width: 35, height: 39)
                .offset(y: -17)
                .overlay {
                    Ellipse()
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.8)
                }

            Ellipse()
                .fill(Color.black.opacity(0.20))
                .frame(width: 13, height: 7)
                .offset(x: -8, y: -22)

            Circle()
                .fill(Color(white: 0.42).opacity(0.55))
                .frame(width: 4, height: 4)
                .offset(x: 4, y: -4)

            Capsule(style: .continuous)
                .fill(Color(white: 0.58))
                .frame(width: 6, height: 11)
                .offset(y: 36)
        }
        .frame(width: 44, height: 78)
        .scaleEffect(x: mirrored ? -1 : 1, y: 1)
        .shadow(color: .black.opacity(0.28), radius: 8, y: 4)
    }

    private var budFill: LinearGradient {
        LinearGradient(
            colors: [
                Color(white: 1.0),
                Color(white: 0.94),
                Color(white: 0.76)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
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

        // A slow halo breathing behind the case.
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
