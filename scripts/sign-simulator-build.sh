#!/bin/sh
# Re-signs the Simulator build with the development certificate, for testing widget
# and Live Activity buttons. Ad-hoc builds have no team ID, and the App Intents daemon
# (linkd) then refuses to run the app's intents ("Unable to get teamId").
#
# Only the App Group is kept. A team signature makes the Simulator enforce
# com.apple.developer.carplay-audio like a real iPhone (refused without a provisioning
# profile that grants it), so CarPlay tests must use the normal ad-hoc build instead.
set -eu
cd "$(dirname "$0")/.."
IDENTITY="${SIGN_IDENTITY:-Apple Development}"
APP=build/Build/Products/Debug-iphonesimulator/Lyricar.app
GROUP="$(/usr/libexec/PlistBuddy -c 'Print LyricarAppGroup' "$APP/Info.plist")"
TMP="$(mktemp -t lyricar-ent.XXXXXX)"
ENT="$TMP.plist"
trap 'rm -f "$TMP" "$ENT"' EXIT
cat > "$ENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>com.apple.security.application-groups</key><array><string>$GROUP</string></array>
</dict></plist>
PLIST
codesign --force --sign "$IDENTITY" --entitlements "$ENT" "$APP/PlugIns/LyricarWidgets.appex"
codesign --force --sign "$IDENTITY" --entitlements "$ENT" "$APP"
codesign -dvv "$APP" 2>&1 | grep TeamIdentifier
