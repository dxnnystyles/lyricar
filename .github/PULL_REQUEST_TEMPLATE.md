<!--
  These comments are invisible in the rendered pull request, so they can stay.
-->

## What this changes

<!-- One paragraph, in plain language. What is different after this is merged? -->

## Why

<!--
  The problem, not the patch. Link the issue if there is one:
  "Closes #123" closes it automatically when this merges.
-->

Closes #

## How it was verified

<!--
  What you actually ran, and what it showed. "Tests pass" is not verification;
  "swift test, 25 passing, plus I played three songs on a device and watched
  the Live Activity follow" is.
-->

- [ ] `cd Packages/LyricsKit && swift test` passes
- [ ] The app builds for the Simulator (`xcodegen generate`, then the
      `xcodebuild ... build` command from CONTRIBUTING.md)
- [ ] I exercised the change by hand, on a device or in the Simulator,
      described above
- [ ] If the change touches CarPlay, widgets or the Live Activity, I checked
      that surface too (UI tours in `LyricarUITests` where they apply)

## Type of change

- [ ] Bug fix, no behaviour change beyond the fix
- [ ] New feature, additive
- [ ] Breaking change, an existing default or name changes
- [ ] Documentation only
- [ ] Repository plumbing (CI, templates, tooling)

## Checklist

- [ ] The pull request targets `main`
- [ ] The diff is limited to the stated change; unrelated cleanups are in their
      own pull request
- [ ] Documentation is updated where behaviour changed, including the README
- [ ] `CHANGELOG.md` has an entry under `Unreleased` if a user would notice
      this change
- [ ] No secret, Spotify client ID, team ID, token, absolute personal path or
      private data in the diff (`Config/Local.xcconfig` stays uncommitted)

## License

By opening this pull request I agree that my contribution is licensed under
the Apache License, Version 2.0, the same license as the project
(see Section 5 of [LICENSE](../LICENSE)).

- [ ] This is my own work, and I have the right to submit it. If my employer
      owns my work, I have their permission

<!--
  Anything you are unsure about, say so here rather than leaving it for review
  to discover. A question in the description is cheaper than a wrong guess in
  the diff.
-->
