# 웹 전환 리팩토링 — 현재 상태 (새 세션은 이 파일부터 읽을 것)

| Field | Value |
|-------|-------|
| 최종 갱신 | 2026-07-28 |
| 현재 위치 | **P4a(읽기 API 계층) 진행 중** — 아래 "P4a 진행 상황" 참고 |
| 실행 지시서 | `docs/REFACTOR_ACTION_PLAN_WEB_2026-07.md` (P4a 절만 읽을 것 — **§"착수 전 인지" 4건 필독**) |
| 결정 근거 | `docs/REFACTOR_DIRECTION_WEB_2026-07.md` |
| 미해결 이슈 | `docs/REFACTOR_BACKLOG.md` |
| 작업 브랜치 | `refactor/web-p0` |

## Phase 진행 상황

| Phase | 상태 | 게이트 | 산출물 |
|---|---|---|---|
| P0 기준선 동결 | ✅ 완료 | G0-1~G0-5 PASS | `DATA_INVENTORY_2026-07-27.md`, `web/tests/golden/`, 백업 `~/Knowledge-backup-2026-07-27/` |
| P1 스키마+이관 | ✅ 완료 | G1-1~G1-6 PASS | `web/supabase/migrations/`, `web/scripts/migrate-from-sqlite.ts`, `FTS_COMPARISON_2026-07.md` |
| P2 Vault→Git | ✅ 완료 | G2-1~G2-5 PASS (G2-2 단서 아래) | 레포 2개 신규 생성 (아래) |
| P3 인증 | ✅ 완료 | G3-1~G3-5 PASS (실측표는 액션플랜 P3 절) | Next 스캐폴드 + `004_rls.sql` + `proxy.ts` + 콜백 2종 |
| **P4a 읽기 API** | 🟡 **진행 중** | 골든 diff 0 · 상태기계 default-deny | 아래 "P4a 진행 상황" |
| P4b~P7 | ⬜ 미착수 | — | — |

## P4a 진행 상황 (2026-07-28)

완료: 인증 401 분기, vitest 도입, `lib/settings.ts`(P-1), `lib/redaction.ts`,
`lib/domain/diet-read.ts`, `/api/rpc` 디스패처 + core/assistant/timeline/diet
읽기 라우트 12종 + REST 별칭. 매직링크 실 세션으로 전부 curl 검증 완료
(커밋 로그에 실측값 포함). 남은 것: knowledge/corpus/inbox 읽기(P4a-6),
G4a-1 자동 회귀 테스트, D-3 상태기계(inbox_item·ingest_job), cron
keepalive, health.ingest.

### ★ 이번 세션에서 드러난 스코프 조정 2건 (오너 승인 완료)

1. **`core.health`는 G4a-1(골든 diff 0)의 문서화된 예외.** 액션플랜 §8이
   "로컬 경로·데몬 필드 제거"를 명시하는데, 실제 골든은 core="Heejun의
   Mac mini"·gateway="m4"·knowledge.{db_path,vault_path,asr_engine,
   llama_ready,llm_engine,whisper_ready,recording_count,
   review_needed_count}가 전부 Mac 로컬 데몬 상태라 Vercel에서 재현 불가능
   (의미 없음). 새 구현은 `ok`/`services`/`diet`만 유지하고 `core`/`gateway`는
   제거, `knowledge`는 `{ok: <DB 도달성>}`으로 축소했다
   (`web/lib/rpc/handlers.ts` `core_health()`). G4a-1 회귀 테스트(P4a-8)는
   이 메서드를 축소된 필드 집합으로만 비교한다.
2. **`diet.dashboard`·`diet.fasting.status`는 P4a에서 제외, 별도 세션으로 이관.**
   액션플랜은 이를 "조회 전용, 최소 범위"로 분류했지만 실제 골든을 까 보니
   Mifflin-St Jeor 플랜 투영(eta_text·pace_text 등 시간상대 한국어 문장),
   HealthKit 참고값 포맷팅, "오늘/내일" 요일상대 문구 생성까지 포함된
   `DietStore.swift`(1400줄)의 도메인 로직 본체였다(C-3 절이 이미 경고한
   그 부분). `diet.day_summary/week_review/goals/profile.get/ping`은
   단순 집계·Mifflin BMR/TDEE 공식이라 이번에 완료했지만, 두 메서드는
   `DietPlanProjection`·`FastingPrefs` 전체 이식이 필요해 후속 작업으로
   분리했다.

## 지금 존재하는 레포 3개

| 레포 | 용도 | 상태 |
|---|---|---|
| `KnowledgeApp` (로컬, origin=`local_knowledge`) | 코드·문서 모노레포. Vercel Root=`web` (P4a에서 설정) | 브랜치 `refactor/web-p0` |
| `heejunyoo/knowledge-vault` (private) | Obsidian vault SoT | 초기 임포트 완료 (273파일) |
| `heejunyoo/knowledge-backup` (private) | 주1회 pg_dump 백업 | 워크플로 동작 검증 완료 |

