import CarPlay
import os
import LyricsKit
import SwiftUI
import UIKit

/// CarPlay is template-only for non-navigation apps, so each "view" is a template:
/// - Karaoke: a list that starts at the current line and runs ahead. CarPlay has no
///   scroll-to-item API and highlights the first row, so the window moves instead of
///   the list and the highlighted row is always the line being sung. Tapping a row
///   jumps the song to that line.
/// - Focus: the current line alone, the next one as its detail, then what follows.
/// - Stage: the lyric card rendered in the selected style (iOS 26 card element), and
///   the styles to pick from. The only place CarPlay shows our own pixels.
/// - Track: what is playing, transport controls, timing nudges, open in Spotify.
@MainActor
final class CarPlayLyricsController {
    private let engine: LyricsEngine
    private let interfaceController: CPInterfaceController
    private weak var scene: CPTemplateApplicationScene?
    private var observer: UUID?
    private var themeObserver: UUID?

    private let karaoke = CPListTemplate(title: "Karaoke", sections: [])
    private let focus = CPListTemplate(title: "Focus", sections: [])
    private let stage = CPListTemplate(title: "Stage", sections: [])
    private let trackInfo = CPListTemplate(title: "Track", sections: [])
    private var artwork: (url: URL, image: UIImage)?
    private var stylePreviews: [LyricTheme: UIImage] = [:]

    init(engine: LyricsEngine, interfaceController: CPInterfaceController, scene: CPTemplateApplicationScene?) {
        self.engine = engine
        self.interfaceController = interfaceController
        self.scene = scene
        karaoke.tabTitle = "Karaoke"
        karaoke.tabImage = UIImage(systemName: "text.quote")
        focus.tabTitle = "Focus"
        focus.tabImage = UIImage(systemName: "quote.opening")
        stage.tabTitle = "Stage"
        stage.tabImage = UIImage(systemName: "paintpalette")
        trackInfo.tabTitle = "Track"
        trackInfo.tabImage = UIImage(systemName: "music.note")
        for template in [karaoke, focus, stage, trackInfo] {
            template.emptyViewTitleVariants = ["Nothing playing"]
            template.emptyViewSubtitleVariants = ["Start a song in Spotify"]
        }
    }

    func install() {
        let templates = [karaoke, focus, stage, trackInfo].prefix(CPTabBarTemplate.maximumTabCount)
        let tabs = CPTabBarTemplate(templates: Array(templates))
        interfaceController.setRootTemplate(tabs, animated: false, completion: nil)
        observer = engine.observe { [weak self] change in self?.handle(change) }
        themeObserver = AppModel.shared.observeTheme { [weak self] _ in self?.renderAll() }
        renderAll()
    }

    func uninstall() {
        if let observer { engine.removeObserver(observer) }
        if let themeObserver { AppModel.shared.removeThemeObserver(themeObserver) }
        observer = nil
        themeObserver = nil
    }

    private func handle(_ change: LyricsEngine.Change) {
        switch change {
        case .line:
            renderKaraoke()
            renderFocus()
            renderStage()
        case .track, .lyrics, .status, .playState:
            renderAll()
        }
    }

    private func renderAll() {
        renderKaraoke()
        renderFocus()
        renderStage()
        renderTrack()
    }

    // MARK: Karaoke

    private func renderKaraoke() {
        guard let track = engine.track else {
            karaoke.updateSections([])
            return
        }
        guard let document = engine.document, !document.lines.isEmpty else {
            karaoke.updateSections([CPListSection(items: [statusItem()], header: track.name, sectionIndexTitle: nil)])
            return
        }

        let limit = Int(CPListTemplate.maximumItemCount)
        let lines: ArraySlice<LyricLine>
        if document.syncType == .lineSynced {
            lines = document.window(around: engine.currentIndex, before: 0, after: min(limit, 12) - 1)
        } else {
            lines = document.lines.prefix(limit)
        }

        let items = lines.map { line -> CPListItem in
            let item = CPListItem(text: line.displayText, detailText: nil)
            if line.id == engine.currentIndex {
                item.isPlaying = engine.isPlaying
                item.playingIndicatorLocation = .trailing
            }
            if document.syncType == .lineSynced, engine.canControl {
                item.handler = { [weak self] _, completion in
                    self?.engine.seek(toLine: line)
                    completion()
                }
            }
            return item
        }
        let header = document.syncType == .lineSynced ? track.name : "\(track.name) (not synced)"
        karaoke.updateSections([CPListSection(items: items, header: header, sectionIndexTitle: nil)])
    }

