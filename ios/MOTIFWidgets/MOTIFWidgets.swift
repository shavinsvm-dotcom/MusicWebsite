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
            snapshot: context.isPreview ? WidgetSamples.nowPlaying : Self.current()
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        let now = Date()
        guard let snapshot = Self.current() else {
            completion(Timeline(
                entries: [NowPlayingEntry(date: now, snapshot: nil)],
                policy: .after(now.addingTimeInterval(900))
            ))
            return
        }

        let current = snapshot.isPlaying && snapshot.hasEnded(at: now)
            ? snapshot.ended(at: now)
            : snapshot
        var entries = [NowPlayingEntry(date: now, snapshot: current)]
        var nextRefresh = now.addingTimeInterval(900)

        // The app reloads on track/play/seek changes. This end entry is the
        // safety net if Lilt disappears before it can update the widget.
        if current.isPlaying,
           let end = current.endDate,
           end > now,
           end.timeIntervalSince(now) < 12 * 60 * 60 {
            entries.append(NowPlayingEntry(date: end, snapshot: current.ended(at: end)))
            nextRefresh = end.addingTimeInterval(30)
        }

        completion(Timeline(entries: entries, policy: .after(nextRefresh)))
    }

    /// A stale snapshot can still claim it is playing long after the app died.
    private static func current() -> SharedNowPlaying? {
        guard let snapshot = SharedNowPlaying.load() else { return nil }
        if snapshot.isPlaying, snapshot.hasEnded(at: Date()) {
            return snapshot.ended(at: Date())
        }
        return snapshot
    }
}

struct MOTIFNowPlayingWidget: Widget {
    let kind = "MOTIFNowPlaying"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NowPlayingProvider()) { entry in
            NowPlayingWidgetView(entry: entry)
        }
        .configurationDisplayName("Now Playing")
        .description("The song in your ears, its live progress, and what comes next.")
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

