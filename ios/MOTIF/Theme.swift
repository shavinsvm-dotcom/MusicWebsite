import CoreImage
import ImageIO
import SwiftUI
import UIKit

struct AppBackground: View {
    var body: some View {
        PaperBackground()
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

/// A quiet warm canvas in light, graphite in dark. No visible texture: the
/// artwork should be the only thing in the app with detail.
private struct PaperBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if colorScheme == .dark {
                Color(red: 0.035, green: 0.035, blue: 0.043)

                LinearGradient(
                    stops: [
                        .init(color: Color(red: 0.105, green: 0.105, blue: 0.122), location: 0),
                        .init(color: Color(red: 0.045, green: 0.045, blue: 0.055), location: 0.52),
                        .init(color: .clear, location: 0.90)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                Color(red: 0.972, green: 0.965, blue: 0.945)

                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(0.42), location: 0),
                        .init(color: .clear, location: 0.45)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.82),
                    .init(color: .black.opacity(colorScheme == .dark ? 0.26 : 0.025), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
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

    /// Blur-free control surface for dense, per-row overlays. Live glass in
    /// every list row is expensive while scrolling; these badges only need a
    /// translucent fill and a hairline edge.
    func rowControl<S: Shape>(_ shape: S, dark: Bool = false) -> some View {
        background {
            shape
                .fill(dark ? Color.black.opacity(0.42) : Color.primary.opacity(0.06))
                .overlay {
                    shape.stroke(
                        dark ? Color.white.opacity(0.16) : Color.primary.opacity(0.08),
                        lineWidth: 0.5
                    )
                }
        }
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

/// Keeps the native navigation bar in charge of page headers: the large title
/// collapses into an inline header while scrolling, with the system's own
/// scroll-edge treatment underneath.
extension View {
    func nativeScrollHeader() -> some View {
        modifier(NativeScrollEdge())
    }

    /// On iOS 26+ the search field folds into a compact toolbar button and
    /// expands into the native search experience — with its scope menu — when
    /// tapped. Earlier versions keep the standard search field.
    func minimizedSearch() -> some View {
        modifier(MinimizedSearch())
    }
}

private struct MinimizedSearch: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.searchToolbarBehavior(.minimize)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

private struct NativeScrollEdge: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
        }
        #else
        content
        #endif
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

/// Motion tokens shared by the player and controls. Apple's spring presets
/// settle predictably without the visible overshoot that makes a control feel
/// jerky; the hand-tuned springs are only a fallback for iOS 16.
enum MotifMotion {
    static var control: Animation {
        if #available(iOS 17.0, *) {
            return .snappy(duration: 0.24, extraBounce: 0)
        } else {
            return .spring(response: 0.28, dampingFraction: 0.88)
        }
    }

    static var settle: Animation {
        if #available(iOS 17.0, *) {
            return .smooth(duration: 0.32)
        } else {
            return .easeInOut(duration: 0.28)
        }
    }

    static var artwork: Animation {
        if #available(iOS 17.0, *) {
            return .smooth(duration: 0.34)
        } else {
            return .easeInOut(duration: 0.30)
        }
    }

    static var overlay: Animation {
        .easeOut(duration: 0.28)
    }
}

/// The app-wide press treatment. Touch-down is a short, damped compression;
/// release is one smooth spring back to rest. Only scale and a whisper of
/// dimming move, so a tap never looks like the button is shaking or flashing.
struct MotifPressStyle: ButtonStyle {
    var scale: CGFloat = 0.975
    var opacity: Double = 0.90
    var haptic: MotifHaptics.Event? = .light

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let animation: Animation = pressed
            ? .easeOut(duration: 0.10)
            : .spring(response: 0.30, dampingFraction: 0.86)

        return configuration.label
            .scaleEffect(pressed ? scale : 1)
            .opacity(pressed ? opacity : 1)
            .animation(reduceMotion ? nil : animation, value: pressed)
            .onChange(of: pressed) { isPressed in
                guard isPressed, let haptic else { return }
                MotifHaptics.play(haptic)
            }
    }
}

