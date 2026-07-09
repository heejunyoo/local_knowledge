#!/usr/bin/env bash
# Install local 7B as the **default** engine when no cloud API key is set.
# Cloud free-tier only becomes #1 after a key is saved in Settings.
set -euo pipefail

ROOT="${KNOWLEDGE_ROOT:-$HOME/Knowledge}"
BIN_REL="tools/llama.cpp/b0/llama-cli"
MODEL_REL="tools/models/llm/Qwen2.5-7B-Instruct-Q4_K_M.gguf"
BIN_DEST="$ROOT/$BIN_REL"
MODEL_DEST="$ROOT/$MODEL_REL"

mkdir -p "$(dirname "$BIN_DEST")" "$(dirname "$MODEL_DEST")" "$ROOT/config" "$ROOT/logs"

echo "== install-llm-field (local 7B = default without cloud keys) =="
echo "root: $ROOT"

# Wrapper that calls Homebrew llama-cli (keeps rpath/dylibs working)
LLAMA_SRC=""
for c in \
  "$(command -v llama-cli 2>/dev/null || true)" \
  /opt/homebrew/bin/llama-cli \
  /usr/local/bin/llama-cli
do
  if [[ -n "$c" && -x "$c" ]]; then
    LLAMA_SRC="$c"
    break
  fi
done

if [[ -z "$LLAMA_SRC" ]]; then
  if command -v brew >/dev/null 2>&1; then
    echo "Installing llama.cpp via Homebrew…"
    brew install llama.cpp
    LLAMA_SRC="$(command -v llama-cli || true)"
  fi
fi

if [[ -z "${LLAMA_SRC:-}" || ! -x "$LLAMA_SRC" ]]; then
  echo "FAIL: llama-cli missing. brew install llama.cpp" >&2
  exit 1
fi

# Thin brew binary needs Cellar dylibs — invoke via absolute path wrapper, do not bare-copy only.
cat > "$BIN_DEST" <<EOF
#!/bin/bash
exec "$LLAMA_SRC" "\$@"
EOF
chmod +x "$BIN_DEST"
echo "OK  wrapper → $BIN_DEST → $LLAMA_SRC"

if [[ -f "$MODEL_DEST" && $(stat -f%z "$MODEL_DEST" 2>/dev/null || echo 0) -gt 1500000000 ]]; then
  echo "OK  7B model present $(du -h "$MODEL_DEST" | awk '{print $1}')"
else
  # Resume partial if present
  PART="$MODEL_DEST.partial"
  URLS=(
    "https://huggingface.co/bartowski/Qwen2.5-7B-Instruct-GGUF/resolve/main/Qwen2.5-7B-Instruct-Q4_K_M.gguf"
    "https://huggingface.co/Qwen/Qwen2.5-7B-Instruct-GGUF/resolve/main/qwen2.5-7b-instruct-q4_k_m.gguf"
  )
  ok=0
  for URL in "${URLS[@]}"; do
    echo "Downloading 7B (~4.5GB) $URL …"
    if curl -L --fail --retry 3 --retry-delay 2 -C - -o "$PART" "$URL"; then
      mv "$PART" "$MODEL_DEST"
      ok=1
      break
    fi
  done
  if [[ "$ok" != "1" ]]; then
    echo "FAIL: place 7B GGUF at $MODEL_DEST" >&2
    exit 1
  fi
  echo "OK  model $(du -h "$MODEL_DEST" | awk '{print $1}')"
fi

# 1.5B is not the product default — remove so resolver never picks it over 7B
rm -f "$ROOT/tools/models/llm/Qwen2.5-1.5B-Instruct-Q4_K_M.gguf" || true

python3 - <<PY
import json, os
from pathlib import Path
root = Path(os.path.expanduser("$ROOT"))
cfg_path = root / "config" / "app.json"
cfg = json.loads(cfg_path.read_text()) if cfg_path.exists() else {}
cfg.setdefault("llm", {})
cfg["llm"]["engine"] = "llama.cpp"
cfg["llm"]["binary_rel"] = "$BIN_REL"
cfg["llm"]["model_rel"] = "$MODEL_REL"
# cloud stays opt-in by key; flag can be true but without keys 7B runs
cfg["llm"]["cloud_enabled"] = cfg["llm"].get("cloud_enabled", True)
cfg.setdefault("rag", {})
cfg["rag"]["use_llama"] = True
cfg_path.write_text(json.dumps(cfg, indent=2, ensure_ascii=False) + "\n")

man_path = root / "config" / "tools_manifest.json"
man = json.loads(man_path.read_text()) if man_path.exists() else {"version": 1, "tools": [], "models": []}
tools = man.setdefault("tools", [])
found = False
for t in tools:
    if "llama" in t.get("name", ""):
        t["binary_rel"] = "$BIN_REL"
        t["version"] = "brew-wrapper"
        found = True
if not found:
    tools.append({"name": "llama.cpp", "version": "brew-wrapper", "binary_rel": "$BIN_REL", "sha256": "PIN"})
models = man.setdefault("models", [])
# drop 1.5b entries
models[:] = [m for m in models if "1.5" not in m.get("name", "") and "1.5" not in m.get("rel", "")]
found = False
for m in models:
    if "qwen" in m.get("name", "").lower() or "llm" in m.get("rel", ""):
        m["name"] = "qwen2.5-7b-instruct-q4_k_m"
        m["rel"] = "$MODEL_REL"
        found = True
if not found:
    models.append({"name": "qwen2.5-7b-instruct-q4_k_m", "rel": "$MODEL_REL", "sha256": "PIN", "tier": "T16"})
man_path.write_text(json.dumps(man, indent=2, ensure_ascii=False) + "\n")
print("OK  config: 7B is default without cloud keys")
PY

EX="$(cd "$(dirname "$0")/.." && pwd)/config/examples/llm_providers.json"
if [[ -f "$EX" && ! -f "$ROOT/config/llm_providers.json" ]]; then
  cp "$EX" "$ROOT/config/llm_providers.json"
fi

echo "Smoke: binary"
"$BIN_DEST" --version 2>&1 | head -3 || true
echo "== done. Without API keys, Knowledge uses local 7B. =="
