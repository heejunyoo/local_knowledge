# Eval scenarios

Scenario **runner** lands in **PR-02**. This directory holds scenario definitions only.

| ID | Intent | Earliest PR |
|----|--------|-------------|
| S02 | State graph default-deny / legal edges only | PR-02 |
| S03 | Stage2 evidence outcomes | PR-08 |
| S04 | Quiet notifications (no success spam) | PR-10a |
| S05 | Threshold keys docs == code | PR-02 (partial via unit test) |
| S06 | Index does not become body SoT for meetings | PR-03 |
| S11 | No wildcard committed transitions | PR-02 |
| S12 | Timeout never equals success | PR-06 |
| S13 | commit_pending reconcile | PR-11 |

Add a scenario in the **same change** as the layer it protects (Harness P2 / AP-08).
