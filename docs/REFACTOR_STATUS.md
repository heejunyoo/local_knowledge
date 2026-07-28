# 웹 전환 리팩토링 — 현재 상태 (새 세션은 이 파일부터 읽을 것)

| Field | Value |
|-------|-------|
| 최종 갱신 | 2026-07-28 |
| 현재 위치 | **P5 구현 완료**(Hub·검색·Diet·Inbox·Settings 5라우트 + PWA + D-4 검색모드 확정). 게이트 G5-4/G5-5 통과, G5-1/G5-2/G5-3는 Chrome 확장 미연결로 curl 기반 기능 검증만 완료·시각적 브라우저 검증 이월. **다음: Chrome 확장 연결 후 G5-1~G5-3 마무리** 또는 P4a 잔여 게이트(G4a-2/G4a-6/corpus.status 갭) 처리, 아래 "다음 작업" 참고 |
| 다음 세션 읽기 순서 | ① 이 파일 ② G5-1~G5-3 마무리 또는 액션플랜 §P6 ③ 막히면 `REFACTOR_BACKLOG.md` |
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
| P4a 읽기 API | ✅ 구현 11/11, 게이트 G4a-1/3/4/5 통과. G4a-2/G4a-6은 외부 의존(PAT/재실행)이라 이월 유지 | 아래 |
| **P4b diet 쓰기 + health.ingest** | ✅ 게이트 G4b-1~G4b-3 통과, G4b-4 이월(발화 채널 미결정) | 아래 |
| **P5 웹 UI** | ✅ 구현 완료(chat 제외 5라우트), G5-4/G5-5 통과 · G5-1/G5-2/G5-3 브라우저 실검증 이월 | 아래 |
| P6~P7 | ⬜ | — |

## P5 게이트 현황

| 게이트 | 상태 |
|---|---|
| G5-1 폰 브라우저에서 URL만으로 로그인 → 전부 동작 | ⬜ curl로 5라우트 전부 200·실 데이터 렌더 확인했으나, 실제 폰 브라우저 시각 검증은 Chrome 확장 미연결로 이월 |
| G5-2 데스크톱 브라우저 동일 | ⬜ 위와 동일 사유로 이월(기능은 curl로 검증 완료) |
| G5-3 PWA 설치 후 홈 화면 아이콘으로 실행 가능 | ⬜ manifest.json/sw.js/아이콘 200 응답 확인까지만. 실기기 설치는 오너 몫 |
| G5-4 Lighthouse 성능·접근성 각 80 이상 | ✅ `next build && next start` 프로덕션 빌드 + `npx lighthouse`(쿠키 주입)로 5라우트 전부 측정 — 성능 96~99, 접근성 95~96 |
| G5-5 D-4 후속 판단 완료 | ✅ `docs/FTS_COMPARISON_2026-07.md`에 3줄 결론 기록, `settings['search.mode']`='tsvector' 확정(변경 불필요) |

## P4a 게이트 현황

| 게이트 | 상태 |
|---|---|
| G4a-1 골든 diff 0 | ✅ **21/21**(`npm run test:regression`) — P4b에서 diet.dashboard·diet.fasting.status 이식 완료로 스킵 0건 |
| G4a-2 inbox 왕복 | ⬜ GitHub PAT 미발급 — 코드는 준비됨(`defaultVaultCommit`), 토큰 발급 후 별도 세션 |
| G4a-3 상태기계 default-deny | ✅ `tests/domain/state-machine.test.ts`(23종 거부) |
| G4a-4 ingest_job 고아 회수 | ✅ 유닛 테스트 + 실 DB 검증(`tests/regression/state-machine.regression.test.ts`) |
| G4a-5 미인증 401 | ✅ |
| G4a-6 검색 골든 30건 | ⬜ `compare-search.ts` 변경 없음, 재실행만 필요 |

## P4b 게이트 현황

