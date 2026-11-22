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
    private var velocity = MotionLightSample()
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
            ? 1.0 / 12.0
            : 1.0 / 20.0
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue) { [weak self] data, _ in
            guard let self, let data else { return }

            // Horizontal tilt is gravity.x; forward/back tilt is gravity.z.
            // Using gravity.y would treat a normally held portrait phone as
            // permanently tilted because gravity points down the screen.
            let rawX = Self.clamp(-data.gravity.x / 0.55)
            let rawY = Self.clamp(data.gravity.z / 0.55)
            let rawRoll = Self.clamp(data.attitude.roll / 1.1)
            let dt = min(0.05, self.motion.deviceMotionUpdateInterval)

            self.lock.lock()
            let x = Self.spring(
                value: self.smoothed.x,
                velocity: self.velocity.x,
                target: rawX,
                stiffness: 82,
                damping: 17,
                dt: dt
            )
            let y = Self.spring(
                value: self.smoothed.y,
                velocity: self.velocity.y,
                target: rawY,
                stiffness: 82,
                damping: 17,
                dt: dt
            )
            let roll = Self.spring(
                value: self.smoothed.roll,
                velocity: self.velocity.roll,
                target: rawRoll,
                stiffness: 54,
                damping: 12,
                dt: dt
            )
            self.smoothed.x = min(1.08, max(-1.08, x.value))
            self.velocity.x = x.velocity
            self.smoothed.y = min(1.08, max(-1.08, y.value))
            self.velocity.y = y.velocity
            self.smoothed.roll = min(1.08, max(-1.08, roll.value))
            self.velocity.roll = roll.velocity
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
        velocity = .level
        lock.unlock()
    }

    var sample: MotionLightSample {
        lock.lock()
        let value = smoothed
        lock.unlock()
        return value
    }

    private static func spring(
        value: Double,
        velocity: Double,
        target: Double,
        stiffness: Double,
        damping: Double,
        dt: Double
    ) -> (value: Double, velocity: Double) {
        let acceleration = (target - value) * stiffness - velocity * damping
        let nextVelocity = velocity + acceleration * dt
        return (value + nextVelocity * dt, nextVelocity)
    }

    private static func clamp(_ value: Double) -> Double {
        min(1, max(-1, value))
    }
}

/// Four pre-blurred edge textures for one piece of artwork.
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
    private static let ciContext = CIContext(options: [.cacheIntermediates: false])
    // The edges are heavily frosted, so a 440 pt square stretches to the
    // artwork without visible loss while halving the masked-blur pixel work
    // that used to hitch right after the player opened.
    private static let renderSide: CGFloat = 440

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
            kCIInputRadiusKey: 40
        ]), let output = filter.outputImage {
            blurred = output.cropped(to: extent)
        } else {
            // Fallback for platforms where the variable-blur filter is absent.
            blurred = input
                .clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 22])
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
    var isPlaying: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var edges: HeroEdgeBlur?
    @State private var isVisible = false

    private let controller = MotionLightController.shared

    private var motionAllowed: Bool {
        !reduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    var body: some View {
        Group {
            if motionAllowed {
                TimelineView(.animation(
                    minimumInterval: 1.0 / 20.0,
                    paused: !isVisible || !isPlaying || scenePhase != .active
                )) { _ in
                    canvas(sample: controller.sample)
                }
            } else {
                canvas(sample: .level)
            }
        }
        .allowsHitTesting(false)
        .task(id: url) {
            edges = await HeroEdgeBlurCache.shared.prepare(for: url)
        }
        .onAppear {
            isVisible = true
            if motionAllowed {
                controller.begin()
            }
        }
        .onDisappear {
            isVisible = false
            if motionAllowed {
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
