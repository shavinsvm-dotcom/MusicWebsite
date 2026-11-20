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
        highlight: Color(red: 1.0, green: 0.94, blue: 0.84),
        fill: Color(red: 0.56, green: 0.76, blue: 1.0)
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
        let side = 16
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: side, height: side),
            format: format
        )
        let sample = renderer.image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }

        guard let cgImage = sample.cgImage,
              let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data)
        else { return .neutral }

        let bytesPerPixel = max(1, cgImage.bitsPerPixel / 8)
        let bytesPerRow = cgImage.bytesPerRow
        var red = 0.0
        var green = 0.0
        var blue = 0.0
        var count = 0.0

        for y in 0..<side {
            for x in 0..<side {
                let offset = y * bytesPerRow + x * bytesPerPixel
                guard offset + 2 < CFDataGetLength(data) else { continue }
                red += Double(bytes[offset]) / 255
                green += Double(bytes[offset + 1]) / 255
                blue += Double(bytes[offset + 2]) / 255
                count += 1
            }
        }

        guard count > 0 else { return .neutral }
        red /= count
        green /= count
        blue /= count

        // Lift the sampled colour toward white for the key light and push the
        // fill slightly cool. Very dark covers still get a visible sheen.
        let key = UIColor(
            red: min(1, 0.52 + red * 0.48),
            green: min(1, 0.50 + green * 0.46),
            blue: min(1, 0.44 + blue * 0.42),
            alpha: 1
        )
        let fill = UIColor(
            red: min(1, red * 0.55 + 0.06),
            green: min(1, green * 0.68 + 0.14),
            blue: min(1, blue * 0.82 + 0.28),
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
        let driftX = sin(time * 0.21) * 0.012 + sin(time * 0.07) * 0.008
        let driftY = cos(time * 0.17) * 0.010
        let lightX = size.width * (0.5 - sample.x * 0.27 + driftX)
        let lightY = size.height * (0.40 + sample.y * 0.22 + driftY)
        let key = CGPoint(x: lightX, y: lightY)

        context.blendMode = .screen

        // Key light.
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: palette.highlight.opacity(0.62 * intensity), location: 0),
                    .init(color: palette.highlight.opacity(0.24 * intensity), location: 0.28),
                    .init(color: palette.highlight.opacity(0.06 * intensity), location: 0.58),
                    .init(color: .clear, location: 0.82)
                ]),
                center: key,
                startRadius: 0,
                endRadius: diagonal * 0.62
            )
        )

        // Cooler fill from the opposite side keeps the cover from looking flat.
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: palette.fill.opacity(0.26 * intensity), location: 0),
                    .init(color: palette.fill.opacity(0.09 * intensity), location: 0.42),
                    .init(color: .clear, location: 0.80)
                ]),
                center: CGPoint(
                    x: size.width - lightX,
                    y: size.height - lightY
                ),
                startRadius: 0,
                endRadius: diagonal * 0.52
            )
        )

        // Specular sweep across the print.
        let angle = -0.62 + sample.roll * 0.34 + sample.x * 0.12
        let bandLength = diagonal * 1.55
        let bandHeight = diagonal * 0.12
        let bandCenter = CGPoint(
            x: size.width * (0.5 - sample.x * 0.34),
            y: size.height * (0.40 + sample.y * 0.26)
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
                        .init(color: palette.highlight.opacity(0.02 * intensity), location: 0.28),
                        .init(color: .white.opacity(0.19 * intensity), location: 0.50),
                        .init(color: palette.highlight.opacity(0.03 * intensity), location: 0.72),
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
                    .init(color: .white.opacity(0.42 * intensity), location: 0.43),
                    .init(color: .white.opacity(0.16 * intensity), location: 0.6),
                    .init(color: .clear, location: 1)
                ]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: size.width, y: size.height)
            ),
            lineWidth: 1.1
        )

        context.blendMode = .normal
    }
}