/// Transport controls follow the system's own feel rather than adding motion
/// for its own sake: the glass stays put, the label dims under the finger and
/// springs back, and only play/pause scales. The heart keeps the player's one
/// celebratory flourish; everything else leans on tint, opacity and haptics,
/// which is how Apple Music and Spotify keep their transport rows calm.
struct PlayerControlPressStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    var pressedOpacity: Double = 0.72
    var haptic: MotifHaptics.Event? = .light

    func makeBody(configuration: Configuration) -> some View {
        PlayerControlPressLabel(
            content: configuration.label,
            isPressed: configuration.isPressed,
            scale: scale,
            pressedOpacity: pressedOpacity,
            haptic: haptic
        )
    }
}

private struct PlayerControlPressLabel<Content: View>: View {
    let content: Content
    let isPressed: Bool
    let scale: CGFloat
    let pressedOpacity: Double
    let haptic: MotifHaptics.Event?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            .scaleEffect(isPressed && !reduceMotion ? scale : 1)
            .opacity(isPressed ? pressedOpacity : 1)
            .animation(pressAnimation, value: isPressed)
            .onChange(of: isPressed) { pressed in
                guard pressed, let haptic else { return }
                MotifHaptics.play(haptic)
            }
    }

    private var pressAnimation: Animation {
        isPressed
            ? .spring(response: 0.12, dampingFraction: 1.0)
            : .spring(response: 0.34, dampingFraction: 0.80)
    }
}

/// Play/pause is the one control that earns a real glyph transition. iOS 17
/// gets the system's symbol replace; iOS 16 crossfades with a small scale. The
/// play triangle is nudged 1pt so its optical centre matches pause.
struct PlayPauseGlyph: View {
    let isPlaying: Bool
    let size: CGFloat
    let weight: Font.Weight

    init(isPlaying: Bool, size: CGFloat = 18, weight: Font.Weight = .semibold) {
        self.isPlaying = isPlaying
        self.size = size
        self.weight = weight
    }

    var body: some View {
        Group {
            if #available(iOS 17.0, *) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .contentTransition(.symbolEffect(.replace.offUp))
            } else {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .id(isPlaying)
                    .transition(.opacity.combined(with: .scale(scale: 0.86)))
            }
        }
        .font(.system(size: size, weight: weight))
        .offset(x: isPlaying ? 0 : 1)
        .animation(.easeOut(duration: 0.14), value: isPlaying)
    }
}

struct ArtworkView: View {
    let url: URL?
    let seed: String
    let onImageLoaded: ((UIImage) -> Void)?
    let highResolution: Bool
    let thumbnail: Bool
    let card: Bool

    @State private var image: UIImage?
    @State private var failed = false

