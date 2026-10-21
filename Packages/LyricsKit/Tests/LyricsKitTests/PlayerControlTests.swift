import Foundation
import Testing
@testable import LyricsKit

/// A source that is playing one track and records the commands it receives.
final class FakePlayer: NowPlayingSource, PlayerControlling, @unchecked Sendable {
    var commands: [PlayerCommand] = []
    let started = Date().addingTimeInterval(-30)
    let track = SpotifyTrack(id: "t", name: "Song", artists: ["A"], album: "B", artworkURL: nil, durationMs: 200_000)

    func currentlyPlaying() async throws -> NowPlaying? {
        let sample = PlaybackSample(trackID: "t", progressMs: Int(Date().timeIntervalSince(started) * 1000),
                                    durationMs: 200_000, isPlaying: true, sampledAt: Date())
        return NowPlaying(track: track, sample: sample, rttMs: 20)
    }

    func send(_ command: PlayerCommand) async throws { commands.append(command) }
}

@MainActor @Suite struct PlayerControlTests {
    @Test func seekMovesLyricsImmediatelyAndReachesSpotify() async throws {
        let engine = LyricsEngine(offsets: UserDefaults(suiteName: "lyricar.tests.\(UUID())")!)
        let player = FakePlayer()
        engine.connect(player)
        defer { engine.stop() }
        engine.apply(try await player.currentlyPlaying())
        #expect(abs((engine.positionMs() ?? 0) - 30_000) < 200)

        engine.perform(.seek(toMs: 120_000))
        // Optimistic: no network round trip needed for the lyrics to jump.
        #expect(abs((engine.positionMs() ?? 0) - 120_000) < 200)
        try await Task.sleep(for: .milliseconds(50))
        #expect(player.commands == [.seek(toMs: 120_000)])
    }

    @Test func pauseFreezesLyricsAtOnce() async throws {
        let engine = LyricsEngine(offsets: UserDefaults(suiteName: "lyricar.tests.\(UUID())")!)
        let player = FakePlayer()
        engine.connect(player)
        defer { engine.stop() }
        engine.apply(try await player.currentlyPlaying())
        engine.perform(.pause)
        #expect(engine.isPlaying == false)
        let frozen = engine.positionMs()
        try await Task.sleep(for: .milliseconds(120))
        #expect(engine.positionMs() == frozen)
    }
}
