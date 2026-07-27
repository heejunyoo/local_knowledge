# KnowledgeApp improvement-loop specification

Use this project-local specification with `$codex-improvement-loop` for
substantive changes. It supplements the global loop contract; it does not
replace it.

## Acceptance criteria

Before declaring a change verified:

1. State the affected product behaviour and the files/tests expected to prove
   it in the ledger.
2. Run `./.codex/verify-loop.sh --changed` after the baseline and after each
   coherent implementation iteration. It discovers changed Swift package test
   targets from the working tree, runs only those targets, and builds the two
   shipped macOS executables when Swift sources changed.
3. Run `./.codex/verify-loop.sh --all` when the change crosses packages,
   changes `Package.swift`, or the selected verifier is insufficient.
4. Treat mobile smoke, field-daemon, cloud-LLM, and tool checks as opt-in:
   they require their documented local service, simulator, credentials, or
   binary. Record them as an accepted gap rather than silently skipping them.
5. Review `git diff --check` and the relevant diff before recording a terminal
   state. Stop after at most three implementation iterations.

## Scope boundary

This verifier is intentionally limited to the Swift package and its shipped
macOS executables. It does not start daemons, make network calls, invoke iOS
simulators, or install tools. Use the existing scripts under `scripts/` for
those explicitly requested integration checks.

## Ledger

Record each loop in `.codex/loop-ledger.md` with the goal, acceptance criteria,
baseline command/result, iterations, score evidence, findings, and one of:
`verified`, `accepted-gap`, `blocked`, or `iteration-limit`.
