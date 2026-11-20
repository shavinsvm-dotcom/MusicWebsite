import AVFoundation
import CoreImage
import ImageIO
import SwiftUI
import UIKit

struct AppBackground: View {
    var body: some View {
        RefractionBackground()
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

/// A slow, soft color field. Large gradients only: no lines, no live blur,
/// no per-frame texture work.
private struct RefractionBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                base
                softColorField(in: geometry.size)
                GrainOverlay()
                    .opacity(isDark ? 0.018 : 0.010)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 30).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }

    private var base: some View {
        ZStack {
            if isDark {
                Color(red: 0.032, green: 0.035, blue: 0.047)
                RadialGradient(
                    colors: [Color(red: 0.20, green: 0.31, blue: 0.42).opacity(0.10), .clear],
                    center: .top,
                    startRadius: 0,
                    endRadius: 560
                )
            } else {
                Color(red: 0.974, green: 0.968, blue: 0.956)
                RadialGradient(
                    colors: [Color(red: 0.62, green: 0.76, blue: 0.90).opacity(0.12), .clear],
                    center: .top,
                    startRadius: 0,
                    endRadius: 560
                )
            }
        }
    }

    private var meshColors: [Color] {
        if isDark {
            return [
                Color(red: 0.012, green: 0.014, blue: 0.022),
                Color(red: 0.035, green: 0.160, blue: 0.200),
                Color(red: 0.018, green: 0.030, blue: 0.055),
                Color(red: 0.200, green: 0.040, blue: 0.150),
                Color(red: 0.055, green: 0.090, blue: 0.210),
                Color(red: 0.020, green: 0.120, blue: 0.150),
                Color(red: 0.030, green: 0.025, blue: 0.045),
                Color(red: 0.240, green: 0.150, blue: 0.340),
                Color(red: 0.015, green: 0.018, blue: 0.030)
            ]
        }

        return [
            Color(red: 0.975, green: 0.970, blue: 0.958),
            Color(red: 0.760, green: 0.860, blue: 0.900),
            Color(red: 0.955, green: 0.950, blue: 0.970),
            Color(red: 0.930, green: 0.820, blue: 0.845),
            Color(red: 0.800, green: 0.820, blue: 0.910),
            Color(red: 0.900, green: 0.930, blue: 0.940),
            Color(red: 0.965, green: 0.960, blue: 0.950),
            Color(red: 0.840, green: 0.790, blue: 0.900),
            Color(red: 0.970, green: 0.965, blue: 0.958)
        ]
    }

    @ViewBuilder
    private func softColorField(in size: CGSize) -> some View {
        let width = max(size.width, 1)
        let height = max(size.height, 1)

        ZStack {
            if #available(iOS 18.0, *) {
                MeshGradient(
                    width: 3,
                    height: 3,
                    points: [
                        [0.00, 0.00], [0.55, 0.00], [1.00, 0.00],
                        [0.00, 0.42], [0.50, 0.38], [1.00, 0.40],
                        [0.00, 1.00], [0.45, 1.00], [1.00, 1.00]
                    ],
                    colors: meshColors
                )
                .scaleEffect(1.18)
                .offset(
                    x: width * (drift ? 0.025 : -0.025),
                    y: height * (drift ? -0.018 : 0.018)
                )
            } else {
                fallbackField(width: width, height: height)
            }

            colorGlows(width: width, height: height)
        }
        .opacity(isDark ? 1 : 0.62)
    }

    private func fallbackField(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            LinearGradient(
                colors: isDark
                    ? [Color(red: 0.020, green: 0.025, blue: 0.050), Color(red: 0.080, green: 0.050, blue: 0.130)]
                    : [Color(red: 0.950, green: 0.930, blue: 0.920), Color(red: 0.820, green: 0.840, blue: 0.920)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.05, green: 0.32, blue: 0.38).opacity(isDark ? 0.42 : 0.18),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: width * 0.62
                    )
                )
                .frame(width: width * 1.35, height: height * 0.90)
                .offset(x: width * 0.24, y: -height * 0.24)

            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.48, green: 0.10, blue: 0.30).opacity(isDark ? 0.36 : 0.16),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: width * 0.64
                    )
                )
                .frame(width: width * 1.35, height: height * 0.90)
                .offset(x: -width * 0.22, y: height * 0.02)

            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.36, green: 0.22, blue: 0.62).opacity(isDark ? 0.36 : 0.14),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: width * 0.56
                    )
                )
                .frame(width: width * 1.25, height: height * 0.80)
                .offset(x: width * 0.04, y: height * 0.26)
        }
        .blendMode(isDark ? .screen : .multiply)
    }

    private func colorGlows(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.16, green: 0.70, blue: 0.86).opacity(isDark ? 0.20 : 0.10),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: width * 0.58
                    )
                )
                .frame(width: width * 1.20, height: height * 0.80)
                .offset(
                    x: width * (drift ? 0.26 : 0.22),
                    y: -height * (drift ? 0.21 : 0.18)
                )

            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.86, green: 0.16, blue: 0.44).opacity(isDark ? 0.16 : 0.08),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: width * 0.60
                    )
                )
                .frame(width: width * 1.25, height: height * 0.85)
                .offset(
                    x: -width * (drift ? 0.24 : 0.20),
                    y: height * (drift ? 0.03 : 0.00)
                )

            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.48, green: 0.30, blue: 0.86).opacity(isDark ? 0.16 : 0.08),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: width * 0.54
                    )
                )
                .frame(width: width * 1.18, height: height * 0.76)
                .offset(
                    x: width * (drift ? 0.03 : -0.03),
                    y: height * (drift ? 0.24 : 0.20)
                )
        }
        .blendMode(isDark ? .screen : .multiply)
    }
}

