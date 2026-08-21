# 웹 전환 리팩토링 — 현재 상태 (새 세션은 이 파일부터 읽을 것)

| Field | Value |
|-------|-------|
| 최종 갱신 | 2026-07-31 |
| 현재 위치 | **C2 완전 완료** + **P6 1~7단계 완료** + **Vercel 프로덕션 배포 완료(2026-07-29)**. `web/` 프로덕션 URL `https://web-rho-lovat-34.vercel.app`(Vercel 프로젝트 `luckyhyun/knowledge-web`, Root Directory=`web`). 필수 환경변수 6종(Supabase 4종+`INGEST_API_TOKEN`+`CRON_SECRET`) 등록 완료, 실 로그인으로 6라우트+`/api/ask` 스모크 확인. C2는 **이메일 채널 폐기 → 앱 내 표시로 종결**(2026-07-29, 마이그레이션 007로 cron·함수·Vault 되돌림). P6은 LLM 캐시/라우팅(캐스케이드)/RAG(ask·askFast)/RPC/`/chat`까지 전부 구현·테스트 완료. P6·C2 작업물은 2026-07-29 커밋 완료(`P6-1`/`P6-2`/`C2`/`chore`/`docs` 5개 — 직전 세션이 구현·검증만 하고 커밋 전에 중단돼 있었음). **프로덕션 URL은 `https://hj-knowledge.vercel.app`으로 교체**(2026-07-31, Vercel 프로젝트 도메인으로 정식 등록 — 이전 `web-rho-lovat-34.vercel.app`은 프로젝트 생성 시 자동 생성된 무작위 별칭이라 서비스와 무관했다. 둘 다 살아 있고 배포 시 양쪽에 붙는다). **로그인은 비밀번호 방식**(매직링크는 복구용으로 강등, `web/scripts/set-password.ts`로 최초 설정). **C3(`diet.estimate_nutrition` LLM 보강)은 2026-07-31 완료** — 도메인 186개·regression 35개 전부 통과, `next build` 성공. **다음 남은 것은 전부 오너의 외부 자격증명 발급 대기: B4(Google OAuth 클라이언트, 최우선) · B3(`GEMINI_API_KEY`/`OPENROUTER_API_KEY`) · B1(GitHub PAT)** |
| 다음 세션 읽기 순서 | ① 이 파일 ② "다음 작업 — MECE 분류" §B부터 ③ 막히면 `REFACTOR_BACKLOG.md`("P6에서 발견" 최신 포함) |
| 결정 근거 | `docs/REFACTOR_DIRECTION_WEB_2026-07.md` (D-3 정의 §2.2) |
| 미해결 이슈 | `docs/REFACTOR_BACKLOG.md` |
| 작업 브랜치 | `refactor/web-p0` |

## ⚠ 먼저 읽을 것 — DB 이전 진행 중 (2026-08-21)

### ⑴ 옛 Knowledge 프로젝트는 정지가 아니라 **삭제**됐다

8/20 기록은 "무료 티어 7일 무활동 정지로 보인다 → Resume 클릭 1회"였다.
**그 진단이 틀렸다.** 교차 확인한 것:

| 증거 | 내용 |
|---|---|
| ingreed `docs/ops/05-migration.md` §8 · `NEXT.md` | "옛 프로젝트 삭제 — 완료(2026-08-11)" |
| ingreed `packages/ui/src/config.ts` 주석 | 그 옛 프로젝트가 곧 **`gppklwzcmfuuhsefdeik`(뭄바이)** |
| `knowledge-backup` 워크플로 | 8/9 성공 → **8/16 실패**, `tenant/user postgres.gppklwzcmfuuhsefdeik not found` |
| DNS·REST | A 레코드 없음 · HTTP 000 (정지라면 도메인은 살아 540 을 준다) |

두 앱이 **한 Supabase 프로젝트를 공유**하고 있었고, ingreed 를 싱가포르로 옮기며
그 프로젝트를 지울 때 Knowledge DB 가 함께 사라졌다. Resume 버튼은 없다.

**데이터 손실은 없다.** 옛 DB 의 마지막 활동이 7/31 이라 8/2 와 8/9 덤프는 바이트가
같다(1,493,017). 8/9 덤프에 public 데이터 **1,583행**이 전부 들어 있다.

### ⑵ 새 자리 — ingreed 프로젝트 안의 `today` 스키마

프로젝트를 새로 세우지 않는다. 개인 앱은 트래픽이 없어 무활동 정지 대상이 되고
이번에 실제로 그렇게 잃었다(keepalive cron 도 못 막았다). **ingreed 는 공개
서비스라 깨어 있다** — 거기 얹히면 같이 산다. 실측으로 확인한 여유:

