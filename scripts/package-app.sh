#!/usr/bin/env bash
# Build Knowledge.app + install to ~/Applications for stable Screen Recording TCC.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

CONFIG="${1:-debug}"
if [[ "$CONFIG" == "release" ]]; then
  swift build -c release --product KnowledgeApp
  swift build -c release --product knowledged
  BIN="$REPO/.build/release"
else
  swift build --product KnowledgeApp
  swift build --product knowledged
  BIN="$REPO/.build/debug"
fi

BUNDLE_ID="local.knowledge.app"
APP_ROOT="$BIN/Knowledge.app"
CONTENTS="$APP_ROOT/Contents"
MACOS="$CONTENTS/MacOS"

rm -rf "$APP_ROOT"
mkdir -p "$MACOS" "$CONTENTS/Resources"

cp "$BIN/KnowledgeApp" "$MACOS/Knowledge"
cp "$BIN/knowledged" "$MACOS/knowledged"
cp "$REPO/Sources/KnowledgeApp/Info.plist" "$CONTENTS/Info.plist"
echo -n 'APPL????' > "$CONTENTS/PkgInfo"

# Stable ad-hoc identity (TCC keys off path + signature)
codesign --force --sign - --identifier "${BUNDLE_ID}.daemon" "$MACOS/knowledged" || true
codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP_ROOT"

# Fixed install location — rebuilds overwrite same path so Screen Recording grant sticks better
INSTALL_DIR="$HOME/Applications"
INSTALL_APP="$INSTALL_DIR/Knowledge.app"
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_APP"
cp -R "$APP_ROOT" "$INSTALL_APP"
codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$INSTALL_APP"

echo "Built:    $APP_ROOT"
echo "Installed:$INSTALL_APP"
echo "Bundle:   $BUNDLE_ID"
echo ""
echo "실행 (권장): open \"$INSTALL_APP\""
echo "화면 기록 설정에 「Knowledge」가 보이면 켜 주세요. 켠 뒤 앱을 완전히 종료하고 다시 실행하세요."
