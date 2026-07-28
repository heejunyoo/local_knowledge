# 검색 비교 리포트 — tsvector/trgm/hybrid vs FTS5 골든 (P1-4)

> `docs/REFACTOR_ACTION_PLAN_WEB_2026-07.md` P1-4 산출물. 게이트 아님(G1-3는 등가 여부만 판정), 참고 자료.
> 방법: `web/scripts/compare-search.ts` — `web/tests/golden/search/queries.json` 30개 쿼리를 `search_docs()`(P1-2 migration, 002/003)로 재실행하고, 전체 매치 집합(top-500) 기준으로 골든(FTS5) doc_id 집합과 대조.

## 결과 (전체 매치 집합 기준 recall)

| id | category | q | 골든# | tsvector recall | trgm# | hybrid# |
|---|---|---|---|---|---|---|
| q01 | noun | 결제 | 20 | 100% | 1 | 28 |
| q02 | noun | 임베딩 | 7 | 100% | 0 | 7 |
| q03 | noun | 모델 | 9 | 100% | 0 | 9 |
| q04 | noun | 데이터 | 15 | 100% | 0 | 15 |
| q05 | noun | 리서치 | 7 | 100% | 0 | 7 |
| q06–q10 | particle | 결제를/모델이/데이터는/임베딩을/리서치를 | 1–3 | 100% | 0 | 동일 |
| q11 | english_tech | RAG | 17 | 100% | 0 | 17 |
| q12 | english_tech | Docker | 8 | 100% | 3 | 8 |
| q13 | english_tech | LLM | 9 | 100% | 1 | 9 |
| **q14** | english_tech | **API** | 20 | **95% (19/20)** | 0 | 34 |
| q15 | english_tech | GenAI | 5 | 100% | 1 | 5 |
| q16–q20 | mixed_ko_en | Reverse Proxy 등 | 0–5 | 100% | 0–3 | 동일+α |
| q21–q25 | multi_word | 리서치 구조화 등 | 1–3 | 100% | 0–3 | 동일+α |
| q26–q30 | zero_hit | (무의미 문자열) | 0 | 100% | 0 | 0 |

**tsvector recall: 30개 중 29개 완전 일치(100%), 1개(q14 "API") 95% — G1-3 실질 통과로 판단.**

## ★ 실측 발견 1 — search_doc.tsv 생성 컬럼의 치명적 토큰화 버그 (수정 완료)

최초 측정 시 q01/q04/q14/q20에서 대량 recall 손실(최저 30%)이 나타났다. 원인 추적 결과:

- `unit obsidian:d9522168412d27536965d703`의 본문에 마크다운 코드 설명으로 등장한 리터럴 `` `<script>` `` 문자열을 Postgres 기본 파서가 **미종결 HTML 태그**로 인식해, 그 지점부터 **문서 끝까지 전체(약 585 단어 중 399단어, 68%)가 색인에서 통째로 누락**되고 있었다.
- FTS5(`unicode61`)는 이런 HTML 태그 특수 처리가 없어 정상 색인되므로, 이것이 recall 손실의 실제 원인이었다(q01/q04/q20이 하필 이 한 문서를 포함하는 쿼리였음).
- **이는 언어적 튜닝이 아니라 파서 오탐 방지**이므로 D-4가 금지한 "품질 개선"에 해당하지 않는다고 판단해 즉시 수정했다: `web/supabase/migrations/003_fix_search_doc_tag_truncation.sql` — 색인 대상 텍스트의 `<`/`>`를 공백으로 치환 후 `to_tsvector`.
- 수정 후 q01/q04/q20은 100% 회복.

## ★ 실측 발견 2 — q14 "API" 1건 누락 (수정하지 않음, 알려진 한계로 accept)

- 누락 문서 `obsidian:d8899618456c6392ed98c5c5`는 `https://developers.google.com/standard-payments/api` 같은 URL을 본문에 포함한다. Postgres 기본 파서는 URL을 `host`/`url_path` 토큰으로 특수 분류해 `standard-payments/api` 전체를 **하나의 복합 토큰**으로 색인한다 — "api"가 독립 단어로 존재하지 않는다.
- FTS5(`unicode61`)는 이런 URL 특수 처리가 없어 `/`를 구분자로 보고 "api"를 독립 토큰으로 분리하므로, 이 1건에서만 차이가 발생한다.
- D-4 지침("trgm 튜닝에 시간을 쓰지 마세요")에 따라 URL 파서 우회(정규식으로 슬래시를 전부 공백 치환 등)는 적용하지 않는다 — 위 실측 발견 1과 달리 이건 "전체 소실 버그"가 아니라 "URL 내부 단어 1개가 다른 토큰으로 분류되는" 정상적인 파서 차이이고, 영향 범위가 이 쿼리 1건·문서 1건에 그친다.
- P4a/P5에서 실사용 중 유사 패턴이 반복되면 그때 재평가한다.

## P5에서 확인할 것
1. 체감 개선 여부 (tsvector가 실사용에서 충분한지)
2. trgm 오탐(무관 문서 혼입) 정도 — 표의 trgm# 열이 tsvector#보다 작거나 0인 쿼리가 많아, 현재 trgm 경로는 아직 정밀도가 낮아 보조 랭킹 신호로만 쓰기에도 검증이 더 필요하다.
3. 응답 지연 차이

## D-4 최종 결정 (2026-07-28, P5)

`search_docs()`를 실 DB(owner 코퍼스, 236 단위) 대상으로 "결제"·"API" 두
쿼리에 대해 3모드 EXPLAIN ANALYZE로 직접 재확인했다.

1. **체감 개선 없음** — trgm은 "결제"에서 1건만 반환했고 그 1건도 이미
   tsvector 28건에 포함된 문서였다(순수 부분집합, 신규 회수 0). "API"에서는
   trgm이 0건이라 위 §실측 발견 2의 누락 1건도 복구하지 못했다. 두 쿼리
   모두 hybrid 결과 집합이 tsvector와 완전히 동일해, hybrid가 얹는 것은
   지연뿐 실질적 recall 이득이 없었다.
2. **trgm 오탐이 아니라 회수 자체가 안 됨** — 우려했던 "무관 문서 혼입"보다
   더 근본적으로, trgm이 이 코퍼스 규모·언어(한국어 위주)에서 tsvector가
   이미 찾은 문서조차 거의 못 찾는다(정밀도 이전에 재현율 문제).
3. **응답 지연** — tsvector 5.5ms vs trgm 86ms vs hybrid 87.8ms
   (EXPLAIN ANALYZE Execution Time, "결제" 기준). trgm 경로는 tsvector 대비
   약 16배 느리다.

**결론: `search.mode = tsvector` 확정.** trgm/hybrid는 이번 코퍼스 규모에서
이득이 없고 지연만 늘려 P5 이후에도 대기 경로로만 남긴다(코드 삭제하지
않음 — 코퍼스가 훨씬 커지거나 오탈자 검색 요구가 생기면 재평가).
`settings['search.mode']`는 이미 `'tsvector'`로 설정되어 있어 추가 반영
불필요(P1에서 명시적으로 기록된 값, 변경 없음).
