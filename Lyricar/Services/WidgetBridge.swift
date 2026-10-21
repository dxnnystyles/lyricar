import Foundation
import LyricsKit
import WidgetKit

/// Hands the full lyric timeline to the widget extension. The widget schedules its own
/// entries per line, so it only needs a reload when the timeline itself changes:
/// new track, lyrics arrived, play/pause, or a seek. Never per line.
@MainActor
final class WidgetBridge {
    private let engine: LyricsEngine

    init(engine: LyricsEngine) {
        self.engine = engine
        engine.observe { [weak self] change in
            switch change {
            // A new track or newly arrived lyrics change what widgets show: reload now.
            // Play-state changes (seeks, drift corrections) are rationed.
            case .track, .lyrics: self?.publish(force: true)
            case .playState: self?.publish()
            case .line, .status: break
            }
        }
    }

    private var lastReload: Date?
    private var lastTrackID: String?
    private var pendingReload: Task<Void, Never>?

    /// The snapshot is always saved; timeline reloads are rationed (WidgetKit grants about
    /// 40 to 70 background reloads a day). A new track reloads at once; anything else at
    /// most every 30 s, coalesced into one delayed reload.
    /// `force`: user actions (a widget button, a style change); iOS grants reloads for those.
    func publish(force: Bool = false) {
        guard let snapshot = engine.snapshot() else { return }
        snapshot.save()
        let trackID = engine.track?.id
        let now = Date()
        if force || trackID != lastTrackID || lastReload.map({ now.timeIntervalSince($0) >= 30 }) ?? true {
            reload(trackID: trackID)
            return
        }
        guard pendingReload == nil, let lastReload else { return }
        let wait = 30 - now.timeIntervalSince(lastReload)
        pendingReload = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard let self, !Task.isCancelled else { return }
            self.engine.snapshot()?.save()
            self.reload(trackID: self.engine.track?.id)
        }
    }

    private func reload(trackID: String?) {
        pendingReload?.cancel()
        pendingReload = nil
        lastTrackID = trackID
        lastReload = Date()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
