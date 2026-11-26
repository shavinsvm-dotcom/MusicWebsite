import Foundation
import SwiftUI
import UIKit

struct LyricWord: Identifiable, Equatable {
    let id: Int
    let text: String
    let start: TimeInterval
    var end: TimeInterval?
}

struct LyricLine: Identifiable, Equatable {
    let id: Int
    let timestamp: TimeInterval?
    var end: TimeInterval?
    let text: String
    var words: [LyricWord]

    var isTimed: Bool { timestamp != nil }
    var isWordTimed: Bool { !words.isEmpty }
}

struct LyricsDocument {
    let lines: [LyricLine]
    let isSynced: Bool

    var isWordSynced: Bool {
        lines.contains { !$0.words.isEmpty }
    }

    static let empty = LyricsDocument(lines: [], isSynced: false)
}

enum LyricsParser {
    private static let lineTimestampRegex = try! NSRegularExpression(
        pattern: "\\[(\\d{1,3}):(\\d{2})(?:\\.(\\d{1,3}))?\\]"
    )
    private static let wordTimestampRegex = try! NSRegularExpression(
        pattern: "<(\\d{1,3}):(\\d{2})(?:\\.(\\d{1,3}))?>"
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
            let lineMatches = lineTimestampRegex.matches(in: line, range: range)

            guard !lineMatches.isEmpty else {
                if !line.hasPrefix("[") {
                    plain.append(line)
                }
                continue
            }

            let text = lineTimestampRegex
                .stringByReplacingMatches(in: line, range: range, withTemplate: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            let parsedWords = makeWords(from: text)

            for match in lineMatches {
                guard let timestamp = seconds(from: match, in: line) else { continue }
                timed.append(
                    LyricLine(
                        id: nextID,
                        timestamp: timestamp,
                        end: nil,
                        text: parsedWords.text.isEmpty ? text : parsedWords.text,
                        words: parsedWords.words
                    )
                )
                nextID += 1
            }
        }

        if !timed.isEmpty {
            timed.sort { ($0.timestamp ?? 0) < ($1.timestamp ?? 0) }
            for index in timed.indices {
                let nextStart = index + 1 < timed.count ? timed[index + 1].timestamp : nil
                timed[index].end = nextStart
                for wordIndex in timed[index].words.indices where timed[index].words[wordIndex].end == nil {
                    timed[index].words[wordIndex].end = nextStart
                        ?? (timed[index].words[wordIndex].start + 0.4)
                }
            }
            return LyricsDocument(lines: timed, isSynced: true)
        }

        while plain.first?.isEmpty == true { plain.removeFirst() }
        while plain.last?.isEmpty == true { plain.removeLast() }

        return LyricsDocument(
            lines: plain.enumerated().map { index, text in
                LyricLine(id: index, timestamp: nil, end: nil, text: text, words: [])
            },
            isSynced: false
        )
    }

    private static func makeWords(from text: String) -> (text: String, words: [LyricWord]) {
        let range = NSRange(location: 0, length: (text as NSString).length)
        let matches = wordTimestampRegex.matches(in: text, range: range)
        guard !matches.isEmpty else {
            return (text.trimmingCharacters(in: .whitespacesAndNewlines), [])
        }

        struct ParsedWord {
            let start: TimeInterval
            let text: String
            var end: TimeInterval?
        }

        var parsed: [ParsedWord] = []

        for (index, match) in matches.enumerated() {
            guard let start = seconds(from: match, in: text) else { continue }

            let segmentStart = match.range.location + match.range.length
            let segmentEnd = index + 1 < matches.count
                ? matches[index + 1].range.location
                : (text as NSString).length
            guard segmentStart <= segmentEnd else { continue }

            let segment = (text as NSString).substring(
                with: NSRange(location: segmentStart, length: segmentEnd - segmentStart)
            )

            if segment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // A trailing empty word tag gives the preceding word an explicit end.
                if !parsed.isEmpty {
                    parsed[parsed.count - 1].end = start
                }
                continue
            }

            parsed.append(ParsedWord(start: start, text: segment, end: nil))
        }

        guard !parsed.isEmpty else {
            return (text.trimmingCharacters(in: .whitespacesAndNewlines), [])
        }

        var words = parsed.enumerated().map { index, word in
            LyricWord(
                id: index,
                text: word.text,
                start: word.start,
                end: word.end
            )
        }

        for index in words.indices where words[index].end == nil {
            if index + 1 < words.count {
                words[index].end = words[index + 1].start
            }
        }

        let joined = words
            .map(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (joined, words)
    }