    // MARK: Focus

    private func renderFocus() {
        guard let track = engine.track else {
            focus.updateSections([])
            return
        }
        guard let document = engine.document, document.syncType == .lineSynced else {
            focus.updateSections([CPListSection(items: [statusItem()], header: track.artistLine, sectionIndexTitle: nil)])
            return
        }

        let now = CPListItem(
            text: engine.currentLine?.displayText ?? "\u{266A}",
            detailText: engine.nextLine.map { "Next: \($0.displayText)" }
        )
        now.isPlaying = engine.isPlaying
        now.playingIndicatorLocation = .trailing

        let start = (engine.currentIndex ?? -1) + 2
        let later = document.lines.dropFirst(start).prefix(3).map { line -> CPListItem in
            let item = CPListItem(text: line.displayText, detailText: nil)
            if engine.canControl {
                item.handler = { [weak self] _, completion in
                    self?.engine.seek(toLine: line)
                    completion()
                }
            }
            return item
        }

        var sections = [CPListSection(items: [now], header: "\(track.name) \u{00B7} \(track.artistLine)", sectionIndexTitle: nil)]
        if !later.isEmpty {
            sections.append(CPListSection(items: later, header: "Later", sectionIndexTitle: nil))
        }
        focus.updateSections(sections)
    }

    // MARK: Stage

    private func renderStage() {
        let theme = AppModel.shared.theme
        var sections: [CPListSection] = []

        let themes = LyricTheme.allCases
        let previews = themes.map { style -> CPListImageRowItemCardElement in
            CPListImageRowItemCardElement(image: preview(for: style), showsImageFullHeight: true,
                                          title: nil, subtitle: style == theme ? "Selected" : nil,
                                          tintColor: UIColor(style.accent))
        }
        let picker = CPListImageRowItem(text: "Style: \(theme.displayName)", cardElements: previews, allowsMultipleLines: true)
        picker.listImageRowHandler = { _, index, completion in
            if themes.indices.contains(index) { AppModel.shared.theme = themes[index] }
            completion()
        }
        sections.append(CPListSection(items: [picker], header: "Choose a style", sectionIndexTitle: nil))

        if let track = engine.track {
            let current = engine.document?.syncType == .lineSynced ? (engine.currentLine?.displayText ?? "\u{266A}") : statusText()
            let card = renderCard(LyricCardFace(theme: theme, trackName: track.name, current: current,
                                                next: engine.nextLine?.displayText),
                                  size: CPListImageRowItemCardElement.maximumImageSize)
            // No title or subtitle: CarPlay would overlay them on the card, repeating its text.
            let element = CPListImageRowItemCardElement(image: card, showsImageFullHeight: true,
                                                        title: nil, subtitle: nil,
                                                        tintColor: UIColor(theme.accent))
            let row = CPListImageRowItem(text: "\(track.name) \u{00B7} \(theme.displayName)", cardElements: [element], allowsMultipleLines: true)
            sections.append(CPListSection(items: [row]))
        }

        stage.updateSections(sections)
    }

    private func preview(for theme: LyricTheme) -> UIImage {
        if let cached = stylePreviews[theme] { return cached }
        let image = renderCard(LyricCardFace(theme: theme, trackName: theme.tagline, current: theme.displayName, next: nil),
                               size: CPListImageRowItemCardElement.maximumImageSize)
        stylePreviews[theme] = image
        return image
    }

