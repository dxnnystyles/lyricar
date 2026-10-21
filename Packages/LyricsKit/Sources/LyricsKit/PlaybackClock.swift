import Foundation

/// One observation of the Spotify player, pinned to the local wall clock.
public struct PlaybackSample: Codable, Hashable, Sendable {
    public var trackID: String
    public var progressMs: Int
    public var durationMs: Int
    public var isPlaying: Bool
    /// Local time the server most likely produced `progressMs`: request start plus half the round trip.
    public var sampledAt: Date

    public init(trackID: String, progressMs: Int, durationMs: Int, isPlaying: Bool, sampledAt: Date) {
        self.trackID = trackID
        self.progressMs = progressMs
        self.durationMs = durationMs
        self.isPlaying = isPlaying
        self.sampledAt = sampledAt
    }
}

/// Interpolates the playback position between polls so lyrics move every frame,
/// not every poll.
///
/// Each sample implies when the track started (`sampledAt - progress`). That estimate
/// is only as good as the request's round trip: the server answered somewhere inside
/// it, so the error is up to half the RTT. The clock therefore keeps the most precise
/// estimate seen recently instead of the newest one, and treats a sample that its
/// uncertainty cannot explain as a real change (seek, even a small one) and applies it
/// immediately.
public struct PlaybackClock: Sendable {
    struct Anchor: Sendable {
        var trackStart: Date
        var uncertaintyMs: Int
        var observedAt: Date
    }

    public private(set) var sample: PlaybackSample?
    private var anchors: [Anchor] = []
    private var best: Anchor?

    /// How long a precise estimate stays authoritative. Long enough to bridge a few
    /// slow responses, short enough that clock drift between devices stays negligible.
    public var anchorLifetime: TimeInterval = 20
    /// Slack on top of the combined uncertainty before a disagreement counts as a seek.
    public var seekSlackMs: Int = 150

    public init() {}

    public func position(at date: Date) -> Int? {
        guard let sample else { return nil }
        guard sample.isPlaying, let best else { return sample.progressMs }
        let ms = Int((date.timeIntervalSince(best.trackStart) * 1000).rounded())
        return min(sample.durationMs, max(0, ms))
    }

    /// The wall-clock moment the track was (or would have been) at 0 ms.
    /// Widgets and Live Activities derive future line times from this.
    public func trackStartDate() -> Date? {
        guard let sample else { return nil }
        if let best, sample.isPlaying { return best.trackStart }
        return sample.sampledAt.addingTimeInterval(-Double(sample.progressMs) / 1000)
    }

    /// Accepts a new sample. Returns true when the caller should treat it as a jump
    /// (new track, play state change, or seek), so precomputed timelines get rebuilt.
    @discardableResult
    public mutating func ingest(_ new: PlaybackSample, rttMs: Int = 200) -> Bool {
        let anchor = Anchor(
            trackStart: new.sampledAt.addingTimeInterval(-Double(new.progressMs) / 1000),
            uncertaintyMs: max(rttMs, 0) / 2,
            observedAt: new.sampledAt
        )
        defer { sample = new }

        guard let old = sample, old.trackID == new.trackID, old.isPlaying == new.isPlaying else {
            reset(to: anchor)
            return true
        }

        guard new.isPlaying else {
            // Paused: the reported position is exact. A change means a seek while paused.
            reset(to: anchor)
            return abs(old.progressMs - new.progressMs) > seekSlackMs
        }

        if let best {
            let disagreementMs = abs(Int((anchor.trackStart.timeIntervalSince(best.trackStart) * 1000).rounded()))
            if disagreementMs > anchor.uncertaintyMs + best.uncertaintyMs + seekSlackMs {
                reset(to: anchor)
                return true
            }
        }

        anchors.append(anchor)
        anchors.removeAll { new.sampledAt.timeIntervalSince($0.observedAt) > anchorLifetime }
        // Most precise wins; on a tie, the newest.
        best = anchors.min { lhs, rhs in
            lhs.uncertaintyMs != rhs.uncertaintyMs ? lhs.uncertaintyMs < rhs.uncertaintyMs : lhs.observedAt > rhs.observedAt
        }
        return false
    }

    public mutating func reset() {
        sample = nil
        anchors = []
        best = nil
    }

    private mutating func reset(to anchor: Anchor) {
        anchors = [anchor]
        best = anchor
    }
}
