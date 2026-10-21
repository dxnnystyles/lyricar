#if DEBUG
import Foundation
import LyricsKit

/// Debug-only stand-in for Spotify, enabled with the `-LyricarDemo` launch argument.
/// It fakes only the playback clock; lyrics still come from LRCLIB through the real
/// engine, so every surface renders real data. Used for screenshots when nothing
/// is playing on the account.
final class DemoSource: NowPlayingSource, PlayerControlling, @unchecked Sendable {
    /// Wall-clock moment the fake track was at 0 ms; commands move it like Spotify would.
    private var started = Date().addingTimeInterval(-34)
    private var pausedAt: Int?
    let track = SpotifyTrack(
        id: "demo-midnight-city",
        name: "Midnight City",
        artists: ["M83"],
        album: "Midnight City",
        artworkURL: nil,
        durationMs: 241_000
    )

    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-LyricarDemo") }

    func currentlyPlaying() async throws -> NowPlaying? {
        let now = Date()
        let progress = pausedAt ?? Int(now.timeIntervalSince(started) * 1000) % track.durationMs
        let sample = PlaybackSample(trackID: track.id, progressMs: progress, durationMs: track.durationMs,
                                    isPlaying: pausedAt == nil, sampledAt: now)
        return NowPlaying(track: track, sample: sample, rttMs: 0)
    }

    func send(_ command: PlayerCommand) async throws {
        NSLog("LYRICAR-DEMO received %@", String(describing: command))
        let now = Date()
        let position = pausedAt ?? Int(now.timeIntervalSince(started) * 1000) % track.durationMs
        switch command {
        case .seek(let ms):
            if pausedAt != nil { pausedAt = ms } else { started = now.addingTimeInterval(-Double(ms) / 1000) }
        case .pause:
            pausedAt = position
        case .play:
            if let paused = pausedAt { started = now.addingTimeInterval(-Double(paused) / 1000) }
            pausedAt = nil
        case .next, .previous:
            started = now
            pausedAt = nil
        }
    }
}
#endif
