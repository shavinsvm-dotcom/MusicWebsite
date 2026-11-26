import SwiftUI

/// Everything the library knows about one song, without exposing file paths.
struct TrackInfoView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    let track: Track

    @State private var fileSize: Int64?

    private var liveTrack: Track {
        library.tracks.first { $0.id == track.id } ?? track
    }

    private var isDownloaded: Bool {
        liveTrack.isCloud && liveTrack.mediaURL.isFileURL && library.isDownloaded(liveTrack)
    }

    private var isStreaming: Bool {
        !liveTrack.mediaURL.isFileURL
    }

    private var sourceText: String {
        switch liveTrack.source {
        case .local:
            return liveTrack.isUploadedToCloud ? "This device · uploaded" : "This device"
        case .cloud:
            return isDownloaded ? "Cloud · downloaded" : "Cloud"
        case .preview:
            return "Preview"
        }
    }

    private var formatText: String {
        let extensionName = (isStreaming ? liveTrack.streamURL?.pathExtension : nil)
            ?? liveTrack.mediaURL.pathExtension
        return extensionName.isEmpty ? "Unknown" : extensionName.uppercased()
    }

    private var sizeText: String {
        if isStreaming { return "Streamed" }
        guard let fileSize else { return "—" }
        return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    private var lyricsText: String {
        switch LyricsService.syncLevel(for: liveTrack) {
        case .wordSynced: return "Word-synced"
        case .lineSynced: return "Line-synced"
        case .plain: return "Plain text"
        case .none: return "None"
        }
    }

    private var lyricsSourceText: String? {
        switch liveTrack.lyricsSource {
        case .automatic: return "Found automatically"
        case .embedded: return "From the file"
        case .manual: return "Added by you"
        case nil: return nil
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Song") {
                    infoRow("Title", liveTrack.title)
                    infoRow("Artist", liveTrack.artist)
                    if !liveTrack.album.isEmpty, liveTrack.album != "Unknown Album" {
                        infoRow("Album", liveTrack.album)
                    }
                    if let year = liveTrack.releaseYear {
                        infoRow("Year", String(year))
                    }
                    infoRow("Duration", liveTrack.durationText)
                }

                Section("File") {
                    infoRow("Source", sourceText)
                    infoRow("Format", formatText)
                    infoRow("Size", sizeText)
                    infoRow(
                        "Added",
                        liveTrack.addedAt.formatted(date: .abbreviated, time: .omitted)
                    )
                    infoRow("Plays", String(library.playCounts[liveTrack.id] ?? 0))
                    infoRow("Favorite", library.isFavorite(liveTrack) ? "Yes" : "No")
                }

                Section("Lyrics") {
                    infoRow("Status", lyricsText)
                    if let lyricsSourceText {
                        infoRow("Source", lyricsSourceText)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle("Song Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: liveTrack.mediaURL) {
                guard liveTrack.mediaURL.isFileURL else {
                    fileSize = nil
                    return
                }

                let url = liveTrack.mediaURL
                let measured = await Task.detached(priority: .utility) {
                    try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
                }.value

                fileSize = measured.map { Int64($0) }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func infoRow(_ title: String, _ value: String) -> some View {
        LabeledContent(title) {
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}
