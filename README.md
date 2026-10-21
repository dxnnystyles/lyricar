<div align="center">

<img src="https://raw.githubusercontent.com/noluyorAbi/lyricar/main/assets/banner.png" width="100%" alt="Lyricar: synced Spotify lyrics on the iPhone, the Lock Screen, the Dynamic Island, widgets and CarPlay">

<b>Synced lyrics for whatever is playing on your Spotify, on the iPhone, the Lock Screen, the Dynamic Island, widgets and CarPlay.</b>

<br>
<br>

<a href="https://github.com/noluyorAbi/lyricar/stargazers">
  <img src="https://img.shields.io/badge/%E2%98%85%20Star%20this%20repo-0b0b0b?style=for-the-badge&logo=github&logoColor=white&labelColor=0b0b0b" height="54" alt="Star lyricar on GitHub">
</a>
&nbsp;&nbsp;
<a href="#quick-start">
  <img src="https://img.shields.io/badge/Build%20it-Xcode%2026-f5a524?style=for-the-badge&logo=xcode&logoColor=white&labelColor=0b0b0b" height="54" alt="Build Lyricar with Xcode 26">
</a>

<br>
<br>

<a href="https://github.com/noluyorAbi/lyricar/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/noluyorAbi/lyricar/ci.yml?branch=main&style=for-the-badge&logo=githubactions&logoColor=white&label=ci&labelColor=0b0b0b" alt="ci"></a>
<a href="https://github.com/noluyorAbi/lyricar/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-Apache%202.0-3a3a3a?style=for-the-badge&labelColor=0b0b0b" alt="license: Apache 2.0"></a>
<img src="https://img.shields.io/badge/iOS-26-3a3a3a?style=for-the-badge&logo=apple&logoColor=white&labelColor=0b0b0b" alt="iOS 26">
<img src="https://img.shields.io/badge/Swift-SwiftUI-3a3a3a?style=for-the-badge&logo=swift&logoColor=white&labelColor=0b0b0b" alt="Swift and SwiftUI">
<a href="https://lyricar.adatepe.dev?utm_source=readme&utm_medium=badge"><img src="https://img.shields.io/badge/website-lyricar.adatepe.dev-f5a524?style=for-the-badge&logo=vercel&logoColor=white&labelColor=0b0b0b" alt="Lyricar website"></a>

<br>
<br>

<table>
  <tr>
    <td width="33%"><img src="https://raw.githubusercontent.com/noluyorAbi/lyricar/main/docs/screens/phone-karaoke.png" alt="Karaoke view on the iPhone, current line pinned in the upper third"></td>
    <td width="33%"><img src="https://raw.githubusercontent.com/noluyorAbi/lyricar/main/docs/screens/home-widgets.png" alt="Lyric Line, Up Next and Remote widgets on the Home Screen"></td>
    <td width="33%"><img src="https://raw.githubusercontent.com/noluyorAbi/lyricar/main/docs/screens/phone-live-karaoke.png" alt="Karaoke view following a live Spotify session"></td>
  </tr>
</table>

<img src="https://raw.githubusercontent.com/noluyorAbi/lyricar/main/docs/screens/dynamic-island-line.png" width="98%" alt="Dynamic Island showing the current lyric line">

<img src="https://raw.githubusercontent.com/noluyorAbi/lyricar/main/docs/screens/carplay-karaoke.png" width="49%" alt="CarPlay Karaoke tab, list windowed around the current line">
<img src="https://raw.githubusercontent.com/noluyorAbi/lyricar/main/docs/screens/carplay-stage-styles.png" width="49%" alt="CarPlay Stage tab with the style picker">

<sub>27 second walkthrough: <a href="https://github.com/noluyorAbi/lyricar/releases/download/v0.1.0/demo.mp4"><code>demo.mp4</code></a> in the <a href="https://github.com/noluyorAbi/lyricar/releases/tag/v0.1.0">v0.1.0 release</a>.</sub>

</div>

<br>

