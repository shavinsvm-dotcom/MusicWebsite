import Foundation
import Yams

enum LyricsFileParser {
    static func parse(_ raw: String) -> LyricsDocument? {
        guard let file = try? YAMLDecoder().decode(LyricsFileDocument.self, from: raw),
              let sourceLines = file.lines,
              !sourceLines.isEmpty
        else { return nil }

        var parsed: [LyricLine] = []
        var nextID = 0

        for sourceLine in sourceLines {
            let words = (sourceLine.words ?? []).enumerated().compactMap { index, word -> LyricWord? in
                guard let start = word.startMs, start.isFinite, start >= 0 else { return nil }
                let end = word.endMs.flatMap { value in
                    value.isFinite && value >= start ? value : nil
                }
                return LyricWord(
                    id: index,
                    text: word.text ?? "",
                    start: start / 1000,
                    end: end.map { $0 / 1000 }
                )
            }

            let lineStart = sourceLine.startMs.flatMap { value in
                value.isFinite && value >= 0 ? value / 1000 : nil
            } ?? words.first?.start

            guard let lineStart else { continue }

            let lineEnd = sourceLine.endMs.flatMap { value in
                value.isFinite && value >= lineStart * 1000 ? value / 1000 : nil
            }

            var text = sourceLine.text ?? words.map(\.text).joined()
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                text = words.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard !text.isEmpty || !words.isEmpty else { continue }

            parsed.append(
                LyricLine(
                    id: nextID,
                    timestamp: lineStart,
                    end: lineEnd,
                    text: text,
                    words: words
                )
            )
            nextID += 1
        }

        guard !parsed.isEmpty else { return nil }
        parsed.sort { ($0.timestamp ?? 0) < ($1.timestamp ?? 0) }

        for index in parsed.indices {
            let nextStart = index + 1 < parsed.count ? parsed[index + 1].timestamp : nil
            let fallbackEnd = parsed[index].end ?? nextStart
            parsed[index].end = fallbackEnd

            for wordIndex in parsed[index].words.indices where parsed[index].words[wordIndex].end == nil {
                parsed[index].words[wordIndex].end = fallbackEnd
                    ?? (parsed[index].words[wordIndex].start + 0.4)
            }
        }

        return LyricsDocument(lines: parsed, isSynced: true)
    }

    static func plainText(from raw: String) -> String? {
        guard let file = try? YAMLDecoder().decode(LyricsFileDocument.self, from: raw) else {
            return nil
        }

        if let plain = file.plain?.trimmingCharacters(in: .whitespacesAndNewlines),
           !plain.isEmpty {
            return plain
        }

        let lines = (file.lines ?? []).compactMap { line -> String? in
            let text = line.text ?? (line.words ?? []).map { $0.text ?? "" }.joined()
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}

private struct LyricsFileDocument: Decodable {
    let version: String?
    let lines: [Line]?
    let plain: String?

    struct Line: Decodable {
        let text: String?
        let startMs: Double?
        let endMs: Double?
        let words: [Word]?

        private enum CodingKeys: String, CodingKey {
            case text
            case startMs = "start_ms"
            case endMs = "end_ms"
            case words
        }
    }

    struct Word: Decodable {
        let text: String?
        let startMs: Double?
        let endMs: Double?

        private enum CodingKeys: String, CodingKey {
            case text
            case startMs = "start_ms"
            case endMs = "end_ms"
        }
    }
}
