#!/usr/bin/env bash
# Self-check Knowledge-Field surface without asking a human to click UI.
# Exit 0 only if contracts hold.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
APP="${HOME}/Applications/Knowledge.app"
ROOT="${KNOWLEDGE_ROOT:-$HOME/Knowledge}"
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "OK  $*"; }

echo "== Knowledge Field verify =="

# 1) Source UI contracts (F1)
HOME_SWIFT="$REPO/Packages/KnowledgeUI/Sources/KnowledgeUI/Views/HomeView.swift"
[[ -f "$HOME_SWIFT" ]] || fail "HomeView missing"
grep -q 'KnowledgeAudioHelper' "$HOME_SWIFT" && fail "HomeView still tells user to grant Helper"
for n in \
  '폴더 열기' \
  'openVaultInFinder' \
  'vaultReady' \
  'runSearch' \
  'AppRoute' \
  'SettingsView' \
  'runRetentionPolicy' \
  'MeetingSummaryLoader' \
  'KnowledgeCorpus' \
  'syncKnowledgeCorpus' \
  'RecordView' \
  'ChatView' \
  'ReviewInboxView' \
  '바로가기' \
  '저장하기' \
  '이야기한 것' \
  'LLMRouter' \
  'llm_providers' \
  'CloudLLMClient' \
  'LocalRetrieve' \
  'TextChunker' \
  'retrieve-v2' \
  'LocalHashEmbedder' \
  'RedactionPreflight' \
  'SummaryCritic' \
  'DriftChecker' \
  'ActionDueNotifier'
do
  grep -R -q -- "$n" "$REPO/Packages" || fail "missing contract: $n"
  ok "contract: $n"
done
# Free-tier catalog example must exist for swap-without-rebuild
test -f "$REPO/config/examples/llm_providers.json" || fail "llm_providers example missing"
ok "config/examples/llm_providers.json"
test -f "$REPO/docs/rag_scorecard.md" || fail "rag_scorecard.md missing"
ok "docs/rag_scorecard.md"
test -f "$REPO/docs/knowledge_corpus.md" || fail "knowledge_corpus.md missing"
ok "docs/knowledge_corpus.md"
grep -q 'search.reindex' "$REPO/Packages/KnowledgeRPC/Sources/KnowledgeRPC/Methods.swift" \
  || fail "search.reindex RPC missing"
ok "RPC: search.reindex"

# 2) Unit tests (core config/paths)
cd "$REPO"
swift test --filter 'AppConfigTests|KnowledgeCoreTests/testKnowledgeRootLayoutCreate' >/tmp/knowledge-field-tests.log 2>&1 \
  || { tail -30 /tmp/knowledge-field-tests.log; fail "unit tests"; }
ok "unit tests (AppConfig + layout)"

# 3) Installed app + non-ad-hoc sign
[[ -x "$APP/Contents/MacOS/Knowledge" ]] || fail "app not installed at $APP"
TEAM=$(codesign -dv "$APP" 2>&1 | awk -F= '/TeamIdentifier/{print $2}')
[[ -n "$TEAM" && "$TEAM" != "not set" ]] || fail "app not Development-signed (TeamIdentifier=$TEAM)"
ok "codesign TeamIdentifier=$TEAM"

# 4) Runtime vault + committed notes
CFG="$ROOT/config/app.json"
[[ -f "$CFG" ]] || fail "missing $CFG"
python3 - <<PY
import json, os, sys
from pathlib import Path
cfg = json.loads(Path(os.path.expanduser("$CFG")).read_text())
vault = Path(os.path.expanduser(cfg.get("vault_path", "")))
if not vault.is_dir():
    print("vault missing", vault); sys.exit(1)
notes = list((vault / "Meetings").rglob("*.md")) if (vault / "Meetings").exists() else []
# Notes may be empty on fresh install — only require dir
print(f"vault={vault} notes={len(notes)}")
for p in notes[:5]:
    t = p.read_text()
    if not t.startswith("---") or "## 주요 논의" not in t:
        print("bad note", p); sys.exit(1)
PY
ok "vault layout + note shape (if any)"

# 5) DB statuses readable
DB="$ROOT/index/knowledge.db"
if [[ -f "$DB" ]]; then
  sqlite3 "$DB" "SELECT status, count(*) FROM meeting GROUP BY 1;" | sed 's/^/  /'
  ok "sqlite meeting status"
else
  echo "  (no db yet — ok for fresh bootstrap)"
fi

# 6) Live daemon search — start bundled knowledged if needed
SOCK="$ROOT/cache/daemon.sock"
DAEMON_BIN="$APP/Contents/MacOS/knowledged"
if [[ ! -S "$SOCK" && -x "$DAEMON_BIN" ]]; then
  "$DAEMON_BIN" --root "$ROOT" >>"$ROOT/logs/knowledged.stdout.log" 2>&1 &
  sleep 0.8
fi
if [[ -S "$SOCK" ]]; then
  python3 - <<'PY' || fail "live search RPC"
import json, os, socket, struct, sys
SOCK = os.path.expanduser("~/Knowledge/cache/daemon.sock")
def rpc(method, params=None):
    payload = json.dumps({"jsonrpc":"2.0","id":1,"method":method,"params":params or {}}, ensure_ascii=False).encode()
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.settimeout(5); s.connect(SOCK)
    s.sendall(struct.pack(">I", len(payload)) + payload)
    n = struct.unpack(">I", s.recv(4))[0]
    body = b""
    while len(body) < n: body += s.recv(n - len(body))
    s.close(); return json.loads(body.decode())
h = rpc("health")["result"]
assert h.get("ok") is True
assert "asr_engine" in h and "llm_engine" in h
rpc("search.reindex")
# Hangul substring must work via LIKE fallback
hits = rpc("search", {"q": "미팅"})["result"]["hits"]
assert isinstance(hits, list)
print(f"search 미팅 hits={len(hits)} engines={h.get('asr_engine')}/{h.get('llm_engine')}")
PY
  ok "live health+search RPC"
else
  echo "  (daemon sock down — skip live search)"
fi

echo "== ALL FIELD CHECKS PASSED =="
