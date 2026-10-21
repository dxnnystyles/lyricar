import Foundation
import Network

/// Lets sign-in use the redirect URI the Spotify app already has registered,
/// `http://127.0.0.1:3000/spotify/callback`, so no dashboard change is needed.
///
/// While the sign-in sheet is open, this listens on the phone's own loopback port 3000.
/// Spotify redirects the sheet there; the server answers with a 302 to
/// `lyricar://callback?<same query>`, which `WebAuthenticationSession` recognizes as
/// its callback and completes. Nothing ever leaves the device.
final class LoopbackRedirectServer: @unchecked Sendable {
    static let port: UInt16 = 3000
    static let path = "/spotify/callback"
    static var redirectURI: String { "http://127.0.0.1:\(port)\(path)" }

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "lyricar.loopback")

    func start() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.port)!)
        // No address reuse: if anything else already holds port 3000, binding fails and
        // sign-in reports an error instead of sharing the port with a possible interceptor.
        // An intercepted code would still be useless: PKCE keeps the verifier in this
        // process, and SpotifyAuth.complete checks the state value.
        parameters.allowLocalEndpointReuse = false
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, _ in
            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let response = Self.response(for: request)
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    /// Pure function so it is easy to reason about: request text in, HTTP response text out.
    static func response(for request: String) -> String {
        let target = request.split(separator: "\r\n").first?.split(separator: " ").dropFirst().first.map(String.init) ?? ""
        guard target.hasPrefix(path), let query = URLComponents(string: target)?.percentEncodedQuery else {
            return "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        }
        let location = "lyricar://callback?\(query)"
        let body = "<html><body style=\"background:#0b0b0f;color:#fff;font-family:-apple-system\">Back to Lyricar\u{2026}</body></html>"
        return "HTTP/1.1 302 Found\r\nLocation: \(location)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
    }
}

#if DEBUG
/// `-LyricarLoopbackSelfTest`: starts the server, requests a fake callback over real
/// loopback TCP, and logs the Location header it answered with.
enum LoopbackSelfTest {
    final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? { nil }
    }

    static func runIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-LyricarLoopbackSelfTest") else { return }
        Task {
            let server = LoopbackRedirectServer()
            do {
                try server.start()
                try await Task.sleep(for: .milliseconds(300))
                let url = URL(string: LoopbackRedirectServer.redirectURI + "?code=TESTCODE&state=TESTSTATE")!
                let session = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
                let (_, response) = try await session.data(from: url)
                let http = response as? HTTPURLResponse
                NSLog("LYRICAR-LOOPBACK status=%d location=%@", http?.statusCode ?? -1, http?.value(forHTTPHeaderField: "Location") ?? "nil")
            } catch {
                NSLog("LYRICAR-LOOPBACK error=%@", String(describing: error))
            }
            server.stop()
        }
    }
}
#endif
