# 리팩토링 중 발견된 무관한 이슈 백로그

> `docs/REFACTOR_ACTION_PLAN_WEB_2026-07.md` §0.2: "눈에 띄는 무관한 문제는 여기 적고 넘어간다." 리팩토링 기간 중 새 항목만 추가한다 (F-6 기능 동결).

## P0에서 발견

- **vault 첨부파일 PII/금융 PDF 3건** (급여명세서·재직증명서·비자 오퍼) — P2-1(vault Git 레포 생성) 착수 전 오너가 유지/제외 결정 필요. 상세: `docs/DATA_INVENTORY_2026-07-27.md` §3.

## P1에서 발견

- **마이그레이션 5건 갭**: P0-8 드리프트로 생긴 unit 1건 + 원래 미인덱스였던 vault 파일 4건(`docs/DATA_INVENTORY_2026-07-27.md` §2 미인덱스 목록)은 백업 SQLite에 존재하지 않아 `migrate-from-sqlite.ts`로 이관하지 못했다. knowledge_unit 236/knowledge_chunk 590/source_pointer 236/search_doc 236까지만 이관됨(SQL 이관 가능한 전량). P4a 인제스트 구현 시 이 5건을 vault 파일에서 직접 읽어 추가한다.
- **search_doc.tsv URL 토큰화 차이 1건**: Postgres 기본 파서가 URL을 `host`/`url_path` 복합 토큰으로 묶어, URL 안에 포함된 단어(예: `.../standard-payments/api`의 "api")가 독립 검색어로 안 잡히는 경우가 있다(`docs/FTS_COMPARISON_2026-07.md` 실측 발견 2, q14 1건). D-4에 따라 튜닝하지 않고 accept. P5 실사용 중 반복되면 재평가.
- **[2026-07-28, G4a-6 재실행] 고빈도어 2건(결제/API)에서 bm25↔ts_rank 랭킹 경계 이탈**: `compare-search.ts`는
  anon 키만 써서 004_rls.sql(P3) 이후 RLS에 전량 차단돼 항상 빈 배열을 반환하는 상태였음(200 OK라
  조용히 통과) — `tests/regression/test-client.ts`와 동일한 admin.generateLink+verifyOtp 인증을
  추가해 수정(코드 변경, `web/scripts/compare-search.ts`). 실제 인증 세션으로 재실행한 결과 30개 중
  28개는 recall 100%, q01(결제, golden 20/실매치 28)·q14(API, golden 20/실매치 34)만 각각 65%/35%로
  하락. 원인은 corpus 드리프트나 유실이 아니라(golden doc_id 전부 `search_doc`에 존재하고 tsv 매치도
  됨을 확인) SQLite bm25와 Postgres ts_rank의 랭킹 알고리즘 차이 — 총 매치가 20건(match_limit)을
  넘는 고빈도어에서만 원래 top-20이던 문서 일부가 20건 윈도 밖으로 밀려남(결제 7건, API 13건이 각각
  idx 20~33 사이로 이동, API는 1건만 진짜 비매치). D-4가 이미 "튜닝 금지, 동등성만 확인" 원칙을
  정해뒀으므로 임의로 고치지 않았음 — 이 현상을 accept할지, 세컨더리 정렬 등으로 완화할지는 오너
  판단 필요(§P5 실사용 중 "결제"/"API" 같은 고빈도어 검색 시 스크롤 없이 안 보이는 결과가 있을 수
  있음이 실제 사용자 영향). `docs/FTS_COMPARISON_2026-07.md`의 q01/q14 100%/95%(top-500 기준)와
  숫자가 달라 보이는 이유는 같은 문서 "실측 발견 3"에 정리함 — D-4 모드 선택 결론은 안 바뀜.
  **[오너 결정 2026-07-29] Accept — 튜닝 안 함.** D-4 원칙 유지, match_limit·세컨더리 정렬 등
  임의 변경 금지. 종결.

## P2에서 발견