| 게이트 | 상태 |
|---|---|
| G4b-1 도메인 유닛 테스트 전부 통과 | ✅ `tests/domain/*.test.ts` 전체(116개) — diet-presets/diet-nutrition-calc/diet-dashboard(26개, planSummary·weightForPlan·fastingStatus·healthReference·dashboard)·ingest-auth/health-ingest 신규 |
| G4b-2 골든 회귀: diet 계열 diff 0 | ✅ diet.dashboard·diet.fasting.status 포함 실제 Supabase 대상 21/21 diff-0(G4a-1과 통합) |
| G4b-3 쓰기 왕복 | ✅ `tests/regression/diet-write.regression.test.ts` — log_meal→day_summary 반영→delete_meal→원복 |
| G4b-4 단식 리마인더 실제 발화 | ⬜ **이월** — 발화 채널(이메일/Web Push 등) 미결정, 액션플랜 §P4b 각주 참고 |

## 완료 (task 1~11, 커밋 11개+ — 상세는 `git log`의 "P4a-" 커밋)

401 분기, vitest(+회귀용 별도 config), `lib/settings.ts`(P-1), `lib/redaction.ts`,
`lib/domain/diet-read.ts`, `/api/rpc` + core/assistant/timeline/diet/knowledge/
corpus/inbox 읽기 17종 + REST 별칭, G4a-1 회귀 자동화.

**task 9(상태기계 D-3)**: `lib/domain/state-machine.ts`(순수 default-deny 그래프
+ R2/R3 복구 규칙) + `lib/db/state-event.ts` + `inbox.promote`/`corpus.sync`/
`search.reindex` RPC 3종 + 고아 회수 lazy 트리거(`inbox.list`/`corpus.status`
진입 시). `corpus.sync`/`search.reindex`는 GitHub PAT 없이 가능한 DB 내부
실작업(`syncConnectedSourceStats`/`reindexMissingSearchDocs`)으로 연결 —
GitHub 기반 실제 vault 재수집은 이월(`REFACTOR_BACKLOG.md` "P4a-9에서 발견").
유닛 테스트 33종 + 실 DB 검증 3종 전부 통과, G4a-1 회귀 무변화(15/18 유지).
회귀 스위트가 2개 파일(`golden.test.ts` + 신규)로 늘면서 각 파일이 동시에
같은 오너 이메일로 매직링크 인증을 시도해 서로의 링크를 무효화하는 경쟁
상태가 발생 — `vitest.regression.config.ts`에 `fileParallelism: false` 추가로
해결(연속 2회 실행으로 재현 확인).

**task 10(`/api/cron/keepalive`)**: `web/lib/cron.ts`(`isCronAuthorized`, `CRON_SECRET`
Bearer 검증 — 미설정 시 기본값 차단) + `app/api/cron/keepalive/route.ts`(anon key로
`settings` 1행 select, RLS로 걸러져도 DB 왕복 자체가 무활동 방지 목적) + `web/vercel.json`
(`crons: [{path, schedule: "0 0 * * *"}]`, 일 1회). 유닛 테스트 4종(`tests/domain/cron.test.ts`)
작성 중 첫 구현의 실제 결함을 발견 — `Bearer ${process.env.CRON_SECRET}` 템플릿 리터럴이
`CRON_SECRET` 미설정 시 문자열 `"Bearer undefined"`가 돼, 그 리터럴 헤더값이 우연히
통과하는 구멍이 있었다. `secret` 미설정을 먼저 명시적으로 걷어내도록 수정 후 재검증 통과.
dev 서버로 3분기(헤더 없음/오답/정답) 실행 확인: 401/401/`{"ok":true}`+200.
`CRON_SECRET` 값은 Vercel 프로젝트 환경변수로 오너가 직접 발급/등록 필요(`docs/ENV_VARS.md`).

