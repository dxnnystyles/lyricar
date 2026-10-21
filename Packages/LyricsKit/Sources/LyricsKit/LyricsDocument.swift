import Foundation

/// Mirrors a common shape for synced lyrics (`syncType`, `lines`, `provider`).
/// The data itself comes from LRCLIB, a public lyrics database, not from Spotify.
public enum SyncType: String, Codable, Sendable {
    case lineSynced
    case unsynced
}

public struct LyricLine: Codable, Hashable, Identifiable, Sendable {
    public var id: Int
    /// Start of the line in milliseconds from track start. Zero for unsynced lyrics.
    public var startMs: Int
    public var text: String

    public init(id: Int, startMs: Int, text: String) {
        self.id = id
        self.startMs = startMs
        self.text = text
    }

    /// Empty LRC lines mark instrumental gaps.
    public var isInstrumental: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }

    public var displayText: String { isInstrumental ? "\u{266A}" : text }
}

public struct LyricsDocument: Codable, Hashable, Sendable {
    public var syncType: SyncType
    public var lines: [LyricLine]
    public var provider: String

    public init(syncType: SyncType, lines: [LyricLine], provider: String) {
        self.syncType = syncType
        self.lines = lines
        self.provider = provider
    }

    /// Index of the line that is active at `positionMs`, or nil before the first line.
    /// Lines are sorted by `startMs`, so this is a binary search for the last start <= position.
    public func lineIndex(at positionMs: Int) -> Int? {
        guard syncType == .lineSynced, !lines.isEmpty else { return nil }
        var low = 0
        var high = lines.count - 1
        var found: Int?
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].startMs <= positionMs {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return found
    }

    /// Lines around `index`, clamped to the document. Used by every compact view.
    public func window(around index: Int?, before: Int, after: Int) -> ArraySlice<LyricLine> {
        guard !lines.isEmpty else { return [] }
        let center = index ?? -1
        let lower = max(0, center - before)
        let upper = min(lines.count - 1, max(center, 0) + after)
        guard lower <= upper else { return [] }
        return lines[lower...upper]
    }
}