private struct GrainOverlay: View {
    var body: some View {
        Image(uiImage: Self.texture)
            .resizable(resizingMode: .tile)
            .ignoresSafeArea()
            .blendMode(.overlay)
    }

    private static let texture: UIImage = {
        let side = 96
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        var state: UInt64 = 0x9E3779B97F4A7C15

        for index in 0..<(side * side) {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let value = UInt8(truncatingIfNeeded: state >> 33)
            let offset = index * 4
            bytes[offset] = value
            bytes[offset + 1] = value
            bytes[offset + 2] = value
            bytes[offset + 3] = 255
        }

        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(
                  width: side,
                  height: side,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: side * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              )
        else { return UIImage() }

        return UIImage(cgImage: image)
    }()
}

/// Groups sibling Liquid Glass controls so they share one offscreen blur
/// pass instead of each starting its own every frame. This matters most while
/// a large cover is scaling and the whole surface is being recomposited.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat
    private let content: () -> Content

    init(spacing: CGFloat = 10, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
        #else
        content()
        #endif
    }
}

extension View {
    /// Uses Apple's Liquid Glass on iOS 26 and falls back to a thin system
    /// material on earlier versions. The only hand-built glass in MOTIF is
    /// the closed mini player, which needs its own compact pill treatment.
    @ViewBuilder
    func nativeGlass<S: Shape>(_ shape: S, interactive: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            if interactive {
                glassEffect(.regular.interactive(), in: shape)
            } else {
                glassEffect(.regular, in: shape)
            }
        } else {
            glassFallback(shape)
        }
        #else
        glassFallback(shape)
        #endif
    }

    @ViewBuilder
    private func glassFallback<S: Shape>(_ shape: S) -> some View {
        background(.ultraThinMaterial, in: shape)
    }

    /// Player chrome opts out of repeated material blur passes on older iOS.
    /// A flat translucent fill keeps the same layering without recompositing
    /// ten live blurs while a full-screen cover is scaling.
    @ViewBuilder
    func playerGlass<S: Shape>(_ shape: S, interactive: Bool = true) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            if interactive {
                glassEffect(.regular.interactive(), in: shape)
            } else {
                glassEffect(.regular, in: shape)
            }
        } else {
            playerGlassFallback(shape)
        }
        #else
        playerGlassFallback(shape)
        #endif
    }

    @ViewBuilder
    private func playerGlassFallback<S: Shape>(_ shape: S) -> some View {
        background {
            shape
                .fill(Color.white.opacity(0.09))
                .overlay {
                    shape.stroke(Color.white.opacity(0.14), lineWidth: 0.7)
                }
        }
    }
}

