import CoreImage
import Foundation
import UIKit

/// Small, app-group artwork files the widget can read without networking.
/// The app writes covers here; the widget only reads files. Widgets cannot
/// fetch images themselves, so every cover a widget draws has to exist here.
enum SharedArtwork {
    static let nowPlayingName = "now-playing.jpg"
    static let nowPlayingBackdropName = "now-playing-backdrop.jpg"
    static let recentPrefix = "recent-"
    private static let maximumPixelSize: CGFloat = 600
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    static var directoryURL: URL? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedNowPlaying.appGroup
        ) else { return nil }

        let directory = container.appendingPathComponent("WidgetArtwork", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            return directory
        } catch {
            return nil
        }
    }

    @discardableResult
    static func saveNowPlaying(_ image: UIImage) -> String? {
        writeBackdrop(from: image)
        return save(image, named: nowPlayingName)
    }

    static func recentName(for trackID: String) -> String {
        let safe = trackID.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
        }
        return recentPrefix + String(safe) + ".jpg"
    }

    /// Skips the JPEG encode when the row already has a file; covers change
    /// rarely and this runs on every debounced library save.
    @discardableResult
    static func saveRecent(_ image: UIImage, trackID: String) -> String? {
        let name = recentName(for: trackID)
        if fileURL(named: name) != nil { return name }
        return save(image, named: name)
    }

    @discardableResult
    static func save(_ image: UIImage, named name: String) -> String? {
        guard let directory = directoryURL,
              let prepared = downsample(image),
              let data = prepared.jpegData(compressionQuality: 0.82)
        else { return nil }

        let target = directory.appendingPathComponent(name)
        do {
            try data.write(to: target, options: .atomic)
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: target.path
            )
            return name
        } catch {
            return nil
        }
    }

    static func fileURL(named name: String?) -> URL? {
        guard let name,
              !name.isEmpty,
              let directory = directoryURL
        else { return nil }

        let url = directory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func image(named name: String?) -> UIImage? {
        guard let url = fileURL(named: name) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    static func remove(named name: String?) {
        guard let url = fileURL(named: name) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Drops cached row covers that the latest snapshot no longer references.
    static func pruneRecent(keeping names: Set<String>) {
        guard let directory = directoryURL,
              let files = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
              )
        else { return }

        for file in files where file.lastPathComponent.hasPrefix(recentPrefix) {
            if !names.contains(file.lastPathComponent) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    /// Blurring a full-size cover inside a widget is expensive enough to risk
    /// a skipped render, so it happens once here and the widget just scales a
    /// tiny JPEG.
    private static func writeBackdrop(from image: UIImage) {
        guard let source = CIImage(image: image) else { return }
        let extent = source.extent
        guard extent.width > 1, extent.height > 1 else { return }

        let target: CGFloat = 96
        let scale = max(target / extent.width, target / extent.height)
        let scaled = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let blurred = scaled
            .clampedToExtent()
            .applyingGaussianBlur(sigma: 9)
            .cropped(to: scaled.extent)

        guard let cgImage = context.createCGImage(blurred, from: scaled.extent) else { return }
        save(UIImage(cgImage: cgImage), named: nowPlayingBackdropName)
    }

    private static func downsample(_ image: UIImage) -> UIImage? {
        let width = image.size.width
        let height = image.size.height
        guard width > 0, height > 0, width.isFinite, height.isFinite else {
            return nil
        }

        let longest = max(width, height)
        guard longest > maximumPixelSize else { return image }

        let scale = maximumPixelSize / longest
        let size = CGSize(
            width: max(1, floor(width * scale)),
            height: max(1, floor(height * scale))
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
