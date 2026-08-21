-- 000: `today` 스키마와 권한 — 오늘의 나가 ingreed 프로젝트에 얹히는 자리.
--
-- 옛 Knowledge 프로젝트(gppklwzcmfuuhsefdeik)는 삭제됐다. 새 DB 는 ingreed 가
-- 쓰는 프로젝트 안에 **별도 스키마**로 세운다. 프로젝트를 따로 두지 않는 이유는
-- 성능이 아니라 생존이다 — 개인 앱은 트래픽이 없어 무활동 정지 대상이 되고,
-- 이번에 실제로 그렇게 잃었다. ingreed 는 공개 서비스라 깨어 있다.
--
-- ⚠ 이 스키마는 ingreed 프로덕션 DB 안에 만들어진다. `ingreed` 스키마의
--   테이블·함수를 이 마이그레이션들은 **건드리지 않는다**.
--
-- ## 권한 — anon 에게는 아무것도 주지 않는다
--
-- ingreed 는 "스키마 미노출 + SECURITY DEFINER 전달 함수" 두 겹으로 261,257행을
-- 막는다. 오늘의 나는 테이블 CRUD 가 61곳이라 전달 함수로 감쌀 수 없다. 대신
-- 같은 두 겹을 이렇게 만든다:
--   ① anon 은 스키마 USAGE 자체가 없다 → PostgREST 가 노출해도 도달하지 못한다
--   ② authenticated 는 도달하되 RLS `owner_id = auth.uid()` 로 자기 행만 (004)
-- 노출 설정이 실수로 바뀌어도 ①이 남는다.
--
-- public 스키마에는 Supabase 이벤트 트리거가 anon 에게 기본 GRANT 를 주지만,
-- 새 스키마에는 그것이 걸리지 않는다. 그래서 여기 적힌 것이 권한의 전부다.

create schema if not exists today;

-- PUBLIC(모든 역할)에 붙는 기본 권한을 먼저 걷어낸다.
revoke all on schema today from public;

grant usage on schema today to authenticated, service_role;

-- 앞으로 이 스키마에 만들어질 객체의 기본 권한. anon 은 목록에 없다.
alter default privileges in schema today
  grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema today
  grant usage, select on sequences to authenticated;
alter default privileges in schema today
  grant execute on functions to authenticated;

alter default privileges in schema today
  grant all on tables to service_role;
alter default privileges in schema today
  grant all on sequences to service_role;
alter default privileges in schema today
  grant all on functions to service_role;

-- pg_trgm 은 search_doc 의 trgm 인덱스(001)와 검색 trgm 모드(002)가 쓴다.
-- Supabase 관례대로 extensions 스키마에 둔다. ingreed 는 자체 bigram 함수를
-- 쓰므로 `%` 연산자나 similarity_threshold 와 충돌하지 않는다.
create extension if not exists pg_trgm with schema extensions;

-- 옛 001 에 있던 `create extension vector` 는 가져오지 않는다.
-- 8/9 백업 덤프를 전수 확인한 결과 **vector 컬럼이 하나도 없다** — 검색은
-- tsvector 로 확정됐고(docs/FTS_COMPARISON_2026-07.md), 임베딩은 쓴 적이 없다.
-- 쓰지 않는 확장을 프로덕션 DB 에 심지 않는다.
