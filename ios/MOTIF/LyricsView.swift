import Foundation
import SwiftUI

struct LyricLine: Identifiable, Equatable {
    let id: Int
    let timestamp: TimeInterval?
    let text: String

    var isTimed: Bool { timestamp != nil }
}

struct LyricsDocument {
    let lines: [LyricLine]
    let isSynced: Bool

    static let empty = LyricsDocument(lines: [], isSynced: false)
}

enum LyricsParser {
    private static let timestampRegex = try! NSRegularExpression(
        pattern: "\\[(\\d{1,3}):(\\d{2})(?:\\.(\\d{1,3}))?\\]"
    )

    static func parse(_ raw: String) -> LyricsDocument {
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let rawLines = normalized.components(separatedBy: "\n")

        var timed: [LyricLine] = []
        var plain: [String] = []
        var nextID = 0

        for rawLine in rawLines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else {
                if !plain.isEmpty { plain.append("") }
                continue
            }

            let range = NSRange(location: 0, length: (line as NSString).length)
            let matches = timestampRegex.matches(in: line, range: range)

            guard !matches.isEmpty else {
                if !line.hasPrefix("[") {
                    plain.append(line)
                }
                continue
            }

            let text = timestampRegex
                .stringByReplacingMatches(in: line, range: range, withTemplate: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            for match in matches {
                guard
                    let minuteRange = Range(match.range(at: 1), in: line),
                    let secondRange = Range(match.range(at: 2), in: line),
                    let minutes = Double(line[minuteRange]),
                    let seconds = Double(line[secondRange])
                else { continue }

                var fraction = 0.0
                if match.range(at: 3).location != NSNotFound,
                   let fractionRange = Range(match.range(at: 3), in: line) {
                    fraction = Double("0.\(line[fractionRange])") ?? 0
                }

                timed.append(LyricLine(
                    id: nextID,
                    timestamp: minutes * 60 + seconds + fraction,
                    text: text
                ))
                nextID += 1
            }
        }

        if !timed.isEmpty {
            timed.sort { ($0.timestamp ?? 0) < ($1.timestamp ?? 0) }
            return LyricsDocument(lines: timed, isSynced: true)
        }

        while plain.first?.isEmpty == true { plain.removeFirst() }
        while plain.last?.isEmpty == true { plain.removeLast() }

        return LyricsDocument(
            lines: plain.enumerated().map { index, text in
                LyricLine(id: index, timestamp: nil, text: text)
            },
            isSynced: false
        )
    }
}

struct LyricsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: LibraryStore

    let track: Track

    @State private var activeIndex: Int?
    @State private var showFinder = false

    private var currentTrack: Track {
        library.tracks.first { existing in
            existing.id == track.id
                || (track.remoteID != nil && existing.remoteID == track.remoteID)
        } ?? track
    }

    private var document: LyricsDocument {
        guard let lyrics = currentTrack.lyrics, !lyrics.isEmpty else { return .empty }
        return LyricsParser.parse(lyrics)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header

                        if document.lines.isEmpty {
                            emptyState
                        } else if document.isSynced {
                            syncedLyrics
                        } else {
                            plainLyrics
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 120)
                }
                .scrollIndicators(.hidden)
                .background(AppBackground())
                .task {
                    // The first layout pass must exist before scrolling to a
                    // line in the middle of the song.
                    try? await Task.sleep(nanoseconds: 80_000_000)
                    scrollToActive(proxy: proxy, animated: false)
                }
                .onChange(of: activeIndex) { _ in
                    scrollToActive(proxy: proxy, animated: true)
                }
            }
            .navigationTitle("Lyrics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $showFinder) {
            LyricsFinderView(track: currentTrack)
                .environmentObject(library)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ArtworkView(url: currentTrack.artworkURL, seed: currentTrack.title + currentTrack.artist)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("LYRICS")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)

                    if document.isSynced {
                        Text("SYNCED")
                            .font(.system(size: 8, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(.white.opacity(0.72))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.10), in: Capsule())
                    }
                }

                Text(currentTrack.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(currentTrack.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.bottom, 24)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)
        }
    }

    private var syncedLyrics: some View {
        VStack(alignment: .leading, spacing: 0) {
            LyricsPlayhead(lines: document.lines) { index in
                if activeIndex != index {
                    activeIndex = index
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(document.lines.enumerated()), id: \.element.id) { index, line in
                let isActive = index == activeIndex

                HStack(alignment: .top, spacing: 12) {
                    Capsule()
                        .fill(isActive ? Color.white.opacity(0.92) : Color.clear)
                        .frame(width: 2, height: isActive ? 25 : 0)
                        .padding(.top, 4)

                    Text(line.text)
                        .font(.system(
                            size: isActive ? 29 : 25,
                            weight: isActive ? .bold : .semibold,
                            design: .serif
                        ))
                        .tracking(-0.35)
                        .lineSpacing(isActive ? 8 : 6)
                        .foregroundStyle(isActive ? Color.white : Color.white.opacity(0.38))
                        .scaleEffect(isActive ? 1 : 0.985, anchor: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .animation(.easeInOut(duration: 0.24), value: isActive)
                }
                    .padding(.vertical, isActive ? 12 : 8)
                    .id(line.id)
                }
            }
        }
        .padding(.top, 4)
    }

    private var plainLyrics: some View {
        Text(document.lines.map(\.text).joined(separator: "\n"))
            .font(.system(size: 25, weight: .regular, design: .serif))
            .tracking(-0.25)
            .lineSpacing(11)
            .foregroundStyle(.white.opacity(0.92))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "quote.bubble")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)

            Text("Lyrics aren’t available for this track.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showFinder = true
            } label: {
                Label("Find Lyrics Online", systemImage: "globe")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.10), in: Capsule())
                    .foregroundStyle(.primary)
            }
            .buttonStyle(MotifPressStyle(scale: 0.94))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 54)
    }

    private func scrollToActive(proxy: ScrollViewProxy, animated: Bool) {
        guard
            let activeIndex,
            document.lines.indices.contains(activeIndex)
        else { return }

        let id = document.lines[activeIndex].id
        if animated {
            withAnimation(.easeInOut(duration: 0.38)) {
                proxy.scrollTo(id, anchor: .center)
            }
        } else {
            proxy.scrollTo(id, anchor: .center)
        }
    }
}

/// Small invisible observer so the large lyric list does not redraw on every
/// playback-progress tick. It publishes only when the active line changes.
private struct LyricsPlayhead: View {
    @EnvironmentObject private var progress: PlaybackProgress

    let lines: [LyricLine]
    let onChange: (Int?) -> Void

    var body: some View {
        Color.clear
            .frame(height: 1)
            .onAppear {
                onChange(index(for: progress.elapsed))
            }
            .onChange(of: progress.elapsed) { elapsed in
                onChange(index(for: elapsed))
            }
    }

    private func index(for elapsed: Double) -> Int? {
        let time = elapsed + 0.06
        return lines.lastIndex(where: { line in
            guard let timestamp = line.timestamp else { return false }
            return timestamp <= time
        })
    }
}
