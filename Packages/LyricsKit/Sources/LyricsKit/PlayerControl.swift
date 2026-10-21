import Foundation

public enum PlayerCommand: Sendable, Equatable {
    case play, pause, next, previous
    case seek(toMs: Int)
}

public enum PlayerControlError: Error, Equatable, Sendable {
    /// Spotify only allows playback control for Premium accounts.
    case premiumRequired
    /// No phone, computer or speaker is currently active in Spotify.
    case noActiveDevice
    case failed(Int)
}

/// Sources that can also steer playback. The Spotify client does; read-only sources need not.
public protocol PlayerControlling: Sendable {
    func send(_ command: PlayerCommand) async throws
}

extension SpotifyClient: PlayerControlling {
    /// Web API player endpoints. Scope: user-modify-playback-state.
    public func send(_ command: PlayerCommand) async throws {
        let (method, path): (String, String) = {
            switch command {
            case .play: return ("PUT", "play")
            case .pause: return ("PUT", "pause")
            case .next: return ("POST", "next")
            case .previous: return ("POST", "previous")
            case .seek(let ms): return ("PUT", "seek?position_ms=\(max(0, ms))")
            }
        }()
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/\(path)")!)
        request.httpMethod = method
        request.setValue("Bearer \(try await tokens.accessToken())", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 8
        let (_, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200...299: return
        case 401:
            await tokens.invalidateAccessToken()
            throw SpotifyError.unauthorized
        case 403: throw PlayerControlError.premiumRequired
        case 404: throw PlayerControlError.noActiveDevice
        case 429: throw SpotifyError.rateLimited(retryAfter: 2)
        default: throw PlayerControlError.failed(status)
        }
    }
}
