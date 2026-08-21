/**
 * 오늘의 나가 쓰는 Postgres 스키마 이름.
 *
 * `public` 이 아니다. 이 DB 는 ingreed 프로젝트 안에 얹혀 있고, public 에는
 * ingreed 의 전달 함수(`ingreed_*`)가 산다. 우리 테이블은 `today` 스키마에
 * 격리돼 있으며 anon 역할에는 스키마 USAGE 조차 주지 않는다
 * (web/supabase/migrations/000_schema.sql).
 *
 * supabase-js 는 이 값을 PostgREST 의 Accept-Profile / Content-Profile 헤더로
 * 보낸다. 따라서 `.from(...)` 과 `.rpc(...)` 가 모두 이 스키마를 향한다 —
 * 호출부 61곳을 고칠 필요가 없는 이유다.
 *
 * ⚠ ingreed 조회는 여기를 타지 않는다. lib/diet/ingreed-client.ts 는
 *   `/rest/v1/rpc/...` 를 fetch 로 직접 부르고 그쪽은 public 스키마다.
 */
export const DB_SCHEMA = "today";
