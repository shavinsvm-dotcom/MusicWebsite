import Combine
import CoreImage
import SwiftUI
import UIKit

enum LivingArtworkSettings {
    static let enabledKey = "motif.livingArtworkEnabled"
    static let defaultEnabled = true
}

/// A quiet, animated treatment for large artwork. It deliberately renders only
/// a handful of moving gradients and dust motes, and drops back to the exact
/// static `ArtworkView` whenever animation would be costly or unwanted.
struct LivingArtworkView: View {
    let url: URL?
    let seed: String
    let isPlaying: Bool
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(LivingArtworkSettings.enabledKey) private var enabled = LivingArtworkSettings.defaultEnabled

    @State private var image: UIImage?
    @State private var palette: LivingArtworkPalette
    @State private var isVisible = false
    @State private var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var thermalState = ProcessInfo.processInfo.thermalState

    private let particles: [LivingArtworkParticle]

    init(url: URL?, seed: String, isPlaying: Bool = true, isActive: Bool = true) {
        self.url = url
        self.seed = seed
        self.isPlaying = isPlaying
        self.isActive = isActive
        _image = State(initialValue: url.flatMap { ArtworkImageCache.shared.image(for: $0) })
        _palette = State(initialValue: LivingArtworkPalette.fallback(seed: seed))
        particles = LivingArtworkParticle.field(seed: seed)
    }

    private var thermalPressure: Bool {
        thermalState == .serious || thermalState == .critical
    }

    private var shouldAnimate: Bool {
        enabled
            && isPlaying
            && isVisible
            && scenePhase == .active
            && !reduceMotion
            && !lowPowerMode
            && !thermalPressure
            && image != nil
    }

    var body: some View {
        ZStack {
            ArtworkView(url: url, seed: seed) { loaded in
                image = loaded
                palette = LivingArtworkPalette(image: loaded, seed: seed)
            }

            if shouldAnimate, let image {
                TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !isActive)) { timeline in
                    LivingArtworkScene(
                        image: image,
                        palette: palette,
                        particles: particles,
                        time: timeline.date.timeIntervalSinceReferenceDate
                    )
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .clipped()
        .onAppear {
            isVisible = true
        }
        .onDisappear {
            isVisible = false
        }
        .onChange(of: url) { newURL in
            image = newURL.flatMap { ArtworkImageCache.shared.image(for: $0) }
            palette = .fallback(seed: seed)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
            thermalState = ProcessInfo.processInfo.thermalState
        }
    }
}

private struct LivingArtworkScene: View {
    let image: UIImage
    let palette: LivingArtworkPalette
    let particles: [LivingArtworkParticle]
    let time: TimeInterval

    var body: some View {
        Canvas(opaque: true) { context, size in
            draw(context: &context, size: size)
        }
    }

    private func draw(context: inout GraphicsContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        guard size.width > 1, size.height > 1,
              image.size.width > 0, image.size.height > 0
        else { return }

        context.fill(Path(rect), with: .color(.black))

        let elapsed = CGFloat(time)
        let cover = coverSize(for: image.size, in: size)
        let breath = 1.045 + 0.006 * sin(elapsed * 0.17)
        let driftX = sin(elapsed * 0.09) * size.width * 0.004
        let driftY = cos(elapsed * 0.075) * size.height * 0.003
        let tilt = sin(elapsed * 0.045) * 0.0035
        let resolvedImage = context.resolve(Image(uiImage: image))

        context.drawLayer { layer in
            layer.translateBy(x: size.width / 2 + driftX, y: size.height / 2 + driftY)
            layer.rotate(by: .radians(Double(tilt)))
            layer.scaleBy(x: breath, y: breath)
            layer.draw(
                resolvedImage,
                in: CGRect(
                    x: -cover.width / 2,
                    y: -cover.height / 2,
                    width: cover.width,
                    height: cover.height
                )
            )
        }

        drawVignette(in: &context, size: size, rect: rect)
        drawLight(in: &context, size: size, rect: rect, time: elapsed)
        drawEdgeBloom(in: &context, size: size, rect: rect, time: elapsed)
        drawSheen(in: &context, size: size, rect: rect, time: elapsed)
        drawParticles(in: &context, size: size)
    }

