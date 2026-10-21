import Foundation
import Testing
@testable import LyricsKit

/// Answers every Spotify request with 401, as Spotify does for a revoked token.
final class UnauthorizedProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }
}

actor CountingTokens: AccessTokenProvider {
    private(set) var invalidations = 0
    func accessToken() async throws -> String { "token" }
    func invalidateAccessToken() async { invalidations += 1 }
}

struct BackgroundRecoveryTests {
    func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UnauthorizedProtocol.self]
        return URLSession(configuration: configuration)
    }

    /// A token Spotify rejects before its local expiry must be refreshed, not reused forever.
    @Test func rejectedTokenIsInvalidatedByPollsAndCommands() async {
        let tokens = CountingTokens()
        let client = SpotifyClient(tokens: tokens, session: session())
        await #expect(throws: SpotifyError.unauthorized) { try await client.currentlyPlaying() }
        await #expect(throws: SpotifyError.unauthorized) { try await client.send(.next) }
        #expect(await tokens.invalidations == 2)
    }

    /// Long songs used to stop at 60 entries and freeze the widget on that line.
    @Test func timelineCoversLongSongs() {
        let lines = (0..<150).map { LyricLine(id: $0, startMs: 1000 + $0 * 1500, text: "line \($0)") }
        let now = Date()
        let snapshot = LyricsSnapshot(
            trackName: "Long", artist: "A", provider: "LRCLIB",
            document: LyricsDocument(syncType: .lineSynced, lines: lines, provider: "LRCLIB"),
            isPlaying: true, durationMs: 300_000, trackStartDate: now, pausedPositionMs: 0, updatedAt: now
        )
        let timeline = snapshot.timeline(from: now)
        #expect(timeline.count == 151)
        #expect(timeline.last?.lineIndex == 149)
    }
}

/// Rejects the first poll as unauthorized, then plays: a token refreshed in between.
final class RecoveringSource: NowPlayingSource, @unchecked Sendable {
    var calls = 0
    let track = SpotifyTrack(id: "t", name: "Song", artists: ["A"], album: "B", artworkURL: nil, durationMs: 200_000)

    func currentlyPlaying() async throws -> NowPlaying? {
        calls += 1
        if calls == 2 { throw SpotifyError.unauthorized }
        let sample = PlaybackSample(trackID: "t", progressMs: 10_000, durationMs: 200_000, isPlaying: true, sampledAt: Date())
        return NowPlaying(track: track, sample: sample, rttMs: 20)
    }
}

@MainActor @Suite struct SignedOutRecoveryTests {
    @Test func goodPollAfterRejectedTokenClearsSignedOut() async {
        let engine = LyricsEngine(offsets: UserDefaults(suiteName: "lyricar.tests.\(UUID())")!)
        let source = RecoveringSource()
        engine.connect(source)
        engine.stop() // Drive polls by hand.
        await engine.pollOnce()
        await engine.pollOnce()
        #expect(engine.status == .signedOut)
        await engine.pollOnce()
        #expect(engine.status != .signedOut)
    }
}
