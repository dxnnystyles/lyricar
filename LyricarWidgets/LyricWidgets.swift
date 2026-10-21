import AppIntents
import LyricsKit
import SwiftUI
import WidgetKit

@main
struct LyricarWidgetsBundle: WidgetBundle {
    var body: some Widget {
        LineWidget()
        VerseWidget()
        KaraokeWidget()
        UpNextWidget()
        RemoteWidget()
        GaugeWidget()
        LyricLiveActivity()
    }
}

// MARK: - Configuration

/// Every widget instance picks its own style in the widget's edit sheet.
/// "Match app" follows whatever is selected in Lyricar.
struct LyricWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Lyric style"
    static let description = IntentDescription("Choose how this widget looks.")

    @Parameter(title: "Style")
    var style: LyricTheme?

    var theme: LyricTheme { style ?? .current }
}

// MARK: - Timeline

/// Precomputes one entry per upcoming lyric line from the snapshot the app wrote.
/// The widget therefore follows the song on its own; the app only reloads it when
/// the timeline changes (track, lyrics, pause, seek, style).
struct LyricProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> LyricEntry {
        LyricEntry(date: .now, snapshot: .placeholder, lineIndex: 1, theme: .current)
    }

    func snapshot(for configuration: LyricWidgetIntent, in context: Context) async -> LyricEntry {
        let snapshot = context.isPreview ? .placeholder : (LyricsSnapshot.load() ?? .placeholder)
        let index = snapshot.document?.lineIndex(at: snapshot.positionMs(at: .now))
        return LyricEntry(date: .now, snapshot: snapshot, lineIndex: index, theme: configuration.theme)
    }

    func timeline(for configuration: LyricWidgetIntent, in context: Context) async -> Timeline<LyricEntry> {
        let theme = configuration.theme
        guard let snapshot = LyricsSnapshot.load() else {
            return Timeline(entries: [LyricEntry(date: .now, snapshot: nil, lineIndex: nil, theme: theme)], policy: .never)
        }
        var entries = snapshot.timeline(from: .now).map { LyricEntry(date: $0.date, snapshot: snapshot, lineIndex: $0.lineIndex, theme: theme) }
        guard snapshot.isPlaying, snapshot.trackEndDate > .now else {
            return Timeline(entries: entries, policy: .never)
        }
        // A song longer than one timeline continues from its last entry; otherwise ask again
        // just after the track ends. The app saves every snapshot even when iOS denies it a
        // reload, so this picks up the next song without the app.
        if entries.count >= LyricsSnapshot.timelineLimit, let last = entries.last {
            return Timeline(entries: entries, policy: .after(last.date))
        }
        entries.append(LyricEntry(date: snapshot.trackEndDate, snapshot: snapshot, lineIndex: nil, theme: theme))
        return Timeline(entries: entries, policy: .after(snapshot.trackEndDate.addingTimeInterval(2)))
    }
}

// MARK: - Line (small, Lock Screen, CarPlay dashboard)

struct LineWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "lyricar.line", intent: LyricWidgetIntent.self, provider: LyricProvider()) { entry in
            LineWidgetView(entry: entry)
                .containerBackground(entry.theme.background, for: .widget)
        }
        .configurationDisplayName("Lyric Line")
        .description("The line playing right now.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Verse (medium, large)

struct VerseWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "lyricar.verse", intent: LyricWidgetIntent.self, provider: LyricProvider()) { entry in
            VerseWidgetView(entry: entry)
                .containerBackground(entry.theme.background, for: .widget)
        }
        .configurationDisplayName("Verse")
        .description("The current line with what came before and what comes next.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - Up Next (small, Lock Screen): pair it with Lyric Line in a CarPlay stack

struct UpNextWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "lyricar.upnext", intent: LyricWidgetIntent.self, provider: LyricProvider()) { entry in
            UpNextWidgetView(entry: entry)
                .containerBackground(entry.theme.background, for: .widget)
        }
        .configurationDisplayName("Up Next")
        .description("The next line, big. Put it beside Lyric Line in CarPlay to read ahead.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

// MARK: - Karaoke (small, medium): the karaoke list in a tile, made for the CarPlay dashboard

struct KaraokeWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "lyricar.karaoke", intent: LyricWidgetIntent.self, provider: LyricProvider()) { entry in
            KaraokeWidgetView(entry: entry)
                .containerBackground(entry.theme.background, for: .widget)
        }
        .configurationDisplayName("Karaoke")
        .description("The current line highlighted, the next lines below. Made for the CarPlay dashboard.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Remote (small): line plus playback buttons

struct RemoteWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "lyricar.remote", intent: LyricWidgetIntent.self, provider: LyricProvider()) { entry in
            RemoteWidgetView(entry: entry)
                .containerBackground(entry.theme.background, for: .widget)
        }
        .configurationDisplayName("Remote")
        .description("The current line with previous, play and next.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Gauge (small, Lock Screen circular): track progress as a dial

struct GaugeWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "lyricar.gauge", intent: LyricWidgetIntent.self, provider: LyricProvider()) { entry in
            GaugeWidgetView(entry: entry)
                .containerBackground(entry.theme.background, for: .widget)
        }
        .configurationDisplayName("Gauge")
        .description("A dial for the song with the current line inside.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

