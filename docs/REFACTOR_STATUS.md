# 웹 전환 리팩토링 — 현재 상태 (새 세션은 이 파일부터 읽을 것)

| Field | Value |
|-------|-------|
| 최종 갱신 | 2026-07-28 |
| 현재 위치 | P4a 읽기 API 완료(9/12) → **다음: task 9 상태기계(D-3)** |
| 다음 세션 읽기 순서 | ① 이 파일 ② 액션플랜 §P4a "작업 단계 4·5"만 ③ 막히면 `REFACTOR_BACKLOG.md` |
| 결정 근거 | `docs/REFACTOR_DIRECTION_WEB_2026-07.md` (D-3 정의 §2.2) |
| 미해결 이슈 | `docs/REFACTOR_BACKLOG.md` |
| 작업 브랜치 | `refactor/web-p0` |

## Phase 진행 상황

| Phase | 상태 | 산출물 |
|---|---|---|
| P0 기준선 동결 | ✅ | `DATA_INVENTORY_2026-07-27.md`, `web/tests/golden/` |
| P1 스키마+이관 | ✅ | `web/supabase/migrations/`, `migrate-from-sqlite.ts` |
| P2 Vault→Git | ✅ | 레포 2개 신규(아래) |
| P3 인증 | ✅ | Next 스캐폴드 + `004_rls.sql` + `proxy.ts` |
| **P4a 읽기 API** | 🟡 9/12 | 아래 |
| P4b~P7 | ⬜ | — |

## P4a 게이트 현황

| 게이트 | 상태 |
|---|---|
| G4a-1 골든 diff 0 | ✅ 15/18 (`npm run test:regression`), 3건 skip(미구현: dashboard·fasting.status·health.sync_status) |
| G4a-2 inbox 왕복 | ⬜ GitHub PAT 미발급 — task 9 이후 별도 |
| G4a-3 상태기계 default-deny | ⬜ **다음(task 9)** |
| G4a-4 ingest_job 고아 회수 | ⬜ task 9에 포함 |
| G4a-5 미인증 401 | ✅ |
| G4a-6 검색 골든 30건 | ⬜ `compare-search.ts` 변경 없음, 재실행만 필요 |

## 완료 (task 1~8, 커밋 9개 — 상세는 `git log`의 "P4a-" 커밋)

401 분기, vitest(+회귀용 별도 config), `lib/settings.ts`(P-1), `lib/redaction.ts`,
`lib/domain/diet-read.ts`, `/api/rpc` + core/assistant/timeline/diet/knowledge/
corpus/inbox 읽기 17종 + REST 별칭, G4a-1 회귀 자동화.

## 다음 작업

9. **상태기계 D-3** `web/lib/domain/state-machine.ts` — 액션플랜 §P4a 작업 단계 4
   그대로. `inbox_item`+`ingest_job` 그래프, `state_event` 기록, 유닛 테스트
   (미선언 전이 20종 거부·와일드카드 금지·heartbeat 회수 4종·attempts 상한).
   커밋 함수는 주입형으로 만들 것(GitHub PAT 없이 테스트 가능해야 함).
   `ingest_job`은 PAT 불필요 — `corpus.sync`/`search.reindex`에 실제 연결하고
   G4a-4까지 이번에 검증.
10. `/api/cron/keepalive` + `vercel.json` Cron 등록.
11. `/api/health/ingest`(Bearer `INGEST_API_TOKEN`) + `health.sync_status`.
    토큰 값은 직접 생성하지 말고 오너가 발급하도록 안내.
12. (별도 세션) `diet.dashboard`·`diet.fasting.status` — `DietPlanProjection`·
    `FastingPrefs` 전체 이식 필요. 착수 전 골든 2개 + `DietStore.swift`의
    `dashboard()`/`fastingStatus()`/`planProjection()` 대조.
13. (급하지 않음) `corpus.status` obsidian 카운트 골든(225) vs 라이브(217) 8건
    갭 원인 미확인 — `REFACTOR_BACKLOG.md` "P4a에서 발견" 참고.

## 이번 세션 스코프 조정 (오너 승인 완료, 상세는 커밋 메시지)

- **`core.health`/`knowledge.health`**: 골든의 Mac 로컬 데몬 필드(db_path 등)는
  Vercel에서 재현 불가 → `ok`/`services`/`diet`만 유지, `knowledge`는
  `{ok: DB 도달성}`으로 축소. G4a-1은 이 필드만 비교.
- **`diet.dashboard`·`diet.fasting.status`**: "조회 전용 최소 범위"로 분류돼
  있었지만 실제론 Mifflin 플랜 투영·HealthKit 참고값 등 도메인 로직 본체
  (C-3 경고) → P4a에서 제외, task 12로 이관.

## 레포 3개

| 레포 | 용도 |
|---|---|
| `KnowledgeApp` (로컬) | 코드·문서 모노레포. Vercel Root=`web`, 브랜치 `refactor/web-p0` |
| `heejunyoo/knowledge-vault` (private) | Obsidian vault SoT |
| `heejunyoo/knowledge-backup` (private) | 주1회 pg_dump 백업 |

## 착수 전 반드시 인지할 것

1. **`create-next-app` 재실행 금지.** `package.json`/`tsconfig.json` 덮어써
   `npm run migrate` 깨짐.
2. **Mac 앱 쓰기 동결(P0-8) 유지 중.** `frozenWriteMethods` 살아있음 — P4b
   완료까지 기본값.
3. **Postgres 직결은 Session Pooler만.** direct(`:5432` IPv6)는 로컬·CI 모두
   실패. 확정값은 `docs/ENV_VARS.md` §Postgres 직결 — 추측 조립 금지.
4. **DB·Auth 작업 시 Supabase 스킬(`.claude/skills/supabase`) 먼저 호출.**
5. **인증 실패 시 코드 고치기 전에 `get_logs(service:"auth")`부터.** P3에서
   순서를 어겨 두 번 헛돌았음.
6. **로그인 테스트는 `web/scripts/generate-magic-link.ts`로.** 메일 미발송이라
   무료 티어 rate limit과 무관. (`tests/regression/test-client.ts`가 같은
   기법을 admin.generateLink+verifyOtp로 자동화해 씀 — 참고 가능.)

## P3 산출물 (P4a 기반)

| 경로 | 역할 |
|---|---|
| `web/app/page.tsx` | 플레이스홀더. P5에서 Hub로 대체 |
| `web/app/login/page.tsx` | 매직링크 로그인 폼 |
| `web/app/auth/{callback,confirm}/route.ts` | 코드/토큰 교환 |
| `web/proxy.ts` + `web/lib/supabase/proxy.ts` | 세션 갱신·보호(`/api/*` 401 분기 포함) |
| `web/lib/supabase/{client,server}.ts` | 브라우저·서버 클라이언트 |
| `web/supabase/migrations/004_rls.sql` | RLS + `owner_all` 정책 |

오너 `auth.uid()` = `47e5b22d-a1f1-4266-b4e5-cd2524b0a37f`. 상세는 `docs/ENV_VARS.md`.

## 기타

- **P2 잔여**: Obsidian Git 플러그인 미설치. 앱 자동 커밋은 오너가 플러그인
  설치 후 확인 필요(`knowledge-vault/COMMIT_PROTOCOL.md`).
- **로컬 도구**: `gh`, `libpq`(psql/pg_dump), `postgresql@17`(중지 상태).
- **커밋 검증 훅**: `.claude/settings.json` PreToolUse — 게이트 통과를
  주장하는 커밋 메시지에 트랜스크립트상 실행 증거가 없으면 차단.
