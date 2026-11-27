import Foundation
import UIKit

/// Small, app-group artwork files the widget can read without networking.
/// The app writes the current cover here; the widget only reads files.
enum SharedArtwork {
    static let nowPlayingName = "now-playing.jpg"
    private static let maximumPixelSize: CGFloat = 600

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
        save(image, named: nowPlayingName)
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
