import ActivityKit
import SwiftUI
import WidgetKit

@main
struct MOTIFWidgetBundle: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        MOTIFNowPlayingWidget()
        MOTIFLibraryWidget()

        if #available(iOS 16.1, *) {
            MOTIFLiveActivity()
        }
    }
}

struct NowPlayingEntry: TimelineEntry {
    let date: Date
    let snapshot: SharedNowPlaying?
}

struct NowPlayingProvider: TimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
        completion(NowPlayingEntry(date: Date(), snapshot: SharedNowPlaying.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        let entry = NowPlayingEntry(date: Date(), snapshot: SharedNowPlaying.load())
        let next = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date().addingTimeInterval(300)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct MOTIFNowPlayingWidget: Widget {
    let kind = "MOTIFNowPlaying"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NowPlayingProvider()) { entry in
            MOTIFNowPlayingWidgetView(entry: entry)
        }
        .configurationDisplayName("Now Playing")
        .description("Your current Lilt track and playback progress.")
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
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.10, blue: 0.12), Color(red: 0.04, green: 0.04, blue: 0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let snapshot = entry.snapshot,
               let value = snapshot.artworkURL,
               let url = URL(string: value) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Color.clear
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .blur(radius: 28)
                .opacity(0.66)
                .overlay(Color.black.opacity(0.30))
            }

            if let snapshot = entry.snapshot {
                if family == .systemLarge {
                    largeContent(snapshot)
                } else {
                    content(snapshot)
                }
            } else {
                emptyState
            }
        }
        .widgetBackground(Color(red: 0.06, green: 0.06, blue: 0.08))
        .widgetURL(URL(string: "motif://nowplaying"))
    }

    private func content(_ snapshot: SharedNowPlaying) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                artwork(snapshot, size: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.title)
                        .font(.system(size: family == .systemSmall ? 12 : 14, weight: .semibold))
                        .lineLimit(1)
                    Text(snapshot.artist)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)

            progressBlock(snapshot)
        }
        .padding(14)
    }

    private func largeContent(_ snapshot: SharedNowPlaying) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                artwork(snapshot, size: 82)

                VStack(alignment: .leading, spacing: 4) {
                    Text(snapshot.title)
                        .font(.system(size: 19, weight: .bold))
                        .lineLimit(2)
                    Text(snapshot.artist)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if !snapshot.album.isEmpty {
                        Text(snapshot.album)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)

            progressBlock(snapshot)
        }
        .padding(18)
    }

    private func progressBlock(_ snapshot: SharedNowPlaying) -> some View {
        VStack(spacing: 6) {
            ProgressView(value: progress(snapshot))
                .tint(.primary)

            HStack {
                Text(snapshot.isPlaying ? "Playing" : "Paused")
                Spacer()
                Text("\(timeText(snapshot.elapsed)) / \(timeText(snapshot.duration))")
            }
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(.secondary)
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

    @ViewBuilder
    private func artwork(_ snapshot: SharedNowPlaying, size: CGFloat) -> some View {
        if let value = snapshot.artworkURL, let url = URL(string: value) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    artworkFallback(size: size)
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
        } else {
            artworkFallback(size: size)
        }
    }

    private func artworkFallback(size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
            .fill(Color.secondary.opacity(0.16))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: max(10, size * 0.3), weight: .semibold))
                    .foregroundStyle(.secondary)
            }
    }

    private var accessoryCircular: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: entry.snapshot?.isPlaying == true ? "waveform" : "pause.fill")
                .font(.system(size: 18, weight: .semibold))
        }
        .widgetURL(URL(string: "motif://nowplaying"))
    }

    private var accessoryRectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.snapshot?.title ?? "Lilt")
                .font(.headline)
                .lineLimit(1)
            Text(entry.snapshot?.artist ?? "Nothing playing")
                .font(.caption2)
                .lineLimit(1)
            if let snapshot = entry.snapshot {
                ProgressView(value: progress(snapshot))
                    .tint(.primary)
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
        return "\(snapshot.title) · \(snapshot.artist)"
    }

    private func progress(_ snapshot: SharedNowPlaying) -> Double {
        guard snapshot.duration > 0 else { return 0 }
        return min(1, max(0, snapshot.elapsed / snapshot.duration))
    }

    private func timeText(_ seconds: Double) -> String {
        let value = max(0, Int(seconds))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

struct LibraryEntry: TimelineEntry {
    let date: Date
    let snapshot: SharedLibrarySnapshot?
}

struct LibraryProvider: TimelineProvider {
    func placeholder(in context: Context) -> LibraryEntry {
        LibraryEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (LibraryEntry) -> Void) {
        completion(LibraryEntry(date: Date(), snapshot: SharedLibrarySnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LibraryEntry>) -> Void) {
        let entry = LibraryEntry(date: Date(), snapshot: SharedLibrarySnapshot.load())
        let next = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date().addingTimeInterval(300)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct MOTIFLibraryWidget: Widget {
    let kind = "MOTIFLibrary"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LibraryProvider()) { entry in
            MOTIFLibraryWidgetView(entry: entry)
        }
        .configurationDisplayName("Your Library")
        .description("A quick look at your Lilt library and recent songs.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct MOTIFLibraryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LibraryEntry

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.10, blue: 0.12), Color(red: 0.04, green: 0.04, blue: 0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    Image(systemName: "square.stack")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("YOUR LIBRARY")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.0)
                        .foregroundStyle(.secondary)
                }

                if let snapshot = entry.snapshot {
                    Text("\(snapshot.trackCount)")
                        .font(.system(size: 32, weight: .bold))
                        .tracking(-1)
                    Text(snapshot.trackCount == 1 ? "song" : "songs")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    if family == .systemMedium || family == .systemLarge, !snapshot.recent.isEmpty {
                        Divider().opacity(0.4)
                        ForEach(snapshot.recent.prefix(family == .systemLarge ? 6 : 3)) { item in
                            HStack(spacing: 7) {
                                miniArtwork(item)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.title)
                                        .font(.system(size: 10, weight: .medium))
                                        .lineLimit(1)
                                    Text(item.artist)
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    } else if !snapshot.recent.isEmpty {
                        Spacer(minLength: 0)
                        Text(snapshot.recent[0].title)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                        Text(snapshot.recent[0].artist)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    Text("Add songs to see them here.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .widgetBackground(Color(red: 0.06, green: 0.06, blue: 0.08))
        .widgetURL(URL(string: "motif://library"))
    }

    @ViewBuilder
    private func miniArtwork(_ item: SharedLibrarySnapshot.Item) -> some View {
        if let value = item.artworkURL, let url = URL(string: value) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    miniArtworkFallback
                }
            }
            .frame(width: 22, height: 22)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        } else {
            miniArtworkFallback
                .frame(width: 22, height: 22)
        }
    }

    private var miniArtworkFallback: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.secondary.opacity(0.16))
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
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

@available(iOS 16.1, *)
struct MOTIFLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MusicActivityAttributes.self) { context in
            LiveActivityLockScreenView(state: context.state)
                .widgetURL(URL(string: "motif://nowplaying"))
                .activityBackgroundTint(Color(red: 0.06, green: 0.06, blue: 0.08))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LiveActivityArtwork(
                        urlString: context.state.artworkURL,
                        size: 32,
                        cornerRadius: 8
                    )
                    .padding(.leading, 4)
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.title)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        Text(context.state.artist)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                        if !context.state.album.isEmpty {
                            Text(context.state.album)
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.42))
                                .lineLimit(1)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 3) {
                        if context.state.isPlaying {
                            ProgressView(
                                timerInterval: timerRange(context.state),
                                countsDown: false
                            )
                            .tint(.white)
                        } else {
                            ProgressView(value: progress(context.state))
                                .tint(.white)
                        }

                        HStack {
                            Text(timeText(context.state.elapsed))
                            Spacer()
                            Text(timeText(max(context.state.duration - context.state.elapsed, 0)))
                        }
                        .font(.system(size: 9, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                LiveActivityArtwork(
                    urlString: context.state.artworkURL,
                    size: 22,
                    cornerRadius: 6
                )
            } compactTrailing: {
                Group {
                    if context.state.isPlaying {
                        Text(timerInterval: timerRange(context.state), countsDown: false)
                    } else {
                        Text(timeText(context.state.elapsed))
                    }
                }
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.8))
            } minimal: {
                Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
                    .foregroundStyle(.white)
            }
            .widgetURL(URL(string: "motif://nowplaying"))
            .keylineTint(.white)
        }
    }

    private func progress(_ state: MusicActivityAttributes.ContentState) -> Double {
        guard state.duration > 0 else { return 0 }
        return min(1, max(0, state.elapsed / state.duration))
    }

    private func timeText(_ seconds: Double) -> String {
        let value = max(0, Int(seconds))
        return String(format: "%d:%02d", value / 60, value % 60)
    }

    private func timerRange(_ state: MusicActivityAttributes.ContentState) -> ClosedRange<Date> {
        let start = state.updatedAt.addingTimeInterval(-state.elapsed)
        let end = start.addingTimeInterval(max(state.duration, 1))
        return start...end
    }
}

