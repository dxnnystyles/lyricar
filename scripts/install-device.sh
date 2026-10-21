#!/bin/sh
# Builds Lyricar for a connected iPhone and installs it with devicectl.
# Usage: scripts/install-device.sh [device-identifier]
# Without an argument it picks the first connected (available) iPhone.
set -eu
cd "$(dirname "$0")/.."
. scripts/config.sh
[ -f Config/Local.xcconfig ] || [ -f Config/Secrets.xcconfig ] || ./scripts/setup.sh
DEVICE="${1:-$(lyricar_device)}"
[ -n "$DEVICE" ] || { echo "No connected iPhone. Plug it in, unlock it, trust this Mac, enable Developer Mode." >&2; exit 1; }
xcodegen generate >/dev/null
mkdir -p build
xcodebuild -project Lyricar.xcodeproj -scheme Lyricar -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath build -allowProvisioningUpdates build \
  > build/install-device.log 2>&1 || { grep -E "error:" build/install-device.log | sort -u | head -8 >&2; exit 1; }
echo "Build succeeded."
APP=build/Build/Products/Debug-iphoneos/Lyricar.app
xcrun devicectl device install app --device "$DEVICE" "$APP"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Info.plist")"
xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE_ID" || \
  echo "Installed. First launch: Settings > General > VPN & Device Management > trust the developer, then open Lyricar."