    private func coverSize(for imageSize: CGSize, in size: CGSize) -> CGSize {
        let scale = max(size.width / imageSize.width, size.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    private func drawVignette(in context: inout GraphicsContext, size: CGSize, rect: CGRect) {
        context.fill(
            Path(rect),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: 0.58),
                    .init(color: .black.opacity(0.34), location: 1)
                ]),
                center: CGPoint(x: size.width * 0.5, y: size.height * 0.46),
                startRadius: 0,
                endRadius: max(size.width, size.height) * 0.78
            )
        )
    }

    private func drawLight(in context: inout GraphicsContext, size: CGSize, rect: CGRect, time elapsed: CGFloat) {
        let coolX = size.width * (0.25 + 0.09 * sin(elapsed * 0.07))
        let coolY = size.height * (0.18 + 0.06 * cos(elapsed * 0.053))
        let warmX = size.width * (0.78 + 0.06 * cos(elapsed * 0.06))
        let warmY = size.height * (0.72 + 0.05 * sin(elapsed * 0.048))

        context.blendMode = .screen

        context.fill(
            Path(rect),
            with: .radialGradient(
                Gradient(colors: [
                    palette.primary.opacity(0.22),
                    palette.primary.opacity(0.03),
                    .clear
                ]),
                center: CGPoint(x: coolX, y: coolY),
                startRadius: 0,
                endRadius: min(size.width, size.height) * 1.05
            )
        )

        context.fill(
            Path(rect),
            with: .radialGradient(
                Gradient(colors: [
                    palette.secondary.opacity(0.17),
                    palette.secondary.opacity(0.02),
                    .clear
                ]),
                center: CGPoint(x: warmX, y: warmY),
                startRadius: 0,
                endRadius: min(size.width, size.height) * 0.95
            )
        )

        let sweep = CGFloat((Double(elapsed) * 0.026).truncatingRemainder(dividingBy: 1))
        let sweepX = -size.width * 0.7 + sweep * size.width * 1.8
        context.fill(
            Path(rect),
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: palette.highlight.opacity(0.08), location: 0.45),
                    .init(color: .clear, location: 1)
                ]),
                startPoint: CGPoint(x: sweepX - size.width * 0.34, y: 0),
                endPoint: CGPoint(x: sweepX + size.width * 0.34, y: size.height)
            )
        )

        context.blendMode = .normal
    }

    private func drawEdgeBloom(in context: inout GraphicsContext, size: CGSize, rect: CGRect, time elapsed: CGFloat) {
        let pulse = 0.09 + 0.025 * sin(elapsed * 0.21)

        context.blendMode = .screen
        context.fill(
            Path(rect),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: palette.primary.opacity(pulse), location: 0.62),
                    .init(color: palette.secondary.opacity(pulse * 0.9), location: 0.84),
                    .init(color: .clear, location: 1)
                ]),
                center: CGPoint(x: size.width * 0.5, y: size.height * 0.46),
                startRadius: 0,
                endRadius: max(size.width, size.height) * 0.74
            )
        )
        context.blendMode = .normal
    }

    private func drawSheen(in context: inout GraphicsContext, size: CGSize, rect: CGRect, time elapsed: CGFloat) {
        let travel = CGFloat((Double(elapsed) * 0.055).truncatingRemainder(dividingBy: 1))
        let x = -size.width * 0.55 + travel * size.width * 2.1
        let halfBand = size.width * 0.16

        context.blendMode = .screen
        context.fill(
            Path(rect),
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: 0.38),
                    .init(color: palette.highlight.opacity(0.13), location: 0.5),
                    .init(color: .clear, location: 0.62),
                    .init(color: .clear, location: 1)
                ]),
                startPoint: CGPoint(x: x - halfBand, y: 0),
                endPoint: CGPoint(x: x + halfBand, y: size.height)
            )
        )
        context.blendMode = .normal
    }

    private func drawParticles(in context: inout GraphicsContext, size: CGSize) {
        let elapsed = CGFloat(time)
        let scale = min(size.width, size.height) / 320

        context.blendMode = .plusLighter

        for particle in particles {
            let progress = CGFloat(
                (time * particle.speed + particle.phase)
                    .truncatingRemainder(dividingBy: 1)
            )
            let fade = sin(progress * .pi)
            let twinkle = 0.66 + 0.34 * sin(
                elapsed * CGFloat(0.7 + particle.speed * 34)
                    + CGFloat(particle.phase) * .pi * 2
            )
            guard fade > 0.01 else { continue }

            let x = size.width * CGFloat(particle.x)
                + sin(elapsed * CGFloat(particle.wobble) + CGFloat(particle.phase) * .pi * 2)
                    * size.width * CGFloat(particle.drift)
            let y = size.height * (1.10 - progress * 1.24)
                + (CGFloat(particle.y) - 0.5) * size.height * 0.04
            let radius = max(0.45, CGFloat(particle.size) * scale)
            let particleRect = CGRect(
                x: x - radius,
                y: y - radius,
                width: radius * 2,
                height: radius * 2
            )

            if particle.glow {
                context.fill(
                    Path(ellipseIn: particleRect.insetBy(dx: -radius * 2.2, dy: -radius * 2.2)),
                    with: .radialGradient(
                        Gradient(colors: [
                            palette.particle.opacity(0.16 * Double(fade)),
                            .clear
                        ]),
                        center: CGPoint(x: x, y: y),
                        startRadius: 0,
                        endRadius: radius * 3.4
                    )
                )
            }

            context.fill(
                Path(ellipseIn: particleRect),
                with: .color(
                    palette.particle.opacity(
                        Double(particle.alpha) * Double(fade) * Double(twinkle)
                    )
                )
            )
        }

        context.blendMode = .normal
    }
}

