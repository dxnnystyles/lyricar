import Foundation
import Testing
@testable import LyricsKit

/// Reproductions for "lyrics drift out of sync". Each test is a scenario seen in
/// the field, driven with synthetic samples so it is deterministic.
@Suite struct SyncPrecisionTests {
    let t0 = Date(timeIntervalSince1970: 3_000_000)

    /// The truth: a track that started exactly at `t0` and keeps playing.
    func truthSample(at offset: TimeInterval, rttMs: Int, serverLagMs: Int = 0) -> (PlaybackSample, Int) {
        // The server answers somewhere inside the round trip; we only know the midpoint.
        let sampledAt = t0.addingTimeInterval(offset)
        let progress = Int(offset * 1000) - serverLagMs
        return (PlaybackSample(trackID: "x", progressMs: progress, durationMs: 300_000, isPlaying: true, sampledAt: sampledAt), rttMs)
    }

    @Test func steadyOffsetBelowOldToleranceIsCorrected() {
        var clock = PlaybackClock()
        // First sample is 300 ms off (slow first request), then precise samples arrive.
        let (bad, badRTT) = truthSample(at: 1, rttMs: 900, serverLagMs: 300)
        clock.ingest(bad, rttMs: badRTT)
        for second in 2...8 {
            let (good, rtt) = truthSample(at: TimeInterval(second), rttMs: 80)
            clock.ingest(good, rttMs: rtt)
        }
        let error = clock.position(at: t0.addingTimeInterval(10))! - 10_000
        #expect(abs(error) <= 60, "residual error \(error) ms")
    }

    @Test func noisySamplesDoNotPullTheClockAway() {
        var clock = PlaybackClock()
        let (precise, rtt) = truthSample(at: 1, rttMs: 60)
        clock.ingest(precise, rttMs: rtt)
        // A slow response whose midpoint guess is 400 ms wrong must not win over the precise one.
        let (noisy, noisyRTT) = truthSample(at: 3, rttMs: 1200, serverLagMs: 400)
        clock.ingest(noisy, rttMs: noisyRTT)
        let error = clock.position(at: t0.addingTimeInterval(5))! - 5000
        #expect(abs(error) <= 60, "residual error \(error) ms")
    }

    @Test func seekIsAppliedImmediately() {
        var clock = PlaybackClock()
        let (a, rtt) = truthSample(at: 1, rttMs: 80)
        clock.ingest(a, rttMs: rtt)
        let seek = PlaybackSample(trackID: "x", progressMs: 120_000, durationMs: 300_000, isPlaying: true, sampledAt: t0.addingTimeInterval(2))
        #expect(clock.ingest(seek, rttMs: 900) == true)
        #expect(clock.position(at: t0.addingTimeInterval(2)) == 120_000)
    }

    @Test func pollingStaysFastWhenPausedSoResumeIsCaughtQuickly() {
        #expect(LyricsEngine.pollInterval(isPlaying: false, hasTrack: true, foreground: true) <= .milliseconds(1000))
        #expect(LyricsEngine.pollInterval(isPlaying: true, hasTrack: true, foreground: true) <= .milliseconds(1000))
        #expect(LyricsEngine.pollInterval(isPlaying: true, hasTrack: true, foreground: false) <= .milliseconds(2000))
    }
}
