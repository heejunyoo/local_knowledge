#!/usr/bin/env bash
# Install policy SoT + example config into ~/Knowledge (or KNOWLEDGE_ROOT).
set -euo pipefail

ROOT="${KNOWLEDGE_ROOT:-$HOME/Knowledge}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "Knowledge root: $ROOT"
echo "Repo:           $REPO_ROOT"

mkdir -p \
  "$ROOT/config" \
  "$ROOT/docs" \
  "$ROOT/schemas" \
  "$ROOT/tools" \
  "$ROOT/audio/raw" \
  "$ROOT/audio/derived" \
  "$ROOT/audio/orphan" \
  "$ROOT/transcripts" \
  "$ROOT/summaries" \
  "$ROOT/index" \
  "$ROOT/logs" \
  "$ROOT/cache" \
  "$ROOT/evals"

# Policy docs (overwrite — SoT lives in repo; runtime copy for offline daemon)
cp -R "$REPO_ROOT/docs/." "$ROOT/docs/"
cp "$REPO_ROOT/Schemas/meeting-summary-v1.json" "$ROOT/schemas/"

# Config: do not clobber existing user config
if [[ ! -f "$ROOT/config/features.json" ]]; then
  cp "$REPO_ROOT/config/examples/features.json" "$ROOT/config/features.json"
  echo "Wrote config/features.json"
else
  echo "Keep existing config/features.json"
fi

if [[ ! -f "$ROOT/config/app.json" ]]; then
  # Expand ~ for this machine
  sed "s|~/Knowledge|$ROOT|g; s|\"vault_path\": \"~/Obsidian/Main\"|\"vault_path\": \"$HOME/Obsidian/Main\"|g" \
    "$REPO_ROOT/config/examples/app.json" > "$ROOT/config/app.json"
  echo "Wrote config/app.json (edit vault_path to your Obsidian vault)"
else
  echo "Keep existing config/app.json"
fi

if [[ ! -f "$ROOT/config/tools_manifest.json" ]]; then
  cp "$REPO_ROOT/config/examples/tools_manifest.json" "$ROOT/config/tools_manifest.json"
  echo "Wrote config/tools_manifest.json"
else
  echo "Keep existing config/tools_manifest.json"
fi

# Ensure default vault dir exists (user can change vault_path anytime)
VAULT="${HOME}/Obsidian/Main"
if [[ -f "$ROOT/config/app.json" ]]; then
  # shellcheck disable=SC2002
  VP=$(python3 -c "import json,os; p=json.load(open(os.path.expanduser('$ROOT/config/app.json'))); print(os.path.expanduser(p.get('vault_path','~/Obsidian/Main')))" 2>/dev/null || echo "$VAULT")
  mkdir -p "$VP"
  echo "Vault dir ready: $VP"
else
  mkdir -p "$VAULT"
fi

echo "Done."
echo "  config:  $ROOT/config/app.json  (vault_path)"
echo "  package: $REPO_ROOT/scripts/package-app.sh && open ~/Applications/Knowledge.app"
echo "  plan:    $REPO_ROOT/docs/implementation_plan_field.md"
