import ActivityKit
import SwiftUI
import WidgetKit

@main
struct MOTIFWidgetBundle: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        MOTIFNowPlayingWidget()

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
        .description("Your current MOTIF track and playback progress.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct MOTIFNowPlayingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NowPlayingEntry

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.10, blue: 0.12), Color(red: 0.04, green: 0.04, blue: 0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let snapshot = entry.snapshot {
                content(snapshot)
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
                artwork(snapshot)

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

            VStack(spacing: 5) {
                ProgressView(value: progress(snapshot))
                    .tint(.primary)

                HStack {
                    Text(snapshot.isPlaying ? "Playing" : "Paused")
                    Spacer()
                    Text(timeText(snapshot.elapsed))
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: "waveform")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.secondary)
            Text("MOTIF")
                .font(.system(size: 15, weight: .bold))
                .tracking(-0.3)
            Text("Play a song to see it here.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(16)
    }

    @ViewBuilder
    private func artwork(_ snapshot: SharedNowPlaying) -> some View {
        if let value = snapshot.artworkURL, let url = URL(string: value) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    artworkFallback
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            artworkFallback
                .frame(width: 44, height: 44)
        }
    }

    private var artworkFallback: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.secondary.opacity(0.16))
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
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
                    Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
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
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(
                        value: progress(context.state)
                    )
                    .tint(.white)
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
                    .foregroundStyle(.white)
            } compactTrailing: {
                Text(timeText(context.state.elapsed))
                    .font(.system(size: 11, weight: .medium))
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
}

@available(iOS 16.1, *)
private struct LiveActivityLockScreenView: View {
    let state: MusicActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: state.isPlaying ? "waveform" : "pause.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 40, height: 40)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(state.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(state.artist)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                ProgressView(value: progress)
                    .tint(.white)
                    .padding(.top, 2)
            }

            Spacer(minLength: 8)

            Text(timeText)
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(14)
    }

    private var progress: Double {
        guard state.duration > 0 else { return 0 }
        return min(1, max(0, state.elapsed / state.duration))
    }

    private var timeText: String {
        let value = max(0, Int(state.elapsed))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
