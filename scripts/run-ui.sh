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

# Stop stale processes from earlier swift run
pkill -f '/KnowledgeApp$' 2>/dev/null || true
pkill -f 'Knowledge\.app/Contents/MacOS/Knowledge' 2>/dev/null || true
# Only kill our knowledged (path contains IdeaProjects or .build)
pkill -f '\.build/.*/knowledged' 2>/dev/null || true
sleep 0.3

if [[ "${WITH_DAEMON:-1}" == "1" ]]; then
  echo "==> Start knowledged → $KNOWLEDGE_ROOT"
  "$DAEMON" --root "$KNOWLEDGE_ROOT" >>"$KNOWLEDGE_ROOT/logs/knowledged.stdout.log" 2>&1 &
  echo $! >"$KNOWLEDGE_ROOT/cache/knowledged.pid"
  sleep 0.4
  if [[ -S "$KNOWLEDGE_ROOT/cache/daemon.sock" ]]; then
    echo "    daemon sock OK"
  else
    echo "    warn: daemon.sock not ready yet (check $KNOWLEDGE_ROOT/logs/knowledged.stdout.log)"
  fi
fi

echo "==> Open UI window"
open "$APP"
echo ""
echo "창이 안 보이면: Dock에서 Knowledge 클릭, 또는 메뉴바 🧠 아이콘 확인"
echo "종료: pkill -f Knowledge.app ; pkill -f '\.build/.*/knowledged'"
