-- diet_meal에 영양가 스냅샷 컬럼 5개를 추가한다.
--
-- 2026-08-17 오너 결정: /diet 에서 기성식품을 이름으로 검색해 1회 섭취량으로
-- 환산한 영양값(당·나트륨·포화지방)과 함께 식단에 기록한다. ingreed 제품
-- 데이터베이스(report_no로 식별)에서 조회한 영양값은 기록 시점의 스냅샷으로
-- 보존해야 한다. ingreed 룰셋이 바뀌어도 과거 식단 기록이 흔들리면 안 되기
-- 때문이다(D7). source는 레코드의 출처를 추적한다: 'ingreed'(제품DB조회) |
-- 'catalog'(자체DB) | 'llm'(LLM추정) | 'generic'(기본값).
--
-- 기존 행이 있으므로 not null 제약을 걸지 않는다. RLS 정책은 004_rls.sql의
-- owner_all 정책이 테이블 단위로 이미 적용되었으므로 재정의하지 않는다.

alter table diet_meal
  add column sugar_g numeric,
  add column sodium_mg numeric,
  add column satfat_g numeric,
  add column source text,
  add column ingreed_report_no text;
