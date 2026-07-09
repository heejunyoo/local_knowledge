# KnowledgeApp

Personal, local-first knowledge repository for Apple Silicon Mac mini.

**Design SoT:** [`~/Documents/PKM-native-app-design.md`](file:///Users/heejunyoo/Documents/PKM-native-app-design.md) (Rev 2 + owner open-question resolutions).

## What this is

- **UI:** `Knowledge.app` (SwiftUI menu bar + review/search) — owns mic / ScreenCaptureKit capture (TCC).
- **Daemon:** LaunchAgent pipeline (ASR → LLM summary → Stage1/2 → human review gate → vault commit).
- **Body SoT:** Obsidian vault markdown for meetings; Apple Notes remains Notes.app (search FTS mirror only).
- **Index:** SQLite pointers, pipeline state, FTS5 (vectors off by default).

Harness-inspired product rules: Single Source of Truth, drift scenarios, layered confidence (schema + evidence), quiet notifications, risk-based eval convergence.

## Repo layout

```text
KnowledgeApp/
  README.md
  Package.swift                 # KnowledgeCore (more packages in later PRs)
  Schemas/                      # JSON Schema SoT (copied into ~/Knowledge/schemas at install)
  docs/                         # Policy bodies (thresholds, privacy, commit, curation, glossary)
  config/examples/              # features.json, app.json templates
  evals/scenarios/              # Drift scenarios (runner lands in PR-02)
  Packages/KnowledgeCore/       # State graph, models, thresholds, schema types
  third_party/                  # Bootstrap scripts for whisper.cpp / llama.cpp (PR-05w)
  scripts/                      # Dev helpers
```

Runtime machine-local tree (created by the app, not committed):

```text
~/Knowledge/
  config/   docs/   schemas/   tools/   audio/   transcripts/
  summaries/   index/   logs/   cache/   evals/
```

## Prerequisites

| Item | Requirement |
|------|-------------|
| Hardware | Apple Silicon Mac mini, **≥ 16 GB** unified memory |
| OS | macOS **14.0+** (dev machine may be 26.x) |
| Xcode | 15+ / current with Swift 5.9+ |
| Obsidian vault | Separate path from `~/Knowledge` (no symlink of vault under Knowledge root) |

## Quick start

```bash
cd ~/IdeaProjects/KnowledgeApp
swift test
```

Install example config into the runtime root (idempotent):

```bash
./scripts/bootstrap-knowledge-root.sh
```

Eval scenarios (graph / recovery / thresholds):

```bash
swift test --filter ScenarioRunnerTests
# definitions: evals/scenarios/*.json
```

Run pipeline daemon (dev):

```bash
swift run knowledged --root ~/Knowledge
# UDS: ~/Knowledge/cache/daemon.sock  (mode 0600)
# methods: ping, health, meeting.create, meeting.transition, meeting.get, meeting.list
# Auto-tick: recorded → ASR → transcribed (or transcribe_failed, never silent success)
```

UI (Toss-inspired):

```bash
./scripts/run-ui.sh
# or after package: open .build/debug/Knowledge.app
```

**백그라운드 엔진(`knowledged`)은 앱이 자동 기동합니다.** 사용자는 CLI로 데몬을 켤 필요가 없습니다.  
(개발자가 파이프라인만 단독 디버깅할 때만 `swift run knowledged`를 쓰면 됩니다.)

Design: `docs/ui/toss_design.md`

## Feature flags

**Only** `~/Knowledge/config/features.json` (never duplicate in `app.json`).

MVP defaults: all automation extras off (`critic`, `vector_search`, `notes_ingest`, cloud, blackhole).

## Implementation track (MVP)

| PR | Scope |
|----|--------|
| 01 | Monorepo + policy SoT + schema + `KnowledgeCore` thresholds/types |
| 02 | Pipeline state graph (default deny) + recovery R1–R6 + ScenarioRunner |
| 03 | SQLite index (meetings, FTS, pipeline_events) |
| 04 | Daemon + UDS JSON-RPC (`knowledged`) |
| **05w** | Tool bootstrap + sha256 verify |
| **05** | Mic capture library + heartbeat + RPC handoff |
| 06a / **06** | Whisper invoker + daemon auto tick |
| **UI** | Menu bar app — Toss design philosophy |
| 07–08 | Summarize Stage1/2 |
| 10b–11 | Review accept + vault commit → **MVP exit** |

Priority rationale: `docs/mvp_priority_scoring.md`  
Design SoT: `~/Documents/PKM-native-app-design.md`

### Tools (ASR/LLM)

```bash
./scripts/bootstrap-knowledge-root.sh
# Drop binaries offline:
./scripts/install-tool-file.sh /path/to/whisper-cli tools/whisper.cpp/1.7.5/whisper-cli
./scripts/install-tool-file.sh /path/to/ggml-large-v3-turbo.bin tools/models/whisper/ggml-large-v3-turbo.bin
# Pin sha256 in ~/Knowledge/config/tools_manifest.json then:
./scripts/verify-tools.sh
```

## Principles (product)

1. **SoT** — one body per knowledge unit; index is pointers (+ Notes FTS *derived* mirror).
2. **Drift first** — scenarios encode normal state; humans do not run checklists.
3. **Human review** before vault commit (no auto-commit).
4. **Layered confidence** — Stage1 schema + Stage2 evidence spans.
5. **Quiet by default** — notify only `failure` / `review_needed` / `action_due`.
6. **Risk-based convergence** — R3–R4 only for silent-miss / security sensitive changes.

## License

Private / personal use. Not for redistribution without owner consent.
