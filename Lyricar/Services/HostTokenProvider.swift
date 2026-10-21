#if DEBUG && targetEnvironment(simulator)
import Foundation
import LyricsKit

/// Simulator-only shortcut: reuses a Spotify access token that another tool on the host
/// Mac keeps fresh, so the CarPlay simulator works without signing in. Opt-in through
/// the `LYRICAR_HOST_TOKEN_FILE` environment variable, an absolute host path to a JSON
/// file `{"access_token": "...", "expires_at": <epoch milliseconds>}`. Simulator apps do
/// not inherit the shell environment: set it in the scheme's Run environment, or launch
/// with `SIMCTL_CHILD_LYRICAR_HOST_TOKEN_FILE=/path/token.json xcrun simctl launch ...`.
/// Read-only: it never refreshes or writes the file, so it cannot rotate the host's
/// refresh token.
struct HostTokenProvider: AccessTokenProvider {
    static var path: String? {
        ProcessInfo.processInfo.environment["LYRICAR_HOST_TOKEN_FILE"].flatMap { $0.isEmpty ? nil : $0 }
    }

    static var isAvailable: Bool {
        path.map(FileManager.default.isReadableFile(atPath:)) ?? false
    }

    private struct File: Decodable {
        let access_token: String
        let expires_at: Double
    }

    func accessToken() async throws -> String {
        guard let path = Self.path, let data = FileManager.default.contents(atPath: path) else {
            throw SpotifyError.notConfigured("No host token file")
        }
        let file = try JSONDecoder().decode(File.self, from: data)
        // expires_at is epoch milliseconds. An expired token means the host tool that
        // writes the file has not refreshed it recently.
        guard file.expires_at / 1000 > Date().timeIntervalSince1970 else { throw SpotifyError.unauthorized }
        return file.access_token
    }
}
#endif
