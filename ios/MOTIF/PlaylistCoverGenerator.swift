import UIKit

/// Draws one-of-a-kind playlist artwork entirely on device. Each cover picks
/// both a pattern family and a curated palette from the playlist name and the
/// generation count, so repeated taps never return the same rainbow twice.
enum PlaylistCoverGenerator {
    private enum Pattern: Int, CaseIterable {
        case sweep
        case tide
        case dunes
        case orbit
        case prism

        var title: String {
            switch self {
            case .sweep: return "Sweep"
            case .tide: return "Tide"
            case .dunes: return "Dunes"
            case .orbit: return "Orbit"
            case .prism: return "Prism"
            }
        }
    }

    private struct Palette {
        let hues: [Double]
        let saturation: CGFloat
        let brightness: CGFloat
        let highlight: CGFloat
        let background: UIColor
    }

    private static let palettes: [Palette] = [
        Palette(
            hues: [0.72, 0.80, 0.88, 0.96],
            saturation: 0.95, brightness: 1.0, highlight: 0.10,
            background: UIColor(red: 0.040, green: 0.020, blue: 0.080, alpha: 1)
        ),
        Palette(
            hues: [0.97, 1.03, 0.07, 0.12],
            saturation: 0.92, brightness: 1.0, highlight: 0.10,
            background: UIColor(red: 0.080, green: 0.030, blue: 0.020, alpha: 1)
        ),
        Palette(
            hues: [0.43, 0.48, 0.53, 0.58],
            saturation: 0.85, brightness: 0.98, highlight: 0.12,
            background: UIColor(red: 0.010, green: 0.050, blue: 0.080, alpha: 1)
        ),
        Palette(
            hues: [0.12, 0.17, 0.22, 0.28],
            saturation: 0.90, brightness: 1.0, highlight: 0.08,
            background: UIColor(red: 0.040, green: 0.060, blue: 0.010, alpha: 1)
        ),
        Palette(
            hues: [0.78, 0.85, 0.92, 0.99],
            saturation: 0.80, brightness: 1.0, highlight: 0.16,
            background: UIColor(red: 0.070, green: 0.020, blue: 0.060, alpha: 1)
        ),
        Palette(
            hues: [0.54, 0.60, 0.66, 0.71],
            saturation: 0.92, brightness: 0.94, highlight: 0.10,
            background: UIColor(red: 0.010, green: 0.030, blue: 0.090, alpha: 1)
        ),
        Palette(
            hues: [0.90, 0.97, 0.05, 0.12],
            saturation: 0.55, brightness: 1.0, highlight: 0.36,
            background: UIColor(red: 0.090, green: 0.060, blue: 0.050, alpha: 1)
        ),
        Palette(
            hues: [0.44, 0.50, 0.56, 0.62],
            saturation: 0.42, brightness: 1.0, highlight: 0.42,
            background: UIColor(red: 0.050, green: 0.070, blue: 0.090, alpha: 1)
        ),
        Palette(
            hues: [0.00, 0.14, 0.33, 0.52, 0.70, 0.85],
            saturation: 0.95, brightness: 1.0, highlight: 0.10,
            background: UIColor(red: 0.020, green: 0.020, blue: 0.030, alpha: 1)
        ),
        Palette(
            hues: [0.02, 0.05, 0.98, 0.94],
            saturation: 0.88, brightness: 1.0, highlight: 0.14,
            background: UIColor(red: 0.080, green: 0.020, blue: 0.040, alpha: 1)
        )
    ]

    private static let paletteNames: [String] = [
        "Ultraviolet", "Sunset", "Lagoon", "Citrus", "Orchid",
        "Cobalt", "Sorbet", "Glacier", "Spectrum", "Ember"
    ]

    struct Preview: Sendable {
        let variant: Int
        let pattern: String
        let palette: String
        let data: Data
    }

    private struct Selection {
        let pattern: Pattern
        let paletteIndex: Int
        let seed: UInt64
    }

    static func jpegData(name: String, variant: Int) -> Data? {
        image(name: name, variant: variant)
            .jpegData(compressionQuality: 0.9)
    }

    /// A small, cheap render used by the cover picker. Returns JPEG data so
    /// the picker can generate its grid away from the main actor.
    static func preview(name: String, variant: Int, side: CGFloat = 460) -> Preview? {
        guard let data = image(name: name, variant: variant, pixelSize: side)
            .jpegData(compressionQuality: 0.88)
        else { return nil }

        let selection = selection(name: name, variant: variant)
        return Preview(
            variant: variant,
            pattern: selection.pattern.title,
            palette: paletteNames[selection.paletteIndex],
            data: data
        )
    }

