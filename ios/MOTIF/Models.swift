import Foundation

struct Track: Identifiable, Codable, Hashable {
    enum Source: String, Codable {
        case local
        case preview
    }

    var id: UUID = UUID()
    var title: String
    var artist: String
    var album: String
    var releaseYear: Int? = nil
    var artworkURL: URL?
    var mediaURL: URL
    var duration: Double
    var source: Source
    var remoteID: String?
    var addedAt: Date = Date()

    var isPreview: Bool { source == .preview }

    var durationText: String {
        guard duration.isFinite, duration > 0 else { return "--:--" }
        let total = Int(duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct Playlist: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var trackIDs: [UUID] = []
    var createdAt: Date = Date()
}

struct LibrarySnapshot: Codable {
    var tracks: [Track] = []
    var favoriteIDs: [UUID] = []
    var playlists: [Playlist] = []
}
