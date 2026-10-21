import ActivityKit
import Foundation

/// One Live Activity per listening session. The track lives in the content state,
/// so a track change updates the activity instead of ending and restarting it.
struct LyricActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var trackName: String
        var artist: String
        var currentLine: String
        var nextLine: String?
        var lineNumber: Int
        var lineCount: Int
        var isPlaying: Bool
        /// Wall-clock start and end of the track, so `ProgressView(timerInterval:)`
        /// animates the progress bar without further updates.
        var trackStart: Date
        var trackEnd: Date
        var pausedFraction: Double
        /// Optional so activities started by an older build (no style field) still decode.
        var themeRaw: String?

        var theme: LyricTheme { themeRaw.flatMap(LyricTheme.init(rawValue:)) ?? .midnight }
    }

    var sessionStarted: Date
}

extension LyricActivityAttributes.ContentState {
    static let preview = LyricActivityAttributes.ContentState(
        trackName: "Open Road",
        artist: "Lyricar",
        currentLine: "Every mile a line I know",
        nextLine: "Radio low, the city sleeps",
        lineNumber: 2,
        lineCount: 31,
        isPlaying: true,
        trackStart: .now.addingTimeInterval(-40),
        trackEnd: .now.addingTimeInterval(203),
        pausedFraction: 0.16,
        themeRaw: LyricTheme.motorsport.rawValue
    )
}