struct LivingArtworkPalette {
    let primary: Color
    let secondary: Color
    let highlight: Color
    let particle: Color

    static func fallback(seed: String) -> LivingArtworkPalette {
        let hue = LivingArtworkSeed.unit(seed, salt: 0xA24B_AED4)
        let primary = Color(hue: hue, saturation: 0.46, brightness: 0.68)
        let secondary = Color(
            hue: (hue + 0.13).truncatingRemainder(dividingBy: 1),
            saturation: 0.38,
            brightness: 0.56
        )
        let highlight = Color(
            hue: (hue + 0.96).truncatingRemainder(dividingBy: 1),
            saturation: 0.20,
            brightness: 0.94
        )
        return LivingArtworkPalette(
            primary: primary,
            secondary: secondary,
            highlight: highlight,
            particle: highlight
        )
    }

    init(image: UIImage, seed: String) {
        let sampled = Self.averageColor(of: image)
        let fallbackHue = LivingArtworkSeed.unit(seed, salt: 0x6D2B_79F5)
        let hue: CGFloat
        let saturation: CGFloat
        let brightness: CGFloat
        var sampledHue: CGFloat = 0
        var sampledSaturation: CGFloat = 0
        var sampledBrightness: CGFloat = 0
        var alpha: CGFloat = 0

        if let sampled,
           sampled.getHue(
               &sampledHue,
               saturation: &sampledSaturation,
               brightness: &sampledBrightness,
               alpha: &alpha
           ),
           sampledSaturation > 0.08 {
            hue = sampledHue
            saturation = sampledSaturation
            brightness = sampledBrightness
        } else {
            hue = CGFloat(fallbackHue)
            saturation = 0.38
            brightness = max(0.42, min(sampledBrightness, 0.72))
        }

        let primary = UIColor(
            hue: hue,
            saturation: min(0.82, max(0.38, saturation * 1.18)),
            brightness: min(0.92, max(0.52, brightness * 1.08)),
            alpha: 1
        )
        let secondary = UIColor(
            hue: (hue + 0.12).truncatingRemainder(dividingBy: 1),
            saturation: min(0.72, max(0.30, saturation * 0.92)),
            brightness: min(0.78, max(0.38, brightness * 0.82)),
            alpha: 1
        )
        let highlight = UIColor(
            hue: (hue + 0.94).truncatingRemainder(dividingBy: 1),
            saturation: 0.16,
            brightness: 0.96,
            alpha: 1
        )

        self.primary = Color(uiColor: primary)
        self.secondary = Color(uiColor: secondary)
        self.highlight = Color(uiColor: highlight)
        self.particle = Color(uiColor: highlight)
    }

    private init(primary: Color, secondary: Color, highlight: Color, particle: Color) {
        self.primary = primary
        self.secondary = secondary
        self.highlight = highlight
        self.particle = particle
    }

    private static let ciContext = CIContext(options: nil)

    private static func averageColor(of image: UIImage) -> UIColor? {
        guard let cgImage = image.cgImage else { return nil }
        let input = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(
            name: "CIAreaAverage",
            parameters: [
                kCIInputImageKey: input,
                kCIInputExtentKey: CIVector(cgRect: input.extent)
            ]
        ),
        let output = filter.outputImage
        else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        ciContext.render(
            output,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        guard bitmap[3] > 0 else { return nil }
        return UIColor(
            red: CGFloat(bitmap[0]) / 255,
            green: CGFloat(bitmap[1]) / 255,
            blue: CGFloat(bitmap[2]) / 255,
            alpha: 1
        )
    }
}

struct LivingArtworkParticle {
    let x: Double
    let y: Double
    let size: Double
    let speed: Double
    let phase: Double
    let wobble: Double
    let drift: Double
    let alpha: Double
    let glow: Bool

    static func field(seed: String) -> [LivingArtworkParticle] {
        var random = LivingArtworkRandom(state: LivingArtworkSeed.hash(seed) | 1)
        return (0..<34).map { index in
            let depth = Double.random(in: 0...1, using: &random)
            return LivingArtworkParticle(
                x: Double.random(in: 0.04...0.96, using: &random),
                y: Double.random(in: 0...1, using: &random),
                size: 0.65 + depth * 1.45,
                speed: 0.006 + depth * 0.014,
                phase: Double.random(in: 0...1, using: &random),
                wobble: 0.10 + depth * 0.22,
                drift: 0.004 + depth * 0.012,
                alpha: 0.16 + depth * 0.30,
                glow: index % 5 == 0
            )
        }
    }
}

struct LivingArtworkRandom: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

enum LivingArtworkSeed {
    static func hash(_ string: String) -> UInt64 {
        var value: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in string.utf8 {
            value ^= UInt64(byte)
            value = value &* 0x0000_0100_0000_01B3
        }
        return value
    }

    static func unit(_ string: String, salt: UInt64) -> Double {
        let value = hash(string) ^ salt
        return Double(value % 10_000) / 10_000
    }
}
