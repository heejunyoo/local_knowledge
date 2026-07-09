#!/usr/bin/env bash
# 제품 실행 경로: ~/Applications/Knowledge.app (터미널 권한 빌려쓰기 아님)
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

export KNOWLEDGE_ROOT="${KNOWLEDGE_ROOT:-$HOME/Knowledge}"
"$REPO/scripts/bootstrap-knowledge-root.sh" >/dev/null 2>&1 || true
"$REPO/scripts/package-app.sh" debug

APP="$HOME/Applications/Knowledge.app"
killall Knowledge 2>/dev/null || true
sleep 0.3

# 데몬은 앱이 자동 기동. 개발 중 소켓만 미리 띄우고 싶으면 WITH_DAEMON=1
if [[ "${WITH_DAEMON:-0}" == "1" ]]; then
  nohup "$APP/Contents/MacOS/knowledged" --root "$KNOWLEDGE_ROOT" \
    >>"$KNOWLEDGE_ROOT/logs/knowledged.stdout.log" 2>&1 &
  sleep 0.4
fi

echo "Opening $APP"
open "$APP"
echo ""
echo "※ 터미널에서 swift run 하면 Terminal 권한이 섞일 수 있어요."
echo "  권한은 시스템 설정 → 화면 기록 → Knowledge 에 주세요."
echo "  권한 변경 후: killall Knowledge; open \"$APP\""
