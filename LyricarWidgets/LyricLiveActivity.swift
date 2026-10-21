import ActivityKit
import SwiftUI
import WidgetKit

/// Lock Screen banner, Dynamic Island, and the `.small` family that iOS 26 shows on
/// CarPlay (and the Apple Watch Smart Stack). Styled by the theme in the content state.
struct LyricLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LyricActivityAttributes.self) { context in
            LyricActivityView(state: context.state, isStale: context.isStale)
                .activityBackgroundTint(context.state.theme.base)
                .activitySystemActionForegroundColor(context.state.theme.accent)
        } dynamicIsland: { context in
            let theme = context.state.theme
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    StyleMark(theme: theme, isLive: context.state.isPlaying)
                        .symbolEffect(.variableColor.iterative, isActive: context.state.isPlaying)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.lineNumber)/\(context.state.lineCount)")
                        .font(theme.label(13))
                        .foregroundStyle(.white.opacity(0.5))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.trackName)
                        .font(theme.label(13))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.state.currentLine)
                            .font(theme.lyric(22))
                            .foregroundStyle(.white)
                            .shadow(color: theme.glow, radius: 5)
                            .lineLimit(2)
                            .contentTransition(.opacity)
                        if let next = context.state.nextLine {
                            Text(next)
                                .font(theme.lyric(15))
                                .foregroundStyle(.white.opacity(0.45))
                                .lineLimit(1)
                        }
                        HStack(spacing: 14) {
                            ThemedProgress(theme: theme, start: context.state.trackStart, end: context.state.trackEnd,
                                           isPlaying: context.state.isPlaying, fraction: context.state.pausedFraction)
                            IntentTransport(theme: theme, isPlaying: context.state.isPlaying, tint: .white)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: "quote.opening")
                    .foregroundStyle(theme.accent)
            } compactTrailing: {
                Text(context.state.currentLine)
                    .font(theme.label(12))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: 90)
            } minimal: {
                Image(systemName: "quote.opening")
                    .foregroundStyle(theme.accent)
            }
            .keylineTint(theme.accent)
        }
        .supplementalActivityFamilies([.small])
    }
}
