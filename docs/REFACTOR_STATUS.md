# 웹 전환 리팩토링 — 현재 상태 (새 세션은 이 파일부터 읽을 것)

| Field | Value |
|-------|-------|
| 최종 갱신 | 2026-07-27 |
| 현재 위치 | **P0·P1·P2 완료 → 다음은 P3(인증)** |
| 실행 지시서 | `docs/REFACTOR_ACTION_PLAN_WEB_2026-07.md` (P3 절만 읽을 것) |
| 결정 근거 | `docs/REFACTOR_DIRECTION_WEB_2026-07.md` |
| 미해결 이슈 | `docs/REFACTOR_BACKLOG.md` |
| 작업 브랜치 | `refactor/web-p0` |

## Phase 진행 상황

| Phase | 상태 | 게이트 | 산출물 |
|---|---|---|---|
| P0 기준선 동결 | ✅ 완료 | G0-1~G0-5 PASS | `DATA_INVENTORY_2026-07-27.md`, `web/tests/golden/`, 백업 `~/Knowledge-backup-2026-07-27/` |
| P1 스키마+이관 | ✅ 완료 | G1-1~G1-6 PASS | `web/supabase/migrations/`, `web/scripts/migrate-from-sqlite.ts`, `FTS_COMPARISON_2026-07.md` |
| P2 Vault→Git | ✅ 완료 | G2-1~G2-5 PASS (G2-2 단서 아래) | 레포 2개 신규 생성 (아래) |
| **P3 인증** | ⬜ **다음** | 미인증 요청이 DB 레이어에서 차단 | Supabase Auth + RLS + Next 미들웨어 |
| P4a~P7 | ⬜ 미착수 | — | — |

## 지금 존재하는 레포 3개

| 레포 | 용도 | 상태 |
|---|---|---|
| `KnowledgeApp` (로컬, origin=`local_knowledge`) | 코드·문서 모노레포. Vercel Root=`web` (P4a에서 설정) | 브랜치 `refactor/web-p0` |
| `heejunyoo/knowledge-vault` (private) | Obsidian vault SoT | 초기 임포트 완료 (273파일) |
| `heejunyoo/knowledge-backup` (private) | 주1회 pg_dump 백업 | 워크플로 동작 검증 완료 |

## ★ P3 착수 전 반드시 인지할 것

1. **RLS가 전부 꺼져 있다.** 14개 테이블 `rowsecurity=false` (2026-07-27 확인).
   → **P3 완료 전 Vercel을 public으로 배포 금지** (액션플랜 §0.3).
2. **Mac 앱 쓰기 동결(P0-8)이 아직 유효하다.** `DietStore.swift`/`InboxStore.swift`에
   `frozenWriteMethods` 살아 있고 revert 커밋 없음. 액션플랜 P1-5 권고에 따라
   **P4b 완료까지 동결 유지**가 기본값이다.
3. **`owner_id`가 전부 placeholder다.** 모든 행이 `00000000-0000-0000-0000-000000000001`.
   P3에서 실제 사용자 가입 후 테이블마다 UPDATE 1건씩 필요 — 절차는 `docs/ENV_VARS.md`에 있음.
4. **Postgres 직결은 Session Pooler만 된다.** direct(`db.<ref>...:5432`)는 IPv6 전용이라
   로컬·CI 모두 실패한다. 확정값·이유는 `docs/ENV_VARS.md` §Postgres 직결.
   **리전이나 `aws-N` 번호를 추측으로 조립하지 말 것.**
5. **Supabase 스킬이 레포에 설치되어 있다** (`.claude/skills/supabase`,
   `supabase-postgres-best-practices`). P3는 Auth·RLS 작업이므로 **먼저 호출할 것.**

## P2 잔여 (P3를 막지 않음)

- **Obsidian Git 플러그인 미설치.** vault에 `obsidian-git`이 없어 G2-1/G2-2는
  git 레벨 push/pull로 대체 검증했다. 앱에서의 자동 커밋·pull은 오너가 플러그인 설치 후 확인 필요.
  설정값 안내는 `knowledge-vault/COMMIT_PROTOCOL.md`.

## 로컬 도구 (이번 세션에 설치됨)

`gh` 2.96 (인증됨) · `libpq`(psql/pg_dump, `/opt/homebrew/opt/libpq/bin`) · `postgresql@17`(복원 검증용, 중지 상태)
