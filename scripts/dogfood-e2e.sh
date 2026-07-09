#!/usr/bin/env bash
# Real dogfood: reindex vectors + synthetic meeting → review → vault → retrieve/RAG
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${KNOWLEDGE_ROOT:-$HOME/Knowledge}"
cd "$REPO"
echo "== build knowledge-dogfood =="
swift build --product knowledge-dogfood 2>&1 | tail -5
BIN="$REPO/.build/debug/knowledge-dogfood"
if [[ ! -x "$BIN" ]]; then
  # SPM may put it in arm64 triple path
  BIN=$(find "$REPO/.build" -name knowledge-dogfood -type f -perm +111 2>/dev/null | head -1)
fi
[[ -x "$BIN" ]] || { echo "FAIL: knowledge-dogfood binary missing"; exit 1; }
echo "run $BIN --root $ROOT"
"$BIN" --root "$ROOT" --reindex --pipeline --commit
echo "== package app (so UI matches dogfood engine) =="
bash "$REPO/scripts/package-app.sh" 2>&1 | tail -8
echo "== dogfood-e2e done =="
