#!/usr/bin/env bash
# Install Knowledge.app using a *real* local codesign identity (not ad-hoc `-`).
# Ad-hoc re-sign changes CDHash every build → System Settings stays ON but runtime TCC denies.
# Apple Development / local cert designated requirements survive rebuilds (no admin).
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

swift build --product KnowledgeApp
swift build --product knowledged
swift build --product KnowledgeAudioHelper

BIN="$REPO/.build/debug"
BUNDLE_ID="local.knowledge.app"
HELPER_ID="local.knowledge.audiohelper"
DAEMON_ID="local.knowledge.app.daemon"
STAMP_DIR="$HOME/Applications/.knowledge-build"
mkdir -p "$STAMP_DIR"

# Prefer Apple Development / any non-ad-hoc codesigning identity in the login keychain.
resolve_identity() {
  if [[ -n "${KNOWLEDGE_CODESIGN_IDENTITY:-}" ]]; then
    echo "$KNOWLEDGE_CODESIGN_IDENTITY"
    return
  fi
  local line id
  line=$(security find-identity -v -p codesigning 2>/dev/null | grep -E 'Apple Development|Developer ID Application|Mac Developer' | head -1 || true)
  if [[ -z "$line" ]]; then
    line=$(security find-identity -v -p codesigning 2>/dev/null | grep -v '0 valid' | grep '"' | head -1 || true)
  fi
  if [[ -z "$line" ]]; then
    echo "ERROR: no codesigning identity in login keychain." >&2
    echo "Other machines work because they sign with a local/dev cert, not ad-hoc (-)." >&2
    echo "Xcode → Settings → Accounts → Manage Certificates → + Apple Development" >&2
    exit 1
  fi
  echo "$line" | sed -E 's/.*"([^"]+)".*/\1/'
}

IDENTITY="$(resolve_identity)"
echo "Codesign identity: $IDENTITY"

sign_bin() {
  local path="$1" ident="$2"
  codesign --force --sign "$IDENTITY" --identifier "$ident" --timestamp=none "$path"
}

APP_ROOT="$BIN/Knowledge.app"
MACOS="$APP_ROOT/Contents/MacOS"
rm -rf "$APP_ROOT"
mkdir -p "$MACOS" "$APP_ROOT/Contents/Resources"
cp "$BIN/KnowledgeApp" "$MACOS/Knowledge"
cp "$BIN/knowledged" "$MACOS/knowledged"
cp "$BIN/KnowledgeAudioHelper" "$MACOS/KnowledgeAudioHelper"
cp "$REPO/Sources/KnowledgeApp/Info.plist" "$APP_ROOT/Contents/Info.plist"
if [[ -f "$REPO/Resources/AppIcon.icns" ]]; then
  cp "$REPO/Resources/AppIcon.icns" "$APP_ROOT/Contents/Resources/AppIcon.icns"
fi
echo -n 'APPL????' > "$APP_ROOT/Contents/PkgInfo"
chmod +x "$MACOS/Knowledge" "$MACOS/knowledged" "$MACOS/KnowledgeAudioHelper"

# Nested executables first, then bundle (no --deep ad-hoc).
sign_bin "$MACOS/KnowledgeAudioHelper" "$HELPER_ID"
sign_bin "$MACOS/knowledged" "$DAEMON_ID"
sign_bin "$MACOS/Knowledge" "$BUNDLE_ID"
codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" --timestamp=none "$APP_ROOT"

# Keep a copy of the signed helper for reference (TCC now follows cert+identifier, not frozen ad-hoc CDHash).
cp "$MACOS/KnowledgeAudioHelper" "$STAMP_DIR/KnowledgeAudioHelper"
shasum -a 256 "$MACOS/KnowledgeAudioHelper" | awk '{print $1}' > "$STAMP_DIR/KnowledgeAudioHelper.sha256"
echo "$IDENTITY" > "$STAMP_DIR/codesign-identity.txt"

INSTALL="$HOME/Applications/Knowledge.app"
mkdir -p "$HOME/Applications"
rm -rf "$INSTALL"
cp -R "$APP_ROOT" "$INSTALL"
# Re-sign after copy (quarantine/copy can break seal on some systems)
sign_bin "$INSTALL/Contents/MacOS/KnowledgeAudioHelper" "$HELPER_ID"
sign_bin "$INSTALL/Contents/MacOS/knowledged" "$DAEMON_ID"
sign_bin "$INSTALL/Contents/MacOS/Knowledge" "$BUNDLE_ID"
codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" --timestamp=none "$INSTALL"

echo "Installed: $INSTALL"
echo "Identity:  $IDENTITY"
echo "Main DR:   $(codesign -d -r- "$INSTALL" 2>&1 | tail -1)"
echo "Run: open \"$INSTALL\""
codesign -dv "$INSTALL" 2>&1 | head -12