| | |
|---|---|
| ingreed DB | **231MB / 500MB** · dead tuple 0 · 캐시 히트율 heap 99.74% |
| 오늘의 나가 쓸 자리 | 1,583행 · 테이블 14 · 인덱스 10 → **10MB 안팎**(추정) |
| 진짜 예산 | 용량이 아니라 `shared_buffers` **229MB**. 지금 DB 231MB 가 거기 딱 맞아 저하가 멎었다 |

그래서 **ingreed NEXT.md 13번(소스 검색 커버리지 복구 · +63MB 추정)은 뒤로 미룬다** —
캐시를 깨는 순간 그 대가를 오늘의 나가 같이 문다.

### 코드·마이그레이션은 준비 끝 (브랜치 `feat/today-schema-on-ingreed-project`)

| 한 것 | |
|---|---|
| `000_schema.sql` 신설 | 스키마·권한. **anon 에게 USAGE 조차 주지 않는다** — ingreed 의 "두 겹"과 같은 층수를 RLS 바깥에 하나 더 세운 것 |
| `001`~`005`·`008`·`009` | 전 객체 `public` → `today`. 테이블 14 · 정책 14 |
| `002` | `today.search_docs()` 로 옮기며 `search_path` 고정. SECURITY INVOKER 유지(DEFINER 로 바꾸면 RLS 를 넘는다) |
| `006`·`007` | **적용 제외.** 006 을 007 이 전부 되돌리므로 건너뛰면 결과가 같다. 적용하면 ingreed 프로덕션에 pg_cron·pg_net 이 심긴다 |
| 확장 | `vector` 제거 — 8/9 덤프 전수 확인 결과 **vector 컬럼이 하나도 없다**. `pg_trgm` 만 남긴다 |
| 코드 | `lib/supabase/schema.ts` 의 `DB_SCHEMA` 한 곳. supabase-js 가 Accept-Profile 헤더로 보내므로 **`.from()` 61곳·`.rpc()` 을 고치지 않았다** |
| `scripts/restore-into-today.sh` | 8/9 덤프 → `today` 적재 + **owner_id 재매핑** + 행수 판정 |
| 백업 워크플로 | `--schema today` 로 좁히고 혼입 가드 2개(실동작 3케이스 확인). 안 고치면 ingreed 218MB 가 매주 커밋된다 |

검증: `npm run test` **27 files / 274 tests** · `npx next build` 성공.

### ✅ 적용까지 끝났다 (2026-08-21)

| 단계 | 결과 |
|---|---|
| 드라이런 | 트랜잭션 안에서 000~009 실행 후 rollback — 문법·권한·확장 전부 통과, 흔적 0 |
| 마이그레이션 적용 | 테이블 14 · 인덱스 25 · 정책 14 · RLS 14 · 함수 1. **`ingreed` 스키마 8테이블 그대로** |
| PostgREST 노출 | `db_schema` = `public,graphql_public,today` (Management API) |
| owner 계정 | `f7da16fd-9394-4967-8010-db236d49dadf` (naheejun87@gmail.com) |
| 데이터 복원 | 8/9 덤프 **1,583행** 전량 · 14테이블 행수 판정 전부 일치 · `state_event` 시퀀스 212 · `search_doc.tsv` 236행 재생성 |
| 용량 | DB 231 → **243MB / 500MB** · `today` **11MB** (추정 "10MB 안팎"과 일치) |

**보안 두 겹을 실제로 확인했다.** anon 키로 `Accept-Profile: today` 를 붙여 직접
찔렀더니 `42501 permission denied for schema today` — 노출 설정이 켜져 있어도
바깥 겹이 막는다.

**ingreed 는 영향받지 않았다.** 적용 전·후·PostgREST 재빌드 후 3회 `smoke_rpc.ts`
7종 전부 통과(134~830ms, 이전과 같은 구간).

검증: `npm run test` 274 · `npm run test:regression` **6 files / 35 tests 통과**
(실 DB · RLS · 골든 비교 포함) · `npx next build` 성공.

### 배선까지 끝났다 (2026-08-21)

| | 결과 |
|---|---|
| Vercel 프로덕션 env | 4종 교체 + **`INGREED_URL`·`INGREED_ANON_KEY` 신규**. 이 둘이 로컬·Vercel 어디에도 없어 **1단계 ingreed 연동이 실제로는 꺼져 있었다** |
| 재배포 | `knowledge-faah52ast` Ready. 배포된 번들에서 새 프로젝트 URL 확인 · 옛 ref 잔존 0 |
| `knowledge-backup` | 시크릿 교체 + 워크플로 전환. 첫 성공본 `knowledge-20260821.sql.gz` (473KB · today COPY 14블록 · ingreed 혼입 0) |