## ★ P4a 착수 전 반드시 인지할 것

1. **`proxy.ts`가 미인증 요청을 307 리다이렉트한다 — G4a-5는 401을 요구한다.**
   `/api/*` 분기를 추가하지 않으면 게이트에서 걸린다. 액션플랜 P4a §착수 전 인지 2번.
2. **`create-next-app`을 다시 하지 말 것.** 스캐폴드는 P3-0에서 완료됐다.
   재실행하면 `package.json`/`tsconfig.json`을 덮어써 P1 스크립트(`npm run migrate`)가 깨진다.
3. **Mac 앱 쓰기 동결(P0-8)이 아직 유효하다.** `DietStore.swift`/`InboxStore.swift`에
   `frozenWriteMethods` 살아 있고 revert 커밋 없음. 액션플랜 P1-5 권고에 따라
   **P4b 완료까지 동결 유지**가 기본값이다.
4. **Postgres 직결은 Session Pooler만 된다.** direct(`db.<ref>...:5432`)는 IPv6 전용이라
   로컬·CI 모두 실패한다. 확정값·이유는 `docs/ENV_VARS.md` §Postgres 직결.
   **리전이나 `aws-N` 번호를 추측으로 조립하지 말 것.**
5. **Supabase 스킬이 레포에 설치되어 있다** (`.claude/skills/supabase`,
   `supabase-postgres-best-practices`). DB·Auth 작업 시 **먼저 호출할 것.**
6. **인증이 실패하면 코드를 고치기 전에 auth 로그부터 읽는다.**
   MCP `get_logs(service:"auth")`. P3에서 이 순서를 어겨 두 번 헛돌았다 — 액션플랜 §P3 회고.
7. **로그인 테스트는 `web/scripts/generate-magic-link.ts`로 한다.** 실제 메일 발송은
   무료 티어 제한(시간당 소수)에 금방 걸린다. 이 스크립트는 메일을 보내지 않아 제한과 무관하다.

## P3에서 만들어진 것 (P4a가 얹힐 기반)

| 경로 | 역할 |
|---|---|
| `web/app/page.tsx` | **플레이스홀더 5줄.** P5에서 Hub로 대체 |
| `web/app/login/page.tsx` | 매직링크 로그인 폼 |
| `web/app/auth/callback/route.ts` | PKCE `?code=` → `exchangeCodeForSession` |
| `web/app/auth/confirm/route.ts` | `?token_hash=` → `verifyOtp` (서버 발급 링크용) |
| `web/proxy.ts` + `web/lib/supabase/proxy.ts` | 세션 갱신·보호. **`code`/`token_hash`는 콜백으로 넘김** |
| `web/lib/supabase/{client,server}.ts` | 브라우저·서버 클라이언트 |
| `web/scripts/create-owner-user.ts` | 오너 계정 생성 (service_role, 1회성) |
| `web/scripts/generate-magic-link.ts` | 메일 없이 로그인 링크 발급 (로컬 전용) |
| `web/supabase/migrations/004_rls.sql` | 14개 테이블 RLS + `owner_all` 정책 |

오너 `auth.uid()` = `47e5b22d-a1f1-4266-b4e5-cd2524b0a37f` (naheejun87@gmail.com).
placeholder `owner_id` 교체 완료 — 상세는 `docs/ENV_VARS.md`.

## P2 잔여 (P4a를 막지 않음)

- **Obsidian Git 플러그인 미설치.** vault에 `obsidian-git`이 없어 G2-1/G2-2는
  git 레벨 push/pull로 대체 검증했다. 앱에서의 자동 커밋·pull은 오너가 플러그인 설치 후 확인 필요.
  설정값 안내는 `knowledge-vault/COMMIT_PROTOCOL.md`.

## 로컬 도구 (2026-07-27 세션에 설치됨)

`gh` 2.96 (인증됨) · `libpq`(psql/pg_dump, `/opt/homebrew/opt/libpq/bin`) · `postgresql@17`(복원 검증용, 중지 상태)

## 커밋 검증 훅 (2026-07-27 추가)

`.claude/settings.json`에 PreToolUse 훅이 있다. `git commit` 직전에만 발동해서, 커밋 메시지가
게이트 통과·Phase 완료를 주장하는데 **실제 실행 증거가 트랜스크립트에 없으면 차단**한다.
검증 주장이 없는 커밋은 즉시 통과하므로 평소엔 보이지 않는다.

> 배경: 2026-07-27 P2에서 복원 절차 문서를 **작성만 하고 실행하지 않은 채** 게이트 통과로
> 보고한 사고가 있었다. "완료 = 실제 실행 검증 통과"를 프롬프트가 아니라 메커니즘으로 집행하기 위한 장치다.
> 이 훅은 커밋 표면만 막는다 — 채팅 보고에서의 미검증 주장은 여전히 사람이 봐야 한다.
