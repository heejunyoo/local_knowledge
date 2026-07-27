# 리팩토링 중 발견된 무관한 이슈 백로그

> `docs/REFACTOR_ACTION_PLAN_WEB_2026-07.md` §0.2: "눈에 띄는 무관한 문제는 여기 적고 넘어간다." 리팩토링 기간 중 새 항목만 추가한다 (F-6 기능 동결).

## P0에서 발견

- **vault 첨부파일 PII/금융 PDF 3건** (급여명세서·재직증명서·비자 오퍼) — P2-1(vault Git 레포 생성) 착수 전 오너가 유지/제외 결정 필요. 상세: `docs/DATA_INVENTORY_2026-07-27.md` §3.

## P1에서 발견

- **마이그레이션 5건 갭**: P0-8 드리프트로 생긴 unit 1건 + 원래 미인덱스였던 vault 파일 4건(`docs/DATA_INVENTORY_2026-07-27.md` §2 미인덱스 목록)은 백업 SQLite에 존재하지 않아 `migrate-from-sqlite.ts`로 이관하지 못했다. knowledge_unit 236/knowledge_chunk 590/source_pointer 236/search_doc 236까지만 이관됨(SQL 이관 가능한 전량). P4a 인제스트 구현 시 이 5건을 vault 파일에서 직접 읽어 추가한다.
- **search_doc.tsv URL 토큰화 차이 1건**: Postgres 기본 파서가 URL을 `host`/`url_path` 복합 토큰으로 묶어, URL 안에 포함된 단어(예: `.../standard-payments/api`의 "api")가 독립 검색어로 안 잡히는 경우가 있다(`docs/FTS_COMPARISON_2026-07.md` 실측 발견 2, q14 1건). D-4에 따라 튜닝하지 않고 accept. P5 실사용 중 반복되면 재평가.
