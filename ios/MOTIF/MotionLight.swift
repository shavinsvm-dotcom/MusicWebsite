import CoreImage
import CoreMotion
import SwiftUI
import UIKit

/// A smoothed snapshot of how the phone is tilted. Values are normalised to
/// roughly -1...1, with zero meaning the phone is level.
struct MotionLightSample {
    var x: Double = 0
    var y: Double = 0
    var roll: Double = 0

    static let level = MotionLightSample()
}

/// One shared Core Motion source for every large cover. Updates are filtered on
/// a background queue and read as a plain snapshot, so the player view never
/// invalidates its whole hierarchy at 30 Hz.
final class MotionLightController {
    static let shared = MotionLightController()

    private let motion = CMMotionManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "motif.motion-light"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        return queue
    }()
    private let lock = NSLock()

    private var smoothed = MotionLightSample()
    private var activeOverlays = 0

    private init() {}

    var isAvailable: Bool { motion.isDeviceMotionAvailable }

    func begin() {
        lock.lock()
        activeOverlays += 1
        let shouldStart = activeOverlays == 1
        lock.unlock()

        guard shouldStart, motion.isDeviceMotionAvailable else { return }

        motion.deviceMotionUpdateInterval = ProcessInfo.processInfo.isLowPowerModeEnabled
            ? 1.0 / 15.0
            : 1.0 / 30.0
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue) { [weak self] data, _ in
            guard let self, let data else { return }

            let rawX = Self.clamp(-data.gravity.x / 0.55)
            let rawY = Self.clamp(data.gravity.y / 0.55)
            let rawRoll = Self.clamp(data.attitude.roll / 1.1)

            self.lock.lock()
            self.smoothed.x += (rawX - self.smoothed.x) * 0.14
            self.smoothed.y += (rawY - self.smoothed.y) * 0.14
            self.smoothed.roll += (rawRoll - self.smoothed.roll) * 0.10
            self.lock.unlock()
        }
    }

    func end() {
        lock.lock()
        activeOverlays = max(0, activeOverlays - 1)
        let shouldStop = activeOverlays == 0
        lock.unlock()

        guard shouldStop else { return }
        motion.stopDeviceMotionUpdates()

        lock.lock()
        smoothed = .level
        lock.unlock()
    }

    var sample: MotionLightSample {
        lock.lock()
        let value = smoothed
        lock.unlock()
        return value
    }

    private static func clamp(_ value: Double) -> Double {
        min(1, max(-1, value))
    }
}

/// Two artwork-derived colours: a warm key light and a cooler fill.
struct CoverLightPalette {
    let highlight: Color
    let fill: Color

    static let neutral = CoverLightPalette(
        highlight: Color(red: 1.0, green: 0.95, blue: 0.86),
        fill: Color(red: 0.54, green: 0.74, blue: 1.0)
    )
}

final class CoverLightPaletteCache {
    static let shared = CoverLightPaletteCache()

    private final class Box {
        let palette: CoverLightPalette
        init(_ palette: CoverLightPalette) { self.palette = palette }
    }

    private let cache = NSCache<NSURL, Box>()

    private init() {
        cache.countLimit = 80
    }

    func palette(for url: URL?) -> CoverLightPalette {
        guard let url else { return .neutral }
        if let cached = cache.object(forKey: url as NSURL) {
            return cached.palette
        }
        guard let image = ArtworkImageCache.shared.image(for: url) else {
            return .neutral
        }
        let palette = Self.makePalette(from: image)
        cache.setObject(Box(palette), forKey: url as NSURL)
        return palette
    }

