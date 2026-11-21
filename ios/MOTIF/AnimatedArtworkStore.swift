import AVFoundation
import CoreImage
import CoreVideo
import Foundation
import UIKit

enum AnimatedArtworkAspect: String {
    case square = "1x1"
    case tall = "3x4"

    var pixelSize: CGSize {
        switch self {
        case .square: return CGSize(width: 720, height: 720)
        case .tall: return CGSize(width: 720, height: 960)
        }
    }
}

/// Builds short, seamlessly looping animated artwork from a cover. iOS 26 asks
/// for these lazily through `MPMediaItemAnimatedArtwork` and uses the tall
/// variant for the full-screen Lock Screen now-playing artwork.
final class AnimatedArtworkStore {
    static let shared = AnimatedArtworkStore()

    private struct Composition {
        let size: CGSize
        let background: CIImage?
        let foreground: CIImage
    }

    private let directory: URL
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let previewCache = NSCache<NSString, UIImage>()
    private let lock = NSLock()
    private var renders: [String: Task<URL?, Never>] = [:]

    private static let frameRate: Int32 = 24
    private static let durationSeconds = 8
    private static let maxCachedVideos = 12
    /// Bump when the generated look changes so the system and the disk cache
    /// pick up the new video instead of reusing an old render.
    private static let renderVersion = "2"

    private init() {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        directory = base.appendingPathComponent("AnimatedArtwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        previewCache.countLimit = 24
        previewCache.totalCostLimit = 64 * 1024 * 1024
    }

    /// Stable identifier for a cover, safe to use in a file name.
    func artworkID(for url: URL) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in url.absoluteString.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return "\(String(hash, radix: 16))-\(Self.renderVersion)"
    }

    /// The first frame of the video. The system uses it while the video loads
    /// and whenever motion is unavailable, so it must share the video's aspect.
    func preview(
        image: UIImage,
        artworkID: String,
        aspect: AnimatedArtworkAspect,
        requestedSize: CGSize
    ) -> UIImage? {
        _ = requestedSize

        let key = "\(artworkID)-\(aspect.rawValue)" as NSString
        if let cached = previewCache.object(forKey: key) { return cached }

        guard let composition = makeComposition(image: image, aspect: aspect) else {
            return nil
        }
        let frame = apply(progress: 0, to: composition)
        guard let cgImage = context.createCGImage(
            frame,
            from: CGRect(origin: .zero, size: composition.size)
        ) else { return nil }

        let output = UIImage(cgImage: cgImage, scale: 1, orientation: .up)
        previewCache.setObject(
            output,
            forKey: key,
            cost: Int(composition.size.width * composition.size.height * 4)
        )
        return output
    }

    /// A local looping video for the requested aspect. Low Power Mode and
    /// Reduce Motion are left to the system's preview-image fallback.
    func video(
        image: UIImage,
        artworkID: String,
        aspect: AnimatedArtworkAspect
    ) async -> URL? {
        guard !ProcessInfo.processInfo.isLowPowerModeEnabled,
              !UIAccessibility.isReduceMotionEnabled
        else { return nil }

        let key = "\(artworkID)-\(aspect.rawValue)"
        let output = directory.appendingPathComponent("\(key).mp4")
        if FileManager.default.fileExists(atPath: output.path) { return output }

        lock.lock()
        if let existing = renders[key] {
            lock.unlock()
            return await existing.value
        }
        let task = Task.detached(priority: .utility) { [weak self] () -> URL? in
            guard let self else { return nil }
            return self.renderVideo(
                image: image,
                artworkID: artworkID,
                aspect: aspect,
                to: output
            )
        }
        renders[key] = task
        lock.unlock()

        let result = await task.value

        lock.lock()
        renders[key] = nil
        lock.unlock()

        if result != nil {
            pruneVideos()
        }
        return result
    }

    /// Generates the Lock Screen variant before the system asks for it.
    func warm(image: UIImage, artworkID: String, aspect: AnimatedArtworkAspect) {
        Task.detached(priority: .utility) { [weak self] in
            // Let playback and the player UI settle before spending time on
            // the video. If the system asks first, it shares the same render.
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            _ = await self?.video(
                image: image,
                artworkID: artworkID,
                aspect: aspect
            )
        }
    }

    private func makeComposition(
        image: UIImage,
        aspect: AnimatedArtworkAspect
    ) -> Composition? {
        guard let cgImage = image.cgImage else { return nil }

        let size = aspect.pixelSize
        let canvas = CGRect(origin: .zero, size: size)
        let source = CIImage(cgImage: cgImage)
        let sourceSize = source.extent.size
        guard sourceSize.width > 1, sourceSize.height > 1 else { return nil }

        let normalized = source.transformed(
            by: CGAffineTransform(
                translationX: -source.extent.minX,
                y: -source.extent.minY
            )
        )

        switch aspect {
        case .square:
            let foreground = normalized
                .transformed(by: fillTransform(from: sourceSize, to: size))
                .cropped(to: canvas)
            return Composition(size: size, background: nil, foreground: foreground)

        case .tall:
            let filled = normalized
                .transformed(by: fillTransform(from: sourceSize, to: size))
                .clampedToExtent()
            let background = filled
                .applyingFilter("CIGaussianBlur", parameters: [
                    kCIInputRadiusKey: 34
                ])
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputBrightnessKey: -0.08,
                    kCIInputSaturationKey: 1.05
                ])
                .cropped(to: canvas)