    private func renderCard<V: View>(_ view: V, size: CGSize) -> UIImage {
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "lyricar", category: "carplay").notice("CARPLAY card maximumImageSize=\(size.width)x\(size.height)")
        let side = CGSize(width: max(size.width, 90), height: max(size.height, 120))
        let renderer = ImageRenderer(content: view.frame(width: side.width, height: side.height))
        renderer.scale = interfaceController.carTraitCollection.displayScale
        return renderer.uiImage ?? UIImage()
    }

    // MARK: Track

    private func renderTrack() {
        guard let track = engine.track else {
            trackInfo.updateSections([])
            return
        }
        let song = CPListItem(text: track.name, detailText: "\(track.artistLine) \u{00B7} Open in Spotify", image: artworkImage(for: track))
        song.accessoryType = .disclosureIndicator
        song.handler = { [weak self] _, completion in
            self?.openInSpotify(track)
            completion()
        }

        var transport: [CPListItem] = []
        if engine.canControl {
            let playPause = CPListItem(text: engine.isPlaying ? "Pause" : "Play", detailText: nil,
                                       image: UIImage(systemName: engine.isPlaying ? "pause.fill" : "play.fill"))
            playPause.handler = { [weak self] _, completion in
                guard let self else { return completion() }
                self.engine.perform(self.engine.isPlaying ? .pause : .play)
                completion()
            }
            let next = CPListItem(text: "Next song", detailText: nil, image: UIImage(systemName: "forward.fill"))
            next.handler = { [weak self] _, completion in
                self?.engine.perform(.next)
                completion()
            }
            let previous = CPListItem(text: "Previous song", detailText: nil, image: UIImage(systemName: "backward.fill"))
            previous.handler = { [weak self] _, completion in
                self?.engine.perform(.previous)
                completion()
            }
            transport = [playPause, next, previous]
        }

        let source = CPListItem(text: sourceText(), detailText: "Lyrics: \(engine.document?.provider ?? "LRCLIB")")
        let late = CPListItem(text: "Lyrics are late", detailText: offsetText(), image: UIImage(systemName: "forward"))
        late.handler = { [weak self] _, completion in
            self?.engine.nudge(byMs: 250)
            completion()
        }
        let early = CPListItem(text: "Lyrics are early", detailText: nil, image: UIImage(systemName: "backward"))
        early.handler = { [weak self] _, completion in
            self?.engine.nudge(byMs: -250)
            completion()
        }
        let resync = CPListItem(text: "Resync with Spotify", detailText: nil, image: UIImage(systemName: "arrow.triangle.2.circlepath"))
        resync.handler = { [weak self] _, completion in
            self?.engine.refreshNow()
            completion()
        }

        var sections = [CPListSection(items: [song], header: track.album, sectionIndexTitle: nil)]
        if !transport.isEmpty {
            sections.append(CPListSection(items: transport, header: "Playback", sectionIndexTitle: nil))
        }
        sections.append(CPListSection(items: [source, late, early, resync], header: "Timing", sectionIndexTitle: nil))
        trackInfo.updateSections(sections)
    }

    private func openInSpotify(_ track: SpotifyTrack) {
        // Inside CarPlay, the scene opens URLs so Spotify comes up on the car screen.
        if let scene {
            scene.open(SpotifyLink.url(for: track), options: nil, completionHandler: nil)
        } else {
            SpotifyLink.open(track)
        }
    }

    private func offsetText() -> String {
        engine.offsetMs == 0 ? "In sync with Spotify" : String(format: "Shifted %+.2f s", Double(engine.offsetMs) / 1000)
    }

    private func sourceText() -> String {
        switch engine.status {
        case .loadingLyrics: return "Finding lyrics"
        case .noLyrics: return "No lyrics found"
        default: return engine.document?.syncType == .lineSynced ? "Line-synced" : "Not synced"
        }
    }

    private func statusText() -> String {
        switch engine.status {
        case .loadingLyrics: return "Finding lyrics"
        case .noLyrics: return "No lyrics for this one"
        default: return "Lyrics not synced"
        }
    }

    private func statusItem() -> CPListItem {
        switch engine.status {
        case .loadingLyrics: return CPListItem(text: "Finding lyrics", detailText: "LRCLIB")
        case .noLyrics: return CPListItem(text: "No lyrics for this one", detailText: "Enjoy the music")
        case .signedOut: return CPListItem(text: "Connect Spotify on your iPhone", detailText: nil)
        case .failed(let message): return CPListItem(text: "Spotify is not answering", detailText: message)
        default: return CPListItem(text: "\u{266A}", detailText: nil)
        }
    }

    private func artworkImage(for track: SpotifyTrack) -> UIImage? {
        guard let url = track.artworkURL else { return nil }
        if let artwork, artwork.url == url { return artwork.image }
        Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url), let image = UIImage(data: data) else { return }
            guard let self, self.engine.track?.artworkURL == url else { return }
            self.artwork = (url, image)
            self.renderTrack()
        }
        return nil
    }
}
