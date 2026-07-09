#!/usr/bin/env bash
# User-level LaunchAgent for knowledged (no admin). Automation phase L3.
set -euo pipefail
ROOT="${KNOWLEDGE_ROOT:-$HOME/Knowledge}"
APP="${HOME}/Applications/Knowledge.app"
BIN="$APP/Contents/MacOS/knowledged"
LABEL="local.knowledge.knowledged"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"

if [[ ! -x "$BIN" ]]; then
  echo "FAIL: $BIN missing — run scripts/package-app.sh first" >&2
  exit 1
fi

mkdir -p "$HOME/Library/LaunchAgents" "$ROOT/logs"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${BIN}</string>
    <string>--root</string>
    <string>${ROOT}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${ROOT}/logs/knowledged.launchd.out.log</string>
  <key>StandardErrorPath</key>
  <string>${ROOT}/logs/knowledged.launchd.err.log</string>
  <key>WorkingDirectory</key>
  <string>${ROOT}</string>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl enable "gui/$(id -u)/${LABEL}" 2>/dev/null || true
echo "OK  LaunchAgent installed: $PLIST"
echo "    Binary: $BIN"
echo "    Uninstall: launchctl bootout gui/\$(id -u)/${LABEL} && rm $PLIST"
