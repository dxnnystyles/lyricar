import AppIntents
import SwiftUI

/// Previous, play/pause, next as intent buttons for Live Activities and widgets.
struct IntentTransport: View {
    let theme: LyricTheme
    let isPlaying: Bool
    var tint: Color? = nil

    var body: some View {
        HStack(spacing: 22) {
            Button(intent: LyricPlaybackIntent(.previous)) { Image(systemName: "backward.fill") }
                .accessibilityLabel("Previous song")
            Button(intent: LyricPlaybackIntent(.playPause)) { Image(systemName: isPlaying ? "pause.fill" : "play.fill") }
                .accessibilityLabel(isPlaying ? "Pause" : "Play")
            Button(intent: LyricPlaybackIntent(.next)) { Image(systemName: "forward.fill") }
                .accessibilityLabel("Next song")
        }
        .buttonStyle(.plain)
        .font(.system(size: 17, weight: .bold))
        .foregroundStyle(tint ?? theme.ink)
    }
}