    init(
        url: URL?,
        seed: String,
        onImageLoaded: ((UIImage) -> Void)? = nil,
        highResolution: Bool = false,
        thumbnail: Bool = false,
        card: Bool = false
    ) {
        self.url = url
        self.seed = seed
        self.onImageLoaded = onImageLoaded
        self.highResolution = highResolution
        self.thumbnail = thumbnail
        self.card = card

        let cached: UIImage?
        if highResolution, let url {
            cached = ArtworkImageCache.shared.heroImage(for: url)
                ?? ArtworkImageCache.shared.image(for: url)
        } else if card, let url {
            cached = ArtworkImageCache.shared.card(for: url)
                ?? ArtworkImageCache.shared.image(for: url)
        } else if thumbnail, let url {
            cached = ArtworkImageCache.shared.thumbnail(for: url)
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
        if card {
            return ArtworkImageCache.shared.card(for: url)
                ?? ArtworkImageCache.shared.image(for: url)
        }
        if thumbnail {
            return ArtworkImageCache.shared.thumbnail(for: url)
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
                    .interpolation(thumbnail || card ? .medium : .high)
                    .antialiased(true)
                    .scaledToFill()
            } else if url != nil, !failed {
                // Rows and cards sit in lazy stacks and shelves; a spinning
                // ProgressView in every loading cell keeps dozens of animations
                // alive while scrolling. The gradient is placeholder enough.
                if thumbnail || card {
                    Color.clear
                } else {
                    ProgressView()
                        .tint(.white)
                }
            } else {
                fallback
            }
        }
        .clipped()
        .task(id: url) {
            if let url {
                let cached: UIImage?
                if highResolution {
                    cached = ArtworkImageCache.shared.heroImage(for: url)
                        ?? ArtworkImageCache.shared.image(for: url)
                } else if card {
                    cached = ArtworkImageCache.shared.card(for: url)
                } else if thumbnail {
                    cached = ArtworkImageCache.shared.thumbnail(for: url)
                } else {
                    cached = ArtworkImageCache.shared.image(for: url)
                }

                if let cached {
                    if image !== cached {
                        image = cached
                    }
                    failed = false
                    onImageLoaded?(cached)

                    // Cached row and card sizes paint immediately; only the
                    // player upgrades itself to the 1200 px hero decode.
                    if thumbnail || card {
                        return
                    }
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
        } else if card {
            if let cached = ArtworkImageCache.shared.card(for: url) {
                image = cached
                failed = false
                onImageLoaded?(cached)
                return
            }
        } else if thumbnail {
            if let cached = ArtworkImageCache.shared.thumbnail(for: url) {
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

        if !highResolution && !thumbnail && !card {
            image = nil
        }
        failed = false

        let loaded: UIImage?
        if highResolution {
            loaded = await ArtworkImageCache.shared.loadHeroImage(for: url)
        } else if card {
            loaded = await ArtworkImageCache.shared.loadCard(for: url)
        } else if thumbnail {
            loaded = await ArtworkImageCache.shared.loadThumbnail(for: url)
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
    private let cardCache = NSCache<NSURL, UIImage>()
    private let thumbnailCache = NSCache<NSURL, UIImage>()
    private let taskLock = NSLock()
    private var loadingTasks: [NSURL: Task<UIImage?, Never>] = [:]
    private var heroLoadingTasks: [NSURL: Task<UIImage?, Never>] = [:]
    private var cardLoadingTasks: [NSURL: Task<UIImage?, Never>] = [:]
    private var thumbnailLoadingTasks: [NSURL: Task<UIImage?, Never>] = [:]

    private init() {
        cache.countLimit = 160
        cache.totalCostLimit = 96 * 1024 * 1024
        heroCache.countLimit = 20
        heroCache.totalCostLimit = 72 * 1024 * 1024
        cardCache.countLimit = 120
        cardCache.totalCostLimit = 72 * 1024 * 1024
        thumbnailCache.countLimit = 220
        thumbnailCache.totalCostLimit = 40 * 1024 * 1024
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func store(_ image: UIImage, for url: URL) {
        // Never let a full-resolution cover enter the shared 720 px cache.
        // The player and blur prep use this cache too, and a multi-megapixel
        // image there turns every row into a large texture upload.
        let maxSide = max(image.size.width, image.size.height)
        guard maxSide <= 900 else { return }
        let cost = Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: url as NSURL, cost: cost)
    }

    func heroImage(for url: URL) -> UIImage? {
        heroCache.object(forKey: url as NSURL)
    }

    func card(for url: URL) -> UIImage? {
        cardCache.object(forKey: url as NSURL)
    }

    func thumbnail(for url: URL) -> UIImage? {
        thumbnailCache.object(forKey: url as NSURL)
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
    func loadImage(for url: URL, maxPixelSize: Int = 720) async -> UIImage? {
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

    /// Card-sized covers feed the 100–170 pt Home, album, artist and playlist
    /// tiles. They sit between the 720 px detail decode and the 220 px row
    /// thumbnail so a grid never pays for four large textures per playlist.
    func loadCard(for url: URL, maxPixelSize: Int = 480) async -> UIImage? {
        if let cached = card(for: url) { return cached }

        let key = url as NSURL
        taskLock.lock()
        if let existing = cardLoadingTasks[key] {
            taskLock.unlock()
            return await existing.value
        }

        let task = Task.detached(priority: .utility) {
            await Self.downsample(url: url, maxPixelSize: maxPixelSize)
        }
        cardLoadingTasks[key] = task
        taskLock.unlock()

        let image = await task.value

        taskLock.lock()
        cardLoadingTasks[key] = nil
        taskLock.unlock()

        if let image {
            let cost = Int(image.size.width * image.size.height * 4)
            cardCache.setObject(image, forKey: key, cost: cost)
        }
        return image
    }

    /// Row-sized covers stay in a smaller cache so a long song list never
    /// forces the full 720 px decode for every 44–64 pt thumbnail.
    func loadThumbnail(for url: URL, maxPixelSize: Int = 220) async -> UIImage? {
        if let cached = thumbnail(for: url) { return cached }

        let key = url as NSURL
        taskLock.lock()
        if let existing = thumbnailLoadingTasks[key] {
            taskLock.unlock()
            return await existing.value
        }

        let task = Task.detached(priority: .utility) {
            await Self.downsample(url: url, maxPixelSize: maxPixelSize)
        }
        thumbnailLoadingTasks[key] = task
        taskLock.unlock()

        let image = await task.value

        taskLock.lock()
        thumbnailLoadingTasks[key] = nil
        taskLock.unlock()

        if let image {
            let cost = Int(image.size.width * image.size.height * 4)
            thumbnailCache.setObject(image, forKey: key, cost: cost)
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
                                .init(color: .black.opacity(0.42), location: 0),
                                .init(color: .clear, location: 0.15),
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

struct PlayerGradient {
    let colors: [Color]

    static let fallback = PlayerGradient(colors: [
        Color(red: 0.035, green: 0.038, blue: 0.052),
        Color(red: 0.070, green: 0.075, blue: 0.095),
        Color(red: 0.025, green: 0.027, blue: 0.038),
        Color(red: 0.060, green: 0.055, blue: 0.080),
        Color(red: 0.095, green: 0.090, blue: 0.120),
        Color(red: 0.040, green: 0.040, blue: 0.060),
        Color(red: 0.022, green: 0.024, blue: 0.034),
        Color(red: 0.055, green: 0.050, blue: 0.072),
        Color(red: 0.020, green: 0.022, blue: 0.032)
    ])
}

struct PlayerGradientView: View {
    let gradient: PlayerGradient

    var body: some View {
        if #available(iOS 18.0, *) {
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                    [0.0, 0.5], [0.5, 0.5], [1.0, 0.5],
                    [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
                ],
                colors: gradient.colors
            )
        } else {
            ZStack {
                LinearGradient(
                    colors: [
                        gradient.colors[0],
                        gradient.colors[4],
                        gradient.colors[8]
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [
                        gradient.colors[4].opacity(0.55),
                        .clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 420
                )
            }
        }
    }
}

/// A full-screen, cover-derived wash for detail pages. It intentionally has
/// no mask or fixed-height artwork, so it cannot end in a visible cut line.
struct DetailBackdrop: View {
    let artworkURL: URL?

    @Environment(\.colorScheme) private var colorScheme
    @State private var gradient = PlayerGradient.fallback

    private var base: Color {
        Color(uiColor: .systemBackground)
    }

    var body: some View {
        ZStack {
            base

            PlayerGradientView(gradient: gradient)
                .opacity(colorScheme == .dark ? 0.76 : 0.18)
                .saturation(colorScheme == .dark ? 1.16 : 0.88)

            LinearGradient(
                stops: [
                    .init(color: base.opacity(0.58), location: 0),
                    .init(color: .clear, location: 0.22),
                    .init(color: .clear, location: 0.54),
                    .init(color: base.opacity(0.54), location: 0.82),
                    .init(color: base.opacity(0.94), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .task(id: artworkURL) {
            guard let artworkURL else {
                gradient = .fallback
                return
            }

            let next = await PlaybackBackdropCache.shared.prepareGradient(for: artworkURL)
            guard !Task.isCancelled else { return }
            gradient = next
        }
    }
}

private final class PlayerGradientBox {
    let gradient: PlayerGradient

    init(_ gradient: PlayerGradient) {
        self.gradient = gradient
    }
}

/// Pre-blurs the player backdrop once, so opening the player never pays for
/// a full-screen live blur while the zoom transition is running.
final class PlaybackBackdropCache {
    static let shared = PlaybackBackdropCache()

    private let cache = NSCache<NSURL, UIImage>()
    private let gradientCache = NSCache<NSURL, PlayerGradientBox>()
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let lock = NSLock()
    private var renders: [NSURL: Task<UIImage?, Never>] = [:]

    /// Matches the aspect of modern iPhones closely enough that the backdrop
    /// needs almost no cropping, so the cover is never magnified to fill.
    private let renderSize = CGSize(width: 720, height: 1560)

    private init() {
        cache.countLimit = 24
        cache.totalCostLimit = 48 * 1024 * 1024
        gradientCache.countLimit = 48
    }

    func gradient(for url: URL) -> PlayerGradient? {
        gradientCache.object(forKey: url as NSURL)?.gradient
    }

    /// A 3×3 colour sample of the cover. The player uses this as a mesh
    /// gradient, so the background never stretches or crops the artwork.
    func prepareGradient(for url: URL) async -> PlayerGradient {
        if let cached = gradient(for: url) { return cached }

        // A 3×3 colour sample only needs a tiny decode. Loading the original
        // file here used to put a full-resolution cover back into the row
        // cache, so every list item that reused the artwork rendered a huge
        // texture.
        guard let artwork = await ArtworkImageCache.shared.loadThumbnail(for: url) else {
            return .fallback
        }

        let sampled = await Task.detached(priority: .utility) {
            Self.makeGradient(from: artwork)
        }.value
        gradientCache.setObject(PlayerGradientBox(sampled), forKey: url as NSURL)
        return sampled
    }

    private static func makeGradient(from image: UIImage) -> PlayerGradient {
        guard let cgImage = image.cgImage else { return .fallback }

        let side = 3
        guard let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return .fallback }

        context.interpolationQuality = .medium
        context.translateBy(x: 0, y: CGFloat(side))
        context.scaleBy(x: 1, y: -1)
        context.draw(
            cgImage,
            in: CGRect(x: 0, y: 0, width: side, height: side)
        )

        guard let data = context.data else { return .fallback }
        let buffer = data.bindMemory(to: UInt8.self, capacity: side * side * 4)
        var colors: [Color] = []
        colors.reserveCapacity(side * side)

        for row in 0..<side {
            let sourceRow = side - 1 - row
            for column in 0..<side {
                let offset = (sourceRow * side + column) * 4
                colors.append(
                    Color(
                        red: Double(buffer[offset]) / 255,
                        green: Double(buffer[offset + 1]) / 255,
                        blue: Double(buffer[offset + 2]) / 255
                    )
                )
            }
        }

        return PlayerGradient(colors: colors)
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    @discardableResult
    func prepare(for url: URL) async -> UIImage? {
        if let cached = image(for: url) { return cached }

        let key = url as NSURL
        lock.lock()
        if let existing = renders[key] {
            lock.unlock()
            return await existing.value
        }

        let size = renderSize
        let ciContext = context
        let task = Task.detached(priority: .utility) { () -> UIImage? in
            guard let artwork = await ArtworkImageCache.shared.loadImage(for: url) else {
                return nil
            }
            return Self.render(artwork, size: size, context: ciContext)
        }
        renders[key] = task
        lock.unlock()

        let rendered = await task.value

        lock.lock()
        renders[key] = nil
        lock.unlock()

        guard let rendered else { return nil }
        cache.setObject(
            rendered,
            forKey: key,
            cost: Int(size.width * size.height * 4)
        )
        return rendered
    }

    private static func render(_ image: UIImage, size: CGSize, context: CIContext) -> UIImage? {
        guard image.size.width > 0,
              image.size.height > 0,
              image.size.height.isFinite,
              image.size.width.isFinite
        else { return nil }

        // Draw the full cover once at the screen's width, upright. Filling
        // the height with a crop would only show half the artwork and read as
        // zoomed in, so the cover keeps its whole frame instead.
        let coverSize = CGSize(
            width: size.width,
            height: size.width * image.size.height / image.size.width
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let cover = UIGraphicsImageRenderer(size: coverSize, format: format)
            .image { _ in
                image.draw(in: CGRect(origin: .zero, size: coverSize))
            }

        guard let cgImage = cover.cgImage else { return nil }

        let canvas = CGRect(origin: .zero, size: size)
        let originY = (size.height - coverSize.height) / 2
        let placed = CIImage(cgImage: cgImage)
            .transformed(by: CGAffineTransform(translationX: 0, y: originY))
            .clampedToExtent()

        // A smooth colour wash fills the whole screen behind everything.
        let wash = placed
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 38])
            .cropped(to: canvas)

        // The band below the cover is the cover's lower edge smeared into a
        // soft, streaky refraction. Mirror it above the cover so the top of
        // the player gets that same band instead of a darker wash derived
        // from the cover's top edge.
        let base = mirroredTopBand(wash, canvas: canvas, bandHeight: originY)

        // The cover itself stays lightly frosted so it reads as artwork rather
        // than a featureless smear.
        let detail = placed
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 7])
            .cropped(to: canvas)

        // Fade the detailed cover into the wash toward the top and bottom.
        // This is what removes the hard edge where a fill-crop used to cut the
        // artwork, and leaves a soft fold-like falloff instead.
        guard let mask = verticalDetailMask(canvas: canvas),
              let blended = CIFilter(name: "CIBlendWithMask", parameters: [
                  kCIInputImageKey: detail,
                  kCIInputBackgroundImageKey: base,
                  "inputMaskImage": mask
              ])?.outputImage
        else { return nil }

        let graded = blended
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 1.04,
                kCIInputBrightnessKey: -0.01,
                kCIInputContrastKey: 1.0
            ])
            .cropped(to: canvas)

        guard let output = context.createCGImage(graded, from: canvas) else {
            return nil
        }
        return UIImage(cgImage: output, scale: 1, orientation: .up)
    }

    /// Flips the band below the cover into the band above it. The copy is
    /// solid at the screen edge and feathered into the original wash where it
    /// meets the artwork, so the two bands read as one mirrored surface.
    private static func mirroredTopBand(
        _ wash: CIImage,
        canvas: CGRect,
        bandHeight: CGFloat
    ) -> CIImage {
        guard bandHeight > 1, bandHeight < canvas.height * 0.5 else {
            return wash
        }

        let band = CGRect(
            x: canvas.minX,
            y: canvas.minY,
            width: canvas.width,
            height: bandHeight
        )
        let mirrored = wash
            .cropped(to: band)
            .transformed(by: CGAffineTransform(scaleX: 1, y: -1))
            .transformed(by: CGAffineTransform(translationX: 0, y: canvas.maxY))

        let seamY = canvas.maxY - bandHeight
        let feather = min(bandHeight * 0.35, 170)
        guard let mask = CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: canvas.midX, y: seamY),
            "inputPoint1": CIVector(x: canvas.midX, y: seamY + feather),
            "inputColor0": CIColor.black,
            "inputColor1": CIColor.white
        ])?.outputImage?
            .clampedToExtent()
            .cropped(to: canvas),
        let banded = CIFilter(name: "CIBlendWithMask", parameters: [
            kCIInputImageKey: mirrored,
            kCIInputBackgroundImageKey: wash,
            "inputMaskImage": mask
        ])?.outputImage
        else { return wash }

        // Composite over the untouched wash so the result always covers the
        // full canvas, even if the mask filter reports only the band extent.
        return banded
            .composited(over: wash)
            .cropped(to: canvas)
    }

    /// White through the middle of the screen, fading to black at the top and
    /// bottom. Used as the detail layer's alpha mask.
    private static func verticalDetailMask(canvas: CGRect) -> CIImage? {
        let center = CIVector(x: canvas.midX, y: canvas.midY)
        let top = CIVector(x: canvas.midX, y: canvas.maxY)
        let bottom = CIVector(x: canvas.midX, y: canvas.minY)

        guard let upper = CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": center,
            "inputPoint1": top,
            "inputColor0": CIColor.white,
            "inputColor1": CIColor.black
        ])?.outputImage?.clampedToExtent().cropped(to: canvas),
        let lower = CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": center,
            "inputPoint1": bottom,
            "inputColor0": CIColor.white,
            "inputColor1": CIColor.black
        ])?.outputImage?.clampedToExtent().cropped(to: canvas)
        else { return nil }

        return upper
            .applyingFilter("CIMultiplyCompositing", parameters: [
                kCIInputBackgroundImageKey: lower
            ])
            .cropped(to: canvas)
    }
}

/// The glass lilypad mark. The asset catalog carries light and dark
/// appearances, and the PNGs are transparent so the mark can sit on paper,
/// obsidian, or artwork without a plate.
struct LiltMark: View {
    var height: CGFloat = 28

    var body: some View {
        Image("LiltMark")
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .accessibilityLabel("Lilt")
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
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

struct SectionHeader<Trailing: View>: View {
    let title: String
    private let trailing: () -> Trailing

    init(title: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 10) {
            SectionTitle(title: title)
            Spacer(minLength: 8)
            GlassGroup(spacing: 8) {
                trailing()
            }
        }
    }
}

/// One glass language for every discrete control: capsules carry words,
/// circles carry icons, and each group is wrapped in a GlassGroup at the call
/// site when several controls sit together.
struct GlassActionButton: View {
    let title: String
    var systemImage: String = "play.fill"
    var prominent = false
    var accessibilityLabel: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: prominent ? 12 : 10, weight: .semibold))
                Text(title)
                    .font(.system(size: prominent ? 15 : 12, weight: .semibold))
            }
            .foregroundStyle(.primary)
            .lineLimit(1)
            .padding(.horizontal, prominent ? 16 : 11)
            .padding(.vertical, prominent ? 11 : 7)
            .background {
                if prominent {
                    Capsule().fill(Color.primary.opacity(0.12))
                }
            }
            .nativeGlass(Capsule(), interactive: true)
            .contentShape(Capsule())
        }
        .buttonStyle(MotifPressStyle(scale: 0.96, opacity: 0.90))
        .accessibilityLabel(accessibilityLabel ?? title)
    }
}

