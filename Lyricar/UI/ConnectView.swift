import AuthenticationServices
import SwiftUI

/// One room, one action: connect Spotify.
struct ConnectView: View {
    let model: AppModel
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var isWorking = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            Text("Lyricar")
                .font(Theme.lyric(52))
                .foregroundStyle(Theme.ink)
            Text("Lyrics that keep time with Spotify.\nOn your phone, your Lock Screen and in the car.")
                .font(Theme.label(18))
                .foregroundStyle(Theme.dim)
                .padding(.top, 10)
            Spacer()

            if let errorText {
                Text(errorText)
                    .font(Theme.label(14))
                    .foregroundStyle(Theme.accent)
                    .padding(.bottom, 14)
                    .transition(.opacity.combined(with: .offset(y: 6)))
            }

            Button(action: connect) {
                HStack(spacing: 10) {
                    if isWorking {
                        ProgressView().tint(Theme.stage)
                    }
                    Text(isWorking ? "Waiting for Spotify" : "Connect Spotify")
                        .contentTransition(.interpolate)
                }
                .font(Theme.label(18))
                .foregroundStyle(Theme.stage)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Theme.accent, in: .capsule)
            }
            .buttonStyle(PressableStyle())
            .disabled(isWorking || model.auth == nil)

            if model.auth == nil {
                Text("SPOTIFY_CLIENT_ID is missing from this build. Run scripts/setup.sh.")
                    .font(Theme.label(13))
                    .foregroundStyle(Theme.dim)
                    .padding(.top, 12)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .animation(Theme.settle, value: errorText)
        .animation(Theme.settle, value: isWorking)
    }

    private func connect() {
        guard let auth = model.auth else { return }
        isWorking = true
        errorText = nil
        Task {
            let loopback = LoopbackRedirectServer()
            defer {
                loopback.stop()
                isWorking = false
            }
            let pkce = SpotifyAuth.PKCE()
            let state = UUID().uuidString
            do {
                try loopback.start()
                let callback = try await webAuthenticationSession.authenticate(
                    using: auth.authorizeURL(pkce: pkce, state: state),
                    callback: .customScheme(SpotifyAuth.callbackScheme),
                    preferredBrowserSession: .shared,
                    additionalHeaderFields: [:]
                )
                try await auth.complete(callback: callback, pkce: pkce, expectedState: state)
                model.connect(with: auth, note: nil)
            } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
                // The user closed the sheet; nothing to report.
            } catch {
                errorText = "Spotify did not accept the sign-in. Try again, and check that port 3000 is free."
            }
        }
    }
}

/// Press feedback for every tappable surface.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.timingCurve(0.2, 0, 0, 1, duration: 0.12), value: configuration.isPressed)
    }
}
