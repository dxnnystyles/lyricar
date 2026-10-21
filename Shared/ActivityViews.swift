import SwiftUI
import WidgetKit

/// Live Activity body, shared so the app's gallery can render it. `familyOverride`
/// stands in for the read-only `activityFamily` environment value.
struct LyricActivityView: View {
    let state: LyricActivityAttributes.ContentState
    let isStale: Bool
    var familyOverride: ActivityFamily?
    @Environment(\.activityFamily) private var environmentFamily
    private var family: ActivityFamily { familyOverride ?? environmentFamily }

    var body: some View {
        let theme = state.theme
        switch family {
        case .small:
            // CarPlay and the Watch Smart Stack: the line, nothing else.
            VStack(alignment: .leading, spacing: 4) {
                Text(state.currentLine)
                    .font(theme.lyric(16))
                    .foregroundStyle(theme.ink)
                    .shadow(color: theme.glow, radius: 4)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                if let next = state.nextLine {
                    Text(next)
                        .font(theme.lyric(12))
                        .foregroundStyle(theme.dim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                HStack(spacing: 4) {
                    if StripeMark.has(theme) {
                        StripeMark(theme: theme, height: 9)
                    }
                    Text(theme.uppercaseLabels ? state.trackName.uppercased() : state.trackName)
                        .font(theme.label(11))
                        .foregroundStyle(theme.accent)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        default:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    StyleMark(theme: theme, isLive: state.isPlaying)
                    Text("\(state.trackName) \u{00B7} \(state.artist)")
                        .lineLimit(1)
                }
                .font(theme.label(13))
                .foregroundStyle(theme.dim)

                Text(state.currentLine)
                    .font(theme.lyric(24))
                    .foregroundStyle(isStale ? theme.dim : theme.ink)
                    .shadow(color: theme.glow, radius: 5)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.opacity)
                if let next = state.nextLine {
                    Text(next)
                        .font(theme.lyric(16))
                        .foregroundStyle(theme.dim)
                        .lineLimit(1)
                }
                HStack(spacing: 14) {
                    ThemedProgress(theme: theme, start: state.trackStart, end: state.trackEnd,
                                   isPlaying: state.isPlaying, fraction: state.pausedFraction)
                    IntentTransport(theme: theme, isPlaying: state.isPlaying)
                }
            }
            .padding(16)
        }
    }
}
