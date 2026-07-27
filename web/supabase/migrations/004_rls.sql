-- P3-2: RLS를 모든 테이블에 예외 없이 적용한다.
-- 액션플랜 원문(§P3-2)의 정책 SQL에 `to authenticated`를 추가했다 — Supabase 보안
-- 체크리스트 권고: TO 절 없이 USING만 쓰면 anon 역할도 정책 평가 대상이 되어 의도가
-- 흐려진다. owner_id는 전 테이블에 `default auth.uid()`가 있어(001_init.sql) 클라이언트가
-- 값을 채우지 않아도 INSERT 시 자동으로 채워진다.

alter table settings           enable row level security;
alter table connected_source   enable row level security;
alter table knowledge_unit     enable row level security;
alter table knowledge_chunk    enable row level security;
alter table note_mirror        enable row level security;
alter table source_pointer     enable row level security;
alter table search_doc         enable row level security;
alter table diet_meal          enable row level security;
alter table diet_workout       enable row level security;
alter table diet_metric        enable row level security;
alter table inbox_item         enable row level security;
alter table ingest_job         enable row level security;
alter table state_event        enable row level security;
alter table llm_answer_cache   enable row level security;

create policy owner_all on settings
  for all to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create policy owner_all on connected_source
  for all to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create policy owner_all on knowledge_unit
  for all to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create policy owner_all on knowledge_chunk
  for all to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create policy owner_all on note_mirror
  for all to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create policy owner_all on source_pointer
  for all to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create policy owner_all on search_doc
  for all to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create policy owner_all on diet_meal
  for all to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create policy owner_all on diet_workout
  for all to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create policy owner_all on diet_metric
  for all to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create policy owner_all on inbox_item
  for all to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create policy owner_all on ingest_job
  for all to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create policy owner_all on state_event
  for all to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create policy owner_all on llm_answer_cache
  for all to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());
