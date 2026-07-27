# KnowledgeApp improvement-loop ledger

## 2026-07-12 — Project loop foundation

- Goal: turn the global manual loop into an auditable, project-local loop for
  the active KnowledgeApp repository without changing product code.
- Acceptance criteria: define scope and terminal states; add a deterministic
  changed-package verifier; preserve opt-in integration checks; record observed
  baseline evidence.
- Baseline: `swift test --filter 'DietNutritionCalcTests|MeetingArtifactReaderTests|DietStoreTests|LLMRouterTests'` — PASS, 15 tests, 0 failures.
- Iteration 1: added `.codex/loop-spec.md` and `.codex/verify-loop.sh`.
  The verifier selected four changed package targets; 84 tests and both macOS
  executable builds passed. It then exposed unrelated, pre-existing trailing
  whitespace in changed documentation because its whitespace check was too
  broad.
- Iteration 2: narrowed the whitespace check to the selected implementation
  scope and added the documented iOS simulator build when mobile files change.
- Verification: `./.codex/verify-loop.sh --changed` — PASS. It selected
  `KnowledgeCoreTests|KnowledgeGatewayTests|KnowledgeUITests|KnowledgeWorkersTests`:
  84 tests, 0 failures; `KnowledgeApp` and `knowledged` builds passed; the
  documented generic iOS Simulator build passed. The global harness audit also
  passed; its global-only maturity score remains 60/100.
- Score: 5/5 observed acceptance criteria met (specification, changed-target
  discovery, selected-test evidence, product-build evidence, audit/diff review).
- Findings: pre-existing trailing whitespace in unrelated changed documentation
  remains outside the implementation scope; it was not modified.
- Iteration 3: made `--all` perform its promised full working-tree whitespace
  review after the complete package suite. `./.codex/verify-loop.sh --all`
  then passed all 100 Swift tests and correctly reported the pre-existing
  documentation whitespace as a nonzero full-tree finding.
- Terminal state: accepted-gap (3 implementation iterations). Owner/next
  action: the author of the current documentation batch should remove the
  reported trailing whitespace before using `--all` as a clean-gate command.
