# MVP priority self-scoring (2026-07-09)

Scoring dimensions (0–10 each), higher = do sooner.

| Dim | Meaning |
|-----|---------|
| U | Unblocks offline vertical slice |
| D | Dependencies already satisfied |
| R | Silent-miss / trust risk if deferred |
| T | Testable without full SwiftUI app |
| E | Effort efficiency (10 = small, clear slice) |

| PR | U | D | R | T | E | **Σ** | Decision |
|----|---|---|---|---|---|-------|----------|
| **05w** tools bootstrap | 9 | 10 | 7 | 9 | 8 | **43** | **Do next** |
| **05** mic capture lib | 10 | 9 | 8 | 7 | 6 | **40** | **Do next** |
| 06 whisper integrate | 10 | 6* | 9 | 6 | 5 | 36 | After 05w (+ optional real binary) |
| 07 summarize Stage1 | 9 | 4 | 8 | 5 | 4 | 30 | After 06 |
| 08 Stage2 evidence | 8 | 3 | 9 | 5 | 4 | 29 | After 07 |
| 10a menu bar UI | 7 | 5 | 4 | 3 | 3 | 22 | Needs app target |
| 10b review UI | 9 | 4 | 7 | 3 | 3 | 26 | After 07/08 |
| 11 vault commit | 10 | 3 | 10 | 5 | 4 | 32 | After 10b |
| 12 SCK online | 5 | 7 | 4 | 4 | 3 | 23 | Post-MVP parallel |
| 09 critic | 3 | 5 | 5 | 6 | 5 | 24 | Post-MVP |

\*06 D rises to 9 once 05w lands.

## Execution order (this session)

1. **PR-05w** — `ToolBootstrap`, manifest verify, offline drop-in install, scripts  
2. **PR-05** — `KnowledgeCapture` mic recorder + heartbeat + raw audio handoff paths  
3. **PR-06a** (thin) — ASR worker invoker that runs whisper-cli **if present**, else clean error (no silent success)

Stop after green tests + commits; report remaining path to MVP exit (PR-11).
