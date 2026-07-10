#!/usr/bin/env bash
# Verify cloud free-tier LLM path without printing secrets.
set -euo pipefail
ROOT="${KNOWLEDGE_ROOT:-$HOME/Knowledge}"
SECRETS="$ROOT/config/secrets.json"
CATALOG="$ROOT/config/llm_providers.json"

echo "── secrets ──"
if [[ ! -f "$SECRETS" ]]; then
  echo "FAIL: no $SECRETS"
  exit 1
fi
python3 - <<PY
import json
from pathlib import Path
d=json.loads(Path("$SECRETS").read_text())
for k,v in sorted(d.items()):
    print(f"  {k}: {'OK len='+str(len(v)) if v else 'EMPTY'}")
if not any(d.values()):
    raise SystemExit("FAIL: no cloud keys")
PY

echo "── catalog ──"
python3 - <<PY
import json
from pathlib import Path
c=json.loads(Path("$CATALOG").read_text())
print("  as_of", c.get("as_of"), "order", c.get("order"))
g=c["providers"]["groq"]
print("  groq primary", g["model"])
print("  groq fallbacks", g.get("fallback_models"))
assert g["model"] == "llama-3.3-70b-versatile", "primary should be 70B versatile for quality"
print("  cloud_enabled check: app.json llm.cloud_enabled should be true")
cfg=json.loads((Path("$ROOT")/"config/app.json").read_text())
print("  cloud_enabled =", cfg.get("llm",{}).get("cloud_enabled"))
assert cfg.get("llm",{}).get("cloud_enabled") is not False
PY

echo "── live Groq (curl) ──"
KEY=$(python3 -c "import json;from pathlib import Path;print(json.loads(Path('$SECRETS').read_text())['groq_api_key'])")
MODEL=$(python3 -c "import json;from pathlib import Path;print(json.loads(Path('$CATALOG').read_text())['providers']['groq']['model'])")
HTTP=$(curl -sS -o /tmp/groq_verify.json -w "%{http_code}" \
  https://api.groq.com/openai/v1/chat/completions \
  -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"system\",\"content\":\"한국어 한 줄. 태금 없이.\"},{\"role\":\"user\",\"content\":\"'준비됨'이라고만 답하세요.\"}],\"max_tokens\":30,\"temperature\":0.2}" \
  --max-time 45)
echo "  http $HTTP model $MODEL"
python3 - <<'PY'
import json
d=json.load(open("/tmp/groq_verify.json"))
if "error" in d:
    print("  FAIL", d["error"])
    raise SystemExit(1)
text=d["choices"][0]["message"]["content"].strip().replace("\n"," ")
print("  answer:", text[:100])
print("── PASS (Groq free tier reachable) ──")
PY
