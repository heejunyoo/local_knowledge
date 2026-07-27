#!/usr/bin/env bash
# Deterministic local verifier for the KnowledgeApp improvement loop.
set -euo pipefail

usage() {
  echo "usage: $0 --changed | --all" >&2
  exit 64
}

[[ $# -eq 1 ]] || usage
mode="$1"
case "$mode" in
  --changed|--all) ;;
  *) usage ;;
esac

cd "$(dirname "$0")/.."

if [[ "$mode" == "--all" ]]; then
  swift test
  git diff --check
  exit 0
fi

changed=()
while IFS= read -r path; do
  changed+=("$path")
done < <(
  {
    git diff --name-only --diff-filter=ACMR HEAD
    git ls-files --others --exclude-standard
  } | sort -u
)

packages=()
scope_paths=()
swift_changed=false
mobile_changed=false
for path in "${changed[@]}"; do
  if [[ "$path" == "Package.swift" ]]; then
    echo "Package.swift changed; use --all for complete package coverage." >&2
    exit 2
  fi
  if [[ "$path" == *.swift ]]; then
    swift_changed=true
  fi
  if [[ "$path" =~ ^Packages/([^/]+)/ ]]; then
    package="${BASH_REMATCH[1]}"
    packages+=("$package")
    scope_paths+=("Packages/$package")
  fi
  if [[ "$path" == Apps/KnowledgeMobile/* ]]; then
    mobile_changed=true
    scope_paths+=("Apps/KnowledgeMobile")
  fi
  if [[ "$path" == Sources/* ]]; then
    scope_paths+=("Sources")
  fi
done

if [[ "${#packages[@]}" -eq 0 ]]; then
  echo "No changed package files detected; no Swift package test target selected."
  if [[ "$mobile_changed" == true ]]; then
    xcodebuild -scheme KnowledgeMobile \
      -project Apps/KnowledgeMobile/KnowledgeMobile.xcodeproj \
      -destination 'generic/platform=iOS Simulator' build
  fi
  [[ "${#scope_paths[@]}" -eq 0 ]] || git diff --check -- "${scope_paths[@]}"
  exit 0
fi

deduplicated_packages=()
while IFS= read -r package; do
  deduplicated_packages+=("$package")
done < <(printf '%s\n' "${packages[@]}" | sort -u)
packages=("${deduplicated_packages[@]}")
targets=()
for package in "${packages[@]}"; do
  target="${package}Tests"
  if [[ -d "Packages/${package}/Tests/${target}" ]]; then
    targets+=("$target")
  else
    echo "No conventional test target for package ${package}; use --all or record an accepted gap." >&2
    exit 2
  fi
done

filter="$(IFS='|'; echo "${targets[*]}")"
echo "Selected test targets: ${filter}"
swift test --filter "$filter"

if [[ "$swift_changed" == true ]]; then
  echo "Building shipped macOS executables after Swift source changes."
  swift build --product KnowledgeApp
  swift build --product knowledged
fi

if [[ "$mobile_changed" == true ]]; then
  echo "Building KnowledgeMobile after mobile source changes."
  xcodebuild -scheme KnowledgeMobile \
    -project Apps/KnowledgeMobile/KnowledgeMobile.xcodeproj \
    -destination 'generic/platform=iOS Simulator' build
fi

git diff --check -- "${scope_paths[@]}"