extension View {
    @ViewBuilder
    func motifBounce(_ trigger: Bool) -> some View {
        if #available(iOS 17.0, *) {
            symbolEffect(.bounce, value: trigger)
        } else {
            self
        }
    }

    @ViewBuilder
    func motifBounce(tick: Int) -> some View {
        if #available(iOS 17.0, *) {
            symbolEffect(.bounce, options: .speed(1.6), value: tick)
        } else {
            self
        }
    }

    func screenEntrance() -> some View {
        modifier(ScreenEntrance())
    }

    @ViewBuilder
    func motifReplace() -> some View {
        if #available(iOS 17.0, *) {
            contentTransition(.symbolEffect(.replace))
        } else {
            self
        }
    }
}

private struct ScreenEntrance: ViewModifier {
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 7)
            .onAppear {
                withAnimation(.easeOut(duration: 0.14)) {
                    appeared = true
                }
            }
            .onDisappear {
                appeared = false
            }
    }
}

struct MotifPressStyle: ButtonStyle {
    var scale: CGFloat = 0.94
    var opacity: Double = 0.86

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let spring: Animation = configuration.isPressed
            ? .spring(response: 0.14, dampingFraction: 0.86)
            : .spring(response: 0.36, dampingFraction: 0.56)

        return configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .brightness(configuration.isPressed ? -0.035 : 0)
            .opacity(configuration.isPressed ? opacity : 1)
            .animation(reduceMotion ? nil : spring, value: configuration.isPressed)
    }
}

/// Slightly deeper press treatment for the player's glass controls: the
/// shadow collapses as the button is pushed in, then springs back out.
struct PlayerControlPressStyle: ButtonStyle {
    var scale: CGFloat = 0.9

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let spring: Animation = configuration.isPressed
            ? .spring(response: 0.13, dampingFraction: 0.84)
            : .spring(response: 0.34, dampingFraction: 0.55)

        return configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .brightness(configuration.isPressed ? -0.045 : 0)
            .shadow(
                color: .black.opacity(configuration.isPressed ? 0.10 : 0.22),
                radius: configuration.isPressed ? 2 : 7,
                y: configuration.isPressed ? 1 : 3
            )
            .animation(reduceMotion ? nil : spring, value: configuration.isPressed)
    }
}

private struct GlassSurface: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        content.nativeGlass(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
        )
    }
}

extension View {
    func glassSurface(radius: CGFloat = 24) -> some View {
        modifier(GlassSurface(radius: radius))
    }
}

struct ArtworkView: View {
    let url: URL?
    let seed: String
    let onImageLoaded: ((UIImage) -> Void)?
    let highResolution: Bool

    @State private var image: UIImage?
    @State private var failed = false

    init(
        url: URL?,
        seed: String,
        onImageLoaded: ((UIImage) -> Void)? = nil,
        highResolution: Bool = false
    ) {
        self.url = url
        self.seed = seed
        self.onImageLoaded = onImageLoaded
        self.highResolution = highResolution

        let cached: UIImage?
        if highResolution, let url {
            cached = ArtworkImageCache.shared.heroImage(for: url)
                ?? ArtworkImageCache.shared.image(for: url)
        } else {
            cached = url.flatMap { ArtworkImageCache.shared.image(for: $0) }
        }
        _image = State(initialValue: cached)
    }