            let maxSide = size.width
            let fit = min(maxSide / sourceSize.width, maxSide / sourceSize.height)
            let fitted = CGSize(
                width: sourceSize.width * fit,
                height: sourceSize.height * fit
            )
            let foreground = normalized
                .transformed(by: CGAffineTransform(scaleX: fit, y: fit))
                .transformed(by: CGAffineTransform(
                    translationX: (size.width - fitted.width) / 2,
                    y: (size.height - fitted.height) / 2
                ))
            return Composition(size: size, background: background, foreground: foreground)
        }
    }

    private func apply(progress: Double, to composition: Composition) -> CIImage {
        let canvas = CGRect(origin: .zero, size: composition.size)
        let center = CGPoint(x: canvas.midX, y: canvas.midY)

        // A slow Ken Burns push: enough movement to read on a Lock Screen,
        // still restrained enough to loop without feeling like a slideshow.
        let scale = 1.05 + 0.10 * progress
        let dx = (progress - 0.5) * composition.size.width * 0.028
        let dy = (progress - 0.5) * composition.size.height * 0.020
        let angle = (progress - 0.5) * 0.6 * .pi / 180

        var transform = CGAffineTransform(
            translationX: center.x + dx,
            y: center.y + dy
        )
        transform = transform.rotated(by: angle)
        transform = transform.scaledBy(x: scale, y: scale)
        transform = transform.translatedBy(x: -center.x, y: -center.y)

        let animated = composition.foreground.transformed(by: transform)
        guard let background = composition.background else {
            return animated.cropped(to: canvas)
        }

        // Drift the blurred bed the other way for a little depth. It stays
        // larger than the frame, so the edges never come into view.
        let backgroundScale = 1.05 + 0.04 * progress
        var backgroundTransform = CGAffineTransform(
            translationX: center.x - dx * 0.35,
            y: center.y - dy * 0.35
        )
        backgroundTransform = backgroundTransform.scaledBy(
            x: backgroundScale,
            y: backgroundScale
        )
        backgroundTransform = backgroundTransform.translatedBy(
            x: -center.x,
            y: -center.y
        )
        let animatedBackground = background.transformed(by: backgroundTransform)
        return animated.composited(over: animatedBackground).cropped(to: canvas)
    }

    private func fillTransform(from source: CGSize, to target: CGSize) -> CGAffineTransform {
        let scale = max(
            target.width / max(source.width, 1),
            target.height / max(source.height, 1)
        )
        var transform = CGAffineTransform(scaleX: scale, y: scale)
        transform.tx = (target.width - source.width * scale) / 2
        transform.ty = (target.height - source.height * scale) / 2
        return transform
    }

    private func renderVideo(
        image: UIImage,
        artworkID: String,
        aspect: AnimatedArtworkAspect,
        to output: URL
    ) -> URL? {
        guard let composition = makeComposition(image: image, aspect: aspect) else {
            return nil
        }

        let size = composition.size
        let width = Int(size.width)
        let height = Int(size.height)
        let temp = directory.appendingPathComponent(
            "\(artworkID)-\(aspect.rawValue)-\(UUID().uuidString).mp4"
        )
        try? FileManager.default.removeItem(at: temp)

        guard let writer = try? AVAssetWriter(outputURL: temp, fileType: .mp4) else {
            return nil
        }

        let compression: [String: Any] = [
            AVVideoAverageBitRateKey: 4_000_000,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            AVVideoExpectedSourceFrameRateKey: Self.frameRate,
            AVVideoMaxKeyFrameIntervalKey: Int(Self.frameRate) * 2
        ]
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: compression
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false

        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: attributes
        )

        guard writer.canAdd(input) else { return nil }
        writer.add(input)
        guard writer.startWriting() else {
            try? FileManager.default.removeItem(at: temp)
            return nil
        }
        writer.startSession(atSourceTime: .zero)

        let frameCount = Int(Self.frameRate) * Self.durationSeconds
        let bounds = CGRect(origin: .zero, size: size)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        for index in 0..<frameCount {
            var waited = 0
            while !input.isReadyForMoreMediaData {
                if writer.status != .writing || waited > 5_000 {
                    writer.cancelWriting()
                    try? FileManager.default.removeItem(at: temp)
                    return nil
                }
                Thread.sleep(forTimeInterval: 0.004)
                waited += 1
            }

            guard let pool = adaptor.pixelBufferPool else {
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: temp)
                return nil
            }
            var buffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer) == kCVReturnSuccess,
                  let buffer
            else {
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: temp)
                return nil
            }

            // A cosine ping-pong keeps the first and last frames identical, so
            // the system's loop has no visible jump.
            let progress = (1 - cos(2.0 * Double.pi * Double(index) / Double(frameCount))) / 2
            let frame = apply(progress: progress, to: composition)
            context.render(
                frame,
                to: buffer,
                bounds: bounds,
                colorSpace: colorSpace
            )

            let time = CMTime(value: CMTimeValue(index), timescale: Self.frameRate)
            guard adaptor.append(buffer, withPresentationTime: time) else {
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: temp)
                return nil
            }
        }

        input.markAsFinished()
        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting { semaphore.signal() }
        semaphore.wait()

        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: temp)
            return nil
        }

        try? FileManager.default.removeItem(at: output)
        do {
            try FileManager.default.moveItem(at: temp, to: output)
            return output
        } catch {
            try? FileManager.default.removeItem(at: temp)
            return nil
        }
    }

    private func pruneVideos() {
        let manager = FileManager.default
        guard let urls = try? manager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let videos = urls.filter { $0.pathExtension == "mp4" }
        guard videos.count > Self.maxCachedVideos else { return }

        let sorted = videos.sorted { lhs, rhs in
            let left = (try? lhs.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate) ?? .distantPast
            let right = (try? rhs.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate) ?? .distantPast
            return left > right
        }

        for url in sorted.dropFirst(Self.maxCachedVideos) {
            try? manager.removeItem(at: url)
        }
    }
}