    private static func seconds(from match: NSTextCheckingResult, in string: String) -> TimeInterval? {
        guard
            let minuteRange = Range(match.range(at: 1), in: string),
            let secondRange = Range(match.range(at: 2), in: string),
            let minutes = Double(string[minuteRange]),
            let seconds = Double(string[secondRange])
        else { return nil }

        var fraction = 0.0
        if match.range(at: 3).location != NSNotFound,
           let fractionRange = Range(match.range(at: 3), in: string) {
            fraction = Double("0.\(string[fractionRange])") ?? 0
        }

        return minutes * 60 + seconds + fraction
    }
}

private struct LyricPlayheadState: Equatable {
    var line: Int?
    var word: Int?

    static let none = LyricPlayheadState(line: nil, word: nil)
}

struct LyricsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerManager

    let track: Track

    @State private var playhead = LyricPlayheadState.none
    @State private var followsPlayback = true
    @State private var showFinder = false
    /// Positive values show each line later, for lyric files that run ahead.
    @State private var timingDelay: Double = 0

    private var currentTrack: Track {
        library.tracks.first { existing in
            existing.id == track.id
                || (track.remoteID != nil && existing.remoteID == track.remoteID)
        } ?? track
    }

    private var document: LyricsDocument {
        LyricsDocumentCache.document(for: currentTrack)
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
                .background(lyricsBackdrop)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { _ in
                            guard followsPlayback else { return }
                            followsPlayback = false
                        }
                )
                .task {
                    // The first layout pass must exist before scrolling to a
                    // line in the middle of the song.
                    try? await Task.sleep(nanoseconds: 80_000_000)
                    guard followsPlayback else { return }
                    scrollToActive(proxy: proxy, animated: false)
                }
                .onChange(of: playhead.line) { _ in
                    guard followsPlayback else { return }
                    scrollToActive(proxy: proxy, animated: true)
                }
                .onChange(of: followsPlayback) { follows in
                    guard follows else { return }
                    scrollToActive(proxy: proxy, animated: true)
                }
            }
            .navigationTitle("Lyrics")
            .navigationBarTitleDisplayMode(.large)
            .nativeScrollHeader()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showFinder = true
                    } label: {
                        Image(systemName: "globe")
                    }
                    .accessibilityLabel("Find different lyrics")
                }

                if document.isSynced {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("0.5s Earlier") { timingDelay -= 0.5 }
                            Button("0.1s Earlier") { timingDelay -= 0.1 }
                            Button("0.1s Later") { timingDelay += 0.1 }
                            Button("0.5s Later") { timingDelay += 0.5 }
                            if timingDelay != 0 {
                                Divider()
                                Button("Reset Timing") { timingDelay = 0 }
                            }
                        } label: {
                            Image(systemName: "timer")
                        }
                        .accessibilityLabel("Lyrics timing")
                        .accessibilityIdentifier("lyrics.timing")
                        .accessibilityValue(
                            timingDelay == 0 ? "On time" : String(format: "%+.1fs", timingDelay)
                        )
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        followsPlayback.toggle()
                    } label: {
                        Image(systemName: followsPlayback ? "location.fill" : "location.slash")
                    }
                    .accessibilityLabel(followsPlayback ? "Stop following lyrics" : "Follow lyrics")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
        .presentationDetents([.medium, .large])
        .task(id: currentTrack.id) {
            timingDelay = LyricsTiming.delay(for: currentTrack.id)
        }
        .onChange(of: timingDelay) { value in
            LyricsTiming.setDelay(value, for: currentTrack.id)
        }
        .sheet(isPresented: $showFinder) {
            LyricsFinderView(track: currentTrack)
                .environmentObject(library)
        }
    }

    private var lyricsBackdrop: some View {
        ZStack {
            AppBackground()

            if let url = currentTrack.artworkURL,
               let image = PlaybackBackdropCache.shared.image(for: url) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .opacity(0.30)
                    .clipped()
            }

            LinearGradient(
                colors: [.black.opacity(0.18), .black.opacity(0.42), .black.opacity(0.70)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(spacing: 14) {
            ArtworkView(
                url: currentTrack.artworkURL,
                seed: currentTrack.title + currentTrack.artist,
                thumbnail: true
            )
            .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.7)
                }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text("LYRICS")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)

                    if let badge = syncBadge {
                        glassBadge(badge)
                    }

                    if currentTrack.lyricsSource == .automatic {
                        glassBadge("AUTO")
                    }
                }

                Text(currentTrack.title)
                    .font(.headline)
                    .lineLimit(2)

                Text(currentTrack.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(lyricsStatus)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .nativeGlass(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.7)
        }
        .padding(.bottom, 24)
    }

    private var syncBadge: String? {
        if document.isWordSynced { return "WORD SYNC" }
        if document.isSynced { return "SYNCED" }
        if !document.lines.isEmpty { return "PLAIN" }
        return nil
    }

    private var lyricsStatus: String {
        if document.isWordSynced {
            return "Word-synced to this recording"
        }
        if document.isSynced {
            return "Timed lyrics matched to this recording"
        }
        if !document.lines.isEmpty {
            return "Plain lyrics · timing unavailable"
        }
        return "No lyrics matched yet"
    }

    private func glassBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(.white.opacity(0.80))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .nativeGlass(Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
            }
    }

    private var syncedLyrics: some View {
        VStack(alignment: .leading, spacing: 0) {
            LyricsPlayhead(lines: document.lines, delay: timingDelay) { next in
                guard next != playhead else { return }
                playhead = next
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(document.lines.enumerated()), id: \.element.id) { index, line in
                    let isActive = index == playhead.line

                    HStack(alignment: .top, spacing: 12) {
                        Capsule()
                            .fill(isActive ? Color.white.opacity(0.92) : Color.clear)
                            .frame(width: 2, height: isActive ? 25 : 0)
                            .padding(.top, 4)

                        lyricText(
                            for: line,
                            isActive: isActive,
                            activeWord: isActive ? playhead.word : nil
                        )
                        .font(.system(
                            size: isActive ? 29 : 25,
                            weight: isActive ? .bold : .semibold,
                            design: .serif
                        ))
                        .tracking(-0.35)
                        .lineSpacing(isActive ? 8 : 6)
                        .scaleEffect(isActive ? 1 : 0.985, anchor: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: isActive)
                    }
                    .padding(.vertical, isActive ? 12 : 8)
                    .background {
                        activeLineGlass(isActive)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        seek(to: line)
                    }
                    .id(line.id)
                }
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func activeLineGlass(_ isActive: Bool) -> some View {
        if isActive {
            Color.clear
                .nativeGlass(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.6)
                }
                .padding(.horizontal, -10)
                .padding(.vertical, -5)
        }
    }

    private func seek(to line: LyricLine) {
        guard let timestamp = line.timestamp,
              player.current?.id == currentTrack.id
        else { return }
        player.seek(to: max(0, timestamp))
    }

    private func lyricText(for line: LyricLine, isActive: Bool, activeWord: Int?) -> Text {
        guard isActive, !line.words.isEmpty else {
            return Text(line.text)
                .foregroundColor(isActive ? .white : .white.opacity(0.38))
        }
        guard let activeWord else {
            return Text(line.text)
                .foregroundColor(.white.opacity(0.38))
        }

        var result = Text("")
        for (index, word) in line.words.enumerated() {
            var part = Text(word.text)
            if index < activeWord {
                part = part.foregroundColor(.white)
            } else if index == activeWord {
                part = part.foregroundColor(.white).fontWeight(.bold)
            } else {
                part = part.foregroundColor(.white.opacity(0.38))
            }
            result = result + part
        }
        return result
    }

    private var plainLyrics: some View {
        Text(document.lines.map(\.text).joined(separator: "\n"))
            .font(.system(size: 25, weight: .regular, design: .serif))
            .tracking(-0.25)
            .lineSpacing(11)
            .foregroundStyle(.white.opacity(0.92))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .nativeGlass(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.6)
            }
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

            Text("Lilt checks automatically when a track starts, preferring word-synced lyrics that fit the recording.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Button {
                showFinder = true
            } label: {
                Label("Find Lyrics Online", systemImage: "globe")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .nativeGlass(Capsule(), interactive: true)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(MotifPressStyle(scale: 0.94))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 40)
        .nativeGlass(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.6)
        }
        .padding(.top, 4)
    }

    private func scrollToActive(proxy: ScrollViewProxy, animated: Bool) {
        guard followsPlayback,
              let line = playhead.line,
              document.lines.indices.contains(line)
        else { return }

        let id = document.lines[line].id
        if animated && !reduceMotion {
            withAnimation(.easeInOut(duration: 0.38)) {
                proxy.scrollTo(id, anchor: .center)
            }
        } else {
            proxy.scrollTo(id, anchor: .center)
        }
    }
}

