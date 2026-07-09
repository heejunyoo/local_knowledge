#!/usr/bin/env bash
# Build .app + start daemon + open UI window (visible).
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

export KNOWLEDGE_ROOT="${KNOWLEDGE_ROOT:-$HOME/Knowledge}"
"$REPO/scripts/bootstrap-knowledge-root.sh" >/dev/null 2>&1 || true

echo "==> Build Knowledge.app"
"$REPO/scripts/package-app.sh" debug
APP="$REPO/.build/debug/Knowledge.app"
DAEMON="$REPO/.build/debug/knowledged"

# Stop stale UI only — daemon is app-managed; leave existing if healthy
killall Knowledge 2>/dev/null || true
killall KnowledgeApp 2>/dev/null || true
sleep 0.3

echo "==> Open UI (daemon auto-starts inside the app)"
open "$APP"
echo ""
echo "사용자는 CLI로 데몬을 켤 필요 없습니다."
echo "창이 안 보이면 Dock에서 Knowledge 를 클릭하세요."