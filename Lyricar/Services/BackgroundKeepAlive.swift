import AVFoundation
import UIKit
import os

/// Keeps the process running in the background (screen locked, Low Power Mode, CarPlay)
/// so the engine keeps polling Spotify and the Live Activity, widgets and CarPlay keep
/// following the song. iOS suspends a backgrounded app within seconds otherwise.
///
/// It plays digital silence with `.mixWithOthers`: Spotify keeps playing and keeps the
/// Now Playing slot, nothing is audible. Background audio is exempt from Low Power Mode.
///
/// The fragile part is staying alive: an audio route change (connecting CarPlay or
/// Bluetooth), an interruption (call, Siri, alarm) or a media services reset all stop the
/// engine silently, and iOS then suspends the app. Every one of those restarts it here.
/// A restart that fails is retried by the watchdog, and while the engine is down in the
/// background a background task holds the process up so the retry can happen at all.
///
/// Fine for a personal sideloaded build; App Review rejects silent-audio keep-alives,
/// so a store build would need ActivityKit push updates from a server instead.
@MainActor
final class BackgroundKeepAlive {
    private var engine = AVAudioEngine()
    private var player = AVAudioPlayerNode()
    private(set) var isRunning = false
    private var wanted = false
    private var observers: [NSObjectProtocol] = []
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "lyricar", category: "keepalive")
    private var watchdog: Timer?
    private var bridgeTask: UIBackgroundTaskIdentifier = .invalid

    /// One line per state change, for the on-device diagnostics log.
    var onEvent: ((String) -> Void)?

    init() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        observers = [
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] note in
                let info = note.userInfo ?? [:]
                let type = (info[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init(rawValue:))
                let reason = info[AVAudioSessionInterruptionReasonKey] as? UInt
                let wasSuspended = info[AVAudioSessionInterruptionWasSuspendedKey] as? Bool ?? false
                let shouldResume = (info[AVAudioSessionInterruptionOptionKey] as? UInt)
                    .map { AVAudioSession.InterruptionOptions(rawValue: $0).contains(.shouldResume) } ?? false
                MainActor.assumeIsolated {
                    self?.handleInterruption(ended: type == .ended, reason: reason, wasSuspended: wasSuspended, shouldResume: shouldResume)
                }
            },
            center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.restartIfNeeded(reason: "route change") }
            },
            center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.rebuild(reason: "media services reset") }
            },
            center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.restartIfNeeded(reason: "engine configuration change") }
            },
        ]
    }

    /// The audio state that decides whether iOS lets the process run, for diagnostics.
    var status: String {
        let session = AVAudioSession.sharedInstance()
        return "keepAlive=\(isRunning) wanted=\(wanted) engine=\(engine.isRunning) player=\(player.isPlaying) "
            + "otherAudio=\(session.isOtherAudioPlaying) silenceHint=\(session.secondaryAudioShouldBeSilencedHint)"
    }

    func start() {
        wanted = true
        // Armed before the attempt, so a start that fails is retried instead of forgotten.
        startWatchdog()
        guard !isRunning else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)

            let format = engine.outputNode.inputFormat(forBus: 0)
            guard format.sampleRate > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(format.sampleRate)) else {
                report("KEEPALIVE no output format, will retry")
                holdProcessIfBackground()
                return
            }
            buffer.frameLength = buffer.frameCapacity // Zero-filled: silence.

            if player.engine == nil { engine.attach(player) }
            engine.disconnectNodeOutput(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            // The buffer is all zeros, so the output is digital silence at any volume.
            // Unity gain rather than 0 keeps the render path a normal playing one, in case
            // the system treats a muted mixer as not playing (unverified, a hedge).
            engine.mainMixerNode.outputVolume = 1
            engine.prepare()
            try engine.start()
            // play() on a stopped engine or an unconnected node raises an Objective-C
            // exception Swift cannot catch (crash seen 14 Oct, 13:10). Check both first.
            guard engine.isRunning, player.engine === engine, !engine.outputConnectionPoints(for: player, outputBus: 0).isEmpty else {
                report("KEEPALIVE engine not ready, will retry")
                holdProcessIfBackground()
                return
            }
            player.stop()
            player.scheduleBuffer(buffer, at: nil, options: .loops)
            player.play()
            isRunning = true
            report("KEEPALIVE started")
            releaseProcessHold()
        } catch {
            isRunning = false
            // 561015905 ('!pla'): playback may not start from the background. That points
            // at a reactivation attempted while suspended, not at the keep-alive itself.
            let code = (error as NSError).code
            report("KEEPALIVE start failed code=\(code) \(error.localizedDescription)")
            holdProcessIfBackground()
        }
    }

    #if DEBUG
    /// `-LyricarKeepAliveStress`: hammers start, stop, restart and rebuild to prove none
    /// of the transitions can reach `play()` in a bad state.
    func stress(cycles: Int) {
        for index in 0..<cycles {
            switch index % 4 {
            case 0: start()
            case 1: restartIfNeeded(reason: "stress")
            case 2: stop(); start()
            default: rebuild(reason: "stress")
            }
        }
        log.notice("KEEPALIVE stress done cycles=\(cycles) running=\(self.isRunning)")
    }
    #endif

    func stop() {
        wanted = false
        watchdog?.invalidate()
        watchdog = nil
        releaseProcessHold()
        guard isRunning else { return }
        player.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isRunning = false
        report("KEEPALIVE stopped")
    }

    /// The engine can also stop without any notification. Checked every 10 s, which is
    /// also the retry cadence after a failed start.
    private func startWatchdog() {
        guard watchdog == nil else { return }
        watchdog = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.restartIfNeeded(reason: "watchdog") }
        }
    }

    private func handleInterruption(ended: Bool, reason: UInt?, wasSuspended: Bool, shouldResume: Bool) {
        let detail = "reason=\(reason.map(String.init) ?? "-") wasSuspended=\(wasSuspended) shouldResume=\(shouldResume)"
        if ended {
            report("KEEPALIVE interruption ended \(detail)")
            // Restart even without shouldResume: that flag is a hint for media players, and
            // this session is mixable silence that may always come back.
            restartIfNeeded(reason: "interruption ended")
        } else if wasSuspended {
            // Delivered late, after the app was suspended: the interruption is already over.
            report("KEEPALIVE stale interruption \(detail)")
            restartIfNeeded(reason: "stale interruption")
        } else {
            isRunning = false
            report("KEEPALIVE interrupted \(detail)")
            // No end notification is guaranteed. Without a hold iOS suspends the process
            // as soon as the audio stops, and nothing would ever restart it.
            holdProcessIfBackground()
        }
    }

    private func restartIfNeeded(reason: String) {
        guard wanted else { return }
        if isRunning, engine.isRunning, player.isPlaying { return }
        report("KEEPALIVE restart after \(reason)")
        isRunning = false
        start()
    }

    private func rebuild(reason: String) {
        guard wanted else { return }
        report("KEEPALIVE rebuild after \(reason)")
        engine = AVAudioEngine()
        player = AVAudioPlayerNode()
        isRunning = false
        start()
    }

    // MARK: Background hold

    /// While the engine is down in the background, a background task keeps the process
    /// running for the watchdog's retries (iOS grants about 30 s).
    private func holdProcessIfBackground() {
        guard wanted, bridgeTask == .invalid, UIApplication.shared.applicationState == .background else { return }
        bridgeTask = UIApplication.shared.beginBackgroundTask(withName: "KeepAliveRestart") { [weak self] in
            MainActor.assumeIsolated {
                self?.report("KEEPALIVE hold expired, running=\(self?.isRunning ?? false)")
                self?.releaseProcessHold()
            }
        }
        // Late in the background iOS may grant no time at all; then there is nothing to hold.
        guard bridgeTask != .invalid else {
            report("KEEPALIVE hold refused")
            return
        }
        report("KEEPALIVE holding process for restart")
        // Retry sooner than the 10 s watchdog: the hold is short.
        Task { [weak self] in
            for _ in 0..<5 {
                try? await Task.sleep(for: .seconds(4))
                guard let self, self.wanted, !self.isRunning else { return }
                self.restartIfNeeded(reason: "hold retry")
            }
        }
    }

    private func releaseProcessHold() {
        guard bridgeTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(bridgeTask)
        bridgeTask = .invalid
    }

    private func report(_ line: String) {
        log.notice("\(line, privacy: .public)")
        onEvent?(line)
    }
}
