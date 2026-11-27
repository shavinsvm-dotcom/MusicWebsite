import SwiftUI
import UIKit
import WidgetKit

@main
struct MOTIFWidgetBundle: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        MOTIFNowPlayingWidget()
        MOTIFLibraryWidget()
    }
}

// MARK: - Sample data

private enum WidgetSamples {
    static let nowPlaying = SharedNowPlaying(
        title: "Midnight City",
        artist: "M83",
        album: "Hurry Up, We’re Dreaming",
        artworkURL: nil,
        isPlaying: true,
        elapsed: 78,
        duration: 244,
        updatedAt: Date(),
        trackID: "sample-track",
        artworkFileName: nil,
        next: [
            .init(id: "sample-next-1", title: "Reunion", artist: "M83"),
            .init(id: "sample-next-2", title: "Wait", artist: "M83"),
            .init(id: "sample-next-3", title: "Steve McQueen", artist: "M83")
        ]
    )

    static let library: SharedLibrarySnapshot = {
        let recent = [
            SharedLibrarySnapshot.Item(id: "sample-1", title: "Midnight City", artist: "M83", artworkURL: nil),
            SharedLibrarySnapshot.Item(id: "sample-2", title: "Alright", artist: "Kendrick Lamar", artworkURL: nil),
            SharedLibrarySnapshot.Item(id: "sample-3", title: "Everything In Its Right Place", artist: "Radiohead", artworkURL: nil),
            SharedLibrarySnapshot.Item(id: "sample-4", title: "New York, I Love You", artist: "LCD Soundsystem", artworkURL: nil),
            SharedLibrarySnapshot.Item(id: "sample-5", title: "Motion Picture Soundtrack", artist: "Radiohead", artworkURL: nil),
            SharedLibrarySnapshot.Item(id: "sample-6", title: "Weird Fishes / Arpeggi", artist: "Radiohead", artworkURL: nil)
        ]
        return SharedLibrarySnapshot(
            trackCount: 428,
            playlistCount: 12,
            recent: recent,
            playlistName: "Late Night",
            playlistArtworkURL: nil,
            favoriteCount: 64,
            mostPlayed: Array(recent.prefix(4)),
            updatedAt: Date()
        )
    }()
}

// MARK: - Now Playing

struct NowPlayingEntry: TimelineEntry {
    let date: Date
    let snapshot: SharedNowPlaying?
}

struct NowPlayingProvider: TimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry(date: Date(), snapshot: WidgetSamples.nowPlaying)
    }

    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
        completion(NowPlayingEntry(
            date: Date(),
            snapshot: context.isPreview ? WidgetSamples.nowPlaying : SharedNowPlaying.load()
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        let now = Date()
        guard let snapshot = SharedNowPlaying.load() else {
            completion(Timeline(
                entries: [NowPlayingEntry(date: now, snapshot: nil)],
                policy: .after(now.addingTimeInterval(900))
            ))
            return
        }

        var entries = [NowPlayingEntry(date: now, snapshot: snapshot)]
        var nextRefresh = now.addingTimeInterval(900)

        // The app reloads on track/play/seek changes. This end entry is the
        // safety net if Lilt disappears before it can update the widget.
        if snapshot.isPlaying,
           let end = snapshot.endDate,
           end > now,
           end.timeIntervalSince(now) < 12 * 60 * 60 {
            entries.append(NowPlayingEntry(
                date: end,
                snapshot: snapshot.ended(at: end)
            ))
            nextRefresh = end.addingTimeInterval(30)
        }

        completion(Timeline(entries: entries, policy: .after(nextRefresh)))
    }
}

