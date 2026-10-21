import LyricsKit
import SwiftUI
import UIKit

/// Previous, play/pause, next. Lyrics react on the tap (the engine moves its clock
/// optimistically); Spotify confirms on the following poll.
struct TransportControls: View {
    let engine: LyricsEngine

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 36) {
                control("backward.fill", label: "Previous") { engine.perform(.previous) }
                control(engine.isPlaying ? "pause.fill" : "play.fill", label: engine.isPlaying ? "Pause" : "Play", size: 30) {
                    engine.perform(engine.isPlaying ? .pause : .play)
                }
                control("forward.fill", label: "Next") { engine.perform(.next) }
            }
            if AppModel.shared.needsReconnectForControls {
                Text("Reconnect Spotify (menu, Disconnect, Connect) to use these controls.")
                    .font(Theme.label(12))
                    .foregroundStyle(Theme.accent)
                    .multilineTextAlignment(.center)
            } else if let error = engine.controlError {
                Text(message(for: error))
                    .font(Theme.label(12))
                    .foregroundStyle(Theme.accent)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
        }
        .animation(Theme.settle, value: engine.controlError)
    }

    private func control(_ symbol: String, label: String, size: CGFloat = 22, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .bold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(Theme.ink)
                .frame(width: 52, height: 44)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }

    private func message(for error: PlayerControlError) -> String {
        switch error {
        case .premiumRequired: return "Spotify allows playback control with Premium, or reconnect Spotify to grant it."
        case .noActiveDevice: return "No active Spotify device. Start playback in Spotify once."
        case .failed(let status): return "Spotify did not accept that (\(status))."
        }
    }
}

/// Opens the current track in the Spotify app, or on the web if the app is missing.
struct OpenInSpotifyButton: View {
    let track: SpotifyTrack?

    var body: some View {
        if let track {
            Button {
                SpotifyLink.open(track)
            } label: {
                Image(systemName: "arrow.up.right.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Open in Spotify")
        }
    }
}

enum SpotifyLink {
    static func url(for track: SpotifyTrack) -> URL {
        URL(string: "spotify:track:\(track.id)")!
    }

    static func webURL(for track: SpotifyTrack) -> URL {
        URL(string: "https://open.spotify.com/track/\(track.id)")!
    }

    @MainActor static func open(_ track: SpotifyTrack) {
        let app = url(for: track)
        if UIApplication.shared.canOpenURL(app) {
            UIApplication.shared.open(app)
        } else {
            UIApplication.shared.open(webURL(for: track))
        }
    }
}
