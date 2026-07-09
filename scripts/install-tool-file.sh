#!/usr/bin/env bash
# Offline install: copy a local file into knowledge tools tree and print sha256.
# Usage: install-tool-file.sh <source> <relpath-under-knowledge-root>
set -euo pipefail
ROOT="${KNOWLEDGE_ROOT:-$HOME/Knowledge}"
SRC="${1:?source file}"
REL="${2:?relative dest e.g. tools/whisper.cpp/1.7.5/whisper-cli}"
DEST="$ROOT/$REL"
mkdir -p "$(dirname "$DEST")"
cp -f "$SRC" "$DEST"
if [[ "$REL" == *cli* || "$REL" == *whisper* || "$REL" == *llama* ]]; then
  chmod +x "$DEST" || true
fi
SHASUM=$(shasum -a 256 "$DEST" | awk '{print $1}')
echo "installed $DEST"
echo "sha256 $SHASUM"
echo "Update config/tools_manifest.json pin for this file, then re-run scripts/verify-tools.sh"
