import Foundation

struct SharedNowPlaying: Codable, Equatable {
    struct NextItem: Codable, Equatable, Identifiable {
        var id: String
        var title: String
        var artist: String

        init(id: String, title: String, artist: String) {
            self.id = id
            self.title = title
            self.artist = artist
        }
    }

    var title: String
    var artist: String
    var album: String
    var artworkURL: String?
    var isPlaying: Bool
    var elapsed: Double
    var duration: Double
    var updatedAt: Date
    var trackID: String?
    var artworkFileName: String?
    var next: [NextItem]?

    init(
        title: String,
        artist: String,
        album: String,
        artworkURL: String?,
        isPlaying: Bool,
        elapsed: Double,
        duration: Double,
        updatedAt: Date,
        trackID: String? = nil,
        artworkFileName: String? = nil,
        next: [NextItem]? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkURL = artworkURL
        self.isPlaying = isPlaying
        self.elapsed = elapsed
        self.duration = duration
        self.updatedAt = updatedAt
        self.trackID = trackID
        self.artworkFileName = artworkFileName
        self.next = next
    }

    /// The instant the track ends, used to seed a final timeline entry so a
    /// widget cannot keep claiming "Playing" forever if the app is killed.
    var endDate: Date? {
        guard duration.isFinite, duration > 0 else { return nil }
        let remaining = max(0, duration - max(0, elapsed))
        return updatedAt.addingTimeInterval(remaining)
    }

    /// True once the anchored elapsed time has run past the track length.
    /// A widget can read a snapshot days after the app last wrote it.
    func hasEnded(at date: Date) -> Bool {
        guard let end = endDate else { return false }
        return end <= date
    }

    /// A date range the system can animate without reloading the widget.
    var timerWindow: ClosedRange<Date>? {
        guard isPlaying,
              duration.isFinite,
              duration > 0,
              elapsed.isFinite,
              elapsed >= 0,
              elapsed < duration
        else { return nil }

        let start = updatedAt.addingTimeInterval(-elapsed)
        let end = start.addingTimeInterval(duration)
        guard end > updatedAt else { return nil }
        return start...end
    }

    func ended(at date: Date) -> SharedNowPlaying {
        var copy = self
        copy.isPlaying = false
        copy.elapsed = max(0, duration)
        copy.updatedAt = date
        return copy
    }

    /// The shared container named by both targets' entitlements files. It is
    /// fixed on purpose: sideload signing tools rewrite bundle ids, and a
    /// group that followed the id would stop matching the provisioning
    /// profile after that rewrite. Keep this in step with
    /// MOTIF/MOTIF.entitlements and MOTIFWidgets/MOTIFWidgets.entitlements;
    /// the build checks all three agree.
    static let appGroup = "group.com.example.motif"

    /// False when the signed app cannot reach its shared container, which is
    /// the usual reason a sideloaded widget has nothing to draw.
    static var hasAppGroup: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) != nil
    }

    private static let storageKey = "motif.nowPlaying"

    static func save(_ snapshot: SharedNowPlaying) {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = try? JSONEncoder().encode(snapshot)
        else { return }
        defaults.set(data, forKey: storageKey)
    }

    static func load() -> SharedNowPlaying? {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = defaults.data(forKey: storageKey)
        else { return nil }
        return try? JSONDecoder().decode(SharedNowPlaying.self, from: data)
    }

    static func clear() {
        UserDefaults(suiteName: appGroup)?.removeObject(forKey: storageKey)
    }
}
