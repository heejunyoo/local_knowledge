# 리팩토링 중 발견된 무관한 이슈 백로그

> `docs/REFACTOR_ACTION_PLAN_WEB_2026-07.md` §0.2: "눈에 띄는 무관한 문제는 여기 적고 넘어간다." 리팩토링 기간 중 새 항목만 추가한다 (F-6 기능 동결).

## P0에서 발견

- **vault 첨부파일 PII/금융 PDF 3건** (급여명세서·재직증명서·비자 오퍼) — P2-1(vault Git 레포 생성) 착수 전 오너가 유지/제외 결정 필요. 상세: `docs/DATA_INVENTORY_2026-07-27.md` §3.

## P1에서 발견

- **마이그레이션 5건 갭**: P0-8 드리프트로 생긴 unit 1건 + 원래 미인덱스였던 vault 파일 4건(`docs/DATA_INVENTORY_2026-07-27.md` §2 미인덱스 목록)은 백업 SQLite에 존재하지 않아 `migrate-from-sqlite.ts`로 이관하지 못했다. knowledge_unit 236/knowledge_chunk 590/source_pointer 236/search_doc 236까지만 이관됨(SQL 이관 가능한 전량). P4a 인제스트 구현 시 이 5건을 vault 파일에서 직접 읽어 추가한다.
- **search_doc.tsv URL 토큰화 차이 1건**: Postgres 기본 파서가 URL을 `host`/`url_path` 복합 토큰으로 묶어, URL 안에 포함된 단어(예: `.../standard-payments/api`의 "api")가 독립 검색어로 안 잡히는 경우가 있다(`docs/FTS_COMPARISON_2026-07.md` 실측 발견 2, q14 1건). D-4에 따라 튜닝하지 않고 accept. P5 실사용 중 반복되면 재평가.

## P2에서 발견

- **P0-5 시크릿 스캔 사각지대**: P0-5의 grep 패턴(`BEGIN .*PRIVATE|api[_-]?key|secret|password|token`)이 `95 🗑️ 아카이브/2022/토페업무/카드 일반 결제.md`의 `transactionKey`/`paymentKey` 값(Toss Payments 2022년 테스트 결제 응답, 거래별 식별자)을 놓쳤다 — 필드명이 패턴에 안 걸림. P2-1 첫 커밋 전 재스캔에서 발견해 오너 확인 후 4쌍 모두 `[REDACTED]`로 추가 리댁션했다(실제 커밋에는 포함 안 됨). 향후 유사 스캔 시 필드명이 아니라 "결제/거래 응답 JSON 전체"를 대상으로 봐야 한다는 교훈.
- **G2-4 미완**: `knowledge-backup` 워크플로(`db-backup.yml`)는 작성·push 완료했지만, `SUPABASE_DB_URL` 레포 Secret 등록은 오너가 GitHub 웹 UI에서 직접 해야 하는 항목(비밀정보이므로 세션에서 다루지 않음). 등록 후 `gh workflow run db-backup.yml --repo heejunyoo/knowledge-backup`으로 수동 실행하고, RESTORE.md 절차로 실제 복원 1회를 수행해야 G2-4가 완결된다.
- **Obsidian Git 플러그인 미설치**: vault에 커뮤니티 플러그인 `obsidian-git`이 설치되어 있지 않음(GUI 전용 설치라 자동화 불가). G2-1/G2-2는 git 레벨 왕복(별도 clone과의 push/pull)으로 대체 검증했으나, 실제 Obsidian 앱에서의 자동 커밋/pull 동작은 오너가 플러그인 설치 후 재확인 필요(`COMMIT_PROTOCOL.md` 설정값 안내 참조).