**백업 워크플로는 세 번 실패하고서 고쳤다. 둘 다 내가 심은 것이다.**

1. `--schema today` 를 준 **supabase CLI 덤프에 데이터가 하나도 담기지 않았다**(2회 재현).
   `--dry-run` 으로 뽑은 pg_dump 인자는 정상이었고 같은 인자를 로컬 pg_dump 17.10 으로
   실행하면 COPY 14블록이 나온다. `--exclude-schema ""` 유무도 갈라 봤지만 둘 다 14였다.
   차이가 "CLI 가 도커 안에서 감싼다"뿐이라 **CLI 를 걷고 같은 이미지를 직접 부른다.**
2. 그 다음 실행은 덤프가 정상(data 1,404,938바이트)인데도 실패했다. 가드가
   `gunzip -c | grep -q` 였다 — grep -q 가 첫 매치에서 끝나면 gunzip 이 SIGPIPE 로
   죽고 `pipefail` 이 파이프라인 실패로 잡는다. **매치가 있을 때만 실패하는 가드**였다.
   압축 푼 것을 파일로 놓고 세는 쪽으로 바꿨다.

### 👤 남은 것 — 오너만 할 수 있다

1. **로그인** — 비밀번호가 아직 없다. 둘 중 하나
   ```bash
   cd web && npx tsx scripts/set-password.ts            # 직접 정한다(입력은 가려진다)
   cd web && npx tsx scripts/generate-magic-link.ts naheejun87@gmail.com https://hj-knowledge.vercel.app
   ```
2. **`/diet`·'오늘' 화면 실렌더링 확인** — 서버 라우트가 새 DB 를 보는지는 로그인 뒤에야
   눈으로 확인된다. 클라이언트 번들이 새 프로젝트를 가리키는 것까지는 확인했다
3. **ingreed 제품 검색 왕복 재확인** — 위 env 두 개가 이제야 붙었다. `/diet` 에서
   "김치사발면" → 80g(용기) → 354kcal 이 8/20 실측값이다

### ⑶ ingreed 쪽 부하는 그대로 남는다

3일 유휴 뒤 `ingreed_search` 가 `57014 statement timeout` 을 오간다(8.5s→500 · 49.6s→200).
우리 폴백이 견디는 것은 확인했다. **같은 인스턴스에 얹은 뒤에도 폴백을 걷지 않는다** —
"ingreed 가 느리다 = 나도 느리다"가 되므로 오히려 더 필요하다.

## ingreed 제품 영양 연동 1단계 (2026-08-17~20, 커밋 `f18a50b`·`9f9617e`·`d3cc2c5`)

`/diet` 에서 기성식품을 이름으로 검색해 **1회 섭취량으로 환산한 영양값**(당·나트륨·
포화지방 포함)과 함께 기록한다. 근거·설계 판단은 `.claude/specs/ingreed-diet-nutrition/spec.md`,
Phase 계획은 같은 폴더 `plan.json`.

| Phase | 상태 | 산출물 |
|---|---|---|
| p1 순수 도메인 + 마이그레이션 파일 | ✅ | `lib/domain/serving-size.ts` · `lib/domain/ingreed-nutrition.ts` · `supabase/migrations/008_diet_meal_nutrition.sql`(**미적용**) |
| p2 클라이언트 + DB + RPC | ✅ | `lib/diet/ingreed-client.ts` · `diet.search_product` · `diet.log_product_meal` |
| p3 화면 + 미리보기 | ✅ | `app/diet/page.tsx` ProductPanel · `diet.preview_product` |

검증: `npm run test` **24 files / 224 tests** · `npx next build` 성공.
실서비스 왕복 확인 — 김치사발면 → 80g(용기) → 354kcal · 나트륨 1414mg.

**하루 건강 점수·등급은 이번 범위가 아니다(2단계).** ingreed 의 A~E 는 100g 기준·
카테고리 상대 등급이라 그대로 더할 수 없다. 그래서 `diet_meal` 에 `grade` 컬럼을
**일부러 만들지 않았다** — 경계를 주석이 아니라 스키마로 강제한다.

2단계에 남은 진짜 문제: **등급 컷을 정할 분포가 없다.** ingreed 는 `ratable` 제품
실측 분포로 컷을 잡았는데, 하루 점수는 사용자가 1명이라 분포가 없다. 외부 기준
(KDRIs 등)을 원문으로 확인해 가져와야 한다 — 하위 모델에 넘길 일이 아니다.

## Phase 진행 상황

