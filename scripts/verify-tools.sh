#!/usr/bin/env bash
# Verify tools_manifest pins under KNOWLEDGE_ROOT (default ~/Knowledge).
set -euo pipefail
ROOT="${KNOWLEDGE_ROOT:-$HOME/Knowledge}"
MANIFEST="$ROOT/config/tools_manifest.json"

if [[ ! -f "$MANIFEST" ]]; then
  echo "missing $MANIFEST — run scripts/bootstrap-knowledge-root.sh first" >&2
  exit 1
fi

python3 - <<'PY' "$ROOT" "$MANIFEST"
import hashlib, json, os, sys
root, manifest_path = sys.argv[1], sys.argv[2]
with open(manifest_path) as f:
    m = json.load(f)

def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

ok = True
entries = []
for t in m.get("tools", []):
    entries.append((t["name"], t["binary_rel"], t.get("sha256", "")))
for t in m.get("models", []):
    entries.append((t["name"], t["rel"], t.get("sha256", "")))

for name, rel, pin in entries:
    path = os.path.join(root, rel)
    pin_l = (pin or "").lower()
    if not os.path.exists(path):
        print(f"MISSING  {name:30} {rel}")
        ok = False
        continue
    if pin_l in ("", "pin_after_download"):
        print(f"PRESENT  {name:30} {rel}  (unpinned)")
        continue
    actual = sha256(path)
    if actual != pin_l:
        print(f"MISMATCH {name:30} expected={pin_l[:12]}… actual={actual[:12]}…")
        ok = False
    else:
        print(f"OK       {name:30} {rel}")

sys.exit(0 if ok else 2)
PY
