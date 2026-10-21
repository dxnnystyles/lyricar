import AuthenticationServices
import CryptoKit
import Foundation
import LyricsKit
import Security

/// Authorization Code with PKCE. No client secret ships in the app.
/// Tokens live in the Keychain and refresh on demand.
actor SpotifyAuth: AccessTokenProvider {
    struct Tokens: Codable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
        /// Space-separated scopes Spotify granted. Nil for tokens stored by older builds.
        var scope: String?
    }

    /// False when the stored session predates playback control and needs one reconnect.
    var canControlPlayback: Bool {
        tokens?.scope?.split(separator: " ").contains("user-modify-playback-state") ?? false
    }

    /// Already registered on the Spotify app; see LoopbackRedirectServer.
    static let redirectURI = LoopbackRedirectServer.redirectURI
    static let callbackScheme = "lyricar"
    static let scopes = "user-read-currently-playing user-read-playback-state user-modify-playback-state"

    let clientID: String
    private var tokens: Tokens?
    private var refreshTask: Task<Tokens, Error>?

    init(clientID: String) {
        self.clientID = clientID
        self.tokens = Keychain.load()
    }

    var isSignedIn: Bool { tokens != nil }

    func accessToken() async throws -> String {
        guard let current = tokens else { throw SpotifyError.unauthorized }
        if current.expiresAt.timeIntervalSinceNow > 60 { return current.accessToken }
        return try await refresh(current).accessToken
    }

    /// Spotify rejected the access token before its local expiry: refresh on the next call.
    func invalidateAccessToken() {
        tokens?.expiresAt = .distantPast
    }

    func signOut() {
        tokens = nil
        Keychain.delete()
    }

    // MARK: Sign in

    struct PKCE {
        let verifier: String
        let challenge: String

        init() {
            var bytes = [UInt8](repeating: 0, count: 64)
            _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            verifier = Data(bytes).base64URL
            challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        }
    }

    nonisolated func authorizeURL(pkce: PKCE, state: String) -> URL {
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url!
    }

    /// Finishes the flow with the callback URL from `WebAuthenticationSession`.
    func complete(callback: URL, pkce: PKCE, expectedState: String) async throws {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == expectedState,
              let code = items.first(where: { $0.name == "code" })?.value else {
            throw SpotifyError.unauthorized
        }
        let response = try await tokenRequest([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
            "client_id": clientID,
            "code_verifier": pkce.verifier,
        ])
        store(response, previousRefresh: nil)
    }

    // MARK: Refresh

    private func refresh(_ current: Tokens) async throws -> Tokens {
        if let refreshTask { return try await refreshTask.value }
        let task = Task { () throws -> Tokens in
            let response = try await tokenRequest([
                "grant_type": "refresh_token",
                "refresh_token": current.refreshToken,
                "client_id": clientID,
            ])
            return store(response, previousRefresh: current.refreshToken)
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            return try await task.value
        } catch SpotifyError.unauthorized {
            signOut()
            throw SpotifyError.unauthorized
        }
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Double
        let scope: String?
    }

    private func tokenRequest(_ form: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((components.percentEncodedQuery ?? "").utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 400 || status == 401 { throw SpotifyError.unauthorized }
        guard status == 200 else { throw SpotifyError.http(status) }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    @discardableResult
    private func store(_ response: TokenResponse, previousRefresh: String?) -> Tokens {
        // Spotify may rotate the refresh token; keep the old one when it does not.
        let new = Tokens(
            accessToken: response.access_token,
            refreshToken: response.refresh_token ?? previousRefresh ?? "",
            expiresAt: Date().addingTimeInterval(response.expires_in),
            scope: response.scope ?? tokens?.scope
        )
        tokens = new
        Keychain.save(new)
        return new
    }
}

private enum Keychain {
    /// Derived from the bundle ID, so each fork keeps its own item.
    static let service = "\(Bundle.main.bundleIdentifier ?? "lyricar").spotify"

    static func save(_ tokens: SpotifyAuth.Tokens) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        delete()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: data,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load() -> SpotifyAuth.Tokens? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(SpotifyAuth.Tokens.self, from: data)
    }

    static func delete() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
    }
}

private extension Data {
    var base64URL: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
