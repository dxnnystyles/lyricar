import Foundation

public struct SpotifyTrack: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var artists: [String]
    public var album: String
    public var artworkURL: URL?
    public var durationMs: Int

    public var artistLine: String { artists.joined(separator: ", ") }

    public init(id: String, name: String, artists: [String], album: String, artworkURL: URL?, durationMs: Int) {
        self.id = id
        self.name = name
        self.artists = artists
        self.album = album
        self.artworkURL = artworkURL
        self.durationMs = durationMs
    }
}

public struct NowPlaying: Sendable {
    public var track: SpotifyTrack
    public var sample: PlaybackSample
    /// Round trip of the request that produced `sample`; bounds its timing error.
    public var rttMs: Int

    public init(track: SpotifyTrack, sample: PlaybackSample, rttMs: Int = 200) {
        self.track = track
        self.sample = sample
        self.rttMs = rttMs
    }
}

/// Anything that can say what is playing: the Spotify Web API, or a demo clock.
public protocol NowPlayingSource: Sendable {
    func currentlyPlaying() async throws -> NowPlaying?
}

public protocol AccessTokenProvider: Sendable {
    func accessToken() async throws -> String
    /// Called when Spotify rejected the current token (401) although it had not expired
    /// locally, for example after a server-side revocation. The next call must refresh.
    func invalidateAccessToken() async
}

public extension AccessTokenProvider {
    func invalidateAccessToken() async {}
}

public enum SpotifyError: Error, Equatable, Sendable {
    case unauthorized
    case rateLimited(retryAfter: TimeInterval)
    case http(Int)
    case notConfigured(String)
}

/// Reads the Spotify Web API player endpoint. Scopes: user-read-currently-playing,
/// user-read-playback-state.
public struct SpotifyClient: NowPlayingSource {
    let tokens: AccessTokenProvider
    let session: URLSession

    public init(tokens: AccessTokenProvider, session: URLSession = .shared) {
        self.tokens = tokens
        self.session = session
    }

    /// Returns nil when nothing is playing or the item is not a track (ads, episodes).
    public func currentlyPlaying() async throws -> NowPlaying? {
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/currently-playing")!)
        request.setValue("Bearer \(try await tokens.accessToken())", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 8

        let started = Date()
        let (data, response) = try await session.data(for: request)
        let finished = Date()
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        switch status {
        case 200: break
        case 204: return nil
        case 401:
            await tokens.invalidateAccessToken()
            throw SpotifyError.unauthorized
        case 429:
            let retry = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init) ?? 5
            throw SpotifyError.rateLimited(retryAfter: retry)
        default: throw SpotifyError.http(status)
        }

        let midpoint = started.addingTimeInterval(finished.timeIntervalSince(started) / 2)
        let rtt = Int(finished.timeIntervalSince(started) * 1000)
        syncLog.notice("RTT \(rtt)")
        var result = try Self.decode(data, sampledAt: midpoint)
        result?.rttMs = rtt
        return result
    }

    static func decode(_ data: Data, sampledAt: Date) throws -> NowPlaying? {
        let payload = try JSONDecoder().decode(CurrentlyPlayingPayload.self, from: data)
        guard let item = payload.item, payload.currently_playing_type == "track", let id = item.id else { return nil }
        let track = SpotifyTrack(
            id: id,
            name: item.name,
            artists: item.artists.map(\.name),
            album: item.album?.name ?? "",
            artworkURL: item.album?.images.first.flatMap { URL(string: $0.url) },
            durationMs: item.duration_ms
        )
        let sample = PlaybackSample(
            trackID: id,
            progressMs: payload.progress_ms ?? 0,
            durationMs: item.duration_ms,
            isPlaying: payload.is_playing,
            sampledAt: sampledAt
        )
        return NowPlaying(track: track, sample: sample)
    }
}

// Field names follow the Web API response.
struct CurrentlyPlayingPayload: Decodable {
    struct Item: Decodable {
        struct Artist: Decodable { let name: String }
        struct Album: Decodable {
            struct Image: Decodable { let url: String }
            let name: String
            let images: [Image]
        }
        let id: String?
        let name: String
        let duration_ms: Int
        let artists: [Artist]
        let album: Album?
    }
    let progress_ms: Int?
    let is_playing: Bool
    let currently_playing_type: String
    let item: Item?
}