| Phase | 상태 | 산출물 |
|---|---|---|
| P0 기준선 동결 | ✅ | `DATA_INVENTORY_2026-07-27.md`, `web/tests/golden/` |
| P1 스키마+이관 | ✅ | `web/supabase/migrations/`, `migrate-from-sqlite.ts` |
| P2 Vault→Git | ✅ | 레포 2개 신규(아래) |
| P3 인증 | ✅ | Next 스캐폴드 + `004_rls.sql` + `proxy.ts` |
| P4a 읽기 API | ✅ 구현 11/11, 게이트 G4a-1/3/4/5 통과. G4a-2/G4a-6은 외부 의존(PAT/재실행)이라 이월 유지 | 아래 |
| **P4b diet 쓰기 + health.ingest** | ✅ 게이트 G4b-1~G4b-3 통과, G4b-4 이월(발화 채널 미결정) | 아래 |
| **P5 웹 UI** | ✅ 구현 완료(chat 제외 5라우트), G5-1~G5-5 전부 통과 | 아래 |
| **P6 생성 경로 이식** | ✅ 캐시/라우팅/RAG/RPC/`/chat` 전부 구현, G6-1~G6-5 통과 | 아래 |
| **C3 estimate_nutrition LLM 보강** | ✅ **완료(2026-07-31)** — 카탈로그 미매칭 음식만 LLM으로 보강. 실 provider 응답 형식만 미검증(B3 키 대기) | 아래 |
| **C2 단식 리마인더** | ✅ **이메일 채널 폐기, 앱 내 표시로 종결(2026-07-29 오너 결정)** — 마이그레이션 007로 cron·함수·Vault 되돌림, Resend 코드 전부 삭제. `RESEND_API_KEY` 불필요 | 아래 |
| P7 | ⬜ | — |

## P5 게이트 현황

| 게이트 | 상태 |
|---|---|
| G5-1 폰 브라우저에서 URL만으로 로그인 → 전부 동작 | ✅ Chrome 확장 연결 후 좁은 뷰포트(500×667)로 매직링크 로그인 + 5라우트 전부 시각 확인(검색은 실제 검색어 "food"로 결과 렌더링까지 확인) |
| G5-2 데스크톱 브라우저 동일 | ✅ 1280×900 뷰포트로 5라우트 전부 시각 확인 |
| G5-3 PWA 설치 후 홈 화면 아이콘으로 실행 가능 | 🟡 manifest.json 파싱(`display: standalone`, 아이콘 2종)·서비스워커 `activated` 상태를 페이지 내 JS로 확인. 실제 폰 홈 화면 설치는 Chrome 확장으로 재현 불가 — 오너 몫으로 이월 |
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
| G4b-4 단식 리마인더 실제 발화 | 🟡 **채널 결정(이메일) + 인프라 완료(2026-07-29)**, 실제 자동 발화는 Vercel 배포 후 Vault 시크릿 등록+`cron.schedule()`로 이월(`docs/ENV_VARS.md` §C2) |

## P6 게이트 현황 (2026-07-29, 커밋 `P6-1`/`P6-2`)

| 게이트 | 상태 |
|---|---|
| G6-1 정상 응답 시 출처(unit_id) 포함 | ✅ `tests/regression/knowledge-ask-rpc.regression.test.ts` 실 DB 확인 |
| G6-2 캐스케이드(첫 provider 무효/실패 → 다음 provider 전이) | ✅ `tests/domain/llm-router.test.ts` |
| G6-3★ 전면 실패 시 extractive(에러 아님) | ✅ 클라우드 키 전부 없음/전부 실패 두 케이스 모두 `tests/domain/llm-router.test.ts` + 실 DB `tests/regression/rag-ask.regression.test.ts`(로컬에 클라우드 키가 없어 자연 발생하는 케이스로 재확인) |
| G6-4 캐시(동일 prompt 2회차 provider 호출 0회) | ✅ `tests/domain/llm-router.test.ts` |
| G6-5 redaction(민감 패턴 시 클라우드 요청 자체 미발생) | ✅ `tests/domain/llm-router.test.ts` |

구현 범위: `web/lib/llm/{cache,db-cache-store,throttle,catalog,secrets,providers,router}.ts`,
`web/lib/rag/{query-terms,synthesize,prompt,citations,ask}.ts`, `web/lib/domain/chat.ts`,
`handlers.ts`의 `knowledge_ask`/`knowledge_ask_fast`/`chat_send`, `POST /api/ask`·`/api/chat`,
`/chat` 페이지(+ BottomNav 6번째 탭). 로컬 7B 폴백 단계는 서버리스 환경상 이식 불가로 명시적
스킵(클라우드 실패 시 바로 extractive) — 액션플랜이 허용한 throttle 재구현(DB/settings 기반)과
동급의 유일한 재설계. `llm_answer_cache` 테이블은 P1(`001_init.sql`)에 이미 존재해 신규 마이그레이션
불필요했음. 상세 설계·판단 근거는 `docs/REFACTOR_BACKLOG.md` "P6에서 발견" 참고(Turbopack 프로젝트
루트 버그 등).