Spotify shows lyrics inside its own app and nowhere else. Lock the phone, open another app or get in the car, and they are gone. Lyricar follows your Spotify playback through the Web API, pulls line-synced lyrics from [LRCLIB](https://lrclib.net), and puts the current line wherever you glance: the Lock Screen, the Dynamic Island, a Home Screen widget, the CarPlay dashboard. The sync drift averages about 27 ms.

It doubles as a small, readable example of the newer iOS surfaces: Live Activities, WidgetKit timelines that run without waking the app, App Intents that control playback from a widget, and CarPlay templates, all fed by one engine.

## What you get

| Surface | Views | Updates |
|---|---|---|
| iPhone app | Karaoke (full sheet, current line pinned in the upper third), Focus (one huge line plus the next), Verse (widget layout at phone size) | 10 Hz local clock, Spotify polled every 1 s (2 to 3 s in the background) |
| Lock Screen and Dynamic Island | Live Activity: Lock Screen banner, Dynamic Island compact, expanded and minimal, and the `.small` family that iOS 26 shows on the CarPlay dashboard and the Watch Smart Stack | Every line change; the progress bar animates on its own via `ProgressView(timerInterval:)` |
| Widgets | Lyric Line, Up Next, Remote (previous, play/pause, next), Verse, Gauge, in Home Screen and Lock Screen sizes | No app wake-ups: the widget gets the whole timed sheet and schedules one timeline entry per line |
| CarPlay | Karaoke (list windowed around the current line), Focus (current line, next as detail), Stage (style picker), Track (song, source, resync, controls) | Same engine, pushed on every line change |

Also: tap any line to jump the song there, previous/play/next everywhere, a per-track "lyrics are late / early" nudge in 0.25 s steps, and eight styles chosen app-wide or per widget.

## Quick start

You need a Mac with Xcode 26, an iPhone on iOS 26 (or just the Simulator), and a Spotify account. Playback controls need Spotify Premium.

```sh
git clone https://github.com/noluyorAbi/lyricar
cd lyricar
brew install xcodegen
./scripts/setup.sh            # asks for team, bundle prefix and Spotify client ID, writes Config/Local.xcconfig
open Lyricar.xcodeproj
```

Pick the `Lyricar` scheme and run. `scripts/setup.sh` writes the gitignored `Config/Local.xcconfig` (template: `Config/Local.xcconfig.example`) and runs `xcodegen generate`. Prefer to fill it in by hand? Copy the example, set `DEVELOPMENT_TEAM`, `LYRICAR_BUNDLE_PREFIX` and `SPOTIFY_CLIENT_ID`, then run `xcodegen generate`.

No Spotify app yet? Run in the Simulator with the `-LyricarDemo` launch argument: a fake playback clock plays "Midnight City" by M83 with real lyrics from LRCLIB.

### 1. Create your Spotify app

1. Open the [Spotify developer dashboard](https://developer.spotify.com/dashboard) and create an app. Pick "Web API".
2. Add the redirect URI `http://127.0.0.1:3000/spotify/callback`.
3. Paste the client ID when `scripts/setup.sh` asks (or pass `--client-id`). There is no client secret: sign-in is Authorization Code with PKCE.
4. Under User Management, add the Spotify accounts that will sign in.

Spotify keeps new apps in Development Mode: the owner needs Premium, and since February 2026 an app allows at most 5 users, each added by hand. That is plenty for you and a few friends, and the reason Lyricar is a build-it-yourself app rather than an App Store app.

Why a loopback redirect: while the sign-in sheet is open, Lyricar listens on the phone's own port 3000 and answers Spotify's redirect with a 302 to `lyricar://callback`, which completes the `ASWebAuthenticationSession` (`LoopbackRedirectServer.swift`). Nothing leaves the device. Scopes: `user-read-currently-playing user-read-playback-state user-modify-playback-state`.

### 2. Put it on your iPhone

Plug the iPhone in, unlock it, trust the Mac, and enable Developer Mode (Settings, Privacy & Security). Then:

```sh
./scripts/install-device.sh
```

With a free Apple ID (Personal Team) the app runs for 7 days; run the script again to renew it. On first launch, trust the developer under Settings, General, VPN & Device Management. A paid Apple Developer Program membership removes the 7-day limit; `scripts/switch-to-paid-team.sh` moves the build to that team once Xcode lists it.

## CarPlay

CarPlay apps outside navigation are template-only, and every category needs an entitlement that Apple grants on request. Lyricar declares `com.apple.developer.carplay-audio`:

- **Simulator:** works today. Lyricar shows on the CarPlay home screen with all four tabs.
- **Real car, without Apple's grant:** the Live Activity (`.small` family) and the small widgets still reach the CarPlay dashboard, because iOS 26 shows them there with no entitlement at all. The Lyricar icon itself does not appear, and device builds use `Lyricar/Lyricar-Device.entitlements` without the CarPlay key so they still sign.
- **Real car, with the grant:** request it at [developer.apple.com/contact/carplay](https://developer.apple.com/contact/carplay) with a paid membership, then run `scripts/switch-to-paid-team.sh --carplay`. Lyricar plays no audio itself, so Apple may refuse the Audio category.

On the dashboard, iOS 26 only offers the small widget size. Put **Lyric Line** and **Up Next** side by side to read ahead; both switch to a dashboard layout on CarPlay. **Remote** adds buttons that are tappable on touchscreen cars.

Reading lyrics while driving is a distraction. The CarPlay views are built to be glanced at, the way the system shows a song title; passengers get the full sheet on the phone.

## Styles

| Style | Look |
|---|---|
| Midnight | Amber on near-black, rounded heavy type |
| Motorsport | Tricolor stripe on a light badge plate, graphite surface, Barlow Condensed ExtraBold Italic |
| Night Drive | Black glass with a blue glow, light-weight Barlow |
| Panoramic | Light band with a cyan-to-blue line, Barlow Medium |
| Sport | Carbon, compressed black type, redline accent and gauge |
| Luxe | Warm black, champagne accent, serif |
| Neon | Synthwave purple, monospaced, glow |
| Daylight | Light background for sun glare |

Every style and widget size is rendered for review by the `-LyricarRenderGallery` launch argument; the results are in [`docs/screens/styles`](docs/screens/styles). Fonts are Barlow and Barlow Condensed under the SIL Open Font License (`Shared/Fonts`).

## How it works

```
Spotify Web API  /me/player/currently-playing  (1 s while visible, 2 to 3 s in background, honors Retry-After)
        |
        v
PlaybackClock    sample pinned to the request midpoint, interpolated locally,
        |        the most precise sample of the last 20 s wins
        v
LyricsEngine     one per process, shared by the phone scene and the CarPlay scene
   |      |      |                     |
 SwiftUI  CarPlay templates   Live Activity        LyricsSnapshot -> App Group -> widget timeline
```

Lyrics come from [LRCLIB](https://lrclib.net), a public, keyless lyrics database, and are fetched at runtime; none are bundled. Lookup order: exact match with album, exact match without album (LRCLIB answers 503 for some album lookups it has not cached), then fuzzy search filtered to tracks within 3 s of the Spotify duration, preferring synced lyrics. A network failure is never cached as "no lyrics"; only a definitive answer is. The data model (`SyncType.lineSynced / .unsynced`, `lines[{startMs, text}]`, `provider`) is the common shape for synced lyrics, so another source can slot in behind it.

### Staying in sync

Measured causes of drift and what fixed them:

| Cause | Fix |
|---|---|
| Polled every 6 s while paused, so resuming left lyrics frozen up to 6 s | 1 s polling whenever a surface shows lyrics, paused or not |
| Drift under 500 ms was never corrected | Precision-weighted clock: each sample's track-start estimate is accurate to half its round trip; the most precise one of the last 20 s wins, so steady error stays within a few tens of ms |
| A slow response could pull the clock off | A sample only moves the clock if it is more precise, or if its uncertainty cannot explain the difference (then it is a seek, even a small one, and applies at once) |
| The old song's last line lingered after a track ended | Extra poll at the predicted end of the track |
| A poll already in flight undid a tap on pause or seek | After a command, polls that predate or contradict it are ignored for 1.5 s; the clock moves on the tap |
| Returning to the app showed stale state | Immediate poll when the app becomes active |
| Songs with more than 60 lines froze the widget on line 60 | Timelines hold 200 lines and ask for a fresh one after the last entry |
| A denied widget reload left the old song on the tile | Each timeline asks again 2 s after its track ends and reads the snapshot the app saved anyway |
| A token Spotify revoked early was reused until its local expiry | A 401 invalidates it, the next poll refreshes |
| A lyrics lookup that hit a dead network on wake showed "No lyrics" for the whole song | Retried after 2, 5 and 10 s while the track plays |
| Polling could hit Spotify's rate limit | 1 s only while a screen shows lyrics, 2 to 3 s in the background; a 429 pauses polling for `Retry-After` |
| A lyrics file timed for a different release | Per-track nudge on phone and CarPlay, remembered per track |

Home Screen widgets have one limit no code removes: WidgetKit grants roughly 40 to 70 background reloads per day. Widgets schedule every line themselves and only need a reload on a track change, pause or seek, so a normal day fits, but a long session with many skips can use up the budget. The Live Activity and CarPlay are not affected by it.

Widget buttons work even when Lyricar is not running: the command handler is registered in the app initializer, and the buttons are `AudioPlaybackIntent`s, so iOS always runs them in the app. In the Simulator, with the app terminated, a tap on Next reaches Spotify 0.3 to 0.8 s later (`WidgetControlTests`).

### Locked phone, Low Power Mode, CarPlay connection

iOS suspends a backgrounded app within seconds, which would freeze the Live Activity, the widgets' next song and CarPlay. Lyricar keeps itself running by playing digital silence with `.mixWithOthers`: Spotify keeps playing and keeps the Now Playing slot, nothing is audible, and Low Power Mode does not suspend background audio.

- The keep-alive starts while the app is in front, so it is already playing when the screen locks. It stays on while music plays and for 30 minutes after a pause, checked once a minute, so it does not drain the battery.
- It restarts after an audio route change (CarPlay, Bluetooth), an interruption (call, Siri, alarm) and a media services reset. A 10 s watchdog catches silent stops and retries failed starts.
- The Live Activity notices when iOS ends it (8 hour limit) or it is swiped away, and is requested again the next time the app is in front.
- In the background, the tick sleeps until the next line instead of running at 10 Hz.

App Review rejects silent-audio keep-alives. A store build would need ActivityKit push updates from a server instead. To check the behavior on a real phone:

```sh
./scripts/install-device.sh     # build, install, launch
# play music, open Lyricar, lock the phone, wait a few minutes, unlock
./scripts/pull-diagnostics.sh   # poll gaps while locked, plus every keep-alive event
```

## Tests

Unit tests for the shared logic (parser, clock, index lookup, widget timeline, Spotify decoding, LRCLIB fallback, sync precision, background recovery):

```sh
cd Packages/LyricsKit && swift test
```

UI tours drive the Simulator, including the CarPlay display, and attach screenshots to the result bundle (Simulator with I/O, External Displays, CarPlay switched on):

```sh
xcodebuild test -project Lyricar.xcodeproj -scheme Lyricar \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:LyricarUITests -resultBundlePath build/tour.xcresult
```

`WidgetTourTests` taps SpringBoard by its German labels ("Bearbeiten", "hinzufügen"); on an English Simulator adjust them. Widget and Live Activity button tests need a team-signed Simulator build: run `scripts/sign-simulator-build.sh` after `build-for-testing`, then `test-without-building`. CarPlay tests use the normal ad-hoc build.

Launch arguments for development:

- `-LyricarDemo`: a fake playback clock on "Midnight City" by M83 instead of Spotify. Lyrics still come from LRCLIB through the real engine.
- `-LyricarLiveActivity`: with `-LyricarDemo`, start the Live Activity at launch.
- `-LyricarRenderGallery`: render every style and widget size to PNG.
- `LYRICAR_HOST_TOKEN_FILE` (environment, Simulator Debug builds only): read a Spotify access token from a JSON file on the Mac (`{"access_token": "...", "expires_at": <epoch ms>}`) and skip the sign-in. Read-only; Lyricar never refreshes or writes it.

## Privacy

Lyricar talks to two services: the Spotify Web API (with your token, stored in the Keychain) and LRCLIB (track name, artist, album and duration, to find lyrics). There is no backend, no analytics and no account. The diagnostics log stays in the app's Documents folder until you pull it.

## FAQ

**Why is it not on the App Store?** Spotify's Development Mode caps an app at 5 users, extended access needs a registered business with a large user base, and App Review rejects the silent-audio keep-alive that keeps the lock-screen lyrics moving. Building it yourself avoids all three.

**Does it work with Apple Music?** Not yet. The engine takes any source that reports a track and a playback position; `MusicKit` support would be a welcome pull request.

**Some songs show no lyrics.** LRCLIB is community-run. If a song is missing or badly timed, you can [contribute it to LRCLIB](https://lrclib.net); the per-track nudge fixes small offsets in the meantime.

## Contributing

Issues and pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) first; the local loop is the quick start above plus `swift test`. Contributions are accepted under the Apache License 2.0.

If Lyricar is useful to you, a star helps other people find it.

## License

Lyricar is open source under the [Apache License 2.0](LICENSE). Use it, modify it, ship it, commercially or otherwise. Keep the notices, state what you changed, and note that the license comes with an express patent grant from every contributor.

Copyright 2026 Alperen Adatepe.

Spotify is a trademark of Spotify AB. Apple, iPhone and CarPlay are trademarks of Apple Inc. Lyricar is an independent project and is not affiliated with or endorsed by either. Lyrics are provided by LRCLIB and belong to their respective rights holders.
