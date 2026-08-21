-- 실측 발견 (P1-4 검증 중): search_doc.tsv 생성 컬럼이 본문에 등장하는 리터럴
-- '<...>' 문자열(예: 마크다운 코드 예시 속 "<script>")을 Postgres 기본 파서가
-- 미종결 HTML 태그로 오인해, 그 지점부터 문서 끝까지 전체가 통째로 색인에서
-- 누락되는 문제를 발견했다 (unit obsidian:d9522168412d27536965d703에서 585개 중
-- 399개 단어 소실 확인). FTS5(unicode61)는 이런 특수 처리가 없어 정상 색인되므로
-- 이는 골든 대비 recall 손실의 실제 원인이었다 (G1-3, docs/FTS_COMPARISON_2026-07.md).
-- 대응: 색인 대상 텍스트에서 '<' '>' 를 공백으로 치환한 뒤 tsvector를 생성한다.
-- 이는 언어적 튜닝(형태소·동의어 등)이 아니라 파서 오탐 방지이며, D-4가 금지한
-- "품질 개선"이 아니라 FTS5와의 동등성 확보에 해당한다.
--
-- 2026-08-21 스키마 이전: `today` 로 옮겼다. 001 을 직접 고치지 않고 이 파일을
-- 남겨 두는 이유는 위 발견 자체가 기록이기 때문이다.
alter table today.search_doc drop column tsv;
alter table today.search_doc add column tsv tsvector generated always as (
  to_tsvector('simple', replace(replace(coalesce(title,'') || ' ' || coalesce(body,''), '<', ' '), '>', ' '))
) stored;
create index search_doc_tsv_idx on today.search_doc using gin (tsv);