**task 11(`health.sync_status`)**: 착수 전 원본 확인 중 `health.ingest`가
액션플랜 §8에서 P4a로 오분류돼 있음을 발견(아래 "이번 세션 스코프 조정" 참고)
— 오너 결정으로 액션플랜부터 정정한 뒤, P4a에 실제로 속하는 `health.sync_status`만
구현. 원본(`MobileHTTPServer.swift`)이 상태와 무관한 고정값을 반환하므로
`lib/rpc/handlers.ts`의 `health_sync_status()`는 그 값을 그대로 반환 —
`lib/rpc/dispatch.ts` 등록 + REST 별칭 `GET /api/health/sync`(세션 보호,
`/api/health/ingest`와 달리 Bearer 예외 아님). `tests/domain/health.test.ts` 1종 +
`golden.test.ts`의 `NOT_YET_IMPLEMENTED`에서 제거해 G4a-1 diff-0 대상 편입.

## P4b (diet 쓰기 도메인 + health.ingest, 커밋 8개 — `git log`의 "P4b-" 커밋)

착수 전 `diet_metric.context` 컬럼 누락(001_init.sql이 놓침 — `weightForPlanLocked()`
우선순위 판정에 필수)을 발견해 `005_diet_metric_context.sql`로 선행 추가.
번역 순서: `diet-presets.ts`(식사 10종/운동 5종) → `diet-nutrition-calc.ts`
(Food 카탈로그 30종, `estimate`/`matchFood`/`parse` — matchFood는 카탈로그
배열 순서상 "과일"의 별칭이 전용 "사과"/"바나나" 항목보다 먼저 매칭되는
원본 그대로의 특성을 재현) → `diet-read.ts` 확장(`planSummary`·
`weightForPlan`·`healthReference`·`fastingStatus`·`localDayTimeLabels`
Seoul 고정·`dashboard`) → `lib/db/diet.ts` 쓰기 함수(insert/delete
meal·workout·metric, `FastingPrefs`는 `settings['diet.fasting']`에 저장
— goals/profile과 동일 패턴, 별도 테이블 없음) → RPC 배선 → `health.ingest`.

번역 중 발견한 원본의 죽은 분기: `planSummary`의 "정체"(daily_deficit<=50)
가지는 delta>0.3일 때의 대체식이 항상 100 이상을 강제해 실질적으로 도달
불가능 — "고치지" 않고 그대로 옮기고 테스트로 근거를 남김.

`health.ingest`는 세션 없는 정적 Bearer 인증이라 RLS를 통과할 수 없어,
오너 승인으로 `web/lib/health-ingest.ts` 1곳에서만 `SUPABASE_SERVICE_ROLE_KEY`
예외 사용 + owner_id 코드 고정(`docs/ENV_VARS.md` 참고) — dev 서버 +
실제 DB로 401/401/200, dedup, `morning_fasted` 자동 태깅, 프로필 체중
동기화까지 검증 후 테스트 데이터 정리 완료.

과정에서 `tests/regression/normalize.ts`의 숨은 버그 발견·수정: 골든
JSON(이미 정규화된 값)을 테스트가 다시 `normalize()`에 통과시킬 때 문자열
분기가 volatile 키를 내용과 무관하게 무조건 `<TS>`로 덮어써 숫자 volatile
키(`hours_since_last_meal`)의 정규화 결과(`<N>`)를 망가뜨리고 있었다 —
이 키가 volatile 키 중 처음으로 숫자값을 가져 지금까지 드러나지 않았음.

G4b-4(단식 리마인더 실제 발화)는 이월 — 위 "P4b 게이트 현황" 및 액션플랜
§P4b 각주 참고.

## P5 (웹 UI, 커밋 8개 — `git log`의 "P5-" 커밋)

**스코프 조정(계획 단계에서 발견, 오너 승인)**: 액션플랜 §P5는 `/chat`을
포함하지만 백엔드 `knowledge.ask`는 P6에서만 구현되어(`dispatch.ts` 미등록)
이번 세션은 **`/chat` 제외** — Hub·검색·Diet·Inbox·Settings 5라우트만
구현. P6 완료 후 별도 세션에서 추가.

