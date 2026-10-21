#!/bin/sh
# Copies Lyricar's on-device diagnostics log from a connected iPhone and summarizes it:
# poll gaps while the phone was locked or in Low Power Mode show whether sync held.
# Usage: scripts/pull-diagnostics.sh [device-identifier]
# Without an argument it picks the first connected (available) iPhone. The bundle ID comes
# from LYRICAR_BUNDLE_PREFIX in Config/Local.xcconfig; LYRICAR_BUNDLE_ID overrides it.
set -eu
cd "$(dirname "$0")/.."
. scripts/config.sh
DEVICE="${1:-$(lyricar_device)}"
[ -n "$DEVICE" ] || { echo "No connected iPhone. Pass a device identifier (xcrun devicectl list devices)." >&2; exit 1; }
BUNDLE_ID="${LYRICAR_BUNDLE_ID:-$(lyricar_setting LYRICAR_BUNDLE_PREFIX).lyricar}"
OUT="${TMPDIR:-/tmp}/lyricar-diagnostics.log"
OLD="${TMPDIR:-/tmp}/lyricar-diagnostics.old.log"
pull() {
  xcrun devicectl device copy from --device "$DEVICE" --domain-type appDataContainer \
    --domain-identifier "$BUNDLE_ID" --source "Documents/$1" --destination "$2" >/dev/null
}
# The app rotates the log at 512 KB; the older half may not exist yet.
: > "$OLD"
pull diagnostics.old.log "$OLD" 2>/dev/null || true
pull diagnostics.log "$OUT.new"
cat "$OLD" "$OUT.new" > "$OUT" && rm -f "$OUT.new"
echo "lines: $(wc -l < "$OUT")"
for cond in "lowPower=true" "protectedData=locked" "app=background"; do
  echo "$cond: $(grep -c "$cond" "$OUT") polls"
done
# Largest gap between consecutive polls (seconds), overall and while locked.
python3 - "$OUT" <<'PY'
import sys, datetime
rows=[l.split(" ") for l in open(sys.argv[1]) if " poll " in l]
def t(r): return datetime.datetime.fromisoformat(r[0].replace("Z","+00:00"))
gaps=[(t(b)-t(a)).total_seconds() for a,b in zip(rows,rows[1:])]
locked=[(t(b)-t(a)).total_seconds() for a,b in zip(rows,rows[1:]) if "protectedData=locked" in " ".join(b)]
lp=[(t(b)-t(a)).total_seconds() for a,b in zip(rows,rows[1:]) if "lowPower=true" in " ".join(b)]
print(f"max gap overall: {max(gaps, default=0):.1f}s, while locked: {max(locked, default=0):.1f}s, in Low Power Mode: {max(lp, default=0):.1f}s")
PY
echo "keep-alive and lifecycle events (last 25):"
grep -E "KEEPALIVE|APP " "$OUT" | tail -25
tail -5 "$OUT"
