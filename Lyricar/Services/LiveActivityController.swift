import ActivityKit
import Foundation
import LyricsKit
import UIKit

/// Mirrors the engine into one Live Activity. The activity shows on the Lock Screen,
/// in the Dynamic Island and, through its `.small` supplemental family, on CarPlay.
@MainActor
final class LiveActivityController {
    private let engine: LyricsEngine
    private var activity: Activity<LyricActivityAttributes>? {
        didSet { if activity?.id != oldValue?.id { watchState() } }
    }
    private var observer: UUID?
    private var stateTask: Task<Void, Never>?
    private var updateTask: Task<Void, Never>?
    private(set) var isEnabled = false

    init(engine: LyricsEngine) {
        self.engine = engine
        // Adopt an activity that survived an app relaunch.
        activity = Activity<LyricActivityAttributes>.activities.first { $0.activityState == .active || $0.activityState == .stale }
        isEnabled = activity != nil
        watchState()
    }

    /// The system ends an activity after 8 hours, and the user can swipe it away. Updates
    /// to it then go nowhere; forget it, so the next foreground push requests a new one.
    private func watchState() {
        stateTask?.cancel()
        guard let activity else { return }
        stateTask = Task { [weak self] in
            for await state in activity.activityStateUpdates where state == .ended || state == .dismissed {
                guard let self, self.activity?.id == activity.id else { return }
                self.activity = nil
                return
            }
        }
    }

    var areActivitiesAllowed: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            observer = engine.observe { [weak self] change in
                guard change != .status else { return }
                self?.push()
            }
            push()
        } else {
            if let observer { engine.removeObserver(observer) }
            observer = nil
            end()
        }
    }

    /// Re-sends the current state, for example after a style change.
    func refresh() { push() }

    /// On entering the foreground: request a new activity if iOS ended the last one.
    /// Never ends one; that stays with the engine's status.
    func restoreIfNeeded() {
        guard isEnabled, activity == nil, contentState() != nil else { return }
        push()
    }

    private func push() {
        guard isEnabled, let state = contentState() else {
            // Only end on a definitive answer. Right after launch the engine has no track
            // yet, and ending then would kill an activity adopted from the last run.
            if engine.status == .nothingPlaying || engine.status == .signedOut { end() }
            return
        }
        // Stale once the next line is due, so the system dims a frozen lyric.
        let stale = engine.nextLine.flatMap { next in
            engine.trackStartDate()?.addingTimeInterval(Double(next.startMs) / 1000 + 2)
        }
        let content = ActivityContent(state: state, staleDate: engine.isPlaying ? stale : nil)

        if let activity {
            // One update at a time, in order: concurrent updates may land out of order and
            // leave an older line on screen.
            let previous = updateTask
            updateTask = Task {
                await previous?.value
                await activity.update(content)
            }
        } else if areActivitiesAllowed, UIApplication.shared.applicationState != .background {
            // Requests from the background always fail; the next foreground push retries.
            activity = try? Activity.request(
                attributes: LyricActivityAttributes(sessionStarted: .now),
                content: content,
                pushType: nil
            )
        }
    }

    private func end() {
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    private func contentState() -> LyricActivityAttributes.ContentState? {
        guard let track = engine.track else { return nil }
        let start = engine.trackStartDate() ?? .now
        let position = engine.positionMs() ?? 0
        let current: String = {
            switch engine.status {
            case .loadingLyrics: return "Finding lyrics"
            case .noLyrics: return "No lyrics for this one"
            default:
                if engine.document?.syncType == .unsynced { return "Lyrics not synced" }
                return engine.currentLine?.displayText ?? "\u{266A}"
            }
        }()
        return LyricActivityAttributes.ContentState(
            trackName: track.name,
            artist: track.artistLine,
            currentLine: current,
            nextLine: engine.nextLine?.displayText,
            lineNumber: (engine.currentIndex ?? -1) + 1,
            lineCount: engine.document?.lines.count ?? 0,
            isPlaying: engine.isPlaying,
            trackStart: start,
            trackEnd: start.addingTimeInterval(Double(track.durationMs) / 1000),
            pausedFraction: track.durationMs > 0 ? Double(position) / Double(track.durationMs) : 0,
            themeRaw: LyricTheme.current.rawValue
        )
    }
}
