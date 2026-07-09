#!/usr/bin/env bash
# Build a real macOS .app with stable bundle id for TCC (screen recording).
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

APP_ROOT="$BIN/Knowledge.app"
CONTENTS="$APP_ROOT/Contents"
MACOS="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"
BUNDLE_ID="local.knowledge.app"

rm -rf "$APP_ROOT"
mkdir -p "$MACOS" "$RES"

cp "$BIN/KnowledgeApp" "$MACOS/Knowledge"
cp "$BIN/knowledged" "$MACOS/knowledged"
cp "$REPO/Sources/KnowledgeApp/Info.plist" "$CONTENTS/Info.plist"
echo -n 'APPL????' > "$CONTENTS/PkgInfo"

# Ad-hoc sign with **stable** identifier so Screen Recording TCC sticks across rebuilds.
# (Unsigned / random SPM ids force re-grant every build.)
codesign --force --deep --sign - \
  --identifier "$BUNDLE_ID" \
  --entitlements /dev/null \
  "$MACOS/knowledged" 2>/dev/null || codesign --force --sign - --identifier "${BUNDLE_ID}.daemon" "$MACOS/knowledged"

codesign --force --deep --sign - \
  --identifier "$BUNDLE_ID" \
  "$APP_ROOT"

echo "Built: $APP_ROOT"
echo "Bundle id: $BUNDLE_ID (use this in 시스템 설정 → 화면 기록)"
echo "Open with: open \"$APP_ROOT\""
echo ""
echo "Note: Terminal로 직접 실행하면 Terminal 앱 권한을 빌려 쓰는 것일 수 있어요."
echo "     제품 경로는 Knowledge.app + 화면 기록 허용입니다."
