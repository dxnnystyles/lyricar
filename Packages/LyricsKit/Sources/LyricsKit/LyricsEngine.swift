import Foundation
import Observation
import os

let syncLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "lyricar", category: "sync")

/// Single source of truth for every surface: phone, CarPlay, Live Activity, widgets.
/// Polls Spotify, fetches lyrics once per track, interpolates the position locally.
@MainActor
@Observable
public final class LyricsEngine {
    public enum Status: Equatable, Sendable {
        case idle
        case signedOut
        case nothingPlaying
        case loadingLyrics
        case ready
        case noLyrics
        case failed(String)
    }

    public enum Change: Sendable {
        case track, lyrics, line, playState, status
    }

    public private(set) var track: SpotifyTrack?
    public private(set) var document: LyricsDocument?
    public private(set) var currentIndex: Int?
    public private(set) var isPlaying = false
    public private(set) var status: Status = .idle

    @ObservationIgnored private var spotify: NowPlayingSource?
    @ObservationIgnored private let lyricsSource: LRCLibClient
    @ObservationIgnored private var clock = PlaybackClock()
    @ObservationIgnored private var cache: [String: LyricsDocument?] = [:]
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [UUID: (Change) -> Void] = [:]

    @ObservationIgnored private var endOfTrackPollFor: String?
    /// Called with a one-line summary after every Spotify poll that returned a track.
    @ObservationIgnored public var onPoll: ((String) -> Void)?
    @ObservationIgnored private let offsets: UserDefaults

    /// Set by the app: true while a screen shows lyrics (phone in front, CarPlay
    /// connected, Live Activity on). Faster polling then, gentler otherwise.
    public var isForeground = true

    /// Per-track manual correction in ms, applied everywhere through `positionMs`
    /// and `trackStartDate`. Positive shows lyrics earlier (for lyrics that lag).
    public private(set) var offsetMs = 0

    /// Polling cadence. A play, pause or seek is noticed within one interval, so this is
    /// the sync budget. Paused polls stay fast too: resuming must not leave lyrics frozen.
    /// Spotify rate limits over a rolling 30 s window; one request per second per user
    /// stays well inside it, and a 429 makes the loop honor Retry-After.
    nonisolated public static func pollInterval(isPlaying: Bool, hasTrack: Bool, foreground: Bool) -> Duration {
        switch (hasTrack, foreground) {
        case (true, true): return .milliseconds(1000)
        case (true, false): return isPlaying ? .milliseconds(2000) : .milliseconds(3000)
        case (false, true): return .seconds(3)
        case (false, false): return .seconds(6)
        }
    }

    private var currentPollInterval: Duration {
        Self.pollInterval(isPlaying: isPlaying, hasTrack: track != nil, foreground: isForeground)
    }

    public init(lyricsSource: LRCLibClient = LRCLibClient(), offsets: UserDefaults = .standard) {
        self.lyricsSource = lyricsSource
        self.offsets = offsets
    }

    // MARK: Playback control

    public private(set) var controlError: PlayerControlError?
    public var canControl: Bool { spotify is PlayerControlling }

    /// Sends a command to Spotify and moves the local clock right away, so lyrics react
    /// on the tap instead of on the next poll. A poll shortly after confirms the result.
    public func perform(_ command: PlayerCommand) {
        guard spotify is PlayerControlling else { return }
        // The local clock moves on the tap, synchronously; only the request is async.
        applyOptimistically(command)
        Task { await deliver(command) }
    }

    /// Awaitable form for callers that must not return before Spotify has the command,
    /// such as App Intents: iOS may suspend the app as soon as the intent returns.
    @discardableResult
    public func send(_ command: PlayerCommand) async -> Bool {
        guard spotify is PlayerControlling else { return false }
        applyOptimistically(command)
        return await deliver(command)
    }

