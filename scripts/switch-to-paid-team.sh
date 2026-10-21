#!/bin/sh
# Moves Lyricar from the free Personal Team to the paid Apple Developer Program team.
#
#   scripts/switch-to-paid-team.sh [TEAM_ID] [--carplay] [--dry-run]
#
# TEAM_ID       Paid team ID. Omitted: taken from Xcode (first team that is not a free
#               Personal Team). Xcode must have refreshed the account (Settings, Accounts).
# --carplay     Also sign device builds with com.apple.developer.carplay-audio. Only after
#               Apple approved the CarPlay request; without the grant, signing fails.
# --dry-run     Show what would change, change nothing.
#
# Both settings land in the gitignored Config/Local.xcconfig (DEVELOPMENT_TEAM and
# LYRICAR_DEVICE_ENTITLEMENTS); project.yml stays untouched.
# Afterwards: scripts/install-device.sh builds with the new team and installs.
set -eu
cd "$(dirname "$0")/.."
. scripts/config.sh

TEAM=""
CARPLAY=0
DRY=0
for arg in "$@"; do
  case "$arg" in
    --carplay) CARPLAY=1 ;;
    --dry-run) DRY=1 ;;
    -*) echo "unknown option $arg" >&2; exit 2 ;;
    *) TEAM="$arg" ;;
  esac
done

if [ -z "$TEAM" ]; then
  TEAM="$(lyricar_xcode_team paid)"
fi
if [ -z "$TEAM" ]; then
  echo "No paid team found in Xcode yet. Open Xcode, Settings, Accounts, select the Apple ID," >&2
  echo "click Download Manual Profiles (or re-add the account), then run this again." >&2
  exit 1
fi
# An Individual enrollment usually converts the Personal Team in place: the team ID
# stays the same and only isFreeProvisioningTeam flips to 0. So refuse a team by
# its free flag, never by its ID.
if defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier 2>/dev/null | python3 -c '
import re, sys
team = "teamID = " + sys.argv[1] + ";"
blocks = [b for b in re.findall(r"\{[^{}]*\}", sys.stdin.read()) if team in b]
free = any("isFreeProvisioningTeam = 1" in b for b in blocks)
paid = any("isFreeProvisioningTeam = 0" in b for b in blocks)
sys.exit(0 if free and not paid else 1)
' "$TEAM"; then
  echo "$TEAM is still a free Personal Team in Xcode. Refresh Settings, Accounts after the" >&2
  echo "enrollment email, then run this again." >&2
  exit 1
fi
echo "Paid team: $TEAM"

CURRENT="$(lyricar_setting DEVELOPMENT_TEAM)"
echo "$LYRICAR_LOCAL DEVELOPMENT_TEAM: ${CURRENT:-<none>} -> $TEAM"
if [ "$CARPLAY" = 1 ]; then
  echo "$LYRICAR_LOCAL LYRICAR_DEVICE_ENTITLEMENTS: $(lyricar_setting LYRICAR_DEVICE_ENTITLEMENTS) -> Lyricar/Lyricar.entitlements (adds carplay-audio)"
fi
[ "$DRY" = 1 ] && { echo "Dry run: nothing changed."; exit 0; }

lyricar_set DEVELOPMENT_TEAM "$TEAM"
if [ "$CARPLAY" = 1 ]; then
  lyricar_set LYRICAR_DEVICE_ENTITLEMENTS Lyricar/Lyricar.entitlements
fi
xcodegen generate >/dev/null
mkdir -p build

# Signing check before anything is installed: a refused App ID or a missing CarPlay grant
# shows up here, not on the phone.
if xcodebuild -project Lyricar.xcodeproj -scheme Lyricar -configuration Debug \
     -destination 'generic/platform=iOS' -derivedDataPath build -allowProvisioningUpdates build \
     > build/switch-team.log 2>&1; then
  echo "Device build signed with $TEAM."
  codesign -d --entitlements - --xml build/Build/Products/Debug-iphoneos/Lyricar.app 2>/dev/null | plutil -p - | grep -E "team-identifier|carplay|application-groups" || true
else
  echo "Build or signing failed; see build/switch-team.log:" >&2
  grep -E "error:" build/switch-team.log | sort -u | head -8 >&2
  echo "If it says the App ID or App Group 'is not available', the IDs are still held by the" >&2
  echo "Personal Team: delete the app from the phone, wait for the free profile to expire, or" >&2
  echo "pick another LYRICAR_BUNDLE_PREFIX in $LYRICAR_LOCAL." >&2
  exit 1
fi
