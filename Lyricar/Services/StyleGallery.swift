#if DEBUG
import LyricsKit
import SwiftUI
import UIKit
import WidgetKit

/// `-LyricarRenderGallery`: renders every style across all widget sizes, the Lock Screen
/// Live Activity, its CarPlay `.small` family and the CarPlay stage card, one sheet per
/// style, into Documents/gallery. For visual review after every design change.
@MainActor
enum StyleGallery {
    static func runIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-LyricarRenderGallery") else { return }
        Task {
            let lyrics = (try? await LRCLibClient().lyrics(for: SpotifyTrack(
                id: "gallery", name: "Midnight City", artists: ["M83"], album: "Midnight City",
                artworkURL: nil, durationMs: 241_000))) ?? LyricsSnapshot.placeholder.document
            render(document: lyrics)
        }
    }

    static func render(document: LyricsDocument?) {
        let now = Date()
        var snapshot = LyricsSnapshot.placeholder
        snapshot.document = document
        // Paused: ImageRenderer cannot draw timer-driven progress views (real widgets can),
        // so the gallery shows the static progress at the same position.
        snapshot.isPlaying = false
        snapshot.pausedPositionMs = 44_000
        snapshot.trackStartDate = now.addingTimeInterval(-44)
        snapshot.updatedAt = now
        let index = document?.lineIndex(at: 44_000)
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("gallery")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        for theme in LyricTheme.allCases {
            let entry = LyricEntry(date: now, snapshot: snapshot, lineIndex: index, theme: theme)
            let lines = document?.lines ?? []
            let current = index.map { lines[$0].displayText } ?? "\u{266A}"
            let next = index.flatMap { $0 + 1 < lines.count ? lines[$0 + 1].displayText : nil }
            let state = LyricActivityAttributes.ContentState(
                trackName: "Midnight City", artist: "M83", currentLine: current, nextLine: next,
                lineNumber: (index ?? 0) + 1, lineCount: lines.count, isPlaying: false,
                trackStart: snapshot.trackStartDate, trackEnd: snapshot.trackEndDate,
                pausedFraction: 0.18, themeRaw: theme.rawValue)

            let sheet = VStack(alignment: .leading, spacing: 18) {
                Text("\(theme.displayName): \(theme.tagline)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                HStack(alignment: .top, spacing: 18) {
                    tile(LineWidgetView(entry: entry, familyOverride: .systemSmall), theme, 170, 170, "Line S")
                    tile(GaugeWidgetView(entry: entry, familyOverride: .systemSmall), theme, 170, 170, "Gauge S")
                    tile(LineWidgetView(entry: entry, familyOverride: .systemMedium), theme, 364, 170, "Line M")
                }
                HStack(alignment: .top, spacing: 18) {
                    carPlayTile(LineWidgetView(entry: entry, familyOverride: .systemSmall, dashboardOverride: true), theme, "CarPlay: Lyric Line")
                    carPlayTile(UpNextWidgetView(entry: entry, familyOverride: .systemSmall, dashboardOverride: true), theme, "CarPlay: Up Next")
                    carPlayTile(KaraokeWidgetView(entry: entry, familyOverride: .systemSmall, dashboardOverride: true), theme, "CarPlay: Karaoke")
                    tile(RemoteWidgetView(entry: entry), theme, 170, 170, "Remote S")
                    tile(UpNextWidgetView(entry: entry, familyOverride: .systemSmall), theme, 170, 170, "Up Next S")
                }
                HStack(alignment: .top, spacing: 18) {
                    tile(VerseWidgetView(entry: entry, familyOverride: .systemMedium), theme, 364, 170, "Verse M")
                    tile(LyricActivityView(state: state, isStale: false, familyOverride: .medium), theme, 364, 170, "Lock Screen")
                }
                HStack(alignment: .top, spacing: 18) {
                    tile(VerseWidgetView(entry: entry, familyOverride: .systemLarge), theme, 364, 382, "Verse L")
                    VStack(alignment: .leading, spacing: 18) {
                        tile(LyricActivityView(state: state, isStale: false, familyOverride: .small), theme, 200, 100, "CarPlay activity")
                        tile(LyricCard(theme: theme, trackName: "Midnight City", artist: "M83", previous: nil,
                                       current: current, next: next), theme, 300, 170, "CarPlay stage")
                    }
                }
            }
            .padding(24)
            .background(Color(white: 0.93))

            let renderer = ImageRenderer(content: sheet)
            renderer.scale = 2
            if let data = renderer.uiImage?.pngData() {
                try? data.write(to: folder.appendingPathComponent("\(theme.rawValue).png"))
            }
        }
        NSLog("LYRICAR-GALLERY wrote %@", folder.path)
    }

    /// CarPlay removes the widget background and draws its own dark surface.
    private static func carPlayTile<V: View>(_ view: V, _ theme: LyricTheme, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            view
                .padding(12)
                .frame(width: 150, height: 150)
                .background(Color(white: 0.11))
                .clipShape(.rect(cornerRadius: 20))
                .environment(\.colorScheme, .dark)
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(.gray)
        }
    }

    private static func tile<V: View>(_ view: V, _ theme: LyricTheme, _ width: CGFloat, _ height: CGFloat, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            view
                .padding(14)
                .frame(width: width, height: height)
                .background(theme.background)
                .clipShape(.rect(cornerRadius: 22))
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(.gray)
        }
    }
}
#endif