    private var resolvedImage: UIImage? {
        if let image { return image }
        guard let url else { return nil }
        if highResolution {
            return ArtworkImageCache.shared.heroImage(for: url)
                ?? ArtworkImageCache.shared.image(for: url)
        }
        return ArtworkImageCache.shared.image(for: url)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: palette,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let image = resolvedImage {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFill()
            } else if url != nil, !failed {
                ProgressView()
                    .tint(.white)
            } else {
                fallback
            }
        }
        .clipped()
        .task(id: url) {
            if let url {
                let cached = highResolution
                    ? ArtworkImageCache.shared.heroImage(for: url)
                        ?? ArtworkImageCache.shared.image(for: url)
                    : ArtworkImageCache.shared.image(for: url)

                if let cached {
                    if image !== cached {
                        image = cached
                    }
                    failed = false
                    onImageLoaded?(cached)

                    // A cached thumbnail can paint immediately, but the player
                    // still upgrades itself to the 1200 px hero decode.
                    if !highResolution || ArtworkImageCache.shared.heroImage(for: url) != nil {
                        return
                    }
                }
            }
            await loadImage()
        }
    }

    @MainActor
    private func loadImage() async {
        guard let url else {
            image = nil
            failed = false
            return
        }

        if highResolution {
            if let cached = ArtworkImageCache.shared.heroImage(for: url) {
                image = cached
                failed = false
                onImageLoaded?(cached)
                return
            }
        } else if let cached = ArtworkImageCache.shared.image(for: url) {
            image = cached
            failed = false
            onImageLoaded?(cached)
            return
        }

        if !highResolution || image == nil {
            image = nil
        }
        failed = false

        let loaded: UIImage?
        if highResolution {
            loaded = await ArtworkImageCache.shared.loadHeroImage(for: url)
        } else {
            loaded = await ArtworkImageCache.shared.loadImage(for: url)
        }

        guard let loaded,
              !Task.isCancelled
        else {
            if !Task.isCancelled { failed = true }
            return
        }

        image = loaded
        onImageLoaded?(loaded)
    }

    private var fallback: some View {
        Text(String(seed.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased())
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(.white.opacity(0.88))
    }

    private var palette: [Color] {
        let lift = 0.10 + stableHue * 0.10
        return [
            Color(white: 0.18 + lift),
            Color(white: 0.10 + lift * 0.45)
        ]
    }

    private var stableHue: Double {
        var hash: UInt64 = 5381
        for scalar in seed.unicodeScalars {
            hash = (hash &* 33) &+ UInt64(scalar.value)
        }
        return Double(hash % 360) / 360
    }
}

final class ArtworkImageCache {
    static let shared = ArtworkImageCache()

    private let cache = NSCache<NSURL, UIImage>()
    private let heroCache = NSCache<NSURL, UIImage>()
    private let taskLock = NSLock()
    private var loadingTasks: [NSURL: Task<UIImage?, Never>] = [:]
    private var heroLoadingTasks: [NSURL: Task<UIImage?, Never>] = [:]

    private init() {
        cache.countLimit = 160
        cache.totalCostLimit = 96 * 1024 * 1024
        heroCache.countLimit = 20
        heroCache.totalCostLimit = 72 * 1024 * 1024
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func store(_ image: UIImage, for url: URL) {
        let cost = Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: url as NSURL, cost: cost)
    }

    func heroImage(for url: URL) -> UIImage? {
        heroCache.object(forKey: url as NSURL)
    }

    func loadHeroImage(for url: URL, maxPixelSize: Int = 1200) async -> UIImage? {
        if let cached = heroImage(for: url) { return cached }

        let key = url as NSURL
        taskLock.lock()
        if let existing = heroLoadingTasks[key] {
            taskLock.unlock()
            return await existing.value
        }

        let task = Task.detached(priority: .userInitiated) {
            await Self.downsample(url: url, maxPixelSize: maxPixelSize)
        }
        heroLoadingTasks[key] = task
        taskLock.unlock()

        let image = await task.value

        taskLock.lock()
        heroLoadingTasks[key] = nil
        taskLock.unlock()

        if let image {
            let cost = Int(image.size.width * image.size.height * 4)
            heroCache.setObject(image, forKey: key, cost: cost)
        }
        return image
    }