/// Small invisible observer so the large lyric list does not redraw on every
/// playback-progress tick. It publishes only when the active line or word changes.
private struct LyricsPlayhead: View {
    @EnvironmentObject private var progress: PlaybackProgress

    let lines: [LyricLine]
    let delay: Double
    let onChange: (LyricPlayheadState) -> Void

    @State private var lastLine: Int?
    @State private var lastWord: Int?

    var body: some View {
        Color.clear
            .frame(height: 1)
            .onAppear {
                emit(progress.elapsed)
            }
            .onChange(of: progress.elapsed) { elapsed in
                emit(elapsed)
            }
            .onChange(of: lines) { _ in
                lastLine = nil
                lastWord = nil
                emit(progress.elapsed)
            }
            .onChange(of: delay) { _ in
                lastLine = nil
                lastWord = nil
                emit(progress.elapsed)
            }
    }

    private func emit(_ elapsed: Double) {
        let next = state(for: elapsed)
        guard next.line != lastLine || next.word != lastWord else { return }
        lastLine = next.line
        lastWord = next.word
        onChange(next)
    }

    private func state(for elapsed: Double) -> LyricPlayheadState {
        let time = elapsed + 0.06 - delay
        guard let lineIndex = lineIndex(at: time) else { return .none }

        let words = lines[lineIndex].words
        guard !words.isEmpty else {
            return LyricPlayheadState(line: lineIndex, word: nil)
        }
        return LyricPlayheadState(
            line: lineIndex,
            word: wordIndex(in: words, at: time)
        )
    }