- **P0-5 시크릿 스캔 사각지대**: P0-5의 grep 패턴(`BEGIN .*PRIVATE|api[_-]?key|secret|password|token`)이 `95 🗑️ 아카이브/2022/토페업무/카드 일반 결제.md`의 `transactionKey`/`paymentKey` 값(Toss Payments 2022년 테스트 결제 응답, 거래별 식별자)을 놓쳤다 — 필드명이 패턴에 안 걸림. P2-1 첫 커밋 전 재스캔에서 발견해 오너 확인 후 4쌍 모두 `[REDACTED]`로 추가 리댁션했다(실제 커밋에는 포함 안 됨). 향후 유사 스캔 시 필드명이 아니라 "결제/거래 응답 JSON 전체"를 대상으로 봐야 한다는 교훈.
- **G2-4 해결 완료** (2026-07-27): 백업 워크플로 실행 → 1.45MB 덤프 생성 → 로컬 Postgres 17로 실제 복원 → 행수 P1 결과와 일치 확인. 해결 과정에서 드러난 문제 3건은 아래 참조.
- **[해결] direct connection이 CI에서 불가**: `db.<ref>.supabase.co:5432`는 무료 티어 IPv6 전용이고 GitHub Actions 러너는 IPv4 전용이라 `Network is unreachable`로 실패했다. Session Pooler(`aws-1-ap-south-1.pooler.supabase.com:5432`)로 전환해 해결. **실측 확정값과 "추측 조립 금지" 경고를 `docs/ENV_VARS.md` §Postgres 직결에 기록**했다. P1 시점에 ENV_VARS.md가 "IPv6라 접속 불가"까지만 적고 해결책을 안 남긴 탓에 P2에서 같은 벽에 다시 부딪혔다 — 실패는 원인만이 아니라 **해결책까지** 문서에 남길 것.
- **[해결] 빈 백업이 success로 커밋됨**: `pg_dump | gzip` 파이프에 `pipefail`이 없어 pg_dump 실패에도 gzip이 exit 0을 반환, 0바이트 백업이 "성공"으로 커밋됐다. `set -o pipefail` + 압축 해제 크기 검증(1000바이트 미만이면 실패)을 추가.
- **[해결] RESTORE.md 절차가 틀렸음**: "docker postgres:16에 psql로 부어라"라고 썼으나, `supabase db dump` 산출물은 `auth` 스키마·`anon`/`service_role` role·`vector` 타입을 전제해 순정 Postgres에서는 **테이블이 0개 생성된다**(실측 725 에러). 복원 대상별 분기 + 순정 Postgres용 prelude SQL + "에러 수백 건은 정상, 판정은 행수 대조"를 실측 기반으로 재작성했다.
- **Obsidian Git 플러그인 미설치**: vault에 커뮤니티 플러그인 `obsidian-git`이 설치되어 있지 않음(GUI 전용 설치라 자동화 불가). G2-1/G2-2는 git 레벨 왕복(별도 clone과의 push/pull)으로 대체 검증했으나, 실제 Obsidian 앱에서의 자동 커밋/pull 동작은 오너가 플러그인 설치 후 재확인 필요(`COMMIT_PROTOCOL.md` 설정값 안내 참조).

## P4a에서 발견

- **[해결 2026-07-28] corpus.status obsidian 8건 갭 원인 확인 — unit_id 충돌 아님**: 골든(P0,
  2026-07-27) 기준 `obsidian=225`, 라이브 `knowledge_unit` 조회는 `obsidian=217`(8건 갭). 이전
  기록은 "§P1 마이그레이션 5건 갭과 갯수가 안 맞아 두 obsidian 커넥터의 `unit_id` 충돌 가능성"을
  미검증 상태로 남겼으나, 라이브 DB 직접 조회로 완전히 재구성됨: `sot_ref like 'Meetings/%'`인
  obsidian 행이 라이브에 **0건**(migrate-from-sqlite.ts가 F-1 결정에 따라 정확히 7건을 의도적으로
  제외 — `where sot_ref not like 'Meetings/%'`), `CyberSourceKey` 참조 노트(P0-8 드리프트로 SQLite가
  224→225가 된 그 1건)도 라이브에 **부재**(백업 SQLite 시점에 없어 이관 대상 자체가 아니었음, 위
  "마이그레이션 5건 갭" 항목의 구성요소 중 하나). 즉 `225 = 217(라이브) + 7(Meetings, F-1 의도적
  제외) + 1(드리프트 unit, 마이그레이션 5건 갭에 이미 포함)` — 정확히 8로 정합. `unit_id` 충돌은
  없었고 유실된 데이터도 없다. `connected_source.unit_count`가 두 obsidian 커넥터(`obsidian-default`/
  `folder:ca0da96e`) 모두 같은 값을 보이는 것도 버그가 아니라 `syncConnectedSourceStats`/원본 Swift
  둘 다 `source_type` 단위로만 집계하기 때문(골든 자체에도 두 항목이 똑같이 225로 찍혀 있어 원본
  동작을 충실히 재현한 것). 남은 실제 조치 대상은 이미 추적 중인 "마이그레이션 5건 갭"(드리프트
  1건 + 미인덱스 4건, P4a 실 vault 재수집 시 처리, GitHub PAT 선행) 하나뿐이며 corpus.status
  자체의 정합성 문제는 없다. G4a-1이 corpus.status를 구조 검증만 하는 것도 계속 타당(값은 F-1
  스코프 조정으로 골든과 의도적으로 다름).

