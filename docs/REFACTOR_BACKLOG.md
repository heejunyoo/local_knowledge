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
  있음이 실제 사용자 영향).

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
