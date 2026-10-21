# Contributing to Lyricar

Thanks for being here. Issues, bug reports and pull requests are all welcome.

One thing to know before you invest time: **scope is defended.** A well argued
no is a normal outcome. Open an issue before building anything substantial, so
nobody spends a weekend on a patch that will not be merged.

## Ways to help that are not code

- File a good bug report. A reproduction is worth more than a patch nobody can
  verify. Name the iOS version, the device, whether you have Spotify Premium,
  and whether CarPlay was involved; the bug report form asks for all of it.
- Improve the documentation. If something confused you, it confuses everyone
  else too, and you are the last person who will remember exactly how.
- Tell us what you tried to do and could not. Missing features are easier to
  see from outside.

## Requirements

- A Mac with Xcode 26 (the app targets iOS 26).
- [Homebrew](https://brew.sh), to install XcodeGen.
- For running on a device: an Apple developer team (a free Personal Team
  works, without CarPlay on the device) and a Spotify app registration of
  your own, for the client ID.

## Getting set up

```bash
git clone https://github.com/noluyorAbi/lyricar
cd lyricar
brew install xcodegen
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

Open `Config/Local.xcconfig` and fill in your own values:

| Setting | What it is |
|---------|------------|
| `LYRICAR_BUNDLE_PREFIX` | A reverse domain prefix you control, for the bundle identifiers and the App Group |
| `DEVELOPMENT_TEAM` | Your Apple developer team ID |
| `SPOTIFY_CLIENT_ID` | The client ID of your app in the Spotify developer dashboard |

For Simulator builds the team can stay empty. In the Spotify developer
dashboard, register `http://127.0.0.1:3000/spotify/callback` as the redirect
URI of your app.

Or run `scripts/setup.sh`, which asks for the same values, writes the file and
generates the project for you (`scripts/setup.sh --help` lists its flags).

`Config/Local.xcconfig` holds your personal team and client ID. Never commit
it.

Then generate the Xcode project and open it:

```bash
xcodegen generate
open Lyricar.xcodeproj
```

The project file is generated from `project.yml` and is not committed. Change
`project.yml`, not the generated project, and run `xcodegen generate` again
after every change to it.

## Running the tests

The unit tests for the shared logic (parser, clock, index lookup, widget
timeline, Spotify decoding, LRCLIB fallback) live in the LyricsKit package and
run on macOS without a Simulator:

```bash
cd Packages/LyricsKit
swift test
```

The app build, the same way CI runs it:

```bash
xcodebuild -project Lyricar.xcodeproj -scheme Lyricar \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

The UI tours drive CarPlay, the widgets and the Live Activity in the Simulator
and attach screenshots to the result bundle. They need a Simulator with I/O,
External Displays and CarPlay switched on, and they are not part of CI:

```bash
xcodebuild test -project Lyricar.xcodeproj -scheme Lyricar \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:LyricarUITests -resultBundlePath build/tour.xcresult
```

The widget and Live Activity button tests need a team-signed Simulator build;
see the README for `scripts/sign-simulator-build.sh`.

CI runs `swift test` and the Simulator build on every push and pull request to
`main`. Run both before you open a pull request. A pull request that fails CI
on the first push is not a problem, but it does cost a round trip.

## Code style

- **Match the surrounding code.** There is no formatter or linter in this
  repository; consistency with the file you are editing is the rule. Swift is
  indented with four spaces, see `.editorconfig`.
- **English only** in code, comments, commit messages and pull requests.
- **No new dependency** without discussing it in an issue first. LyricsKit has
  no external packages, and that is on purpose.
- **Keep the diff to one subject.** Unrelated cleanups belong in their own pull
  request, however tempting it is to fix them while passing.
- **No emoji, no em dashes and no en dashes** in code, comments or
  documentation. Use a comma, a semicolon, a colon, a period or parentheses.

## Commit messages

Short imperative subject, under about 72 characters, no trailing period:

```
fix the Live Activity freezing after a route change
add an Up Next widget for the Lock Screen
```

A body is optional. When you write one, explain why, not what; the diff already
says what.

## Pull requests

- Branch off `main` and target it.
- Fill in the pull request template. The verification section is the part that
  gets read first.
- If the change is visible, include a screenshot or a short recording. For
  CarPlay, the Simulator's CarPlay window is enough.
- Add a `CHANGELOG.md` entry under `Unreleased` whenever a user would notice
  the change.
- Expect review comments. They are about the code.

## License of contributions

Lyricar is licensed under the [Apache License, Version 2.0](LICENSE). By
submitting a contribution, you agree that it is licensed under the same
license (inbound equals outbound, as Section 5 of the license describes).
There is no contributor license agreement to sign.

A [Developer Certificate of Origin](https://developercertificate.org/) sign-off
is welcome but optional:

```bash
git commit -s -m "your message"
```

Only submit work you wrote yourself or otherwise have the right to submit. If
your employer owns what you write, get their permission first.

## Questions

Open a [discussion](https://github.com/noluyorAbi/lyricar/discussions) or an
issue. For a security problem, do not open an issue; follow
[SECURITY.md](SECURITY.md) instead.