struct MOTIFNowPlayingWidget: Widget {
    let kind = "MOTIFNowPlaying"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NowPlayingProvider()) { entry in
            MOTIFNowPlayingWidgetView(entry: entry)
        }
        .configurationDisplayName("Now Playing")
        .description("Your current Lilt track, live progress, and what is coming next.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

private struct MOTIFNowPlayingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NowPlayingEntry

    @ViewBuilder
    var body: some View {
        switch family {
        case .accessoryCircular:
            accessoryCircular
        case .accessoryRectangular:
            accessoryRectangular
        case .accessoryInline:
            accessoryInline
        default:
            fullWidget
        }
    }

    private var fullWidget: some View {
        ZStack {
            NowPlayingBackdrop(snapshot: entry.snapshot)

            if let snapshot = entry.snapshot {
                if family == .systemLarge {
                    largeContent(snapshot)
                } else if family == .systemMedium {
                    mediumContent(snapshot)
                } else {
                    smallContent(snapshot)
                }
            } else {
                emptyState
            }
        }
        .widgetBackground(Color(red: 0.06, green: 0.06, blue: 0.08))
        .widgetURL(URL(string: "motif://nowplaying"))
    }

    private func smallContent(_ snapshot: SharedNowPlaying) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                ArtworkThumbnail(
                    fileName: snapshot.artworkFileName,
                    remoteURL: snapshot.artworkURL,
                    size: 44
                )

                Spacer(minLength: 0)

                Image(systemName: snapshot.isPlaying ? "waveform" : "pause.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Text(snapshot.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)

            Text(snapshot.artist)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            progressBlock(snapshot, compact: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func mediumContent(_ snapshot: SharedNowPlaying) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 12) {
                ArtworkThumbnail(
                    fileName: snapshot.artworkFileName,
                    remoteURL: snapshot.artworkURL,
                    size: 58
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(snapshot.title)
                        .font(.system(size: 16, weight: .bold))
                        .lineLimit(2)
                    Text(snapshot.artist)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if !snapshot.album.isEmpty {
                        Text(snapshot.album)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: snapshot.isPlaying ? "waveform" : "pause.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 3)
            }

            Spacer(minLength: 0)

            progressBlock(snapshot)

            if let next = snapshot.next?.first {
                HStack(spacing: 5) {
                    Image(systemName: "text.line.last.and.arrowtriangle.forward")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Next · \(next.title)")
                        .font(.system(size: 9, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func largeContent(_ snapshot: SharedNowPlaying) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                ArtworkThumbnail(
                    fileName: snapshot.artworkFileName,
                    remoteURL: snapshot.artworkURL,
                    size: 92
                )

                VStack(alignment: .leading, spacing: 5) {
                    Text(snapshot.title)
                        .font(.system(size: 21, weight: .bold))
                        .lineLimit(2)
                    Text(snapshot.artist)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if !snapshot.album.isEmpty {
                        Text(snapshot.album)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: snapshot.isPlaying ? "waveform" : "pause.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }

            progressBlock(snapshot)

            if let next = snapshot.next, !next.isEmpty {
                Divider()
                    .overlay(Color.white.opacity(0.14))

                VStack(alignment: .leading, spacing: 7) {
                    Text("UP NEXT")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(.secondary)

                    ForEach(Array(next.prefix(3))) { item in
                        HStack(spacing: 8) {
                            Image(systemName: "music.note")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .frame(width: 11)
                            Text(item.title)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text(item.artist)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func progressBlock(_ snapshot: SharedNowPlaying, compact: Bool = false) -> some View {
        VStack(spacing: 6) {
            progressBar(snapshot)

            HStack(spacing: 3) {
                Text(snapshot.isPlaying ? "Playing" : "Paused")
                    .lineLimit(1)

                Spacer(minLength: 2)

                if compact {
                    compactTime(snapshot)
                } else if let window = snapshot.timerWindow {
                    Text(timerInterval: window, countsDown: false)
                    Text("·")
                    Text(timerInterval: window, countsDown: true)
                } else {
                    Text(timeText(snapshot.elapsed))
                    Text("·")
                    Text(timeText(max(snapshot.duration - snapshot.elapsed, 0)))
                }
            }
            .font(.system(size: 9, weight: .medium).monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private func compactTime(_ snapshot: SharedNowPlaying) -> some View {
        Group {
            if let window = snapshot.timerWindow {
                Text(timerInterval: window, countsDown: true)
            } else {
                Text(timeText(max(snapshot.duration - snapshot.elapsed, 0)))
            }
        }
        .lineLimit(1)
    }

    @ViewBuilder
    private func progressBar(_ snapshot: SharedNowPlaying) -> some View {
        if let window = snapshot.timerWindow {
            ProgressView(timerInterval: window, countsDown: false)
                .tint(.primary)
                .labelsHidden()
        } else {
            ProgressView(value: progress(snapshot))
                .tint(.primary)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: "waveform")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.secondary)
            Text("lilt")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .tracking(-0.5)
            Text("Play a song to see it here.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(16)
    }

    private var accessoryCircular: some View {
        ZStack {
            AccessoryWidgetBackground()

            if let snapshot = entry.snapshot,
               let image = SharedArtwork.image(named: snapshot.artworkFileName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 38, height: 38)
                    .clipShape(Circle())
            } else {
                Image(systemName: entry.snapshot?.isPlaying == true ? "waveform" : "pause.fill")
                    .font(.system(size: 18, weight: .semibold))
            }
        }
        .widgetAccentable()
        .widgetURL(URL(string: "motif://nowplaying"))
    }

    private var accessoryRectangular: some View {
        HStack(spacing: 8) {
            if let snapshot = entry.snapshot {
                ArtworkThumbnail(
                    fileName: snapshot.artworkFileName,
                    remoteURL: nil,
                    size: 30
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(snapshot.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(snapshot.artist)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    progressBar(snapshot)
                        .frame(height: 3)
                }
            } else {
                Text("Lilt · Nothing playing")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .widgetURL(URL(string: "motif://nowplaying"))
    }

    private var accessoryInline: some View {
        Text(inlineText)
            .widgetURL(URL(string: "motif://nowplaying"))
    }

    private var inlineText: String {
        guard let snapshot = entry.snapshot else { return "Lilt · Nothing playing" }
        let prefix = snapshot.isPlaying ? "Playing · " : ""
        return "\(prefix)\(snapshot.title) · \(snapshot.artist)"
    }

    private func progress(_ snapshot: SharedNowPlaying) -> Double {
        guard snapshot.duration > 0 else { return 0 }
        return min(1, max(0, snapshot.elapsed / snapshot.duration))
    }

    private func timeText(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let value = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

// MARK: - Library / Recently Played

struct LibraryEntry: TimelineEntry {
    let date: Date
    let snapshot: SharedLibrarySnapshot?
}

struct LibraryProvider: TimelineProvider {
    func placeholder(in context: Context) -> LibraryEntry {
        LibraryEntry(date: Date(), snapshot: WidgetSamples.library)
    }

    func getSnapshot(in context: Context, completion: @escaping (LibraryEntry) -> Void) {
        completion(LibraryEntry(
            date: Date(),
            snapshot: context.isPreview ? WidgetSamples.library : SharedLibrarySnapshot.load()
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LibraryEntry>) -> Void) {
        let now = Date()
        completion(Timeline(
            entries: [LibraryEntry(date: now, snapshot: SharedLibrarySnapshot.load())],
            policy: .after(now.addingTimeInterval(1_800))
        ))
    }
}

struct MOTIFLibraryWidget: Widget {
    let kind = "MOTIFLibrary"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LibraryProvider()) { entry in
            MOTIFLibraryWidgetView(entry: entry)
        }
        .configurationDisplayName("Recently Played")
        .description("Jump back into the songs you have played most recently.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct MOTIFLibraryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LibraryEntry

    var body: some View {
        ZStack {
            LibraryBackdrop()

            if let snapshot = entry.snapshot {
                if family == .systemLarge {
                    largeContent(snapshot)
                } else if family == .systemMedium {
                    mediumContent(snapshot)
                } else {
                    smallContent(snapshot)
                }
            } else {
                emptyState
            }
        }
        .widgetBackground(Color(red: 0.06, green: 0.06, blue: 0.08))
        .widgetURL(URL(string: "motif://library"))
    }

    private func smallContent(_ snapshot: SharedLibrarySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header(snapshot)

            Text("\(snapshot.trackCount)")
                .font(.system(size: 30, weight: .bold))
                .tracking(-0.8)
            Text(snapshot.trackCount == 1 ? "song" : "songs")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            if let first = snapshot.recent.first {
                HStack(spacing: 8) {
                    ArticleArtwork(item: first, size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(first.title)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                        Text(first.artist)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } else {
                Text("Play something to fill this.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func mediumContent(_ snapshot: SharedLibrarySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header(snapshot)
                .padding(.bottom, 2)

            ForEach(Array(snapshot.recent.prefix(3))) { item in
                recentRow(item)
            }

            Spacer(minLength: 0)

            footer(snapshot)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func largeContent(_ snapshot: SharedLibrarySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            header(snapshot)

            ForEach(Array(snapshot.recent.prefix(6))) { item in
                recentRow(item)
            }

            Spacer(minLength: 0)

            footer(snapshot)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func header(_ snapshot: SharedLibrarySnapshot) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("RECENTLY PLAYED")
                .font(.system(size: 9, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text("\(snapshot.trackCount) songs")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func recentRow(_ item: SharedLibrarySnapshot.Item) -> some View {
        if let url = playURL(item) {
            Link(destination: url) {
                row(item)
            }
        } else {
            row(item)
        }
    }

    private func row(_ item: SharedLibrarySnapshot.Item) -> some View {
        HStack(spacing: 8) {
            ArticleArtwork(item: item, size: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Text(item.artist)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "play.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private func footer(_ snapshot: SharedLibrarySnapshot) -> some View {
        HStack(spacing: 6) {
            Text("\(snapshot.playlistCount) playlists")
            if let favorites = snapshot.favoriteCount {
                Text("·")
                Text("\(favorites) favorites")
            }
            if let playlist = snapshot.playlistName, !playlist.isEmpty {
                Text("·")
                Text(playlist)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .semibold))
        }
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(.tertiary)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: "square.stack")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.secondary)
            Text("Your library")
                .font(.system(size: 16, weight: .bold))
            Text("Open Lilt and play something to see recent songs here.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(16)
    }

    private func playURL(_ item: SharedLibrarySnapshot.Item) -> URL? {
        guard UUID(uuidString: item.id) != nil else { return nil }
        return URL(string: "motif://play/\(item.id)")
    }
}

// MARK: - Shared artwork views

private struct ArtworkThumbnail: View {
    let fileName: String?
    let remoteURL: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let image = SharedArtwork.image(named: fileName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let remoteURL, let url = URL(string: remoteURL) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
    }

    private var fallback: some View {
        RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
            .fill(Color.secondary.opacity(0.16))
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: max(9, size * 0.28), weight: .semibold))
                    .foregroundStyle(.secondary)
            }
    }
}

private struct ArticleArtwork: View {
    let item: SharedLibrarySnapshot.Item
    let size: CGFloat

    var body: some View {
        ArtworkThumbnail(
            fileName: item.artworkFileName,
            remoteURL: item.artworkURL,
            size: size
        )
    }
}

private struct NowPlayingBackdrop: View {
    let snapshot: SharedNowPlaying?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.10, blue: 0.12),
                    Color(red: 0.04, green: 0.04, blue: 0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let snapshot {
                if let image = SharedArtwork.image(named: snapshot.artworkFileName) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 28)
                        .opacity(0.66)
                } else if let value = snapshot.artworkURL,
                          let url = URL(string: value) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable()
                                .scaledToFill()
                                .blur(radius: 28)
                                .opacity(0.66)
                        } else {
                            Color.clear
                        }
                    }
                }
            }

            Color.black.opacity(0.24)
        }
        .clipped()
    }
}

private struct LibraryBackdrop: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.10, green: 0.10, blue: 0.12),
                Color(red: 0.04, green: 0.04, blue: 0.05)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private extension View {
    @ViewBuilder
    func widgetBackground(_ color: Color) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            containerBackground(for: .widget) { color }
        } else {
            background(color)
        }
    }
}