    /// Loads and downsamples artwork once per URL. Playlist mosaics often ask
    /// for the same covers several times in one frame; sharing the task keeps
    /// those cells from starting duplicate network and decode work.
    func loadImage(for url: URL, maxPixelSize: Int = 900) async -> UIImage? {
        if let cached = image(for: url) { return cached }

        let key = url as NSURL
        taskLock.lock()
        if let existing = loadingTasks[key] {
            taskLock.unlock()
            return await existing.value
        }

        let task = Task.detached(priority: .utility) {
            await Self.downsample(url: url, maxPixelSize: maxPixelSize)
        }
        loadingTasks[key] = task
        taskLock.unlock()

        let image = await task.value

        taskLock.lock()
        loadingTasks[key] = nil
        taskLock.unlock()

        if let image {
            store(image, for: url)
        }
        return image
    }

    private static func downsample(url: URL, maxPixelSize: Int) async -> UIImage? {
        let data: Data?
        if url.isFileURL {
            data = try? Data(contentsOf: url, options: .mappedIfSafe)
        } else {
            data = try? await URLSession.shared.data(from: url).0
        }

        guard let data else { return nil }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else {
            return UIImage(data: data)
        }

        return UIImage(cgImage: cgImage)
    }
}

/// Cached blurred artwork for the progressive frost behind hero copy.
/// Rendering this per card would add a live blur to every scroll frame, so it
/// is generated once per URL at low resolution and only masked at draw time.
final class ArtworkBlurCache {
    static let shared = ArtworkBlurCache()

    private let cache = NSCache<NSURL, UIImage>()
    private let lock = NSLock()
    private var tasks: [NSURL: Task<UIImage?, Never>] = [:]
    private static let ciContext = CIContext(options: nil)
    private static let renderSide: CGFloat = 480

    private init() {
        cache.countLimit = 36
        cache.totalCostLimit = 48 * 1024 * 1024
    }

    func image(for url: URL?) -> UIImage? {
        guard let url else { return nil }
        return cache.object(forKey: url as NSURL)
    }

    func prepare(for url: URL?) async -> UIImage? {
        guard let url else { return nil }
        if let cached = image(for: url) { return cached }

        let key = url as NSURL
        lock.lock()
        if let existing = tasks[key] {
            lock.unlock()
            return await existing.value
        }

        let task = Task.detached(priority: .utility) { () -> UIImage? in
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

        let image = await task.value

        lock.lock()
        tasks[key] = nil
        lock.unlock()

        if let image {
            let cost = Int(image.size.width * image.size.height * 4)
            cache.setObject(image, forKey: key, cost: cost)
        }
        return image
    }

    private static func render(_ image: UIImage) -> UIImage? {
        let side = renderSide
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
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
        let blurred = input
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 24])
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 1.12,
                kCIInputBrightnessKey: -0.025,
                kCIInputContrastKey: 1.03
            ])
            .cropped(to: input.extent)

        guard let output = ciContext.createCGImage(blurred, from: input.extent) else {
            return nil
        }
        return UIImage(cgImage: output)
    }
}

/// Frosts the lower part of a hero card so type sits on blurred artwork rather
/// than a flat black gradient. The blur itself is already cached.
struct ProgressiveArtworkBlur: View {
    let url: URL?
    var strength: Double = 0.92

    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geometry in
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .opacity(strength)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .clear, location: 0.18),
                                .init(color: .black.opacity(0.20), location: 0.36),
                                .init(color: .black.opacity(0.82), location: 0.62),
                                .init(color: .black, location: 0.82),
                                .init(color: .black, location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
        .allowsHitTesting(false)
        .task(id: url) {
            image = await ArtworkBlurCache.shared.prepare(for: url)
        }
    }
}

/// Pre-blurs the player backdrop once, so opening the player never pays for
/// a full-screen live blur while the zoom transition is running.
final class PlaybackBackdropCache {
    static let shared = PlaybackBackdropCache()

    private let cache = NSCache<NSURL, UIImage>()
    private let context = CIContext(options: nil)
    private let renderSize = CGSize(width: 180, height: 320)

