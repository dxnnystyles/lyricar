import Foundation
import LyricsKit
import UIKit
import Observation
import os

private let syncLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "lyricar", category: "intent")

/// Process-wide owner of the engine. The phone scene and the CarPlay scene
/// both read from the same instance, so they never disagree about the line.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    let engine = LyricsEngine()
    @ObservationIgnored let liveActivity: LiveActivityController
    @ObservationIgnored let widgets: WidgetBridge
    @ObservationIgnored let keepAlive = BackgroundKeepAlive()
    @ObservationIgnored private(set) var auth: SpotifyAuth?

    private(set) var isConnected = false
    private(set) var connectionNote: String?
    var liveActivityOn = false {
        didSet {
            liveActivity.setEnabled(liveActivityOn)
            updateLiveness()
        }
    }

    /// Keep polling in the background while music plays, so the Live Activity and
    /// widgets follow pauses, seeks and skips. On by default: sync is the product.
    var backgroundSync = UserDefaults.standard.object(forKey: "backgroundSync") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(backgroundSync, forKey: "backgroundSync")
            updateLiveness()
        }
    }

    /// The selected style. Shared through the App Group so the widget extension and
    /// Live Activity read the same value; observers re-render CarPlay.
    var theme: LyricTheme = .current {
        didSet {
            guard theme != oldValue else { return }
            LyricTheme.current = theme
            liveActivity.refresh()
            widgets.publish(force: true)
            themeObservers.values.forEach { $0(theme) }
        }
    }
    @ObservationIgnored private var themeObservers: [UUID: (LyricTheme) -> Void] = [:]

    @discardableResult
    func observeTheme(_ handler: @escaping (LyricTheme) -> Void) -> UUID {
        let id = UUID()
        themeObservers[id] = handler
        return id
    }

    func removeThemeObserver(_ id: UUID) { themeObservers[id] = nil }

    @ObservationIgnored private var restoreTask: Task<Void, Never>?

    /// Runs a widget or Live Activity button press to completion, even when iOS launched
    /// the app in the background just for it: wait for the session, learn the current
    /// state if this process has none yet, then send and await the command.
    func handle(_ action: PlaybackAction) async {
        await restoreTask?.value
        guard engine.isConnected else {
            syncLog.notice("INTENT \(action.rawValue) dropped: not connected")
            return
        }
        if engine.track == nil { await engine.pollOnce() }
        let command: PlayerCommand
        switch action {
        case .playPause: command = engine.isPlaying ? .pause : .play
        case .next: command = .next
        case .previous: command = .previous
        }
        syncLog.notice("INTENT \(action.rawValue) -> \(String(describing: command))")
        await engine.send(command)
        widgets.publish(force: true)
    }

    @ObservationIgnored private var phoneActive = true
    @ObservationIgnored private var carPlayConnected = false

    func setPhoneActive(_ active: Bool) {
        phoneActive = active
        if active {
            engine.refreshNow()
            // Only the foreground may start a Live Activity; recreate one the system ended.
            liveActivity.restoreIfNeeded()
        }
        updateLiveness()
    }

    func setCarPlayConnected(_ connected: Bool) {
        carPlayConnected = connected
        updateLiveness()
    }

    /// One place decides how hard to work: fast polling while any surface is visible,
    /// background keep-alive while music plays and something outside the app shows lyrics.
    @ObservationIgnored private var lastActiveAt: Date?
    @ObservationIgnored private var livenessCheck: Task<Void, Never>?

    private func updateLiveness() {
        engine.isForeground = phoneActive || carPlayConnected || liveActivityOn
        if engine.isPlaying || phoneActive { lastActiveAt = Date() }
        // The keep-alive runs whenever the app is in front, so it is already playing when
        // the screen locks: iOS may refuse to start audio from the background. It then
        // stays on while music plays and for 30 minutes after a pause or after leaving
        // the app, so a resume from the lock screen, the car or another device is picked up.
        let recentlyActive = lastActiveAt.map { Date().timeIntervalSince($0) < 30 * 60 } ?? false
        let wantsKeepAlive = isConnected && (liveActivityOn || carPlayConnected || (backgroundSync && recentlyActive))
        wantsKeepAlive ? keepAlive.start() : keepAlive.stop()
        // Nothing else re-evaluates the 30 minutes while paused; without this check the
        // keep-alive would run until the battery is empty.
        if wantsKeepAlive, livenessCheck == nil {
            livenessCheck = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                    self?.updateLiveness()
                }
            }
        } else if !wantsKeepAlive {
            livenessCheck?.cancel()
            livenessCheck = nil
        }
    }

    @ObservationIgnored private var lifecycleObservers: [NSObjectProtocol] = []

    /// Lifecycle and lock events in the diagnostics log, each with the audio state, so a
    /// device run shows what the keep-alive looked like when the screen locked.
    private func observeLifecycle() {
        let events: [(Notification.Name, String)] = [
            (UIApplication.didEnterBackgroundNotification, "background"),
            (UIApplication.willEnterForegroundNotification, "foreground"),
            (UIApplication.protectedDataWillBecomeUnavailableNotification, "locking"),
            (UIApplication.protectedDataDidBecomeAvailableNotification, "unlocked"),
        ]
        lifecycleObservers = events.map { name, label in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    Diagnostics.record("APP \(label) \(self.keepAlive.status)", keepAlive: self.keepAlive.isRunning)
                }
            }
        }
    }

    private init() {
        liveActivity = LiveActivityController(engine: engine)
        widgets = WidgetBridge(engine: engine)
        liveActivityOn = liveActivity.isEnabled
        // Observers do not fire inside init; re-attach an activity that survived a relaunch.
        if liveActivityOn { liveActivity.setEnabled(true) }

        engine.observe { [weak self] change in
            if change == .playState || change == .track { self?.updateLiveness() }
        }
        // One diagnostic line per poll result (line changes are too frequent to matter).
        engine.onPoll = { [weak self] summary in
            Diagnostics.record(summary, keepAlive: self?.keepAlive.isRunning ?? false)
        }
        keepAlive.onEvent = { [weak self] event in
            Diagnostics.record(event, keepAlive: self?.keepAlive.isRunning ?? false)
        }
        observeLifecycle()

        let clientID = (Bundle.main.object(forInfoDictionaryKey: "SpotifyClientID") as? String) ?? ""
        if !clientID.isEmpty, !clientID.hasPrefix("$(") {
            auth = SpotifyAuth(clientID: clientID)
        }
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let flag = arguments.firstIndex(of: "-LyricarTheme"), arguments.indices.contains(flag + 1),
           let forced = LyricTheme(rawValue: arguments[flag + 1]) {
            theme = forced
            LyricTheme.current = forced
        }
        LoopbackSelfTest.runIfRequested()
        StyleGallery.runIfRequested()
        if arguments.contains("-LyricarKeepAliveStress") { keepAlive.stress(cycles: 200) }
        #endif
        restoreTask = Task { await restore() }
    }

    private func restore() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-LyricarStickyDemo") {
            UserDefaults.standard.set(true, forKey: "LyricarStickyDemo")
        }
        if DemoSource.isRequested || UserDefaults.standard.bool(forKey: "LyricarStickyDemo") {
            engine.connect(DemoSource())
            isConnected = true
            connectionNote = "Demo clock, real LRCLIB lyrics"
            if ProcessInfo.processInfo.arguments.contains("-LyricarLiveActivity") { liveActivityOn = true }
            return
        }
        #endif
        if let auth, await auth.isSignedIn {
            connect(with: auth, note: nil)
            return
        }
        #if DEBUG && targetEnvironment(simulator)
        if HostTokenProvider.isAvailable {
            connect(with: HostTokenProvider(), note: "Simulator: using the host Spotify token")
        }
        #endif
    }

    /// True when signed in with a session that lacks the playback-control permission.
    private(set) var needsReconnectForControls = false

    func connect(with tokens: AccessTokenProvider, note: String?) {
        if let auth = tokens as? SpotifyAuth {
            Task { needsReconnectForControls = !(await auth.canControlPlayback) }
        }
        engine.connect(SpotifyClient(tokens: tokens))
        isConnected = true
        connectionNote = note
        updateLiveness()
    }

    func signOut() async {
        await auth?.signOut()
        engine.signOut()
        liveActivityOn = false
        isConnected = false
        connectionNote = nil
    }
}
