#!/usr/bin/env bash
# Build & run menu bar app + optional daemon.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

echo "Building…"
swift build --product KnowledgeApp --product knowledged

BIN="$REPO/.build/debug"
export KNOWLEDGE_ROOT="${KNOWLEDGE_ROOT:-$HOME/Knowledge}"

if [[ "${WITH_DAEMON:-1}" == "1" ]]; then
  if ! pgrep -f "knowledged" >/dev/null 2>&1; then
    echo "Starting knowledged…"
    "$BIN/knowledged" --root "$KNOWLEDGE_ROOT" &
    sleep 0.5
  fi
fi

echo "Launching KnowledgeApp (Toss-inspired menu bar)…"
exec "$BIN/KnowledgeApp"
