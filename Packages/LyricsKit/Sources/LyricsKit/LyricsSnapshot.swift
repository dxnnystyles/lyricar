import Foundation

/// Everything a widget needs to render lyrics without the app running.
/// Written to the App Group by the app, read by the widget extension.
public struct LyricsSnapshot: Codable, Hashable, Sendable {
    public var trackName: String
    public var artist: String
    public var provider: String
    public var document: LyricsDocument?
    public var isPlaying: Bool
    public var durationMs: Int
    /// Wall-clock moment the track was at 0 ms. Only meaningful while playing.
    public var trackStartDate: Date
    /// Position to show while paused.
    public var pausedPositionMs: Int
    public var updatedAt: Date

    public init(trackName: String, artist: String, provider: String, document: LyricsDocument?, isPlaying: Bool,
                durationMs: Int, trackStartDate: Date, pausedPositionMs: Int, updatedAt: Date) {
        self.trackName = trackName
        self.artist = artist
        self.provider = provider
        self.document = document
        self.isPlaying = isPlaying
        self.durationMs = durationMs
        self.trackStartDate = trackStartDate
        self.pausedPositionMs = pausedPositionMs
        self.updatedAt = updatedAt
    }

    /// App Group shared by the app and the widget extension. Read from the `LyricarAppGroup`
    /// Info.plist key, which the build derives from `LYRICAR_BUNDLE_PREFIX`. Without the key
    /// (tests, other hosts) it falls back to `group.` plus the app's bundle ID.
    public static let appGroup: String = {
        if let group = Bundle.main.object(forInfoDictionaryKey: "LyricarAppGroup") as? String, !group.isEmpty {
            return group
        }
        var id = Bundle.main.bundleIdentifier ?? "lyricar"
        for suffix in [".widgets", ".uitests"] where id.hasSuffix(suffix) {
            id.removeLast(suffix.count)
        }
        return "group." + id
    }()
    static let key = "lyrics.snapshot.v1"

    public var trackEndDate: Date { trackStartDate.addingTimeInterval(Double(durationMs) / 1000) }

    public func positionMs(at date: Date) -> Int {
        guard isPlaying else { return pausedPositionMs }
        return min(durationMs, max(0, Int(date.timeIntervalSince(trackStartDate) * 1000)))
    }

    /// Timeline entries for a widget: one at `now`, then one at each upcoming line start
    /// until the track ends or `limit` is reached. WidgetKit renders them on schedule,
    /// so the widget follows the song with zero app wake-ups. The limit is above the line
    /// count of nearly every LRC file; the widget asks for a fresh timeline after the last
    /// entry anyway, so a longer song continues instead of freezing.
    public static let timelineLimit = 200

    public func timeline(from now: Date, limit: Int = timelineLimit) -> [(date: Date, lineIndex: Int?)] {
        let first = (now, document?.lineIndex(at: positionMs(at: now)))
        guard isPlaying, let document, document.syncType == .lineSynced, now < trackEndDate else { return [first] }

        let position = positionMs(at: now)
        let upcoming = document.lines
            .filter { $0.startMs > position }
            .prefix(limit - 1)
            .map { (trackStartDate.addingTimeInterval(Double($0.startMs) / 1000), Optional($0.id)) }
        return [first] + upcoming
    }

    public func save(to defaults: UserDefaults? = UserDefaults(suiteName: appGroup)) {
        guard let defaults, let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
    }

    public static func load(from defaults: UserDefaults? = UserDefaults(suiteName: appGroup)) -> LyricsSnapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(LyricsSnapshot.self, from: data)
    }

    public static let placeholder = LyricsSnapshot(
        trackName: "Open Road",
        artist: "Lyricar",
        provider: "LRCLIB",
        document: LyricsDocument(syncType: .lineSynced, lines: [
            LyricLine(id: 0, startMs: 0, text: "Headlights on an empty road"),
            LyricLine(id: 1, startMs: 4000, text: "Every mile a line I know"),
            LyricLine(id: 2, startMs: 9000, text: "Radio low, the city sleeps"),
            LyricLine(id: 3, startMs: 13000, text: "Sing it back before it fades"),
        ], provider: "LRCLIB"),
        isPlaying: false,
        durationMs: 243_000,
        trackStartDate: .distantPast,
        pausedPositionMs: 5000,
        updatedAt: .distantPast
    )
}
