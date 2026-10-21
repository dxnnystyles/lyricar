import Foundation

/// Parses LRC text: `[mm:ss.xx] line`, several timestamps per line,
/// metadata tags such as `[ar:...]`, and the `[offset:+/-ms]` tag.
public enum LRCParser {
    public static func parse(_ text: String, provider: String) -> LyricsDocument {
        var offsetMs = 0
        var timed: [(Int, String)] = []

        for rawLine in text.components(separatedBy: .newlines) {
            var rest = Substring(rawLine.trimmingCharacters(in: .whitespaces))
            var stamps: [Int] = []

            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                if let ms = parseTimestamp(tag) {
                    stamps.append(ms)
                } else if tag.lowercased().hasPrefix("offset:") {
                    // Clamped to 10 minutes either way, so a hostile tag cannot overflow the subtraction below.
                    offsetMs = min(max(Int(tag.dropFirst("offset:".count).trimmingCharacters(in: .whitespaces)) ?? 0, -600_000), 600_000)
                }
                rest = rest[rest.index(after: close)...]
            }

            let body = rest.trimmingCharacters(in: .whitespaces)
            for stamp in stamps {
                timed.append((stamp, body))
            }
        }

        // A positive LRC offset means lyrics appear earlier.
        let lines = timed
            .map { (max(0, $0.0 - offsetMs), $0.1) }
            .enumerated()
            .sorted { $0.element.0 == $1.element.0 ? $0.offset < $1.offset : $0.element.0 < $1.element.0 }
            .enumerated()
            .map { LyricLine(id: $0.offset, startMs: $0.element.element.0, text: $0.element.element.1) }

        return LyricsDocument(syncType: .lineSynced, lines: lines, provider: provider)
    }

    public static func plain(_ text: String, provider: String) -> LyricsDocument {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .enumerated()
            .map { LyricLine(id: $0.offset, startMs: 0, text: $0.element) }
        return LyricsDocument(syncType: .unsynced, lines: lines, provider: provider)
    }

    /// `mm:ss`, `mm:ss.x`, `mm:ss.xx`, `mm:ss.xxx` or `mm:ss:xx`.
    static func parseTimestamp(_ tag: Substring) -> Int? {
        let parts = tag.split(separator: ":", omittingEmptySubsequences: false)
        // Minutes are bounded so the arithmetic below cannot trap on untrusted input.
        guard parts.count == 2 || parts.count == 3, let minutes = Int(parts[0]), (0...9_999).contains(minutes) else { return nil }

        let secondsPart: Substring
        var fraction: Substring = ""
        if parts.count == 3 {
            secondsPart = parts[1]
            fraction = parts[2]
        } else if let dot = parts[1].firstIndex(of: ".") {
            secondsPart = parts[1][..<dot]
            fraction = parts[1][parts[1].index(after: dot)...]
        } else {
            secondsPart = parts[1]
        }

        guard let seconds = Int(secondsPart), (0..<60).contains(seconds), fraction.allSatisfy(\.isNumber) else { return nil }
        var fractionMs = 0
        if !fraction.isEmpty {
            let padded = (String(fraction) + "000").prefix(3)
            fractionMs = Int(padded) ?? 0
        }
        return (minutes * 60 + seconds) * 1000 + fractionMs
    }
}
