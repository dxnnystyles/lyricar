import LyricsKit
import SwiftUI
import WidgetKit

// Widget views live here (not in the extension) so the app can render them too,
// for the style gallery and visual checks. `familyOverride` stands in for the
// read-only `widgetFamily` environment value outside WidgetKit.

// MARK: - Timeline entry

struct LyricEntry: TimelineEntry {
    let date: Date
    let snapshot: LyricsSnapshot?
    let lineIndex: Int?
    let theme: LyricTheme

    var line: LyricLine? { lineIndex.flatMap { snapshot?.document?.lines[$0] } }

    func lines(before: Int, after: Int) -> [LyricLine] {
        Array(snapshot?.document?.window(around: lineIndex, before: before, after: after) ?? [])
    }

    var isLive: Bool {
        guard let snapshot else { return false }
        return snapshot.isPlaying && date < snapshot.trackEndDate
    }

    var lineText: String {
        guard let snapshot else { return "Play something in Spotify" }
        guard let document = snapshot.document else { return "No lyrics yet" }
        if document.syncType == .unsynced { return document.lines.first?.displayText ?? "" }
        return line?.displayText ?? "\u{266A}"
    }

    var nextText: String? {
        guard let document = snapshot?.document, document.syncType == .lineSynced else { return nil }
        let next = (lineIndex ?? -1) + 1
        return next < document.lines.count ? document.lines[next].displayText : nil
    }
}

// MARK: - Views

struct LineWidgetView: View {
    let entry: LyricEntry
    var familyOverride: WidgetFamily?
    /// Forces the CarPlay dashboard layout (for the gallery).
    var dashboardOverride: Bool?
    @Environment(\.widgetFamily) private var environmentFamily
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
    private var family: WidgetFamily { familyOverride ?? environmentFamily }
    /// CarPlay (and StandBy) remove the widget background: that is the signal to switch
    /// to the dashboard layout, which only has to work at a glance from the driver's seat.
    private var onDashboard: Bool { dashboardOverride ?? !showsBackground }