    private static func makePalette(from image: UIImage) -> CoverLightPalette {
        guard let cgImage = image.cgImage else { return .neutral }

        let side = 16
        let bytesPerRow = side * 4
        let data = UnsafeMutablePointer<UInt8>.allocate(capacity: side * bytesPerRow)
        defer { data.deallocate() }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = CGContext(
            data: data,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return .neutral }

        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        var red = 0.0
        var green = 0.0
        var blue = 0.0
        var count = 0.0

        for offset in stride(from: 0, to: side * bytesPerRow, by: 4) {
            // Explicit RGBA byte order: R, G, B, A.
            red += Double(data[offset]) / 255
            green += Double(data[offset + 1]) / 255
            blue += Double(data[offset + 2]) / 255
            count += 1
        }

        guard count > 0 else { return .neutral }
        red /= count
        green /= count
        blue /= count

        // The key is a film-light white tinted by the cover. The fill is a
        // restrained cool bounce so the sheen stays clean instead of muddy.
        let key = UIColor(
            red: min(1, 0.72 + red * 0.28),
            green: min(1, 0.70 + green * 0.28),
            blue: min(1, 0.64 + blue * 0.26),
            alpha: 1
        )
        let fill = UIColor(
            red: min(1, 0.12 + red * 0.38),
            green: min(1, 0.22 + green * 0.42),
            blue: min(1, 0.40 + blue * 0.44),
            alpha: 1
        )

        return CoverLightPalette(highlight: Color(uiColor: key), fill: Color(uiColor: fill))
    }
}

/// A single GPU-backed layer that paints a moving key light, fill light,
/// specular sweep, and rim light over the artwork. It has no layout cost and
/// only redraws while a large cover is on screen.
struct LivingLightOverlay: View {
    let url: URL?
    var intensity: Double = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var palette = CoverLightPalette.neutral
    @State private var isVisible = false

    private let controller = MotionLightController.shared

    var body: some View {
        Group {
            if reduceMotion {
                canvas(sample: .level, time: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isVisible)) { timeline in
                    canvas(
                        sample: controller.sample,
                        time: timeline.date.timeIntervalSinceReferenceDate
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .blendMode(.screen)
        .onAppear {
            isVisible = true
            palette = CoverLightPaletteCache.shared.palette(for: url)
            if !reduceMotion {
                controller.begin()
            }
        }
        .onDisappear {
            isVisible = false
            if !reduceMotion {
                controller.end()
            }
        }
    }

    private func canvas(sample: MotionLightSample, time: TimeInterval) -> some View {
        Canvas(rendersAsynchronously: true) { context, size in
            draw(context: &context, size: size, sample: sample, time: time)
        }
    }

    private func draw(
        context: inout GraphicsContext,
        size: CGSize,
        sample: MotionLightSample,
        time: TimeInterval
    ) {
        guard size.width > 1, size.height > 1 else { return }

        let diagonal = hypot(size.width, size.height)
        let driftX = sin(time * 0.21) * 0.010 + sin(time * 0.07) * 0.007
        let driftY = cos(time * 0.17) * 0.008
        let lightX = size.width * (0.5 - sample.x * 0.24 + driftX)
        let lightY = size.height * (0.41 + sample.y * 0.20 + driftY)
        let key = CGPoint(x: lightX, y: lightY)

        context.blendMode = .screen

        // Broad key wash.
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: palette.highlight.opacity(0.38 * intensity), location: 0),
                    .init(color: palette.highlight.opacity(0.13 * intensity), location: 0.34),
                    .init(color: palette.highlight.opacity(0.025 * intensity), location: 0.66),
                    .init(color: .clear, location: 0.88)
                ]),
                center: key,
                startRadius: 0,
                endRadius: diagonal * 0.64
            )
        )

        // Tight highlight for the surface glint.
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: .white.opacity(0.11 * intensity), location: 0),
                    .init(color: palette.highlight.opacity(0.045 * intensity), location: 0.45),
                    .init(color: .clear, location: 1)
                ]),
                center: key,
                startRadius: 0,
                endRadius: diagonal * 0.25
            )
        )

        // Restrained cool bounce from the opposite side.
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: palette.fill.opacity(0.12 * intensity), location: 0),
                    .init(color: palette.fill.opacity(0.035 * intensity), location: 0.50),
                    .init(color: .clear, location: 0.84)
                ]),
                center: CGPoint(
                    x: size.width - lightX,
                    y: size.height - lightY
                ),
                startRadius: 0,
                endRadius: diagonal * 0.48
            )
        )

        // Narrow specular sweep across the print.
        let angle = -0.62 + sample.roll * 0.32 + sample.x * 0.10
        let bandLength = diagonal * 1.45
        let bandHeight = diagonal * 0.075
        let bandCenter = CGPoint(
            x: size.width * (0.5 - sample.x * 0.30),
            y: size.height * (0.41 + sample.y * 0.23)
        )
        context.drawLayer { layer in
            layer.translateBy(x: bandCenter.x, y: bandCenter.y)
            layer.rotate(by: .radians(angle))
            let band = Path(CGRect(
                x: -bandLength / 2,
                y: -bandHeight / 2,
                width: bandLength,
                height: bandHeight
            ))
            layer.clip(to: band)
            layer.fill(
                band,
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: palette.highlight.opacity(0.015 * intensity), location: 0.30),
                        .init(color: .white.opacity(0.135 * intensity), location: 0.50),
                        .init(color: palette.highlight.opacity(0.02 * intensity), location: 0.70),
                        .init(color: .clear, location: 1)
                    ]),
                    startPoint: CGPoint(x: 0, y: -bandHeight / 2),
                    endPoint: CGPoint(x: 0, y: bandHeight / 2)
                )
            )
        }

        // A thin rim on the edge nearest the light.
        let rimRect = CGRect(origin: .zero, size: size).insetBy(dx: 0.75, dy: 0.75)
        context.stroke(
            Path(rimRect),
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white.opacity(0.26 * intensity), location: 0.43),
                    .init(color: .white.opacity(0.10 * intensity), location: 0.62),
                    .init(color: .clear, location: 1)
                ]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: size.width, y: size.height)
            ),
            lineWidth: 1
        )

        context.blendMode = .normal
    }
}

