#!/usr/bin/env bash
# Build a real macOS .app so windows + mic TCC + menu bar work.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

CONFIG="${1:-debug}"
# Note: multiple --product flags are unreliable; build each product explicitly.
if [[ "$CONFIG" == "release" ]]; then
  swift build -c release --product KnowledgeApp
  swift build -c release --product knowledged
  BIN="$REPO/.build/release"
else
  swift build --product KnowledgeApp
  swift build --product knowledged
  BIN="$REPO/.build/debug"
fi

APP_ROOT="$BIN/Knowledge.app"
CONTENTS="$APP_ROOT/Contents"
MACOS="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"

rm -rf "$APP_ROOT"
mkdir -p "$MACOS" "$RES"

cp "$BIN/KnowledgeApp" "$MACOS/Knowledge"
cp "$REPO/Sources/KnowledgeApp/Info.plist" "$CONTENTS/Info.plist"
# Agent binary alongside app for convenience (optional)
cp "$BIN/knowledged" "$MACOS/knowledged"

# PkgInfo
echo -n 'APPL????' > "$CONTENTS/PkgInfo"

echo "Built: $APP_ROOT"
echo "Open with: open \"$APP_ROOT\""