    private init() {
        cache.countLimit = 32
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    @discardableResult
    func prepare(for url: URL) async -> UIImage? {
        if let cached = image(for: url) { return cached }

        let artwork: UIImage?
        if let cachedArtwork = ArtworkImageCache.shared.image(for: url) {
            artwork = cachedArtwork
        } else if url.isFileURL {
            artwork = UIImage(contentsOfFile: url.path)
        } else {
            guard let (data, _) = try? await URLSession.shared.data(from: url) else {
                return nil
            }
            artwork = UIImage(data: data)
        }

        guard let artwork else { return nil }
        ArtworkImageCache.shared.store(artwork, for: url)

        let size = renderSize
        let ciContext = context
        let rendered = await Task.detached(priority: .utility) {
            Self.render(artwork, size: size, context: ciContext)
        }.value

        guard let rendered else { return nil }
        cache.setObject(rendered, forKey: url as NSURL)
        return rendered
    }

    func preparedImage(for url: URL) -> UIImage? {
        if let cached = image(for: url) { return cached }
        guard let artwork = ArtworkImageCache.shared.image(for: url) else { return nil }
        guard let rendered = Self.render(artwork, size: renderSize, context: context) else {
            return nil
        }
        cache.setObject(rendered, forKey: url as NSURL)
        return rendered
    }

    private static func render(_ image: UIImage, size: CGSize, context: CIContext) -> UIImage? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let scaled = renderer.image { _ in
            let factor = max(size.width / image.size.width, size.height / image.size.height)
            let drawSize = CGSize(
                width: image.size.width * factor,
                height: image.size.height * factor
            )
            image.draw(in: CGRect(
                x: (size.width - drawSize.width) / 2,
                y: (size.height - drawSize.height) / 2,
                width: drawSize.width,
                height: drawSize.height
            ))
        }

        guard let cgImage = scaled.cgImage else { return nil }
        let input = CIImage(cgImage: cgImage)
        let blurred = input
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 16])
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 1.38,
                kCIInputBrightnessKey: -0.055,
                kCIInputContrastKey: 1.04
            ])
            .cropped(to: input.extent)

        guard let output = context.createCGImage(blurred, from: input.extent) else {
            return nil
        }
        return UIImage(cgImage: output)
    }
}

@MainActor
final class SpatialAudioMonitor: ObservableObject {
    @Published private(set) var badge: String?

    private var observers: [NSObjectProtocol] = []

    init() {
        refresh()

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        })

        if #available(iOS 15.0, *) {
            observers.append(center.addObserver(
                forName: AVAudioSession.spatialPlaybackCapabilitiesChangedNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            })
        }

        if #available(iOS 18.0, *) {
            observers.append(center.addObserver(
                forName: AVAudioSession.renderingModeChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            })
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func refresh() {
        let session = AVAudioSession.sharedInstance()
        var next: String?

        if #available(iOS 18.0, *) {
            switch session.renderingMode {
            case .dolbyAtmos:
                next = "Dolby Atmos"
            case .dolbyAudio:
                next = "Dolby Audio"
            case .spatialAudio:
                next = "Spatial Audio"
            default:
                break
            }
        }

        if next == nil, #available(iOS 15.0, *) {
            if session.currentRoute.outputs.contains(where: { $0.isSpatialAudioEnabled }) {
                next = "Spatial Audio"
            }
        }

        badge = next
    }
}

struct LiltWordmark: View {
    var height: CGFloat = 18

    var body: some View {
        Image("LiltWordmark")
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .accessibilityLabel("Lilt")
    }
}

struct SectionTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 19, weight: .semibold))
            .tracking(-0.3)
    }
}

struct TrackRow: View {
    let track: Track
    var queue: [Track]? = nil

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerManager
    @State private var downloadPulse = 0