private struct NowPlayingWidgetView: View {
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
            homeScreen
        }
    }

    // MARK: Home Screen

    private var homeScreen: some View {
        ZStack {
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
        .widgetContainerBackground {
            NowPlayingBackground(artworkName: entry.snapshot?.artworkFileName)
        }
        .widgetURL(URL(string: "motif://nowplaying"))
    }

    private func smallContent(_ snapshot: SharedNowPlaying) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 8) {
                ArtworkTile(
                    fileName: snapshot.artworkFileName,
                    seed: snapshot.title,
                    size: 42,
                    corner: 0.2
                )
                Spacer(minLength: 0)
                PlaybackGlyph(isPlaying: snapshot.isPlaying, size: 12)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                Text(snapshot.artist)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                progressBar(snapshot)
                timeLabel(snapshot)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func mediumContent(_ snapshot: SharedNowPlaying) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ArtworkTile(
                fileName: snapshot.artworkFileName,
                seed: snapshot.title,
                size: 76,
                corner: 0.16
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .top, spacing: 6) {
                    Text(snapshot.title)
                        .font(.system(size: 16, weight: .bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                    Spacer(minLength: 0)
                    PlaybackGlyph(isPlaying: snapshot.isPlaying, size: 11)
                }

                Text(snapshot.artist)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if !snapshot.album.isEmpty {
                    Text(snapshot.album)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .opacity(0.8)
                        .lineLimit(1)
                }

                Spacer(minLength: 2)

                HStack(spacing: 6) {
                    progressBar(snapshot)
                    timeLabel(snapshot)
                }

                if let next = snapshot.next?.first {
                    upNextLine(next)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func largeContent(_ snapshot: SharedNowPlaying) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 14) {
                ArtworkTile(
                    fileName: snapshot.artworkFileName,
                    seed: snapshot.title,
                    size: 86,
                    corner: 0.14
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(snapshot.title)
                        .font(.system(size: 20, weight: .bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Text(snapshot.artist)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if !snapshot.album.isEmpty {
                        Text(snapshot.album)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .opacity(0.8)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                PlaybackGlyph(isPlaying: snapshot.isPlaying, size: 13)
                    .padding(.top, 2)
            }

            HStack(spacing: 7) {
                progressBar(snapshot)
                timeLabel(snapshot)
            }

            if let next = snapshot.next, !next.isEmpty {
                Divider()
                    .overlay(Color.primary.opacity(0.12))

                VStack(alignment: .leading, spacing: 7) {
                    Text("UP NEXT")
                        .font(.system(size: 8.5, weight: .bold))
                        .tracking(1.0)
                        .foregroundStyle(.secondary)

                    ForEach(Array(next.prefix(3))) { item in
                        HStack(spacing: 7) {
                            Image(systemName: "music.note")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 10)
                            Text(item.title)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                            Spacer(minLength: 4)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func upNextLine(_ item: SharedNowPlaying.NextItem) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.turn.down.right")
                .font(.system(size: 8, weight: .semibold))
            Text("Next · \(item.title)")
                .font(.system(size: 9, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "waveform")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(.secondary)

            Text("Nothing playing")
                .font(.system(size: 13, weight: .semibold))

            Text(SharedNowPlaying.hasAppGroup
                 ? "Open Lilt and play a song."
                 : "Lilt cannot share data with widgets. Open Lilt › Settings › Widgets.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Lock Screen

    private var accessoryCircular: some View {
        ZStack {
            AccessoryWidgetBackground()

            if let snapshot = entry.snapshot,
               let image = SharedArtwork.image(named: snapshot.artworkFileName) {
                Image(uiImage: image)
                    .resizable()
                    .accentedFullColor()
                    .scaledToFill()
                    .frame(width: 34, height: 34)
                    .clipShape(Circle())
            } else {
                Image(systemName: entry.snapshot?.isPlaying == true ? "waveform" : "pause.fill")
                    .font(.system(size: 17, weight: .semibold))
            }
        }
        .widgetAccentable()
    }

    private var accessoryRectangular: some View {
        HStack(spacing: 8) {
            if let snapshot = entry.snapshot {
                ArtworkTile(
                    fileName: snapshot.artworkFileName,
                    seed: snapshot.title,
                    size: 32,
                    corner: 0.18
                )

                VStack(alignment: .leading, spacing: 2) {
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
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lilt")
                        .font(.headline)
                    Text("Nothing playing")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var accessoryInline: some View {
        Text(inlineText)
    }

    private var inlineText: String {
        guard let snapshot = entry.snapshot else { return "Lilt · Nothing playing" }
        let prefix = snapshot.isPlaying ? "Playing · " : ""
        return "\(prefix)\(snapshot.title) · \(snapshot.artist)"
    }

    // MARK: Progress

    @ViewBuilder
    private func progressBar(_ snapshot: SharedNowPlaying) -> some View {
        if let window = activeWindow(snapshot) {
            ProgressView(timerInterval: window, countsDown: false)
                .progressViewStyle(.linear)
                .labelsHidden()
        } else {
            ProgressView(value: progress(snapshot))
                .progressViewStyle(.linear)
                .labelsHidden()
        }
    }

    @ViewBuilder
    private func timeLabel(_ snapshot: SharedNowPlaying) -> some View {
        Group {
            if let window = activeWindow(snapshot) {
                Text(timerInterval: window, countsDown: true)
            } else {
                Text(timeText(max(snapshot.duration - snapshot.elapsed, 0)))
            }
        }
        .font(.system(size: 9, weight: .semibold).monospacedDigit())
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    /// Only animate against a window that is still running, so a stale
    /// snapshot cannot pin the widget to 0:00.
    private func activeWindow(_ snapshot: SharedNowPlaying) -> ClosedRange<Date>? {
        guard let window = snapshot.timerWindow, window.upperBound > entry.date else {
            return nil
        }
        return window
    }

    private func progress(_ snapshot: SharedNowPlaying) -> Double {
        guard snapshot.duration.isFinite, snapshot.duration > 0 else { return 0 }
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
            LibraryWidgetView(entry: entry)
        }
        .configurationDisplayName("Recently Played")
        .description("Jump back into the songs you have played most recently.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct LibraryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LibraryEntry

    var body: some View {
        ZStack {
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
        .widgetContainerBackground {
            LibraryBackground()
        }
        .widgetURL(URL(string: "motif://library"))
    }

    private func smallContent(_ snapshot: SharedLibrarySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let first = snapshot.recent.first {
                ArtworkTile(
                    fileName: first.artworkFileName,
                    seed: first.title,
                    size: 46,
                    corner: 0.18
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text(first.title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    Text(first.artist)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text("Recently played")
                    .font(.system(size: 13, weight: .semibold))
                Text("Play a song and it lands here.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            HStack(spacing: 5) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 8, weight: .semibold))
                Text("\(snapshot.trackCount) songs")
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func mediumContent(_ snapshot: SharedLibrarySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            header(snapshot)

            ForEach(Array(snapshot.recent.prefix(3))) { item in
                recentRow(item)
            }

            Spacer(minLength: 0)

            footer(snapshot)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func largeContent(_ snapshot: SharedLibrarySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header(snapshot)

            ForEach(Array(snapshot.recent.prefix(6))) { item in
                recentRow(item)
            }

            Spacer(minLength: 0)

            footer(snapshot)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func header(_ snapshot: SharedLibrarySnapshot) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("RECENTLY PLAYED")
                .font(.system(size: 8.5, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text("\(snapshot.trackCount) songs")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .opacity(0.8)
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
            ArtworkTile(
                fileName: item.artworkFileName,
                seed: item.title,
                size: 26,
                corner: 0.2
            )

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
                .foregroundStyle(.secondary)
                .opacity(0.7)
        }
        .contentShape(Rectangle())
    }

    private func footer(_ snapshot: SharedLibrarySnapshot) -> some View {
        HStack(spacing: 5) {
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
        .foregroundStyle(.secondary)
        .opacity(0.85)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "square.stack")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(.secondary)

            Text("Your library")
                .font(.system(size: 13, weight: .semibold))

            Text(SharedNowPlaying.hasAppGroup
                 ? "Open Lilt and play something to fill this."
                 : "Lilt cannot share data with widgets. Open Lilt › Settings › Widgets.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func playURL(_ item: SharedLibrarySnapshot.Item) -> URL? {
        guard UUID(uuidString: item.id) != nil else { return nil }
        return URL(string: "motif://play/\(item.id)")
    }
}

// MARK: - Shared pieces

private struct ArtworkTile: View {
    let fileName: String?
    let seed: String
    let size: CGFloat
    let corner: CGFloat

    var body: some View {
        Group {
            if let image = SharedArtwork.image(named: fileName) {
                Image(uiImage: image)
                    .resizable()
                    .accentedFullColor()
                    .scaledToFill()
            } else {
                ArtworkPlaceholder(seed: seed)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * corner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * corner, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
    }
}

private struct ArtworkPlaceholder: View {
    let seed: String

    var body: some View {
        ZStack {
            LinearGradient(
                colors: Self.gradient(seed),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "music.note")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    private static func gradient(_ seed: String) -> [Color] {
        var hash: UInt64 = 5381
        for scalar in seed.unicodeScalars {
            hash = (hash &* 33) &+ UInt64(scalar.value)
        }
        let hue = Double(hash % 360) / 360
        return [
            Color(hue: hue, saturation: 0.45, brightness: 0.80),
            Color(hue: hue + 0.07 > 1 ? hue - 0.55 : hue + 0.07, saturation: 0.55, brightness: 0.46)
        ]
    }
}

private struct PlaybackGlyph: View {
    let isPlaying: Bool
    let size: CGFloat

    var body: some View {
        Image(systemName: isPlaying ? "waveform" : "pause.fill")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

// MARK: - Backgrounds

/// Everything that paints behind the content lives here, so WidgetKit can
/// remove it for the clear, tinted, vibrant and StandBy appearances instead
/// of flattening a dark slab over the whole widget.
private struct NowPlayingBackground: View {
    @Environment(\.colorScheme) private var scheme
    let artworkName: String?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: WidgetInk.base(scheme),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if artworkName != nil,
               let backdrop = SharedArtwork.image(named: SharedArtwork.nowPlayingBackdropName) {
                Image(uiImage: backdrop)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .opacity(scheme == .dark ? 0.85 : 0.55)
            }

            WidgetInk.scrim(scheme)
        }
    }
}

private struct LibraryBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        LinearGradient(
            colors: WidgetInk.base(scheme),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private enum WidgetInk {
    static func base(_ scheme: ColorScheme) -> [Color] {
        if scheme == .dark {
            return [
                Color(red: 0.15, green: 0.155, blue: 0.18),
                Color(red: 0.05, green: 0.05, blue: 0.06)
            ]
        }
        return [
            Color(red: 0.985, green: 0.98, blue: 0.975),
            Color(red: 0.91, green: 0.905, blue: 0.90)
        ]
    }

    static func scrim(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black.opacity(0.30) : Color.white.opacity(0.55)
    }
}

// MARK: - Availability helpers

private extension View {
    @ViewBuilder
    func widgetContainerBackground<Background: View>(
        @ViewBuilder content: () -> Background
    ) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            containerBackground(for: .widget) { content() }
        } else {
            background(content())
        }
    }

}

private extension Image {
    /// Keep artwork photographic in the clear and tinted appearances instead
    /// of letting the system flatten it into a white shape.
    @ViewBuilder
    func accentedFullColor() -> some View {
        if #available(iOSApplicationExtension 18.0, *) {
            widgetAccentedRenderingMode(.fullColor)
        } else {
            self
        }
    }
}
