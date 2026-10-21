import Foundation
import Testing
@testable import LyricsKit

/// Serves canned LRCLIB answers keyed by whether the request carries an album.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let (status, data) = Self.handler?(request) ?? (500, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}

@Suite(.serialized) struct LRCLibFallbackTests {
    let track = SpotifyTrack(id: "t", name: "Midnight City", artists: ["M83"], album: "Midnight City", artworkURL: nil, durationMs: 241_000)

    func client() -> LRCLibClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return LRCLibClient(session: URLSession(configuration: configuration))
    }

    @Test func albumLookup503FallsBackToLookupWithoutAlbum() async throws {
        StubProtocol.handler = { request in
            let query = request.url?.query ?? ""
            if query.contains("album_name") { return (503, Data()) }
            if request.url?.path == "/api/get" {
                return (200, Data(#"{"duration":241,"instrumental":false,"syncedLyrics":"[00:37.68] Waiting in a car"}"#.utf8))
            }
            return (404, Data())
        }
        let document = try #require(try await client().lyrics(for: track))
        #expect(document.syncType == .lineSynced)
        #expect(document.lines.first?.text == "Waiting in a car")
    }

    @Test func everyAttemptFailingThrowsSoTheMissIsNotCached() async {
        StubProtocol.handler = { _ in (503, Data()) }
        await #expect(throws: SpotifyError.self) { try await client().lyrics(for: track) }
    }

    @Test func definitiveMissReturnsNil() async throws {
        StubProtocol.handler = { request in request.url?.path == "/api/search" ? (200, Data("[]".utf8)) : (404, Data()) }
        #expect(try await client().lyrics(for: track) == nil)
    }
}