struct HeroEdgeBlur {
    let left: UIImage
    let right: UIImage
    let top: UIImage
    let bottom: UIImage
}

private enum BlurEdge {
    case left, right, top, bottom
}

/// Renders the blurred side edges once per artwork, so the live layer only has
/// to draw two cached textures. The blur is sharp at the hinge and increases
/// cubically toward the moving edge, the same trick Apple uses in the iPhone
/// Duo unfold: content stays readable near the crease and the outer panel
/// frosts over as it swings away.
final class HeroEdgeBlurCache {
    static let shared = HeroEdgeBlurCache()

    private final class Box {
        let edges: HeroEdgeBlur
        init(_ edges: HeroEdgeBlur) { self.edges = edges }
    }

    private let cache = NSCache<NSURL, Box>()
    private let lock = NSLock()
    private var tasks: [NSURL: Task<HeroEdgeBlur?, Never>] = [:]
    private static let ciContext = CIContext(options: nil)
    private static let renderSide: CGFloat = 620

    private init() {
        cache.countLimit = 12
        cache.totalCostLimit = 96 * 1024 * 1024
    }

    func cached(for url: URL?) -> HeroEdgeBlur? {
        guard let url else { return nil }
        return cache.object(forKey: url as NSURL)?.edges
    }

    func prepare(for url: URL?) async -> HeroEdgeBlur? {
        guard let url else { return nil }
        if let cached = cached(for: url) { return cached }

        let key = url as NSURL
        lock.lock()
        if let existing = tasks[key] {
            lock.unlock()
            return await existing.value
        }

        let task = Task.detached(priority: .utility) { () -> HeroEdgeBlur? in
            let source: UIImage?
            if let cached = ArtworkImageCache.shared.image(for: url) {
                source = cached
            } else {
                source = await ArtworkImageCache.shared.loadImage(for: url)
            }
            guard let source else { return nil }
            return Self.render(source)
        }
        tasks[key] = task
        lock.unlock()

        let edges = await task.value

        lock.lock()
        tasks[key] = nil
        lock.unlock()

        if let edges {
            let cost = Int(edges.left.size.width * edges.left.size.height * 4) * 4
            cache.setObject(Box(edges), forKey: key, cost: cost)
        }
        return edges
    }