순서: 공통 기반(`theme.css`=TossTheme.swift 이식, `lib/rpc/client.ts`
브라우저 fetch 헬퍼, `components/ui/*` 프리미티브, `AppShell`+5탭
`BottomNav`) → Hub(`assistant.today` 1회 호출 서버 컴포넌트) → 검색
(`knowledge.search`, 4상태) → Diet(가장 큼 — 계획/단식/링/슬롯/한줄입력/
프리셋/오늘기록/주간·목표·내정보 바텀시트, `DietView.swift` 1202줄 이식) →
Inbox(`ReviewInboxView.swift`는 미팅 리뷰라 F-1로 폐기, 실제 백엔드인
텍스트 인박스 상태기계에 맞춰 재구성) → Settings(`SettingsView.swift`의
Mac 전용 항목 대신 코퍼스 상태+동기화+검색모드 표시+로그아웃으로 축소) →
PWA(`sips`로 아이콘 리사이즈, `manifest.json`, 데이터 캐시 없는 오프라인
셸 `sw.js`) → D-4 검색모드 확정.

D-4: 실 DB(오너 코퍼스 236 단위) 대상 EXPLAIN ANALYZE로 tsvector/trgm/
hybrid 재확인 — trgm은 tsvector가 이미 찾은 문서의 부분집합만 반환(신규
회수 0)하면서 약 16배 느려(5.5ms vs 86ms) `tsvector` 확정
(`docs/FTS_COMPARISON_2026-07.md`).

