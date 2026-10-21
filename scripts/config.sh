# shellcheck shell=sh
# Shared helpers for the scripts in this folder. Source it after `cd` to the repo root.
#
#   lyricar_setting NAME        prints the effective value of an xcconfig setting, read the way
#                               Config/Base.xcconfig resolves it: Base, then Secrets, then Local.
#   lyricar_set NAME VALUE      writes NAME = VALUE into Config/Local.xcconfig (mode 0600),
#                               replacing an existing line for NAME.

LYRICAR_LOCAL=Config/Local.xcconfig

lyricar_setting() {
  for file in Config/Base.xcconfig Config/Secrets.xcconfig "$LYRICAR_LOCAL"; do
    [ -f "$file" ] && sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$file"
  done | tail -1 | sed 's/[[:space:]]*$//'
}

lyricar_set() (
  umask 077
  [ -f "$LYRICAR_LOCAL" ] || printf '// Local settings, gitignored. See Config/Local.xcconfig.example.\n' > "$LYRICAR_LOCAL"
  tmp="$LYRICAR_LOCAL.tmp"
  awk -v name="$1" -v value="$2" '
    $0 ~ "^[[:space:]]*" name "[[:space:]]*=" { if (!done) print name " = " value; done = 1; next }
    { print }
    END { if (!done) print name " = " value }
  ' "$LYRICAR_LOCAL" > "$tmp"
  mv "$tmp" "$LYRICAR_LOCAL"
  chmod 600 "$LYRICAR_LOCAL"
)

# First Xcode team ID: paid teams first, then free Personal Teams unless $1 is "paid".
lyricar_xcode_team() {
  defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier 2>/dev/null | python3 -c '
import re, sys
blocks = re.findall(r"\{[^{}]*\}", sys.stdin.read())
order = ["0"] if sys.argv[1] == "paid" else ["0", "1"]
for flag in order:
    for block in blocks:
        match = re.search(r"teamID = (\w+);", block)
        if match and "isFreeProvisioningTeam = " + flag in block:
            print(match.group(1))
            sys.exit(0)
' "${1:-any}"
}

# First connected, available iPhone (devicectl identifier).
lyricar_device() {
  xcrun devicectl list devices 2>/dev/null | awk '/available/ && !/unavailable/ && /iPhone/ {for (i=1;i<=NF;i++) if ($i ~ /^[0-9A-F-]{36}$/) {print $i; exit}}'
}