/// The single loud control on a page. Primary actions get an ink-on-paper
/// capsule; everything else stays glass so a screen has one obvious next step.
struct LiltPrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var height: CGFloat = 44
    var expands = true
    var isEnabled = true
    var accessibilityLabel: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .bold))
                }

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(Color(uiColor: .systemBackground))
            .padding(.horizontal, 18)
            .frame(maxWidth: expands ? CGFloat.infinity : nil)
            .frame(height: height)
            .background(Color.primary, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(MotifPressStyle(scale: 0.97, opacity: 0.94))
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityLabel(accessibilityLabel ?? title)
    }
}

struct GlassIconButton: View {
    let systemImage: String
    let label: String
    var size: CGFloat = 30
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size >= 40 ? 15 : 13, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: size, height: size)
                .nativeGlass(Circle(), interactive: true)
                .contentShape(Circle())
        }
        .buttonStyle(MotifPressStyle(scale: 0.92))
        .accessibilityLabel(label)
    }
}

struct GlassPillMenuLabel: View {
    let title: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
            }

            Text(title)

            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.primary)
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .nativeGlass(Capsule(), interactive: true)
        .contentShape(Capsule())
    }
}

extension View {
    /// Groups a short row of transport buttons inside one glass pill.
    func glassTransport() -> some View {
        foregroundStyle(.primary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .nativeGlass(Capsule(), interactive: true)
    }
}

/// The mini player's progress ring, shared with the Home listening strip.
struct ArtworkProgressRing: View {
    var size: CGFloat = 38
    var cornerRadius: CGFloat = 12.5
    var tint: Color = .white

    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var progress: PlaybackProgress