## C2 종결 (단식 리마인더 — 이메일 폐기 → 앱 내 표시, 2026-07-29)

**최종 상태**: 이메일 채널을 전면 폐기했다. 판단 근거는 리마인더의 알맹이가 이미 도메인
계층에 있었다는 점이다 — `fastingStatus()`가 `goal_met`을 계산해 `label`("목표 14h 달성 ·
공복 14.2h")과 `hint`("목표 공복을 채웠어요")를 만들고 `/diet`가 이미 렌더링하고 있었다.
이메일이 담당한 건 "앱을 열지 않아도 알려주는" 푸시 성격뿐이었고, 개인용 서비스 하나를 위해
외부 서비스 계정·API 키·5분 주기 pg_cron·pg_net 아웃바운드를 유지할 가치가 없다고 판단했다.

제거: `web/lib/email/`, `/api/cron/fasting-reminder`, `FastingSession.reminderSentAt`,
`markFastingReminderSent()`, 관련 테스트 2파일. DB는
`007_drop_fasting_reminder_cron.sql`로 `cron.unschedule` + 함수 drop + Vault 시크릿 2종 삭제
(적용 후 `cron.job` 0건·함수 0건·시크릿 0건 확인). `private` 스키마와 `pg_net`은 남겼다.
추가: `goal_met`일 때 `/diet` 단식 카드에 "✓ 목표 달성" 배지 + 초록 진행바. 배지 글자색은
green-500이 아니라 grey-900 — `#03b26c`는 green-50 배경 대비 2.5:1로 WCAG AA 미달이라
P5의 blue-500 접근성 감점을 반복하지 않기 위함.

아래는 폐기 전 구현 기록(히스토리).

### (폐기됨) 구현 상세

`FastingSession`에 `reminderSentAt` 필드 추가(웹 신규, 원본에 없음) → `web/lib/email/resend.ts`
(Resend REST, `RESEND_API_KEY` 미설정 시 스킵) → `web/app/api/cron/fasting-reminder/route.ts`
(DB 접근 없는 순수 발송기 — `health-ingest.ts` 1곳 한정 `SUPABASE_SERVICE_ROLE_KEY` 예외를 넓히지
않기 위한 설계) → `web/supabase/migrations/006_fasting_reminder_cron.sql`의
`private.trigger_fasting_reminder()`(SECURITY DEFINER, `pg_net.http_post`로 위 라우트 호출 후
`reminder_sent_at` 기록, anon/authenticated EXECUTE 권한 revoke 확인 완료).
`tests/domain/fasting-reminder.test.ts` + `tests/regression/fasting-reminder.regression.test.ts`
전부 통과.

**2026-07-29 후속(Vercel 배포 직후 완결)**: Vault 시크릿 2종
(`fasting_reminder_target_url`=프로덕션 URL, `cron_secret`=`CRON_SECRET`과 동일 값) 등록 완료,
`select private.trigger_fasting_reminder();` 수동 실행으로 에러 없음 확인 후
`cron.schedule('fasting-reminder', '*/5 * * * *', 'select private.trigger_fasting_reminder();')`
등록 완료(job id=1). `RESEND_API_KEY`가 아직 미발급이라 실제 이메일 발송은 조건 충족 시에도
`web/lib/email/resend.ts`에서 조용히 스킵된다(에러 아님) — 키 발급만 하면 별도 배포 없이 다음
5분 주기부터 바로 실발송 전환.

## C3 (estimate_nutrition LLM 보강, 2026-07-31)

카탈로그 30종(`diet-nutrition-calc.ts`)이 못 맞춘 음식만 LLM으로 메운다. 그 전까지 카탈로그 밖
음식은 일반식 평균(150kcal/100g)으로 떨어지고 `/diet` 빠른입력이 그 값을 버려서, 사실상 열량
기록이 안 되고 있었다.

**설계 3줄**: ① LLM에는 **100g/100ml 기준값만** 묻고 분량 곱셈은 우리가 한다 — 프롬프트가
음식명+단위에만 의존해 같은 음식이면 분량이 달라도 캐시가 적중한다(실측 확인). ② 카탈로그가
맞춘 음식은 **LLM 호출 0회**. ③ 응답 계약은 가산만 — `matched`(카탈로그 수록 여부)는 그대로 두고
`source`(`catalog`|`llm`|`generic`)를 추가, UI는 `matched || source==="llm"`에서 kcal을 저장한다.

응답 검증은 형식·범위(kcal 0~900 / 단백질 0~100) + 물리 정합(`protein×4 ≤ kcal+20`). 키 없음·
스로틀 차단·파싱 실패·범위 밖·라우터 예외는 **전부 규칙 기반 추정치로의 폴백**이고 에러가 아니다
(G6-3과 같은 원칙).

산출물: `web/lib/domain/diet-nutrition-llm.ts`(순수), `web/lib/diet/nutrition-enrich.ts`(배선),
`handlers.ts::diet_estimate_nutrition`, `estimateAsDict`의 `source` 인자, `/diet` 빠른입력 조건,
`tests/domain/diet-nutrition-llm.test.ts`(19종), `tests/regression/diet-estimate-nutrition.regression.test.ts`(4종).
`lib/llm/*`는 변경 없이 재사용.

**검증**: 도메인 186개 / regression 35개 전부 통과, `npx tsc --noEmit`·`next build` 성공.
dev 서버 + 매직링크 세션으로 `/api/rpc` 실호출 3종(카탈로그 `source:catalog` / 미매칭
`source:generic` 폴백 / 자유 텍스트) 확인 — 새 모듈이 `/api/rpc` 체인에 LLM 라우터를 처음
끌어들이므로 리포 루트 JSON 정적 import(Turbopack 경계, 백로그 "P6에서 발견")가 실제로 로드되는지도
같이 확인됐다.

**미검증 1건**: 실 provider가 이 프롬프트에 어떤 형식으로 답하는지(B3 키 3종 전부 미발급).
회귀 테스트는 fetch만 스텁하고 라우터·프로바이더 파싱·실 DB 캐시(`llm_answer_cache`, 테스트 후
행 삭제 확인)·검증·스케일링은 실제 코드로 돌린다 — 키 발급 후 실호출 1회로 종결 가능.

**비목표**: 분량 추론("된장찌개 한 그릇" → g). 오너 결정으로 제외 — 상세는
`REFACTOR_BACKLOG.md` "P6에서 발견"의 C3 항목.

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

**2026-07-28 추가 세션**: Chrome 확장 연결 후 G5-1/G5-2 마무리 —
매직링크 로그인(`generate-magic-link.ts`) → 좁은 뷰포트(500×667)·데스크톱
(1280×900) 두 뷰포트로 5라우트 전부 시각 확인, 검색은 실 검색어 "food"로
결과 렌더링까지 확인. G5-3은 manifest.json 파싱(`display: standalone`,
아이콘 2종)·서비스워커 `activated` 상태를 페이지 내 JS로 확인(실기기 홈
화면 설치 자체는 Chrome 확장으로 재현 불가 — 오너 몫 유지).

검증 중 Inbox에서 2026-07-10에 남은 테스트 데이터
(`inbox_item` id `67ebfe19`/`4cd08f3f`, text "dogfood final inbox"/
"dogfood inbox full", status=promoted) 발견 — 오너 확인 후 SQL로 삭제,
Inbox 빈 상태(empty state) 렌더링까지 재확인.

**2026-07-28 A1/A2 세션**: 아래 "다음 작업" §A 두 항목 완료.
`compare-search.ts`가 P3(RLS) 이후로도 anon 키만 써서 실제로는 항상 빈 결과를
반환하던 버그를 발견해 인증 로직 추가 후 재실행(코드 변경 있음 — "재실행만
필요" 전제가 실제로는 틀렸음). corpus.status obsidian 8건 갭은 `knowledge_unit`
직접 조회로 완전히 재구성해 unit_id 충돌 가설을 기각. 상세는 `REFACTOR_BACKLOG.md`
"P4a에서 발견" 최신 두 항목, 요약은 아래 §A 표.

## 다음 작업 — MECE 분류 + 자체 스코어링 (2026-07-29 갱신)

**2026-07-29 세션 요약**: C1(P6 착수)·C2(단식 리마인더 이메일) 둘 다 오너 승인 하에
완료(위 "P6 게이트 현황"·"C2 상세" 참고). 아래 §B/§C는 그 결과로 새로 갱신됨 —
이전 버전의 C1/C2 항목은 제거하고 B3(신규 API 키·배포)·C3(diet.estimate_nutrition)로 대체.

분류 기준(차단 요인, 상호배타적): **A=블로커 없음(지금 바로 착수 가능)
/ B=오너의 외부 자격증명·값 발급이 선행조건 / C=오너의 정책·설계 결정
자체가 산출물(CLAUDE.md 안전 바닥 대상 포함)**. 스코어는 5점 척도
(Impact=완료 시 가치, Effort=소요 노력·낮을수록 쉬움, Urgency=지금
안 하면 손해가 커지는 정도). 우선순위는 Impact 대비 Effort로 판단하되
Urgency가 동률을 깬다.

### A. 블로커 없음 — 완료(2026-07-28)

| 항목 | 결과 |
|---|---|
| **A1. G4a-6** 검색 골든 30건 재실행 | ⚠️ **예상과 다름 — `compare-search.ts` 코드 변경 필요했음**. 004_rls.sql(P3) 이후 anon 키 단독 호출은 RLS에 전량 차단돼(200 OK+빈 배열) 재실행만으로는 무의미 — `test-client.ts`와 동일한 인증(admin.generateLink+verifyOtp)을 추가해 수정. 실제 인증 결과: 30건 중 28건 recall 100%, q01(결제)·q14(API) 2건만 65%/35% — 원인은 corpus 유실이 아니라 총 매치 20건(match_limit) 초과 시 SQLite bm25 vs Postgres ts_rank 랭킹 차이로 원래 top-20 문서 일부가 윈도 밖으로 밀림(문서 자체는 존재·매치 확인). D-4가 "튜닝 금지" 원칙이라 임의 수정 안 함 — accept 여부는 오너 판단 필요. 상세: `REFACTOR_BACKLOG.md` "P4a에서 발견" 최신 항목 |
| **A2. corpus.status** obsidian 225(골든) vs 217(라이브) 8건 갭 원인 조사 | ✅ **완전 해명, unit_id 충돌 없음**. `knowledge_unit` 직접 조회로 `225 = 217(라이브) + 7(Meetings, F-1 의도적 제외, 라이브에 0건 확인) + 1(P0-8 드리프트 unit, 마이그레이션 5건 갭에 이미 포함, 라이브 부재 확인)`로 정확히 정합. 이전 백로그의 "두 obsidian 커넥터 unit_id 충돌 가능성" 가설은 기각(데이터 유실 없음, `connected_source.unit_count` 공유는 원본 Swift와 동일한 source_type 단위 집계 방식). 상세: `REFACTOR_BACKLOG.md` "P4a에서 발견" |

두 항목 모두 착수 자체는 문제 없었으나, A1은 실행 중 코드 버그(스크립트 인증 누락)를 발견해 고쳐야 했고 결과 자체는 "게이트 형식 종결"이 아니라 새로운 (작지만 실제) 오너 판단 대상을 하나 남김 — MECE 표의 Effort 추정(1)이 실측보다 낮았던 사례로 기록.

### B. 오너의 외부 자격증명/값 발급이 선행조건 (발급 후엔 Effort 낮음)

| 항목 | Impact | Effort | Urgency | 비고 |
|---|---|---|---|---|
| **B1. G4a-2** GitHub PAT 발급 → inbox 왕복(vault 실제 커밋) 검증 | 4 | 2 | 3 | 검증 자체는 가벼우나, 여기 딸린 **후속 구현**(`corpus.sync`/`search.reindex`를 DB 내부 계산에서 GitHub Contents API 기반 실제 재수집으로 교체, `REFACTOR_BACKLOG.md` "P4a-9에서 발견")은 Effort 4~5의 별도 작업 — PAT 발급이 그 전체 체인의 진짜 병목 |
| ~~**B2. INGEST_API_TOKEN** Vercel 환경변수 정식 발급/등록~~ | — | — | — | **완료(2026-07-29)** — B3에 통합, 랜덤 토큰 생성+Vercel Production 등록 완료 |
| **B3. LLM API 키 발급·등록** (2026-07-31 갱신: 프로덕션에 키 0종) | 4 | 1 | 3 | ~~Vercel 배포~~·~~INGEST_API_TOKEN~~·~~CRON_SECRET~~ **완료(2026-07-29)**. ~~`RESEND_API_KEY`~~ **불필요해짐**(이메일 채널 폐기). 남은 건 ① `GEMINI_API_KEY`(aistudio.google.com/apikey), ② `OPENROUTER_API_KEY`(openrouter.ai/keys) — P6 캐스케이드 2·3순위(`GROQ_API_KEY`만으로도 골격은 동작하지만 groq 실패 시 폴백 없이 extractive로 떨어짐). 발급 후 `vercel env add <KEY> production` 대행 가능. **2026-07-31 갱신**: `vercel env ls production` 실측 결과 **프로덕션에 LLM 키가 하나도 없다**(등록된 6종은 Supabase 4종·`INGEST_API_TOKEN`·`CRON_SECRET`뿐 — `GROQ_API_KEY`조차 없음). 즉 `/chat`·`/api/ask`는 지금 항상 extractive로, C3(estimate_nutrition LLM 보강)는 항상 규칙 기반으로 떨어진다(둘 다 에러는 아님, 설계된 폴백). 키 1종만 등록해도 세 경로가 동시에 살아난다 — Impact를 3→4로 상향 |
| **B4. Google OAuth 클라이언트 발급** (2026-07-29 신규) | 2 | 1 | 1 | **2026-07-31: 우선순위 강등**(5/1/4 → 2/1/1). 이 항목의 목적이던 "로그인 진입 마찰"은 비밀번호 로그인 도입으로 해소됐다 — Google은 이제 있으면 좋은 선택지일 뿐 병목이 아니다. 아래는 원문. 로그인 진입 마찰 해소. 오너가 console.cloud.google.com에서 OAuth 클라이언트(웹) 생성 → 승인된 리디렉션 URI에 `https://gppklwzcmfuuhsefdeik.supabase.co/auth/v1/callback` 등록 → client ID/secret을 Supabase 대시보드 Authentication→Providers→Google에 입력. 코드 쪽(`/login` Google 버튼·스타일링)은 선행 완료. **리스크**: `disable_signup: true`라 최초 Google 로그인이 신규가입으로 막힐 수 있음 — 이론상 이메일 확인된 기존 계정과 자동 identity 연결되어 통과해야 하나 실측 필요. 막히면 가입을 잠깐 열고 연결 후 재차단(uid는 어느 쪽이든 보존) |

**추천 순서(2026-07-31 재갱신)**: B3(LLM 키) → B1(GitHub PAT) → B4(Google, 선택).
B3는 키 **1종만** 등록해도 `/chat`·`/api/ask`·C3 세 경로가 한꺼번에 살아난다(지금 프로덕션
LLM 키 0종). B1은 P4a-9 이월 전체를 여는 별개 열쇠. B4는 비밀번호 로그인 도입으로 병목에서
빠졌다.

### C. 오너의 정책·설계 결정 자체가 산출물 (결정 전엔 착수 불가)

| 항목 | Impact | Effort | Urgency | 비고 |
|---|---|---|---|---|
| ~~**C3. diet.estimate_nutrition LLM 보강**~~ | — | — | — | **완료(2026-07-31)** — 위 "C3" 절 참고. 실 provider 응답 형식만 B3 대기 |

**§C는 현재 비어 있다** — 오너의 정책·설계 결정을 기다리는 항목이 없다. 남은 것은 전부 §B(자격증명 발급).

### 종합 권장 순서

1. ~~(지금 바로) A1 → A2~~ — **완료(2026-07-28)**
2. ~~C1(P6 착수)·C2(단식 리마인더 채널)~~ — **완료(2026-07-29)**, 결과는 위
   "P6 게이트 현황"·"C2 상세" 참고
3. ~~Vercel 배포·INGEST_API_TOKEN·CRON_SECRET~~ — **완료(2026-07-29)**,
   `luckyhyun/knowledge-web` 프로덕션 배포+환경변수 등록+C2 cron.schedule까지 완결
3-1. ~~P6/C2 커밋~~ — **완료(2026-07-29)**. 재검증 후 5개 커밋으로 정리:
   `npm run test` 167개 / `npm run test:regression` 33개 전부 통과, `next build` 성공
3-2. ~~C2 이메일 채널 폐기 → 앱 내 표시~~ — **완료(2026-07-29)**, 마이그레이션 007
4. (오너에게 요청, 최우선) **B4 Google OAuth 클라이언트 발급** — 로그인 진입 마찰의 유일한 병목
5. (오너에게 요청) B3 LLM 키 2종(GEMINI/OPENROUTER) 발급 —
   대행 불가(제3자 계정 인증), 발급 후 등록은 제가 `vercel env add`로 대행 가능
6. (오너에게 요청) B1 GitHub PAT 발급 — 별개 체인(P4a-9 이월 해소)
7. ~~C3 diet.estimate_nutrition LLM 보강~~ — **완료(2026-07-31)**, 위 "C3" 절 참고.
   A1이 남긴 검색 랭킹 경계는 이미 accept로 종결(`REFACTOR_BACKLOG.md`)

**이 시점에서 블로커 없는 작업은 남아 있지 않다.** 4~6번(B4/B3/B1)은 전부 오너가 외부
서비스에서 값을 발급해야 착수 가능하고, 발급 후 등록·검증은 대행 가능하다.

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
