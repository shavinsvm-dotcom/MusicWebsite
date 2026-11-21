import UIKit

/// Draws the generated playlist artwork entirely on device: glossy prismatic
/// ribbons, sampled from one curved spine so every band stays parallel and the
/// highlight rolls along the fold like satin. Two layouts alternate so
/// "Generate cover" keeps producing something new.
enum PlaylistCoverGenerator {
    private enum Layout: Int {
        case sweep
        case tide
    }

    private static let pixelSize: CGFloat = 1024

    static func jpegData(name: String, variant: Int) -> Data? {
        image(name: name, variant: variant)
            .jpegData(compressionQuality: 0.9)
    }

    static func image(name: String, variant: Int) -> UIImage {
        let size = CGSize(width: pixelSize, height: pixelSize)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            draw(
                in: context.cgContext,
                size: pixelSize,
                seed: stableSeed(for: name) &+ UInt64(abs(variant) &* 977),
                layout: Layout(rawValue: abs(variant) % 2) ?? .sweep
            )
        }
    }

    // MARK: - Canvas

    private static func draw(
        in context: CGContext,
        size: CGFloat,
        seed: UInt64,
        layout: Layout
    ) {
        context.setFillColor(
            UIColor(red: 0.024, green: 0.024, blue: 0.038, alpha: 1).cgColor
        )
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))

        drawBloom(in: context, size: size, hue: normalizedHue(0.74 + Double(seed % 5) * 0.02))

        context.saveGState()
        if layout == .tide {
            context.translateBy(x: size / 2, y: size / 2)
            context.rotate(by: .pi / 2)
            context.scaleBy(x: -1, y: 1)
            context.translateBy(x: -size / 2, y: -size / 2)
        }
        drawRibbons(in: context, size: size, seed: seed, layout: layout)
        context.restoreGState()

        drawVignette(in: context, size: size)
    }

    private static func drawBloom(in context: CGContext, size: CGFloat, hue: Double) {
        let colors = [
            UIColor(hue: CGFloat(hue), saturation: 0.80, brightness: 0.52, alpha: 0.62).cgColor,
            UIColor(hue: CGFloat(hue), saturation: 0.85, brightness: 0.30, alpha: 0.18).cgColor,
            UIColor.clear.cgColor
        ] as CFArray

        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors,
            locations: [0, 0.55, 1]
        ) else { return }

        let center = CGPoint(x: size * 0.14, y: size * 1.04)
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
        seed: UInt64,
        layout: Layout
    ) {
        let bandCount = 24
        let spacing = size * 0.083
        let thickness = size * 0.180
        let bow = -0.10 + CGFloat(seed % 3) * 0.075
        let hueShift = layout == .tide ? 0.17 : 0.0
        let baseHue = 0.63 - 11 * 0.088 + Double(seed % 7) * 0.012 + hueShift

        for index in 0..<bandCount {
            let offset = -size * 0.95 + CGFloat(index) * spacing
            let p0 = CGPoint(x: -size * 0.30, y: offset + size * 0.02)
            let c1 = CGPoint(x: size * 0.28, y: offset - size * 0.06 + bow * size)
            let c2 = CGPoint(x: size * 0.62, y: offset + size * 0.52 - bow * size)
            let p1 = CGPoint(x: size * 1.30, y: offset + size * 0.70)

            drawBand(
                in: context,
                p0: p0,
                c1: c1,
                c2: c2,
                p1: p1,
                thickness: thickness,
                hue: baseHue + Double(index) * 0.088
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
        hue: Double
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
            let taper = min(1, min(t, 1 - t) * 6)
            let width = thickness * (0.55 + 0.45 * taper)

            top.append(point)
            bottom.append(CGPoint(x: point.x, y: point.y + width))
            minY = min(minY, point.y)
            maxY = max(maxY, point.y + width)
        }

        let path = CGMutablePath()
        path.addLines(between: top + bottom.reversed())
        path.closeSubpath()

        guard let gradient = bandGradient(hue: normalizedHue(hue)) else { return }

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

    private static func bandGradient(hue: Double) -> CGGradient? {
        let stops: [(CGFloat, UIColor)] = [
            (0.00, bandColor(hue, saturation: 0.60, brightness: 0.55)),
            (0.10, bandColor(hue, saturation: 0.95, brightness: 0.92)),
            (0.30, bandColor(hue, saturation: 0.72, brightness: 1.00, whiten: 0.09)),
            (0.46, bandColor(hue, saturation: 0.96, brightness: 1.00)),
            (0.74, bandColor(hue, saturation: 0.90, brightness: 0.92)),
            (1.00, bandColor(hue, saturation: 0.70, brightness: 0.55))
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
        whiten: CGFloat = 0
    ) -> UIColor {
        let base = UIColor(
            hue: CGFloat(hue),
            saturation: saturation,
            brightness: brightness,
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
}