    private var fraction: CGFloat {
        guard player.duration > 0 else { return 0 }
        return CGFloat(min(max(progress.elapsed / player.duration, 0), 1))
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(tint.opacity(0.16), lineWidth: 1.5)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .trim(from: 0, to: max(fraction, 0.001))
                .stroke(
                    tint.opacity(0.94),
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .animation(.linear(duration: 0.24), value: fraction)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct TrackRow: View {
    let track: Track
    var queue: [Track]? = nil
    /// A plain reference, not an environment object: a song row needs the
    /// player to start playback, never to observe it.
    let player: PlayerManager
    @Binding var showNowPlaying: Bool

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var nowPlaying: NowPlayingMarker
    @State private var downloadPulse = 0
    @State private var showInfo = false

    private var isCurrent: Bool {
        guard let currentID = nowPlaying.trackID else { return false }
        if currentID == track.id { return true }
        guard let remoteID = nowPlaying.remoteID,
              let trackRemoteID = track.remoteID
        else { return false }
        return remoteID == trackRemoteID
    }

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
                ZStack(alignment: .bottomTrailing) {
                    ArtworkView(
                        url: track.artworkURL,
                        seed: track.title + track.artist,
                        thumbnail: true
                    )
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                    Image(systemName: "play.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(width: 18, height: 18)
                        .rowControl(Circle(), dark: true)
                        .padding(3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(MotifPressStyle(scale: 0.97, opacity: 0.9))
            .accessibilityLabel("Play \(track.title)")

            VStack(alignment: .leading, spacing: 3) {
                Button {
                    player.play(track, queue: queue ?? [track])
                } label: {
                    Text(track.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(MotifPressStyle(scale: 0.99, opacity: 0.9))
                .accessibilityLabel("Play \(track.title)")

                if track.artist.isEmpty {
                    Text("Unknown artist")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    NavigationLink {
                        LibraryArtistDetailView(
                            artistName: track.artist,
                            showNowPlaying: $showNowPlaying
                        )
                    } label: {
                        Text(track.artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(track.artist), artist")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isFavorite {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isUploading || isEnriching {
                ProgressView()
                    .controlSize(.small)
                    .tint(.secondary)
            }

            HStack(spacing: 6) {
                if isCurrent {
                    PlayingWaveform(isPlaying: nowPlaying.isPlaying)
                        .frame(width: 14, height: 12)
                }

                Text(track.durationText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 2) {
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
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.primary)
                                .motifReplace()
                                .motifBounce(tick: downloadPulse)
                                .animation(.spring(response: 0.30, dampingFraction: 0.70), value: isDownloaded)
                        }
                    }
                    .frame(width: 30, height: 30)
                    .frame(width: 30, height: 38)
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
                    showInfo = true
                } label: {
                    Label("Song Info", systemImage: "info.circle")
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
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            }
            .accessibilityLabel("More")
            .accessibilityIdentifier("track.more")
            .padding(.horizontal, 3)
            .padding(.vertical, 3)
            // One live glass capsule per row is the most expensive thing in a
            // long song list while it scrolls. The menu is a dense overlay, so
            // use the blur-free row treatment the theme already provides.
            .rowControl(Capsule())
        }
        .padding(.vertical, 6)
        .sheet(isPresented: $showInfo) {
            TrackInfoView(track: track)
                .environmentObject(library)
        }
    }
}
