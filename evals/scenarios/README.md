# Eval scenarios

JSON scenarios executed by `KnowledgeCore.ScenarioRunner` (PR-02).

```bash
cd ~/IdeaProjects/KnowledgeApp && swift test --filter ScenarioRunnerTests
```

| ID | File | Intent | Status |
|----|------|--------|--------|
| S02 | `S02_graph_edges.json` | Legal edges + default-deny guards | **active** |
| S02b | `S02b_recovery.json` | Crash recovery R1–R4 | **active** |
| S05 | `S05_threshold_keys.json` | Threshold key SoT list | **active** |
| S11 | `S11_no_wildcard_committed.json` | Only `commit_pending → committed` | **active** |
| S12 | `S12_timeout_never_success.json` | Timeout ≠ success | **active** |
| S03 | — | Stage2 evidence outcomes | PR-08 |
| S04 | — | Quiet notifications | PR-10a |
| S06 | — | Index vs body SoT | PR-03 |
| S13 | — | commit_pending reconcile | PR-11 |

Worker timeout policy is unit-tested in `KnowledgeWorkersTests` (timeout never `succeeded`).

Add a scenario in the **same change** as the layer it protects (Harness P2 / AP-08).