    private static func render(_ image: UIImage) -> HeroEdgeBlur? {
        let side = renderSide
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: side, height: side),
            format: format
        )

        let square = renderer.image { _ in
            let factor = max(side / max(1, image.size.width), side / max(1, image.size.height))
            let drawSize = CGSize(
                width: image.size.width * factor,
                height: image.size.height * factor
            )
            image.draw(in: CGRect(
                x: (side - drawSize.width) / 2,
                y: (side - drawSize.height) / 2,
                width: drawSize.width,
                height: drawSize.height
            ))
        }

        guard let cgImage = square.cgImage else { return nil }
        let input = CIImage(cgImage: cgImage)

        guard let left = progressiveEdge(input, edge: .left),
              let right = progressiveEdge(input, edge: .right),
              let top = progressiveEdge(input, edge: .top),
              let bottom = progressiveEdge(input, edge: .bottom)
        else { return nil }
        return HeroEdgeBlur(left: left, right: right, top: top, bottom: bottom)
    }

    /// One half of the cover behaves like a frosted panel on a hinge: no blur
    /// at the centre, then a steep cubic ramp toward the free edge.
    private static func progressiveEdge(_ input: CIImage, edge: BlurEdge) -> UIImage? {
        let extent = input.extent
        let center = CGPoint(x: extent.midX, y: extent.midY)
        let point: CGPoint
        switch edge {
        case .left: point = CGPoint(x: extent.minX, y: extent.midY)
        case .right: point = CGPoint(x: extent.maxX, y: extent.midY)
        case .top: point = CGPoint(x: extent.midX, y: extent.maxY)
        case .bottom: point = CGPoint(x: extent.midX, y: extent.minY)
        }

        guard let gradient = CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: center.x, y: center.y),
            "inputPoint1": CIVector(x: point.x, y: point.y),
            "inputColor0": CIColor.black,
            "inputColor1": CIColor.white
        ])?.outputImage?.cropped(to: extent) else { return nil }

        // Gamma darkens the middle of the mask, keeping the hinge-side detail
        // crisp while the outermost slice takes the full blur.
        let mask = gradient.applyingFilter("CIGammaAdjust", parameters: [
            "inputPower": 1.9
        ])

        let blurred: CIImage
        if let filter = CIFilter(name: "CIMaskedVariableBlur", parameters: [
            "inputImage": input.clampedToExtent(),
            "inputMask": mask,
            kCIInputRadiusKey: 56
        ]), let output = filter.outputImage {
            blurred = output.cropped(to: extent)
        } else {
            // Fallback for platforms where the variable-blur filter is absent.
            blurred = input
                .clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 30])
                .cropped(to: extent)
        }

        guard let output = Self.ciContext.createCGImage(blurred, from: extent) else {
            return nil
        }
        return edgeMasked(UIImage(cgImage: output), edge: edge)
    }

    private static func edgeMasked(_ image: UIImage, edge: BlurEdge) -> UIImage? {
        let size = image.size
        guard size.width > 1, size.height > 1 else { return nil }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        return renderer.image { rendererContext in
            image.draw(in: CGRect(origin: .zero, size: size))
            let context = rendererContext.cgContext
            let white = UIColor.white

            // Keep the blur at the free edge only; the sharp half underneath
            // remains visible through the transparent centre.
            context.setBlendMode(.destinationIn)
            let alphaColors = [
                white.withAlphaComponent(1).cgColor,
                white.withAlphaComponent(0.84).cgColor,
                white.withAlphaComponent(0.18).cgColor,
                white.withAlphaComponent(0).cgColor
            ] as CFArray
            guard let alphaGradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: alphaColors,
                locations: [0, 0.30, 0.57, 0.74]
            ) else { return }

            let start: CGPoint
            let end: CGPoint
            switch edge {
            case .left:
                start = CGPoint(x: 0, y: 0)
                end = CGPoint(x: size.width, y: 0)
            case .right:
                start = CGPoint(x: size.width, y: 0)
                end = CGPoint(x: 0, y: 0)
            case .top:
                start = CGPoint(x: 0, y: 0)
                end = CGPoint(x: 0, y: size.height)
            case .bottom:
                start = CGPoint(x: 0, y: size.height)
                end = CGPoint(x: 0, y: 0)
            }

            context.drawLinearGradient(
                alphaGradient,
                start: start,
                end: end,
                options: []
            )

            // The panel also falls into shadow as it turns away, which is what
            // sells the fold more than blur alone.
            context.setBlendMode(.sourceAtop)
            let shadeColors = [
                UIColor.black.withAlphaComponent(0.32).cgColor,
                UIColor.black.withAlphaComponent(0.13).cgColor,
                UIColor.black.withAlphaComponent(0).cgColor
            ] as CFArray
            guard let shade = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: shadeColors,
                locations: [0, 0.33, 0.70]
            ) else { return }

            context.drawLinearGradient(
                shade,
                start: start,
                end: end,
                options: []
            )
        }
    }

}

