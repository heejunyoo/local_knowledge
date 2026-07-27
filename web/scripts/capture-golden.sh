#!/usr/bin/env bash
# Capture a golden regression snapshot from the live Mac gateway (/v1/rpc).
# See docs/REFACTOR_ACTION_PLAN_WEB_2026-07.md P0-4 / §6.
#
# Usage: web/scripts/capture-golden.sh --out /tmp/g1
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
WEB="$REPO/web"
BASE_URL="${KNOWLEDGE_GATEWAY_URL:-http://127.0.0.1:8741}"
TOKEN_FILE="${GOLDEN_TOKEN_FILE:-$WEB/.secrets-local/golden-capture.token}"
OUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) OUT="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done
[[ -n "$OUT" ]] || { echo "usage: capture-golden.sh --out <dir>" >&2; exit 1; }

if [[ -n "${GOLDEN_TOKEN:-}" ]]; then
  TOKEN="$GOLDEN_TOKEN"
elif [[ -f "$TOKEN_FILE" ]]; then
  TOKEN="$(cat "$TOKEN_FILE")"
else
  echo "FAIL: no pairing token. Set GOLDEN_TOKEN or create $TOKEN_FILE" >&2
  echo "  (mint one: POST /v1/pair/start on loopback, then /v1/pair/complete)" >&2
  exit 1
fi

mkdir -p "$OUT/read" "$OUT/search/results"

rpc() {
  local method="$1"
  local params="${2:-{}}"
  curl -s -m 10 -X POST "$BASE_URL/v1/rpc" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$method\",\"params\":$params}"
}

# §8 R(읽기) 메서드 — 실측으로 gateway RPC에 실제 구현되어 응답하는 것만 포함.
# 제외: diet.json/inbox.json/assistant.gaps.evening/assistant.onboarding.dismissed
#   → probe 결과 -32601 Method not found (클라이언트 로컬 전용이거나 미구현, NORMALIZE.md 참조)
# 제외: knowledge.ask / knowledge.ask.fast → LLM 생성 경로(P6), 비결정적이라 G0-1 재현성
#   게이트 대상에서 제외 (§8에서는 R이지만 Phase가 P6이므로 이 단계 스코프 아님)
READ_METHODS=(
  core.ping
  core.health
  core.services
  assistant.today
  assistant.week_review
  assistant.gaps
  timeline.list
  knowledge.health
  corpus.status
  inbox.list
  diet.day_summary
  diet.dashboard
  diet.week_review
  diet.goals
  diet.profile.get
  diet.fasting.status
  diet.ping
  health.sync_status
)

echo "== capturing ${#READ_METHODS[@]} read methods =="
for m in "${READ_METHODS[@]}"; do
  resp="$(rpc "$m")"
  if ! echo "$resp" | python3 "$REPO/web/scripts/normalize.py" > "$OUT/read/$m.json" 2>"$OUT/read/$m.err"; then
    echo "FAIL: $m -> $(cat "$OUT/read/$m.err")" >&2
    exit 1
  fi
  rm -f "$OUT/read/$m.err"
  if grep -q '"error"' "$OUT/read/$m.json" && ! grep -q '"result"' "$OUT/read/$m.json"; then
    echo "WARN: $m returned an error (kept in snapshot for visibility):"
    cat "$OUT/read/$m.json" >&2
  fi
done

echo "== capturing search queries =="
cp "$REPO/web/tests/golden/search/queries.json" "$OUT/search/queries.json"

python3 - "$OUT" "$BASE_URL" "$TOKEN" "$REPO" <<'PYEOF'
import json, subprocess, sys, urllib.request

out_dir, base_url, token, repo = sys.argv[1:5]
with open(f"{repo}/web/tests/golden/search/queries.json", encoding="utf-8") as f:
    queries = json.load(f)

for q in queries:
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": "knowledge.search", "params": {"q": q["q"]}}).encode()
    req = urllib.request.Request(
        f"{base_url}/v1/rpc", data=body, method="POST",
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=10) as r:
        resp = json.load(r)
    hits = (resp.get("result") or {}).get("hits", [])
    doc_ids = [h.get("doc_id") for h in hits]
    result = {"id": q["id"], "category": q["category"], "q": q["q"], "count": len(doc_ids), "doc_ids": doc_ids}
    with open(f"{out_dir}/search/results/{q['id']}.json", "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")
    print(f"  {q['id']} ({q['category']}): \"{q['q']}\" -> {len(doc_ids)} hits")
PYEOF

echo "== done: $OUT =="