    @discardableResult
    private func deliver(_ command: PlayerCommand) async -> Bool {
        guard let controller = spotify as? PlayerControlling else { return false }
        var ok = false
        do {
            try await controller.send(command)
            controlError = nil
            ok = true
        } catch let error as PlayerControlError {
            controlError = error
        } catch {
            controlError = .failed(0)
        }
        syncLog.notice("COMMAND \(String(describing: command)) ok=\(ok)")
        try? await Task.sleep(for: .milliseconds(command == .next || command == .previous ? 350 : 600))
        await pollOnce()
        return ok
    }

    /// True once a source is attached (signed in, or the demo clock).
    public var isConnected: Bool { spotify != nil }

    /// Jumps playback to the start of a lyric line.
    public func seek(toLine line: LyricLine) {
        // A little lead so the line is not cut off; the offset maps lyric time to track time.
        perform(.seek(toMs: max(0, line.startMs - offsetMs - 150)))
    }

    /// The state a just-sent command should produce, and until when polls that contradict
    /// it are treated as stale (Spotify takes a moment to apply a command).
    private struct Expectation {
        var issuedAt: Date
        var until: Date
        var isPlaying: Bool?
        var positionMs: Int?
        var trackChange: Bool
    }
    @ObservationIgnored private var expectation: Expectation?

    /// True when a poll result must not override the optimistic state.
    func isStale(_ now: NowPlaying, previousTrackID: String?) -> Bool {
        guard let expectation else { return false }
        // Request answered from before the command: always stale.
        if now.sample.sampledAt < expectation.issuedAt { return true }
        guard Date() < expectation.until else {
            self.expectation = nil
            return false
        }
        if expectation.trackChange {
            if now.track.id == previousTrackID { return true }
            self.expectation = nil
            return false
        }
        if let playing = expectation.isPlaying, playing != now.sample.isPlaying { return true }
        if let target = expectation.positionMs, abs(now.sample.progressMs - target) > 1500 + 2000 { return true }
        self.expectation = nil
        return false
    }

    private func applyOptimistically(_ command: PlayerCommand) {
        let now = Date()
        switch command {
        case .next, .previous:
            expectation = Expectation(issuedAt: now, until: now.addingTimeInterval(1.5), isPlaying: nil, positionMs: nil, trackChange: true)
            return
        case .seek(let ms):
            expectation = Expectation(issuedAt: now, until: now.addingTimeInterval(1.5), isPlaying: nil, positionMs: ms, trackChange: false)
        case .pause:
            expectation = Expectation(issuedAt: now, until: now.addingTimeInterval(1.5), isPlaying: false, positionMs: nil, trackChange: false)
        case .play:
            expectation = Expectation(issuedAt: now, until: now.addingTimeInterval(1.5), isPlaying: true, positionMs: nil, trackChange: false)
        }
        guard let sample = clock.sample else { return }
        let position = clock.position(at: now) ?? sample.progressMs
        var guess = sample
        guess.sampledAt = now
        switch command {
        case .seek(let ms): guess.progressMs = ms
        case .pause: guess.progressMs = position; guess.isPlaying = false
        case .play: guess.progressMs = position; guess.isPlaying = true
        case .next, .previous: return
        }
        clock.ingest(guess, rttMs: 0)
        if isPlaying != guess.isPlaying {
            isPlaying = guess.isPlaying
        }
        notify(.playState)
        updateIndex()
    }

    // MARK: Manual sync correction

    static let offsetsKey = "lyricOffsetsByTrack"

    /// Nudges the lyrics for the current track and remembers it for next time.
    public func nudge(byMs delta: Int) {
        guard let id = track?.id else { return }
        offsetMs = max(-10_000, min(10_000, offsetMs + delta))
        var all = offsets.dictionary(forKey: Self.offsetsKey) as? [String: Int] ?? [:]
        all[id] = offsetMs == 0 ? nil : offsetMs
        offsets.set(all, forKey: Self.offsetsKey)
        updateIndex()
        notify(.playState)
    }

    private func loadOffset(for trackID: String) {
        offsetMs = (offsets.dictionary(forKey: Self.offsetsKey) as? [String: Int])?[trackID] ?? 0
    }

    // MARK: Lifecycle

    public func connect(_ client: NowPlayingSource) {
        spotify = client
        start()
    }

