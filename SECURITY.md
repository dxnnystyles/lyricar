# Security policy

## Reporting a vulnerability

Do not open a public issue.

Report it privately through GitHub:

**[Report a vulnerability](https://github.com/noluyorAbi/lyricar/security/advisories/new)**

That form is private between you and the maintainer. It creates a draft
security advisory where the fix can be discussed, and where you are credited by
name when it is published, unless you ask not to be.

### What to include

The more of this you can supply, the faster it gets fixed:

- what an attacker can do, in one sentence
- the affected version or commit, and whether the current `main` is affected
- a reproduction: exact steps, or a proof of concept
- the environment: iOS version, device or Simulator, and whether CarPlay,
  widgets or the Live Activity are involved
- any mitigation you have found

### What happens next

| Step | Commitment |
|------|------------|
| Acknowledgement that a human has read it | within 7 days |
| An assessment: confirmed, not a vulnerability, or more information needed | within 7 days of acknowledgement |
| Progress updates while a fix is in flight | at least every 14 days |
| Fix released, advisory published | as soon as a fix exists and is tested |

Lyricar is maintained by one person. If you have heard nothing after 7 days,
assume the message was missed rather than ignored, and send a reminder on the
same advisory.

### Disclosure

Coordinated disclosure, please. Give a fix a reasonable window before going
public: 90 days is the usual expectation, shorter if the issue is already being
exploited, and negotiable if a fix is genuinely hard. When the fix ships, the
advisory is published with credit to you.

There is no bug bounty. This is an independent project with no security budget.

## Supported versions

Security fixes land on the latest release line and on `main`.

| Version | Supported |
|---------|-----------|
| 0.1.x | Yes |
| < 0.1.0 | No |

Only the latest release in a supported line receives fixes. A fix is not
backported to an earlier patch release of the same line.

## Scope

In scope, and worth reporting:

- leaking or mishandling the Spotify access token or refresh token, for example
  storing it outside the Keychain, logging it, or sending it anywhere other
  than Spotify
- weaknesses in the Spotify sign-in flow: the local redirect listener, the
  `lyricar://` URL scheme callback, or the OAuth state and PKCE handling
- Lyricar sending data to LRCLIB or any other service beyond what a lyrics
  lookup needs (LRCLIB receives the track title, artist, album and duration,
  nothing else)
- data shared through the App Group with the widget extension being readable
  or writable by something that should not have access
- crashes or code paths that untrusted input can trigger, such as a crafted
  lyrics file from LRCLIB or a crafted URL opened through the `lyricar://`
  scheme

Out of scope:

- vulnerabilities in Spotify, LRCLIB, iOS or CarPlay themselves; report those
  to their owners
- findings from an automated scanner with no demonstrated impact
- anything that requires an attacker who already has full control of the
  unlocked device
- social engineering of the maintainer or of users
- the content of lyrics served by LRCLIB

If you are not sure which side of the line a finding sits on, report it. Being
told it is out of scope costs you one message.
