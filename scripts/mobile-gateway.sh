#!/usr/bin/env bash
# Start knowledged with mobile HTTP gateway + emit pairing code.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${KNOWLEDGE_ROOT:-$HOME/Knowledge}"
PORT="${KNOWLEDGE_HTTP_PORT:-8741}"
cd "$REPO"
swift build --product knowledged 2>&1 | tail -3
BIN="$REPO/.build/debug/knowledged"
[[ -x "$BIN" ]] || BIN=$(find "$REPO/.build" -name knowledged -type f | head -1)
echo "Tip: Tailscale IP → Settings on iPhone. Port $PORT"
echo "Starting: $BIN --root $ROOT --http-port $PORT --pair"
exec "$BIN" --root "$ROOT" --http-port "$PORT" --pair