    public func signOut() {
        stop()
        spotify = nil
        clock.reset()
        track = nil
        document = nil
        currentIndex = nil
        set(.signedOut)
    }

    public func start() {
        guard spotify != nil, pollTask == nil else { return }
        pollTask = Task { [weak self] in await self?.pollLoop() }
        tickTask = Task { [weak self] in await self?.tickLoop() }
    }

    public func stop() {
        pollTask?.cancel()
        tickTask?.cancel()
        pollTask = nil
        tickTask = nil
    }

    /// Forces an immediate poll, for example after the CarPlay scene connects.
    public func refreshNow() {
        Task { await pollOnce() }
    }

    // MARK: Observation for UIKit surfaces (CarPlay, Live Activity, widgets)

    @discardableResult
    public func observe(_ handler: @escaping (Change) -> Void) -> UUID {
        let id = UUID()
        observers[id] = handler
        return id
    }

    public func removeObserver(_ id: UUID) {
        observers[id] = nil
    }

    // MARK: Derived values

    public func positionMs(at date: Date = Date()) -> Int? { clock.position(at: date).map { $0 + offsetMs } }
    public func trackStartDate() -> Date? { clock.trackStartDate()?.addingTimeInterval(-Double(offsetMs) / 1000) }

    public var currentLine: LyricLine? { currentIndex.flatMap { document?.lines[$0] } }

    public var nextLine: LyricLine? {
        guard let document, document.syncType == .lineSynced else { return nil }
        let next = (currentIndex ?? -1) + 1
        return next < document.lines.count ? document.lines[next] : nil
    }

    public func snapshot(now: Date = Date()) -> LyricsSnapshot? {
        guard let track else { return nil }
        return LyricsSnapshot(
            trackName: track.name,
            artist: track.artistLine,
            provider: document?.provider ?? "LRCLIB",
            document: document,
            isPlaying: isPlaying,
            durationMs: track.durationMs,
            trackStartDate: trackStartDate() ?? now,
            pausedPositionMs: positionMs(at: now) ?? 0,
            updatedAt: now
        )
    }

    // MARK: Loops

    private func pollLoop() async {
        while !Task.isCancelled {
            let wait = await pollOnce()
            try? await Task.sleep(for: wait)
        }
    }

    @discardableResult
    public func pollOnce() async -> Duration {
        guard let spotify else { return .seconds(6) }
        do {
            guard let now = try await spotify.currentlyPlaying() else {
                apply(nil)
                return currentPollInterval
            }
            apply(now)
            return currentPollInterval
        } catch SpotifyError.unauthorized {
            // The client has invalidated the token; the next poll refreshes it.
            set(.signedOut)
            return .seconds(2)
        } catch SpotifyError.rateLimited(let retryAfter) {
            syncLog.notice("RATE-LIMITED retryAfter=\(retryAfter)")
            return .seconds(max(retryAfter, 1))
        } catch is CancellationError {
            return currentPollInterval
        } catch {
            if track == nil { set(.failed(error.localizedDescription)) }
            return currentPollInterval
        }
    }

    /// 10 Hz while a screen shows lyrics: lines last seconds, and we only publish on index
    /// change. Otherwise the loop sleeps until the next line or the end of the track
    /// (at most 1 s), which keeps background CPU near zero without delaying a line.
    private func tickLoop() async {
        while !Task.isCancelled {
            updateIndex()
            pollAtTrackEnd()
            try? await Task.sleep(for: tickDelay)
        }
    }

    private var tickDelay: Duration {
        let cap = isForeground ? 100 : 1000
        guard isPlaying, let position = positionMs(at: Date()) else { return .milliseconds(cap) }
        var wait = cap
        if let next = nextLine { wait = min(wait, next.startMs - position) }
        // Past the end-of-track poll the remaining time is negative: fall back to the cap
        // instead of spinning until the poll lands.
        if let track, case let end = track.durationMs - 300 - (position - offsetMs), end > 0 { wait = min(wait, end) }
        return .milliseconds(max(20, wait))
    }

    // MARK: State transitions