struct HeroEdgeBlurOverlay: View {
    let url: URL?
    var intensity: Double = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var edges: HeroEdgeBlur?
    @State private var isVisible = false

    private let controller = MotionLightController.shared

    var body: some View {
        Group {
            if reduceMotion {
                canvas(sample: .level)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !isVisible)) { _ in
                    canvas(sample: controller.sample)
                }
            }
        }
        .allowsHitTesting(false)
        .task(id: url) {
            edges = await HeroEdgeBlurCache.shared.prepare(for: url)
        }
        .onAppear {
            isVisible = true
            if !reduceMotion {
                controller.begin()
            }
        }
        .onDisappear {
            isVisible = false
            if !reduceMotion {
                controller.end()
            }
        }
    }

    private func canvas(sample: MotionLightSample) -> some View {
        Canvas(rendersAsynchronously: true) { context, size in
            guard let edges, size.width > 1, size.height > 1 else { return }

            let horizontal = smoothstep(0.015, 0.55, abs(sample.x)) * 0.95 * intensity
            let vertical = smoothstep(0.015, 0.55, abs(sample.y)) * 0.95 * intensity

            if horizontal > 0.01 {
                drawEdge(
                    sample.x > 0 ? edges.right : edges.left,
                    edge: sample.x > 0 ? .right : .left,
                    strength: horizontal,
                    size: size,
                    context: &context
                )
            }

            if vertical > 0.01 {
                drawEdge(
                    sample.y > 0 ? edges.top : edges.bottom,
                    edge: sample.y > 0 ? .top : .bottom,
                    strength: vertical,
                    size: size,
                    context: &context
                )
            }
        }
    }

    private func drawEdge(
        _ image: UIImage,
        edge: BlurEdge,
        strength: Double,
        size: CGSize,
        context: inout GraphicsContext
    ) {
        let rect = CGRect(origin: .zero, size: size)
        let horizontal = edge == .left || edge == .right
        let normalized = min(1, strength / 0.95)
        let inset = (horizontal ? size.width : size.height)
            * CGFloat(0.026 * normalized) / 2
        let stretched: CGRect

        if horizontal {
            stretched = rect
                .insetBy(dx: -inset, dy: 0)
                .offsetBy(dx: edge == .right ? inset : -inset, dy: 0)
        } else {
            stretched = rect
                .insetBy(dx: 0, dy: -inset)
                .offsetBy(dx: 0, dy: edge == .top ? -inset : inset)
        }

        context.drawLayer { layer in
            layer.clip(to: Path(rect))
            layer.opacity = strength
            layer.draw(Image(uiImage: image), in: stretched)
        }
    }

    private func smoothstep(_ edge0: Double, _ edge1: Double, _ value: Double) -> Double {
        let t = min(1, max(0, (value - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }
}
