import CoreImage
import Foundation
import SwiftUI
import UIKit

enum VisualSettings {
    static let refractionKey = "motif.refractionBackgroundEnabled"
}

enum RefractionMode: Equatable {
    case ambient
    case player

    var intensity: Float {
        switch self {
        case .ambient: return 0.34
        case .player: return 1.0
        }
    }

    var imageOpacity: Double {
        switch self {
        case .ambient: return 0.34
        case .player: return 0.58
        }
    }
}

/// A cover-derived light field. It deliberately does not show the artwork
/// literally: the cover is blurred into color, and a slow ripple distorts it
/// so the background feels like light moving through glass.
struct RefractionBackdrop: View {
    let url: URL?
    let seed: String
    var mode: RefractionMode = .ambient

    @State private var artwork: UIImage?
    @State private var palette: [Color] = []

    init(url: URL?, seed: String, mode: RefractionMode = .ambient) {
        self.url = url
        self.seed = seed
        self.mode = mode
        _artwork = State(initialValue: url.flatMap {
            PlaybackBackdropCache.shared.preparedImage(for: $0)
        })
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let artwork {
                    RefractionPlate(
                        artwork: artwork,
                        palette: palette,
                        mode: mode,
                        size: geometry.size
                    )
                } else {
                    Color.clear
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .background(Color.black)
        .allowsHitTesting(false)
        .task(id: url) {
            await loadArtwork()
        }
    }

    @MainActor
    private func loadArtwork() async {
        guard let url else { return }

        if let prepared = PlaybackBackdropCache.shared.preparedImage(for: url) {
            apply(prepared)
            return
        }

        guard let prepared = await PlaybackBackdropCache.shared.prepare(for: url) else {
            return
        }
        apply(prepared)
    }

    private func apply(_ image: UIImage) {
        let colors = RefractionPalette.colors(for: image, key: url?.absoluteString ?? seed)

        if artwork == nil {
            artwork = image
            palette = colors
        } else {
            withAnimation(.easeInOut(duration: 0.85)) {
                artwork = image
                palette = colors
            }
        }
    }
}

private struct RefractionPlate: View {
    let artwork: UIImage
    let palette: [Color]
    let mode: RefractionMode
    let size: CGSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var paused: Bool {
        reduceMotion || scenePhase != .active
    }

    var body: some View {
        ZStack {
            if #available(iOS 17.0, *) {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: paused)) { timeline in
                    plate(time: paused ? 0 : timeline.date.timeIntervalSinceReferenceDate)
                        .layerEffect(
                            ShaderLibrary.motifRefraction(
                                .float2(Float(size.width), Float(size.height)),
                                .float(Float(plateTime(paused ? 0 : timeline.date.timeIntervalSinceReferenceDate))),
                                .float(mode.intensity)
                            ),
                            maxSampleOffset: CGSize(width: 26, height: 26)
                        )
                }
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: paused)) { timeline in
                    plate(time: paused ? 0 : timeline.date.timeIntervalSinceReferenceDate)
                }
            }

            scrim
        }
        .frame(width: size.width, height: size.height)
    }

    private func plateTime(_ time: TimeInterval) -> TimeInterval {
        time.truncatingRemainder(dividingBy: 240)
    }

    private func plate(time: TimeInterval) -> some View {
        ZStack {
            Color.black

            Image(uiImage: artwork)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
                .saturation(1.38)
                .opacity(mode.imageOpacity)

            ForEach(Array(palette.enumerated()), id: \.offset) { index, color in
                let phase = Double(index) * 1.7
                let width = size.width * (0.82 + CGFloat(index) * 0.16)

                Circle()
                    .fill(color)
                    .frame(width: width, height: width * 0.72)
                    .blur(radius: size.width * 0.20)
                    .offset(
                        x: CGFloat(sin(time * 0.055 + phase)) * size.width * 0.19,
                        y: CGFloat(cos(time * 0.043 + phase * 0.8)) * size.height * 0.15
                    )
                    .opacity(mode == .player ? 0.30 : 0.18)
            }

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(mode == .player ? 0.18 : 0.36), location: 0),
                    .init(color: .clear, location: 0.34),
                    .init(color: .clear, location: 0.62),
                    .init(color: .black.opacity(mode == .player ? 0.30 : 0.46), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private var scrim: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(mode == .player ? 0.34 : 0.48), location: 0),
                    .init(color: .clear, location: 0.30),
                    .init(color: .clear, location: 0.56),
                    .init(color: .black.opacity(mode == .player ? 0.68 : 0.76), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [
                    .clear,
                    .black.opacity(mode == .player ? 0.16 : 0.28)
                ],
                center: .center,
                startRadius: size.width * 0.12,
                endRadius: size.width * 0.82
            )
        }
        .frame(width: size.width, height: size.height)
    }
}

/// One-pixel color extraction gives us a useful palette without scanning the
/// whole artwork. The result is cached per URL so the animation never pays for
/// Core Image work on a frame.
private final class RefractionPaletteBox: NSObject {
    let colors: [Color]

    init(colors: [Color]) {
        self.colors = colors
    }
}

private enum RefractionPalette {
    private static let cache = NSCache<NSString, RefractionPaletteBox>()
    private static let context = CIContext(options: nil)

    static func colors(for image: UIImage, key: String) -> [Color] {
        if let cached = cache.object(forKey: key as NSString) {
            return cached.colors
        }

        guard let cgImage = image.cgImage else {
            return fallbackColors(for: key)
        }

        let input = CIImage(cgImage: cgImage)
        let base = averageColor(of: input) ?? UIColor(white: 0.18, alpha: 1)

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        base.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        let baseSaturation = max(0.18, min(0.68, saturation * 1.18 + 0.05))
        let baseBrightness = max(0.16, min(0.52, brightness * 1.06))

        let colors = [
            Color(uiColor: UIColor(
                hue: hue,
                saturation: baseSaturation,
                brightness: baseBrightness,
                alpha: 1
            )),
            Color(uiColor: UIColor(
                hue: (hue + 0.075).truncatingRemainder(dividingBy: 1),
                saturation: min(0.72, baseSaturation * 1.08),
                brightness: max(0.13, baseBrightness * 0.82),
                alpha: 1
            )),
            Color(uiColor: UIColor(
                hue: (hue + 0.925).truncatingRemainder(dividingBy: 1),
                saturation: min(0.66, baseSaturation * 0.90),
                brightness: max(0.11, baseBrightness * 0.72),
                alpha: 1
            ))
        ]

        cache.setObject(RefractionPaletteBox(colors: colors), forKey: key as NSString)
        return colors
    }

    private static func averageColor(of input: CIImage) -> UIColor? {
        guard let filter = CIFilter(name: "CIAreaAverage") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: input.extent), forKey: kCIInputExtentKey)
        guard let output = filter.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        return UIColor(
            red: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1
        )
    }

    private static func fallbackColors(for key: String) -> [Color] {
        var hash: UInt64 = 5381
        for scalar in key.unicodeScalars {
            hash = (hash &* 33) &+ UInt64(scalar.value)
        }

        let hue = CGFloat(hash % 360) / 360
        return [
            Color(red: 0.16, green: 0.18, blue: 0.24),
            Color(uiColor: UIColor(hue: hue, saturation: 0.28, brightness: 0.24, alpha: 1)),
            Color(uiColor: UIColor(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.34, brightness: 0.16, alpha: 1))
        ]
    }
}
