-- P3-2: RLS를 모든 테이블에 예외 없이 적용한다.
-- 액션플랜 원문(§P3-2)의 정책 SQL에 `to authenticated`를 추가했다 — Supabase 보안
-- 체크리스트 권고: TO 절 없이 USING만 쓰면 anon 역할도 정책 평가 대상이 되어 의도가
-- 흐려진다. owner_id는 전 테이블에 `default auth.uid()`가 있어(001_init.sql) 클라이언트가
-- 값을 채우지 않아도 INSERT 시 자동으로 채워진다.
--
-- 2026-08-21 스키마 이전: 전 테이블이 `today` 스키마에 있다. RLS 는 여전히
-- 필수다 — anon 은 스키마 USAGE 가 없어 애초에 도달하지 못하지만(000), 도달하는
-- authenticated 를 자기 행으로 묶는 것은 이 정책뿐이다. 두 겹 중 안쪽.

alter table today.settings           enable row level security;
alter table today.connected_source   enable row level security;
alter table today.knowledge_unit     enable row level security;
alter table today.knowledge_chunk    enable row level security;
alter table today.note_mirror        enable row level security;
alter table today.source_pointer     enable row level security;
alter table today.search_doc         enable row level security;
alter table today.diet_meal          enable row level security;
alter table today.diet_workout       enable row level security;
alter table today.diet_metric        enable row level security;
alter table today.inbox_item         enable row level security;
alter table today.ingest_job         enable row level security;
alter table today.state_event        enable row level security;
alter table today.llm_answer_cache   enable row level security;

create policy owner_all on today.settings
  for all to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create policy owner_all on today.connected_source
  for all to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create policy owner_all on today.knowledge_unit
  for all to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create policy owner_all on today.knowledge_chunk
  for all to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create policy owner_all on today.note_mirror
  for all to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create policy owner_all on today.source_pointer
  for all to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create policy owner_all on today.search_doc
  for all to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create policy owner_all on today.diet_meal
  for all to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create policy owner_all on today.diet_workout
  for all to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create policy owner_all on today.diet_metric
  for all to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create policy owner_all on today.inbox_item
  for all to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create policy owner_all on today.ingest_job
  for all to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create policy owner_all on today.state_event
  for all to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create policy owner_all on today.llm_answer_cache
  for all to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());