검증: 매 슬라이스마다 dev 서버 + curl(쿠키 세션)로 5라우트 전부 실 DB
데이터 렌더 확인, Diet는 log_meal→dashboard 반영→delete_meal→원복 왕복,
Inbox는 create→promote(PAT 미발급으로 promote_failed 경로까지) 확인 후
테스트 데이터 정리(SQL). `npm run test`(116개)·`test:regression`(23개)
전부 유지. `next build && next start` 프로덕션 빌드 후 `npx lighthouse`에
쿠키를 주입해 5라우트 전부 측정 — 성능 96~99·접근성 95~96(위 게이트 표).
접근성 감점 원인은 전부 `--toss-blue-500`(#3182F6) 텍스트의 대비비 — Toss
디자인 토큰 자체의 특성이라 이번 세션에서 임의 변경하지 않음(색상 변경은
전체 앱 정체성에 영향, 오너 판단 필요 시 별도 논의).

**Chrome 확장 미연결로 이번 세션은 curl 기반 기능 검증까지만 완료** —
실제 폰·데스크톱 브라우저에서의 시각 확인(G5-1/G5-2)과 PWA 홈 화면 설치
실기기 확인(G5-3)은 다음 세션(확장 연결 후) 또는 오너가 직접 진행.

## 다음 작업

- **G5-1~G5-3 마무리** — Chrome 확장(https://claude.ai/chrome) 설치·연결
  후 모바일/데스크톱 뷰포트로 5라우트 시각 확인 + PWA 실기기 설치 확인.
- **P6(생성 경로 이식) 착수 여부 결정** — LLM 라우팅·extractive fallback
  구현 후 `/chat` 라우트를 P5에 추가하는 후속 작업 포함.
- **G4b-4(단식 리마인더 실제 발화) 후속** — 실제 알림 채널(이메일/Web Push
  예외 허용/기타) 결정은 오너 몫. 결정 후 pg_cron 스케줄 등록 + 별도 phase로.
- (아무 때나) G4a-2(inbox 왕복): GitHub PAT 발급 후 vault 레포 실제 커밋
  왕복 검증.
- (아무 때나) G4a-6(검색 골든 30건): `compare-search.ts` 재실행만 필요.
- (급하지 않음) `corpus.status` obsidian 카운트 골든(225) vs 라이브(217) 8건
  갭 원인 미확인 — `REFACTOR_BACKLOG.md` "P4a에서 발견" 참고.
- (급하지 않음) `INGEST_API_TOKEN` 값을 오너가 Vercel 환경변수로 발급/등록
  (라우트는 구현 완료, 로컬 임시 토큰으로 curl 검증 마침).

## 이번 세션 스코프 조정 (오너 승인 완료, 상세는 커밋 메시지)

- **`core.health`/`knowledge.health`**: 골든의 Mac 로컬 데몬 필드(db_path 등)는
  Vercel에서 재현 불가 → `ok`/`services`/`diet`만 유지, `knowledge`는
  `{ok: DB 도달성}`으로 축소. G4a-1은 이 필드만 비교.
- **`diet.dashboard`·`diet.fasting.status`**: "조회 전용 최소 범위"로 분류돼
  있었지만 실제론 Mifflin 플랜 투영·HealthKit 참고값 등 도메인 로직 본체
  (C-3 경고) → P4a에서 제외, task 12로 이관.
- **`corpus.sync`/`search.reindex`(task 9)**: GitHub PAT 미발급으로 원본 Swift의
  실제 obsidian/notes/files 재수집을 재현할 수 없어 DB 내부 실작업(connected_source
  통계 재계산 / search_doc 누락분 upsert)으로 축소. 상세·후속 task는
  `REFACTOR_BACKLOG.md` "P4a-9에서 발견" 참고.
- **`health.ingest`(task 11 착수 전 발견, 2026-07-28)**: 액션플랜 §8이 P4a로
  분류했으나 실측 오류. 원본 핸들러가 `DietStore.swift`의 `ingestHealthSamples`→
  `logWorkout`/`logMetric`을 직접 호출하는데, 이 둘은 같은 §8 표에서 이미
  `diet.log_workout`/`diet.log_metric`으로 **P4b**로 분류돼 있었다(위 세 항목과
  동일한 C-3류 오분류 패턴). `logMetric`은 추가로 활성 단식 중 `morning_fasted`
  태그를 위해 task 12의 `FastingPrefs` 상태도 참조한다. 오너 결정으로 액션플랜
  §8/§P4a/§P4b를 먼저 정정(P4b 작업 단계 4에 편입)한 뒤, P4a에 실제로 속하는
  `health.sync_status`(원본이 상태 무관 고정값이라 문제 없음)만 이번 세션에 구현.
- **G4b-4(단식 리마인더 실제 발화) 이월(2026-07-28, P4b)**: Swift 원본에도
  실제 알림 스케줄링 코드가 없고(순수 폴링), 방향성 문서가 가정한 Web Push는
  액션플랜 §P5가 명시적으로 금지 — 실제 알림 채널이 미결정이라 새 외부
  서비스 도입(CLAUDE.md 안전 바닥 대상) 없이 이번 세션은 이월. 상세는
  액션플랜 §P4b 각주.
- **`health.ingest` service role 예외(2026-07-28, P4b)**: `SUPABASE_SERVICE_ROLE_KEY`는
  "`web/app`·`web/lib` import 금지" 원칙이었으나, 세션 없는 정적 Bearer
  인증인 `health.ingest`는 RLS를 통과할 방법이 없어 `web/lib/health-ingest.ts`
  1곳에 한해 예외 허용(owner_id는 코드에서 고정값 명시). 다른 파일로 확대 금지.

## 레포 3개

| 레포 | 용도 |
|---|---|
| `KnowledgeApp` (로컬) | 코드·문서 모노레포. Vercel Root=`web`, 브랜치 `refactor/web-p0` |
| `heejunyoo/knowledge-vault` (private) | Obsidian vault SoT |
| `heejunyoo/knowledge-backup` (private) | 주1회 pg_dump 백업 |

## 착수 전 반드시 인지할 것

1. **`create-next-app` 재실행 금지.** `package.json`/`tsconfig.json` 덮어써
   `npm run migrate` 깨짐.
2. **Mac 앱 쓰기 동결(P0-8) 유지 중.** `frozenWriteMethods`/`DietStore.frozenForMigration`
   살아있음 — **P4b가 이번에 완료됐으니 동결 해제 여부는 오너 결정 필요**
   (골든 재검증·G0-4 재확인 없이 임의로 풀지 말 것, Swift 쪽 변경이라 이
   세션 스코프 밖).
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
