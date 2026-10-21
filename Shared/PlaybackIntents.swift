import AppIntents
import Foundation
import os

enum PlaybackAction: String, AppEnum {
    case playPause, next, previous

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Playback action"
    static let caseDisplayRepresentations: [PlaybackAction: DisplayRepresentation] = [
        .playPause: "Play or pause",
        .next: "Next song",
        .previous: "Previous song",
    ]
}

/// Set by the app at launch. `LiveActivityIntent.perform` runs in the app's process,
/// so buttons in the Live Activity and widgets reach the same engine as the phone UI.
@MainActor
enum PlaybackCommandRouter {
    /// Registered by the app's `App` initializer, which runs on every launch, including
    /// the background launch iOS does just to run this intent.
    static var handler: ((PlaybackAction) async -> Void)?
}

/// `AudioPlaybackIntent` and `LiveActivityIntent` both make iOS run `perform` in the
/// app's process (launching it in the background if needed), never in the widget
/// extension, which has no Spotify session.
struct LyricPlaybackIntent: AudioPlaybackIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Control Spotify playback"
    static let isDiscoverable = false

    @Parameter(title: "Action")
    var action: PlaybackAction

    init() {}

    init(_ action: PlaybackAction) {
        self.action = action
    }

    func perform() async throws -> some IntentResult {
        // Awaited end to end: returning early would let iOS suspend the app before the
        // request reaches Spotify.
        let process = Bundle.main.bundleIdentifier ?? "?"
        let hasHandler = await PlaybackCommandRouter.handler != nil
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "lyricar", category: "intent")
            .notice("INTENT perform \(action.rawValue) process=\(process) handler=\(hasHandler)")
        if let handler = await PlaybackCommandRouter.handler {
            await handler(action)
        }
        return .result()
    }
}
