#!/bin/sh
# Writes Config/Local.xcconfig (gitignored, mode 0600) with your signing identity and
# Spotify client ID, then regenerates Lyricar.xcodeproj.
#
#   scripts/setup.sh [--team TEAM_ID] [--prefix com.yourname] [--client-id ID] [--no-generate]
#
# Every value can also come from the environment (DEVELOPMENT_TEAM, LYRICAR_BUNDLE_PREFIX,
# SPOTIFY_CLIENT_ID) or from SPOTIFY_ENV_FILE, a dotenv file with a SPOTIFY_CLIENT_ID= line.
# Missing values are asked for when run in a terminal; existing settings are the defaults.
# Without --team the first team Xcode knows is used (Settings, Accounts), paid before free.
set -eu
cd "$(dirname "$0")/.."
. scripts/config.sh

TEAM="${DEVELOPMENT_TEAM:-}"
PREFIX="${LYRICAR_BUNDLE_PREFIX:-}"
CLIENT_ID="${SPOTIFY_CLIENT_ID:-}"
GENERATE=1
while [ $# -gt 0 ]; do
  case "$1" in
    --team) TEAM="${2:?--team needs a value}"; shift 2 ;;
    --prefix) PREFIX="${2:?--prefix needs a value}"; shift 2 ;;
    --client-id) CLIENT_ID="${2:?--client-id needs a value}"; shift 2 ;;
    --no-generate) GENERATE=0; shift ;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument $1" >&2; exit 2 ;;
  esac
done

if [ -z "$CLIENT_ID" ] && [ -n "${SPOTIFY_ENV_FILE:-}" ]; then
  CLIENT_ID="$(grep '^SPOTIFY_CLIENT_ID=' "$SPOTIFY_ENV_FILE" | cut -d= -f2- | tr -d '"' | tr -d "'")"
fi
[ -n "$TEAM" ] || TEAM="$(lyricar_setting DEVELOPMENT_TEAM)"
[ -n "$TEAM" ] || TEAM="$(lyricar_xcode_team)"
CURRENT_PREFIX="$(lyricar_setting LYRICAR_BUNDLE_PREFIX)"
[ -n "$CLIENT_ID" ] || CLIENT_ID="$(lyricar_setting SPOTIFY_CLIENT_ID)"

ask() { # ask VAR "Prompt" default
  if [ -t 0 ]; then
    printf '%s [%s]: ' "$2" "$3" >&2
    read -r answer || answer=""
    eval "$1=\"\${answer:-\$3}\""
  else
    eval "$1=\"\$3\""
  fi
}
if [ -z "$PREFIX" ]; then
  ask PREFIX "Bundle ID prefix (reverse DNS you control)" "${CURRENT_PREFIX:-com.example}"
fi
if [ -z "$CLIENT_ID" ] && [ -t 0 ]; then
  ask CLIENT_ID "Spotify client ID (developer.spotify.com dashboard)" ""
fi

case "$PREFIX" in
  *[!A-Za-z0-9.-]*|.*|*.) echo "Invalid bundle ID prefix: $PREFIX" >&2; exit 2 ;;
esac

lyricar_set DEVELOPMENT_TEAM "$TEAM"
lyricar_set LYRICAR_BUNDLE_PREFIX "$PREFIX"
lyricar_set SPOTIFY_CLIENT_ID "$CLIENT_ID"
echo "Wrote $LYRICAR_LOCAL: team ${TEAM:-<none, Simulator only>}, bundle ID $PREFIX.lyricar"
if [ -n "$CLIENT_ID" ]; then
  echo "Spotify client ID: set"
else
  echo "Spotify client ID: missing. The app builds but cannot sign in until you add it." >&2
fi

if [ "$GENERATE" = 1 ]; then
  command -v xcodegen >/dev/null || { echo "xcodegen not found: brew install xcodegen" >&2; exit 1; }
  xcodegen generate >/dev/null
  echo "Generated Lyricar.xcodeproj"
fi