    static func image(name: String, variant: Int, pixelSize: CGFloat = 1024) -> UIImage {
        let size = CGSize(width: pixelSize, height: pixelSize)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        let selection = selection(name: name, variant: variant)

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            draw(
                in: context.cgContext,
                size: pixelSize,
                seed: selection.seed,
                pattern: selection.pattern,
                palette: palettes[selection.paletteIndex]
            )
        }
    }

    private static func selection(name: String, variant: Int) -> Selection {
        let step = abs(variant)
        let nameSeed = stableSeed(for: name)
        let pattern = Pattern.allCases[step % Pattern.allCases.count]
        let paletteIndex = (step * 3 + Int(nameSeed % UInt64(palettes.count))) % palettes.count
        let seed = mix(nameSeed ^ (UInt64(bitPattern: Int64(step)) &* 0x9E37_79B9_7F4A_7C15))
        return Selection(pattern: pattern, paletteIndex: paletteIndex, seed: seed)
    }

    // MARK: - Canvas

    private static func draw(
        in context: CGContext,
        size: CGFloat,
        seed: UInt64,
        pattern: Pattern,
        palette: Palette
    ) {
        context.setFillColor(palette.background.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))

        drawBloom(in: context, size: size, hue: paletteHue(palette, t: 0.78), alpha: 0.55)

        switch pattern {
        case .sweep:
            drawRibbons(
                in: context, size: size,
                count: 24, spacing: 0.083, thickness: 0.180,
                bow: -0.10 + CGFloat(seed % 3) * 0.075,
                wave: 0, cycles: 2, phase: 0,
                palette: palette, hueStart: 0, hueEnd: 1
            )

        case .tide:
            context.saveGState()
            context.translateBy(x: size / 2, y: size / 2)
            context.rotate(by: .pi / 2)
            context.scaleBy(x: -1, y: 1)
            context.translateBy(x: -size / 2, y: -size / 2)
            drawRibbons(
                in: context, size: size,
                count: 22, spacing: 0.092, thickness: 0.210,
                bow: 0.04,
                wave: 0, cycles: 2, phase: 0,
                palette: palette, hueStart: 0.12, hueEnd: 1
            )
            context.restoreGState()

        case .dunes:
            drawRibbons(
                in: context, size: size,
                count: 22, spacing: 0.098, thickness: 0.320,
                bow: -0.18,
                wave: 0.06, cycles: 2.1,
                phase: CGFloat(seed % 7) / 7 * .pi * 2,
                palette: palette, hueStart: 0, hueEnd: 1
            )

        case .orbit:
            drawRings(in: context, size: size, seed: seed, palette: palette)

        case .prism:
            drawPrism(in: context, size: size, seed: seed, palette: palette)
        }

        drawVignette(in: context, size: size)
    }

    private static func drawBloom(
        in context: CGContext,
        size: CGFloat,
        hue: Double,
        alpha: CGFloat
    ) {
        let colors = [
            UIColor(hue: CGFloat(hue), saturation: 0.82, brightness: 0.55, alpha: alpha).cgColor,
            UIColor(hue: CGFloat(hue), saturation: 0.90, brightness: 0.34, alpha: alpha * 0.34).cgColor,
            UIColor.clear.cgColor
        ] as CFArray

        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors,
            locations: [0, 0.55, 1]
        ) else { return }

        let center = CGPoint(x: size * 0.18, y: size * 0.96)
        context.drawRadialGradient(
            gradient,
            startCenter: center,
            startRadius: 0,
            endCenter: center,
            endRadius: size * 0.92,
            options: [.drawsAfterEndLocation]
        )
    }

    // MARK: - Ribbons

    private static func drawRibbons(
        in context: CGContext,
        size: CGFloat,
        count: Int,
        spacing: CGFloat,
        thickness: CGFloat,
        bow: CGFloat,
        wave: CGFloat,
        cycles: CGFloat,
        phase: CGFloat,
        palette: Palette,
        hueStart: Double,
        hueEnd: Double
    ) {
        for index in 0..<count {
            let offset = -size * 0.95 + CGFloat(index) * spacing * size
            let p0 = CGPoint(x: -size * 0.30, y: offset + size * 0.02)
            let c1 = CGPoint(x: size * 0.28, y: offset - size * 0.06 + bow * size)
            let c2 = CGPoint(x: size * 0.62, y: offset + size * 0.52 - bow * size)
            let p1 = CGPoint(x: size * 1.30, y: offset + size * 0.70)

            let progress = count > 1 ? Double(index) / Double(count - 1) : 0
            let hue = paletteHue(
                palette,
                t: hueStart + (hueEnd - hueStart) * progress
            )

            drawBand(
                in: context,
                p0: p0, c1: c1, c2: c2, p1: p1,
                thickness: thickness * size,
                wave: wave * size,
                cycles: cycles,
                phase: phase,
                hue: hue,
                palette: palette
            )
        }
    }

    private static func drawBand(
        in context: CGContext,
        p0: CGPoint,
        c1: CGPoint,
        c2: CGPoint,
        p1: CGPoint,
        thickness: CGFloat,
        wave: CGFloat,
        cycles: CGFloat,
        phase: CGFloat,
        hue: Double,
        palette: Palette
    ) {
        let steps = 48
        var top: [CGPoint] = []
        var bottom: [CGPoint] = []
        top.reserveCapacity(steps + 1)
        bottom.reserveCapacity(steps + 1)

        var minY = CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude

        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let point = cubicPoint(p0, c1, c2, p1, t)
            let ripple = wave == 0 ? 0 : sin(t * .pi * 2 * cycles + phase) * wave

            let topPoint = CGPoint(x: point.x, y: point.y + ripple)
            top.append(topPoint)
            bottom.append(CGPoint(x: point.x, y: topPoint.y + thickness))
            minY = min(minY, topPoint.y)
            maxY = max(maxY, topPoint.y + thickness)
        }

        let path = CGMutablePath()
        path.addLines(between: top + bottom.reversed())
        path.closeSubpath()

        guard let gradient = bandGradient(hue: hue, palette: palette) else { return }

        context.saveGState()
        context.addPath(path)
        context.clip()
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: minY),
            end: CGPoint(x: 0, y: maxY),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
        context.restoreGState()
    }

    // MARK: - Prism bars

    private static func drawPrism(
        in context: CGContext,
        size: CGFloat,
        seed: UInt64,
        palette: Palette
    ) {
        var random = SeededRandom(seed: seed)
        let phase = CGFloat(seed % 9) / 9 * .pi * 2
        var x = -size * 0.12

        while x < size * 1.12 {
            let width = size * (0.025 + random.nextUnit() * 0.10)
            let hue = paletteHue(palette, t: Double((x + width / 2) / size))

            let steps = 24
            var left: [CGPoint] = []
            var right: [CGPoint] = []
            left.reserveCapacity(steps + 1)
            right.reserveCapacity(steps + 1)

            for step in 0...steps {
                let t = CGFloat(step) / CGFloat(steps)
                let sway = sin(t * .pi * 2 + phase) * size * 0.022
                left.append(CGPoint(x: x + sway, y: size * t))
                right.append(CGPoint(x: x + width + sway, y: size * t))
            }

            let path = CGMutablePath()
            path.addLines(between: left + right.reversed())
            path.closeSubpath()

            if let gradient = bandGradient(hue: hue, palette: palette) {
                context.saveGState()
                context.addPath(path)
                context.clip()
                context.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: x, y: 0),
                    end: CGPoint(x: x + width, y: 0),
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
                )
                context.restoreGState()
            }

            x += width * 0.82
        }
    }

    // MARK: - Orbit rings

    private static func drawRings(
        in context: CGContext,
        size: CGFloat,
        seed: UInt64,
        palette: Palette
    ) {
        let center = CGPoint(
            x: size * (0.42 + CGFloat(seed % 5) * 0.040),
            y: size * (0.44 + CGFloat((seed / 5) % 3) * 0.035)
        )
        let rings = 15
        let maxRadius = size * 1.08
        let minRadius = size * 0.045
        let step = (maxRadius - minRadius) / CGFloat(rings)

        for index in stride(from: rings - 1, through: 0, by: -1) {
            let progress = CGFloat(index) / CGFloat(rings - 1)
            let radius = minRadius + (maxRadius - minRadius) * progress
            let width = step * 1.45
            let inner = max(0, radius - width / 2)
            let outer = radius + width / 2

            let circle = CGPath(
                ellipseIn: CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                ),
                transform: nil
            )
            let stroked = circle.copy(
                strokingWithWidth: width,
                lineCap: .butt,
                lineJoin: .miter,
                miterLimit: 10
            )

            guard let gradient = bandGradient(
                hue: paletteHue(palette, t: Double(1 - progress)),
                palette: palette
            ) else { continue }

            context.saveGState()
            context.addPath(stroked)
            context.clip()
            context.drawRadialGradient(
                gradient,
                startCenter: center,
                startRadius: inner,
                endCenter: center,
                endRadius: outer,
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
            context.restoreGState()
        }
    }

    // MARK: - Palette and shading

    private static func bandGradient(hue: Double, palette: Palette) -> CGGradient? {
        let stops: [(CGFloat, UIColor)] = [
            (0.00, bandColor(hue, saturation: 0.55, brightness: 0.55, palette: palette)),
            (0.10, bandColor(hue, saturation: 0.95, brightness: 0.94, palette: palette)),
            (0.30, bandColor(hue, saturation: 0.72, brightness: 1.00, whiten: palette.highlight, palette: palette)),
            (0.46, bandColor(hue, saturation: 0.96, brightness: 1.00, palette: palette)),
            (0.74, bandColor(hue, saturation: 0.90, brightness: 0.92, palette: palette)),
            (1.00, bandColor(hue, saturation: 0.62, brightness: 0.55, palette: palette))
        ]

        return CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: stops.map { $0.1.cgColor } as CFArray,
            locations: stops.map { $0.0 }
        )
    }

    private static func bandColor(
        _ hue: Double,
        saturation: CGFloat,
        brightness: CGFloat,
        whiten: CGFloat = 0,
        palette: Palette
    ) -> UIColor {
        let base = UIColor(
            hue: CGFloat(normalizedHue(hue)),
            saturation: min(1, max(0, saturation * palette.saturation)),
            brightness: min(1, max(0, brightness * palette.brightness)),
            alpha: 1
        )

        guard whiten > 0 else { return base }

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        base.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return UIColor(
            red: red + (1 - red) * whiten,
            green: green + (1 - green) * whiten,
            blue: blue + (1 - blue) * whiten,
            alpha: 1
        )
    }

    private static func paletteHue(_ palette: Palette, t: Double) -> Double {
        let hues = palette.hues.map { normalizedHue($0) }
        guard hues.count > 1 else { return hues.first ?? 0 }

        let clamped = min(max(t, 0), 1)
        let scaled = clamped * Double(hues.count - 1)
        let index = min(Int(scaled), hues.count - 2)
        let fraction = scaled - Double(index)

        let start = hues[index]
        let end = hues[index + 1]
        var delta = end - start
        if delta > 0.5 { delta -= 1 }
        if delta < -0.5 { delta += 1 }
        return normalizedHue(start + delta * fraction)
    }

    private static func drawVignette(in context: CGContext, size: CGFloat) {
        let colors = [
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(0.46).cgColor
        ] as CFArray

        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors,
            locations: [0.45, 1]
        ) else { return }

        let center = CGPoint(x: size / 2, y: size / 2)
        context.drawRadialGradient(
            gradient,
            startCenter: center,
            startRadius: 0,
            endCenter: center,
            endRadius: size * 0.78,
            options: [.drawsAfterEndLocation]
        )
    }

    // MARK: - Helpers

    private struct SeededRandom {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed | 1
        }

        mutating func nextUnit() -> CGFloat {
            state = state &+ 0x9E37_79B9_7F4A_7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
            value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
            value ^= value >> 31
            return CGFloat(Double(value >> 11) / Double(UInt64(1) << 53))
        }
    }

    private static func cubicPoint(
        _ p0: CGPoint,
        _ c1: CGPoint,
        _ c2: CGPoint,
        _ p1: CGPoint,
        _ t: CGFloat
    ) -> CGPoint {
        let u = 1 - t
        let a = u * u * u
        let b = 3 * u * u * t
        let c = 3 * u * t * t
        let d = t * t * t

        return CGPoint(
            x: a * p0.x + b * c1.x + c * c2.x + d * p1.x,
            y: a * p0.y + b * c1.y + c * c2.y + d * p1.y
        )
    }

    private static func normalizedHue(_ hue: Double) -> Double {
        let wrapped = hue.truncatingRemainder(dividingBy: 1)
        return wrapped < 0 ? wrapped + 1 : wrapped
    }

    private static func stableSeed(for name: String) -> UInt64 {
        var hash: UInt64 = 5381
        for scalar in name.unicodeScalars {
            hash = (hash &* 33) &+ UInt64(scalar.value)
        }
        return hash
    }

    private static func mix(_ value: UInt64) -> UInt64 {
        var result = value
        result ^= result >> 33
        result = result &* 0xFF51_AFD7_ED55_8CCD
        result ^= result >> 33
        result = result &* 0xC4CE_B9FE_1A85_EC53
        result ^= result >> 33
        return result
    }
}