    private func lineIndex(at time: Double) -> Int? {
        var low = 0
        var high = lines.count - 1
        var result: Int?

        while low <= high {
            let middle = (low + high) / 2
            if let timestamp = lines[middle].timestamp, timestamp <= time {
                result = middle
                low = middle + 1
            } else {
                high = middle - 1
            }
        }

        return result
    }

    private func wordIndex(in words: [LyricWord], at time: Double) -> Int? {
        var low = 0
        var high = words.count - 1
        var result: Int?

        while low <= high {
            let middle = (low + high) / 2
            if words[middle].start <= time {
                result = middle
                low = middle + 1
            } else {
                high = middle - 1
            }
        }

        return result
    }
}

/// Per-song lyric timing nudge, stored on this device. Most LRC files line up
/// as-is, so an absent value means exactly on time.
private enum LyricsTiming {
    private static let prefix = "motif.lyricsDelay."

    static func delay(for id: UUID) -> Double {
        let value = UserDefaults.standard.double(forKey: prefix + id.uuidString)
        return min(max(value, -5), 5)
    }

    static func setDelay(_ value: Double, for id: UUID) {
        let clamped = min(max(value, -5), 5)
        UserDefaults.standard.set(clamped, forKey: prefix + id.uuidString)
    }
}

private struct LyricsDocumentKey: Hashable {
    let id: UUID
    let fileLength: Int
    let textLength: Int
    let source: String
    let fileStart: String
    let fileEnd: String
    let textStart: String
    let textEnd: String

    init(track: Track) {
        let file = track.lyricsFile ?? ""
        let text = track.lyrics ?? ""
        id = track.id
        fileLength = file.utf8.count
        textLength = text.utf8.count
        source = track.lyricsSource?.rawValue ?? "-"
        fileStart = String(file.prefix(24))
        fileEnd = String(file.suffix(24))
        textStart = String(text.prefix(24))
        textEnd = String(text.suffix(24))
    }
}

@MainActor
private enum LyricsDocumentCache {
    private static var documents: [LyricsDocumentKey: LyricsDocument] = [:]
    private static var keys: [LyricsDocumentKey] = []

    static func document(for track: Track) -> LyricsDocument {
        let key = LyricsDocumentKey(track: track)

        if let cached = documents[key] { return cached }

        let fileDocument = track.lyricsFile
            .flatMap { $0.isEmpty ? nil : LyricsFileParser.parse($0) }
        let textDocument = track.lyrics.flatMap { lyrics -> LyricsDocument? in
            guard !lyrics.isEmpty else { return nil }
            return LyricsParser.parse(lyrics)
        }

        let document: LyricsDocument
        if let fileDocument, fileDocument.isWordSynced {
            document = fileDocument
        } else if let textDocument, textDocument.isWordSynced {
            document = textDocument
        } else if let fileDocument, fileDocument.isSynced {
            document = fileDocument
        } else {
            document = textDocument ?? .empty
        }

        documents[key] = document
        keys.append(key)
        if keys.count > 48 {
            documents.removeValue(forKey: keys.removeFirst())
        }
        return document
    }
}