    var body: some View {
        let isDownloaded = track.isCloud && library.isDownloaded(track)
        let isDownloading = track.isCloud && library.isDownloading(track)
        let isFavorite = library.isFavorite(track)
        let isUploaded = track.isUploadedToCloud
        let isUploading = library.isUploading(track)
        let isEnriching = library.isEnriching(track)

        HStack(spacing: 12) {
            Button {
                player.play(track, queue: queue ?? [track])
            } label: {
                HStack(spacing: 12) {
                    ArtworkView(url: track.artworkURL, seed: track.title + track.artist)
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    if isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if isUploading || isEnriching {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.secondary)
                    } else if isUploaded {
                        Image(systemName: "cloud.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(track.durationText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(MotifPressStyle(scale: 0.99, opacity: 0.9))

            if track.isCloud {
                Button {
                    guard !isDownloaded, !isDownloading else { return }
                    downloadPulse += 1
                    Task { await library.download(track) }
                } label: {
                    Group {
                        if isDownloading {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.secondary)
                        } else {
                            Image(systemName: isDownloaded ? "checkmark.circle.fill" : "arrow.down.circle")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .motifReplace()
                                .motifBounce(tick: downloadPulse)
                                .animation(.spring(response: 0.30, dampingFraction: 0.70), value: isDownloaded)
                        }
                    }
                    .frame(width: 32, height: 42)
                    .contentShape(Rectangle())
                }
                .buttonStyle(MotifPressStyle(scale: 0.86))
                .disabled(isDownloaded || isDownloading)
                .accessibilityLabel(isDownloaded ? "Available offline" : "Download for offline")
            }

            Menu {
                Button {
                    player.play(track, queue: queue ?? [track])
                } label: {
                    Label("Play", systemImage: "play.fill")
                }

                Button {
                    player.playNext(track)
                } label: {
                    Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                }

                Button {
                    player.addToQueue(track)
                } label: {
                    Label("Add to Queue", systemImage: "text.badge.plus")
                }

                Button {
                    library.toggleFavorite(track)
                } label: {
                    Label(
                        library.isFavorite(track) ? "Remove favorite" : "Favorite",
                        systemImage: library.isFavorite(track) ? "heart.slash" : "heart"
                    )
                }

                if !library.playlists.isEmpty {
                    Menu {
                        ForEach(library.playlists) { playlist in
                            Button(playlist.name) {
                                library.add(track, to: playlist.id)
                            }
                        }
                    } label: {
                        Label("Add to playlist", systemImage: "text.badge.plus")
                    }
                }

                if track.isCloud {
                    if library.isDownloaded(track) {
                        Button(role: .destructive) {
                            library.removeDownload(track)
                        } label: {
                            Label("Remove download", systemImage: "icloud.slash")
                        }
                    } else {
                        Button {
                            Task { await library.download(track) }
                        } label: {
                            Label("Download for offline", systemImage: "arrow.down.circle")
                        }
                        .disabled(library.isDownloading(track))
                    }
                }

                if track.source == .local && track.mediaURL.isFileURL {
                    if !isUploaded {
                        if isEnriching {
                            Button {} label: {
                                Label("Identifying & finding cover…", systemImage: "sparkles")
                            }
                            .disabled(true)
                        } else {
                            Button {
                                Task { await library.enrichTrack(track) }
                            } label: {
                                Label("Identify & find cover", systemImage: "wand.and.stars")
                            }
                            .disabled(isUploading)
                        }
                    }

                    if isUploaded {
                        Button {} label: {
                            Label("Uploaded to cloud", systemImage: "checkmark.icloud")
                        }
                        .disabled(true)
                    } else if isUploading {
                        Button {} label: {
                            Label("Uploading…", systemImage: "icloud.and.arrow.up")
                        }
                        .disabled(true)
                    } else {
                        Button {
                            Task { await library.uploadToCloud(track) }
                        } label: {
                            Label("Upload to cloud", systemImage: "icloud.and.arrow.up")
                        }
                    }
                }

                if library.contains(track) {
                    Button(role: .destructive) {
                        library.delete(track)
                    } label: {
                        Label("Delete from library", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 42)
                    .contentShape(Rectangle())
            }
        }
        .padding(.vertical, 6)
    }
}