## P4a-9(상태기계 D-3)에서 발견

- **GitHub 기반 실제 vault 재수집 이월**: `corpus.sync`/`search.reindex`(`ingest_job` 상태기계)는
  이번 세션에서 GitHub PAT 없이 가능한 "DB 내부 실작업"으로만 연결했다 —
  `corpus.sync`는 `connected_source.unit_count`/`last_sync_at` 재계산(`syncConnectedSourceStats`,
  `web/lib/db/corpus.ts`), `search.reindex`는 `knowledge_unit` 중 `search_doc`에 없는 항목만
  upsert(`reindexMissingSearchDocs`, `web/lib/db/search.ts`). 원본 Swift가 하던 실제 obsidian/notes/
  files 재수집(vault 파일을 GitHub에서 읽어 `knowledge_unit`/`knowledge_chunk` 갱신)은 하지 않는다.
  `VAULT_GITHUB_TOKEN`(`docs/ENV_VARS.md`) 발급 후 별도 세션에서 두 워커를 GitHub Contents API 기반
  실제 수집 로직으로 교체할 것. 이때 위 항목의 "P1에서 발견 — 마이그레이션 5건 갭"도 함께 해소된다.
- **G4a-2(inbox.promote 실제 vault 커밋 왕복) 이월**: 같은 이유(PAT 미발급)로 미검증. `defaultVaultCommit`/
  `defaultVaultPathChecker`(`web/lib/db/inbox.ts`)는 구현 완료 상태이고 토큰만 없으면 안전하게
  `promote_failed`(error_code=`vault_token_missing`)로 떨어짐을 실 DB로 확인했다
  (`tests/regression/state-machine.regression.test.ts`). 토큰 발급 후 `knowledge-vault` 레포에
  실제로 커밋되는지, `10 📥 수집함/` 경로 한정이 지켜지는지만 확인하면 된다.

## P3에서 발견

- **RLS 무관 보안 경고 3건 (P3 이전부터 존재, 004_rls.sql 적용 후에도 남음)**: `get_advisors(security)` 기준
  (1) `public.search_docs` 함수 `search_path` 미고정(WARN), (2)(3) `pg_trgm`/`vector` 익스텐션이 `public`
  스키마에 설치됨(WARN, 별도 스키마로 이동 권장). P3 스코프(RLS·인증) 밖이라 손대지 않음 — 필요 시 별도 이슈로 처리.
  **[2026-07-29 갱신]** P6(C2)에서 `pg_net` 확장을 추가하며 같은 종류의 경고(`extension_in_public`)가
  1건 더 늘었다(총 4건) — 동일 원칙으로 이번 세션도 손대지 않음.

## P6에서 발견 (C2/P6, 2026-07-29)

- **[해결] Turbopack이 프로젝트 루트(`web/`) 밖 정적 import를 "Module not found"로 거부**: `web/lib/redaction.ts`가
  P4a부터 `../../docs/redaction_patterns.json`(리포 루트의 SoT JSON)을 정적 import해왔지만, 이 파일을
  실제로 쓰는 코드가 이번 P6(LLM router의 클라우드 호출 직전 redaction preflight) 전까지 하나도 없어서
  `vitest`(Vite 기반, 문제 없음) 테스트로만 검증됐고 Next.js 앱 런타임(Turbopack)에서는 한 번도 실행된 적이
  없었다. 이번에 처음 실제 라우트 체인(`app/api/ask` 등)에 연결되며 dev 서버에서 `Module not found`로
  드러났다 — 원인은 Turbopack이 프로젝트 루트를 `web/`으로 자동 추론해 그 밖의 경로(`../../docs/...`,
  `../../../config/...`) 접근을 차단한 것. `web/next.config.ts`에 `turbopack.root: path.join(__dirname, "..")`
  (리포 루트)를 명시해 해결, dev 서버로 기존 5라우트 + 신규 `/chat`·`/api/ask` 전부 재확인 완료. **`health.ingest`
  등 이번 P6 이전 코드는 `redaction.ts`를 쓰지 않아 이 버그가 실제 프로덕션에 영향을 준 적은 없다** — 하지만
  `web/lib/llm/catalog.ts`(`config/examples/llm_providers.json` 참조)도 같은 패턴이라 이 수정이 없었으면
  P6 전체가 런타임에서 깨졌을 것. 향후 리포 루트 파일을 정적 import하는 신규 코드를 추가할 때 이 설정이
  이미 있으니 별도 조치 불필요.