    func apply(_ now: NowPlaying?) {
        guard let now else {
            if track != nil || status != .nothingPlaying {
                track = nil
                document = nil
                currentIndex = nil
                isPlaying = false
                clock.reset()
                notify(.track)
                set(.nothingPlaying)
            }
            return
        }

        if isStale(now, previousTrackID: track?.id) {
            syncLog.notice("SYNC stale sample ignored after a command")
            return
        }
        let isNewTrack = track?.id != now.track.id
        let predicted = clock.position(at: now.sample.sampledAt)
        let jumped = clock.ingest(now.sample, rttMs: now.rttMs)
        onPoll?("poll playing=\(now.sample.isPlaying) progress=\(now.sample.progressMs) drift=\((predicted ?? now.sample.progressMs) - now.sample.progressMs) rtt=\(now.rttMs)")
        syncLog.notice("SYNC reported=\(now.sample.progressMs) predicted=\(predicted ?? -1) drift=\((predicted ?? now.sample.progressMs) - now.sample.progressMs) playing=\(now.sample.isPlaying) jumped=\(jumped) newTrack=\(isNewTrack)")

        if isNewTrack {
            track = now.track
            loadOffset(for: now.track.id)
            document = nil
            currentIndex = nil
            notify(.track)
            loadLyrics(for: now.track)
        } else if status == .signedOut || status == .nothingPlaying || status == .idle {
            // A poll answered again after a rejected token: same track, so nothing above
            // reset the status, and the phone would keep saying "signed out".
            if let cached = cache[now.track.id] { setDocument(cached, for: now.track.id) } else { loadLyrics(for: now.track) }
        }
        if isPlaying != now.sample.isPlaying {
            isPlaying = now.sample.isPlaying
            notify(.playState)
        } else if jumped && !isNewTrack {
            // Seek: surfaces with precomputed timelines must rebuild them.
            notify(.playState)
        }
        updateIndex()
    }

    /// Waits before each retry of a lyrics lookup that failed on the network.
    static let lyricsRetryDelays: [Duration] = [.seconds(2), .seconds(5), .seconds(10)]

    private func loadLyrics(for track: SpotifyTrack, attempt: Int = 0) {
        if let cached = cache[track.id] {
            setDocument(cached, for: track.id)
            return
        }
        set(.loadingLyrics)
        Task { [weak self, lyricsSource] in
            do {
                let document = try await lyricsSource.lyrics(for: track)
                guard let self else { return }
                if self.cache.count >= 200 { self.cache.removeAll(keepingCapacity: true) }
                self.cache[track.id] = document
                self.setDocument(document, for: track.id)
            } catch {
                // Network trouble is not an answer: leave it uncached and ask again while
                // the track is still playing (a locked phone often wakes into a dead link).
                guard attempt < Self.lyricsRetryDelays.count else {
                    self?.setDocument(nil, for: track.id)
                    return
                }
                try? await Task.sleep(for: Self.lyricsRetryDelays[attempt])
                guard let self, self.track?.id == track.id else { return }
                self.loadLyrics(for: track, attempt: attempt + 1)
            }
        }
    }

    private func setDocument(_ document: LyricsDocument?, for trackID: String) {
        guard track?.id == trackID else { return }
        self.document = document
        notify(.lyrics)
        set(document == nil ? .noLyrics : .ready)
        updateIndex()
    }

    /// The next track starts the moment this one ends; ask right then instead of
    /// showing the old song's last line until the next regular poll.
    private func pollAtTrackEnd() {
        guard isPlaying, let track, endOfTrackPollFor != track.id,
              let position = clock.position(at: Date()), position >= track.durationMs - 300 else { return }
        endOfTrackPollFor = track.id
        refreshNow()
    }

    private func updateIndex() {
        let index = positionMs(at: Date()).flatMap { document?.lineIndex(at: $0) }
        if index != currentIndex {
            currentIndex = index
            notify(.line)
        }
    }

    private func set(_ new: Status) {
        guard status != new else { return }
        status = new
        notify(.status)
    }

    private func notify(_ change: Change) {
        for handler in observers.values { handler(change) }
    }
}
