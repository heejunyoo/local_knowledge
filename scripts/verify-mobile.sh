#!/usr/bin/env bash
# Mobile Core gateway smoke (loopback). No iPhone required.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${KNOWLEDGE_ROOT:-$HOME/Knowledge}"
PORT="${KNOWLEDGE_HTTP_PORT:-8747}"
BIN="$REPO/.build/debug/knowledged"

cd "$REPO"
if [[ ! -x "$BIN" ]]; then
  echo "Building knowledged…"
  swift build --product knowledged 2>&1 | tail -3
fi
[[ -x "$BIN" ]] || BIN=$(find "$REPO/.build" -name knowledged -type f | head -1)
[[ -x "$BIN" ]] || { echo "knowledged binary missing"; exit 1; }

# Free the port if a previous smoke left something behind
if lsof -ti :"$PORT" >/dev/null 2>&1; then
  # Only kill if it looks like knowledged (best-effort)
  lsof -ti :"$PORT" | while read -r p; do
    cmd=$(ps -p "$p" -o comm= 2>/dev/null || true)
    if [[ "$cmd" == *knowledged* ]] || [[ "$cmd" == *knowledged ]]; then
      kill "$p" 2>/dev/null || true
    fi
  done
  sleep 0.4
fi

LOG=$(mktemp)
"$BIN" --root "$ROOT" --http-port "$PORT" --no-pipeline >"$LOG" 2>&1 &
PID=$!
cleanup() { kill "$PID" 2>/dev/null || true; wait "$PID" 2>/dev/null || true; rm -f "$LOG"; }
trap cleanup EXIT

for i in $(seq 1 30); do
  if curl -sf "http://127.0.0.1:$PORT/v1/health" >/dev/null 2>&1; then
    break
  fi
  sleep 0.2
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "knowledged died:"; cat "$LOG"; exit 1
  fi
  if [[ $i -eq 30 ]]; then
    echo "timeout waiting for gateway"; cat "$LOG"; exit 1
  fi
done

BASE="http://127.0.0.1:$PORT"
fail=0
check() {
  local name="$1"
  shift
  if "$@"; then
    echo "  OK  $name"
  else
    echo "  FAIL $name"
    fail=1
  fi
}

echo "=== verify-mobile (port $PORT) ==="

H=$(curl -sS "$BASE/v1/health")
check "health.ok" python3 -c "import sys,json; d=json.loads(sys.argv[1]); assert d.get('ok') is True" "$H"
check "health.diet" python3 -c "import sys,json; d=json.loads(sys.argv[1]); assert d.get('services',{}).get('diet') is True" "$H"

START=$(curl -sS -X POST "$BASE/v1/pair/start")
CODE=$(python3 -c "import sys,json; print(json.load(sys.stdin)['code'])" <<<"$START")
check "pair.code" test "${#CODE}" -eq 6

COMP=$(curl -sS -X POST "$BASE/v1/pair/complete" \
  -H 'Content-Type: application/json' \
  -d "{\"code\":\"$CODE\",\"device_name\":\"verify-mobile\"}")
TOK=$(python3 -c "import sys,json; print(json.load(sys.stdin)['token'])" <<<"$COMP")
check "pair.token" test -n "$TOK"

ASK=$(curl -sS -X POST "$BASE/v1/rpc" \
  -H "Authorization: Bearer $TOK" -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"knowledge.ask.fast","params":{"q":"검증","limit":3}}')
check "ask.fast" python3 -c "import sys,json; d=json.loads(sys.argv[1]); assert 'result' in d and d['result'].get('answer') is not None" "$ASK"

REV=$(curl -sS -X POST "$BASE/v1/rpc" \
  -H "Authorization: Bearer $TOK" -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":2,"method":"knowledge.review.list","params":{}}')
check "review.list" python3 -c "import sys,json; d=json.loads(sys.argv[1]); assert 'result' in d" "$REV"

DIET=$(curl -sS -X POST "$BASE/v1/rpc" \
  -H "Authorization: Bearer $TOK" -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":3,"method":"diet.ping","params":{}}')
check "diet.ping" python3 -c "import sys,json; d=json.loads(sys.argv[1]); assert d.get('result',{}).get('ok') is True" "$DIET"

CHAT=$(curl -sS -X POST "$BASE/v1/chat" \
  -H "Authorization: Bearer $TOK" -H 'Content-Type: application/json' \
  -d '{"message":"verify snack 11kcal","mode":"auto"}')
check "chat.diet" python3 -c "import sys,json; d=json.loads(sys.argv[1]); assert 'answer' in d and d.get('engine')" "$CHAT"

curl -sS -X POST "$BASE/v1/pair/revoke" \
  -H "Authorization: Bearer $TOK" -H 'Content-Type: application/json' -d '{}' >/dev/null
CODE401=$(curl -sS -o /tmp/vm-rev.json -w "%{http_code}" -X POST "$BASE/v1/rpc" \
  -H "Authorization: Bearer $TOK" -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":9,"method":"core.ping","params":{}}')
check "revoke.401" test "$CODE401" = "401"

# Tailscale hint (optional)
TS_IP=""
if command -v tailscale >/dev/null 2>&1; then
  TS_IP=$(tailscale ip -4 2>/dev/null | head -1 || true)
elif [[ -x /Applications/Tailscale.app/Contents/MacOS/Tailscale ]]; then
  TS_IP=$(/Applications/Tailscale.app/Contents/MacOS/Tailscale ip -4 2>/dev/null | head -1 || true)
fi
if [[ -n "$TS_IP" ]]; then
  echo "  TIP Core URL for iPhone: http://${TS_IP}:8741"
else
  echo "  TIP Set Core URL to http://<mac-tailscale-ip>:8741 on iPhone"
fi

if [[ "$fail" -ne 0 ]]; then
  echo "=== SMOKE_FAIL ==="
  exit 1
fi
echo "=== SMOKE_OK ==="