    var body: some View {
        let theme = entry.theme
        switch family {
        case .accessoryInline:
            Text(entry.line?.displayText ?? entry.snapshot?.trackName ?? "Lyricar")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.snapshot?.trackName ?? "Lyricar")
                    .font(theme.label(11))
                    .widgetAccentable()
                Text(entry.lineText)
                    .font(theme.lyric(15))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .systemMedium:
            HStack(alignment: .center, spacing: 14) {
                StyleMark(theme: theme, isLive: entry.isLive)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.lineText)
                        .font(theme.lyric(24))
                        .foregroundStyle(theme.ink)
                        .shadow(color: theme.glow, radius: 5)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                    if let next = entry.nextText {
                        Text(next).font(theme.lyric(15)).foregroundStyle(theme.dim).lineLimit(1)
                    }
                    TrackLabel(entry: entry)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        default:
            if onDashboard {
                DashboardLyric(theme: theme, label: "NOW", primary: entry.lineText, secondary: entry.nextText)
            } else {
                smallBody(theme)
            }
        }
    }

    private func smallBody(_ theme: LyricTheme) -> some View {
            VStack(alignment: .leading, spacing: 0) {
                StyleMark(theme: theme, isLive: entry.isLive)
                Spacer(minLength: 6)
                Text(entry.lineText)
                    .font(theme.lyric(19))
                    .foregroundStyle(theme.ink)
                    .shadow(color: theme.glow, radius: 5)
                    .minimumScaleFactor(0.6)
                    .lineLimit(4)
                Spacer(minLength: 6)
                TrackLabel(entry: entry)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct VerseWidgetView: View {
    let entry: LyricEntry
    var familyOverride: WidgetFamily?
    @Environment(\.widgetFamily) private var environmentFamily
    private var family: WidgetFamily { familyOverride ?? environmentFamily }

    var body: some View {
        let theme = entry.theme
        let large = family == .systemLarge
        VStack(alignment: .leading, spacing: large ? 12 : 6) {
            HStack {
                StyleMark(theme: theme, isLive: entry.isLive)
                Text(theme.uppercaseLabels ? (entry.snapshot?.trackName.uppercased() ?? "LYRICAR") : (entry.snapshot?.trackName ?? "Lyricar"))
                    .font(theme.label(11))
                    .tracking(theme.uppercaseLabels ? 1.1 : 0)
                    .foregroundStyle(theme.accent)
                    .lineLimit(1)
                Spacer()
                Text(entry.snapshot?.artist ?? "")
                    .font(theme.label(11))
                    .foregroundStyle(theme.dim)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if entry.snapshot?.document == nil {
                Text(entry.lineText).font(theme.lyric(20)).foregroundStyle(theme.dim)
            } else {
                ForEach(entry.lines(before: 1, after: large ? 4 : 1)) { line in
                    let isNow = line.id == entry.lineIndex
                    Text(line.displayText)
                        .font(theme.lyric(isNow ? (large ? 26 : 20) : (large ? 18 : 14)))
                        .foregroundStyle(isNow ? theme.ink : theme.dim)
                        .shadow(color: isNow ? theme.glow : .clear, radius: 5)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
            }
            Spacer(minLength: 0)
            if large, let snapshot = entry.snapshot {
                HStack(spacing: 14) {
                    ThemedProgress(theme: theme, start: snapshot.trackStartDate, end: snapshot.trackEndDate,
                                   isPlaying: snapshot.isPlaying,
                                   fraction: Double(snapshot.pausedPositionMs) / Double(max(snapshot.durationMs, 1)))
                    IntentTransport(theme: theme, isPlaying: snapshot.isPlaying)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct GaugeWidgetView: View {
    let entry: LyricEntry
    var familyOverride: WidgetFamily?
    @Environment(\.widgetFamily) private var environmentFamily
    private var family: WidgetFamily { familyOverride ?? environmentFamily }

    var body: some View {
        let theme = entry.theme
        let snapshot = entry.snapshot
        ZStack {
            ThemedRing(theme: theme, start: snapshot?.trackStartDate, end: snapshot?.trackEndDate,
                       isPlaying: snapshot?.isPlaying ?? false,
                       fraction: snapshot.map { Double($0.pausedPositionMs) / Double(max($0.durationMs, 1)) } ?? 0,
                       lineWidth: family == .accessoryCircular ? 4 : 9)
                .padding(family == .accessoryCircular ? 2 : 4)

            if family == .accessoryCircular {
                Image(systemName: "quote.opening").font(.system(size: 14, weight: .bold))
            } else {
                VStack(spacing: 2) {
                    Text(entry.lineText)
                        .font(theme.lyric(13))
                        .foregroundStyle(theme.ink)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.6)
                        .frame(width: 92)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Pieces

struct StyleMark: View {
    let theme: LyricTheme
    let isLive: Bool

    var body: some View {
        if StripeMark.has(theme) {
            StripeMark(theme: theme)
        } else {
            Image(systemName: isLive ? "waveform" : "music.note")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(theme.accent)
                .shadow(color: theme.glow, radius: 4)
        }
    }
}

struct TrackLabel: View {
    let entry: LyricEntry

    var body: some View {
        let theme = entry.theme
        Text(theme.uppercaseLabels ? (entry.snapshot?.trackName.uppercased() ?? "") : (entry.snapshot?.trackName ?? ""))
            .font(theme.label(11))
            .tracking(theme.uppercaseLabels ? 1 : 0)
            .foregroundStyle(theme.dim)
            .lineLimit(1)
    }
}


// MARK: - CarPlay dashboard

/// The CarPlay dashboard layout: a label, one line as large as fits, a thin accent
/// rule, the following line. System primary/secondary ink, because CarPlay draws its
/// own background behind widgets.
struct DashboardLyric: View {
    let theme: LyricTheme
    let label: String
    let primary: String
    let secondary: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                if StripeMark.has(theme) {
                    StripeMark(theme: theme, height: 9)
                } else {
                    Capsule().fill(theme.accent).frame(width: 14, height: 3)
                }
                Text(label)
                    .font(theme.label(10))
                    .tracking(1.2)
                    .foregroundStyle(theme.accent)
            }
            Text(primary)
                .font(theme.lyric(22))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let secondary {
                Rectangle().fill(theme.accent.opacity(0.6)).frame(width: 22, height: 2)
                Text(secondary)
                    .font(theme.lyric(14))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// "Up Next": the line after the current one, big, and the one after that. Placed
/// next to Lyric Line in a CarPlay stack it doubles the visible lyrics.
struct UpNextWidgetView: View {
    let entry: LyricEntry
    var familyOverride: WidgetFamily?
    var dashboardOverride: Bool?
    @Environment(\.widgetFamily) private var environmentFamily
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
    private var family: WidgetFamily { familyOverride ?? environmentFamily }
    private var onDashboard: Bool { dashboardOverride ?? !showsBackground }

    var body: some View {
        let theme = entry.theme
        let upcoming = entry.lines(before: 0, after: 2).filter { $0.id != entry.lineIndex }
        let next = upcoming.first?.displayText ?? (entry.snapshot == nil ? "Play something in Spotify" : "\u{266A}")
        let after = upcoming.dropFirst().first?.displayText
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("NEXT").font(theme.label(10)).widgetAccentable()
                Text(next).font(theme.lyric(15)).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            if onDashboard {
                DashboardLyric(theme: theme, label: "NEXT", primary: next, secondary: after)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(theme.uppercaseLabels ? "NEXT" : "Next")
                        .font(theme.label(11)).tracking(1).foregroundStyle(theme.accent)
                    Text(next)
                        .font(theme.lyric(19)).foregroundStyle(theme.ink)
                        .shadow(color: theme.glow, radius: 5)
                        .lineLimit(3).minimumScaleFactor(0.6)
                    if let after {
                        Text(after).font(theme.lyric(13)).foregroundStyle(theme.dim).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}


/// "Remote": the current line with large previous / play-pause / next buttons. Small,
/// so it also works in a CarPlay widget stack (interactive on touchscreen cars).
struct RemoteWidgetView: View {
    let entry: LyricEntry

    var body: some View {
        let theme = entry.theme
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.lineText)
                .font(theme.lyric(16))
                .foregroundStyle(theme.ink)
                .shadow(color: theme.glow, radius: 4)
                .lineLimit(3)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            HStack {
                Button(intent: LyricPlaybackIntent(.previous)) {
                    Image(systemName: "backward.fill").frame(maxWidth: .infinity, minHeight: 34)
                }
                .accessibilityLabel("Previous song")
                Button(intent: LyricPlaybackIntent(.playPause)) {
                    Image(systemName: entry.snapshot?.isPlaying == true ? "pause.fill" : "play.fill")
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .accessibilityLabel(entry.snapshot?.isPlaying == true ? "Pause" : "Play")
                Button(intent: LyricPlaybackIntent(.next)) {
                    Image(systemName: "forward.fill").frame(maxWidth: .infinity, minHeight: 34)
                }
                .accessibilityLabel("Next song")
            }
            .buttonStyle(.plain)
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(theme.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// "Karaoke": the karaoke list in one tile. Previous line faded, current line highlighted
/// with an accent bar, the next two below. The timeline moves it line by line, so on the
/// CarPlay dashboard it scrolls with the song without the app being a CarPlay app.
struct KaraokeWidgetView: View {
    let entry: LyricEntry
    var familyOverride: WidgetFamily?
    var dashboardOverride: Bool?
    @Environment(\.widgetFamily) private var environmentFamily
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
    private var family: WidgetFamily { familyOverride ?? environmentFamily }
    private var onDashboard: Bool { dashboardOverride ?? !showsBackground }

    var body: some View {
        let theme = entry.theme
        let medium = family == .systemMedium
        let lines = entry.lines(before: 1, after: medium ? 3 : 2)
        let primary: Color = onDashboard ? .primary : theme.ink
        let secondary: Color = onDashboard ? .secondary : theme.dim
        VStack(alignment: .leading, spacing: medium ? 6 : 4) {
            if entry.snapshot?.document == nil {
                Text(entry.lineText)
                    .font(theme.lyric(16))
                    .foregroundStyle(secondary)
            } else {
                ForEach(lines) { line in
                    let isNow = line.id == entry.lineIndex
                    let isPast = (entry.lineIndex ?? -1) > line.id
                    HStack(alignment: .top, spacing: 6) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(isNow ? theme.accent : .clear)
                            .frame(width: 3)
                        Text(line.displayText)
                            .font(theme.lyric(isNow ? (medium ? 20 : 16) : (medium ? 14 : 12)))
                            .foregroundStyle(isNow ? primary : secondary.opacity(isPast ? 0.55 : 1))
                            .shadow(color: isNow && !onDashboard ? theme.glow : .clear, radius: 4)
                            .lineLimit(isNow ? 3 : 1)
                            .minimumScaleFactor(0.6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