- **[해결, 2026-07-29] Vercel CLI 배포도 같은 함정의 변주 — `web/` 안에서 `vercel --prod`를 실행하면
  `docs/`·`config/`가 통째로 빠짐**: 위 Turbopack 수정 후 최초 프로덕션 배포 시도에서 같은
  `Module not found`가 재현됐다. 원인은 dev 서버와 다르다 — Turbopack 설정 문제가 아니라, Vercel CLI가
  현재 작업 디렉토리(`web/`)만 업로드 소스로 삼아 리포 루트 파일 자체가 서버에 존재하지 않았다.
  리포 루트(`KnowledgeApp/`)에서 `vercel link`+`vercel --prod`를 실행하고, 프로젝트의
  `rootDirectory: "web"`(Vercel API `PATCH /v9/projects/{id}`로 설정, `sourceFilesOutsideRootDirectory`는
  기본 `true`라 별도 설정 불필요)을 지정해 해결 — 리포 전체가 업로드되고 Vercel이 `web/`을 빌드 루트로
  쓰되 상위 파일도 포함한다. 상세 절차와 최종 배포 정보는 `docs/ENV_VARS.md` §Vercel 프로덕션 배포 참고.
- **[완료, 2026-07-31] diet.estimate_nutrition LLM 보강(C3)**: 오너가 "신기능으로 승인"했으나(원본 Swift엔
  이 기능 자체가 없음), P6(포팅) 작업과 성격이 달라 One Thing 원칙에 따라 P6 세션 스코프에서 제외했던 항목.
  별도 세션에서 구현 완료 — `web/lib/domain/diet-nutrition-llm.ts`(순수: 프롬프트·응답 검증·스케일링) +
  `web/lib/diet/nutrition-enrich.ts`(라우터·스토어 배선).
  - **LLM에는 100g/100ml 기준값만 묻는다**. 분량 곱셈은 우리가 한다 — 프롬프트가 음식명+단위에만 의존해
    "된장찌개 200g"과 "된장찌개 350g"이 같은 캐시 키를 쓰고(실측: 2회차 클라우드 호출 0회), 응답 검증이
    숫자 두 개의 범위 체크로 끝난다.
  - **카탈로그 매칭 시 LLM 호출 0회**. 미매칭일 때만 탄다.
  - 응답 계약은 **가산만** — `matched`(카탈로그 수록 여부)의 의미를 바꾸지 않고 `source`
    (`catalog`|`llm`|`generic`)를 추가했다. `/diet` 빠른입력은 `matched || source==="llm"`일 때 kcal까지
    저장한다. `diet.estimate_nutrition`은 골든 대상이 아니라(골든 러너가 무인자 `dispatch(method, {})`로
    호출) G4a-1 diff-0과 무관.
  - 응답 검증은 형식·범위(kcal 0~900, 단백질 0~100) + **물리 정합**(`protein×4 ≤ kcal+20` — 카탈로그 30종
    전부가 만족하는 부등식). 키 없음·스로틀 차단·파싱 실패·범위 밖·라우터 예외는 전부 규칙 기반
    추정치로의 폴백이고 에러가 아니다(G6-3과 같은 원칙).
  - **비목표(의도적 제외)**: 분량 추론. "된장찌개 한 그릇"처럼 숫자가 없는 문장의 g/ml을 LLM이 정하는 것은
    오너 결정으로 범위에서 뺐다 — 검증 대상이 늘고 캐시가 문장 단위가 돼 적중률이 떨어진다. 이 경우는 지금도
    `parse()`가 null을 반환해 UI가 원문만 저장하는 기존 동작 그대로다.
  - **미검증 1건**: 실 provider가 이 프롬프트에 어떤 형식으로 답하는지는 확인 못 했다(GROQ/GEMINI/OPENROUTER
    키 전부 미발급 — B3). 회귀 테스트는 fetch만 스텁하고 라우터·프로바이더 파싱·실 DB 캐시·검증·스케일링은
    실제 코드로 돌린다. B3 발급 후 실호출 1회로 종결 가능.