@available(iOS 16.1, *)
private struct LiveActivityArtwork: View {
    let urlString: String?
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
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
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var fallback: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white.opacity(0.12))
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
    }
}

@available(iOS 16.1, *)
private struct LiveActivityLockScreenView: View {
    let state: MusicActivityAttributes.ContentState

    var body: some View {
        ZStack {
            background

            LinearGradient(
                colors: [.black.opacity(0.18), .black.opacity(0.52)],
                startPoint: .top,
                endPoint: .bottom
            )

            HStack(spacing: 12) {
                LiveActivityArtwork(
                    urlString: state.artworkURL,
                    size: 46,
                    cornerRadius: 10
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(state.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(state.artist)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                    if state.isPlaying {
                        ProgressView(
                            timerInterval: timerRange,
                            countsDown: false
                        )
                        .tint(.white)
                        .padding(.top, 2)
                    } else {
                        ProgressView(value: progress)
                            .tint(.white)
                            .padding(.top, 2)
                    }
                }

                Spacer(minLength: 8)

                Group {
                    if state.isPlaying {
                        Text(timerInterval: timerRange, countsDown: false)
                    } else {
                        Text(timeText)
                    }
                }
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.6))
            }
            .padding(14)
        }
    }

    @ViewBuilder
    private var background: some View {
        if let value = state.artworkURL, let url = URL(string: value) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .blur(radius: 32)
            .opacity(0.58)
        }
    }

    private var progress: Double {
        guard state.duration > 0 else { return 0 }
        return min(1, max(0, state.elapsed / state.duration))
    }

    private var timerRange: ClosedRange<Date> {
        let start = state.updatedAt.addingTimeInterval(-state.elapsed)
        let end = start.addingTimeInterval(max(state.duration, 1))
        return start...end
    }

    private var timeText: String {
        let value = max(0, Int(state.elapsed))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
