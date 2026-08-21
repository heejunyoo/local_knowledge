-- P1-2: 초기 스키마 (docs/REFACTOR_ACTION_PLAN_WEB_2026-07.md §P1-2 초안 기반)
-- 보정: diet_workout.id / diet_metric.id는 uuid가 아니라 text
--   (HealthKit 유입 id가 'hk-workout-<uuid>', 'hk-sleep-2026-07-07' 형태라 uuid 캐스팅 불가)
-- meeting / action_item / chunk_vector는 만들지 않음 (F-1, C-7)
-- RLS는 켜지 않음 (P3에서 일괄 활성화)
--
-- 2026-08-21 스키마 이전: 전 객체가 `public` → `today` 로 옮겨졌다. ingreed 가
-- 쓰는 프로젝트 안에 얹히므로 public 을 공유하지 않는다. 확장 선언은 000 으로
-- 옮겼고 `vector` 는 미사용이라 뺐다(000 주석).

create table today.settings (
  owner_id uuid not null default auth.uid(),
  key        text not null,
  value      jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (owner_id, key)
);

create table today.connected_source (
  id           text primary key,
  owner_id     uuid not null default auth.uid(),
  source_type  text not null,
  root_path    text,
  label        text,
  enabled      boolean not null default true,
  last_sync_at timestamptz,
  last_error   text,
  unit_count   integer not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index on today.connected_source (source_type);

create table today.knowledge_unit (
  unit_id      text primary key,
  owner_id     uuid not null default auth.uid(),
  source_type  text not null,                  -- 'obsidian' | 'notes'
  title        text,
  scope        text not null default 'personal',
  sot_kind     text not null,                  -- 'vault_md' | 'notes_app'
  sot_ref      text not null,
  content_hash text,
  in_corpus    boolean not null default true,
  rag_eligible boolean not null default true,
  updated_at   timestamptz not null default now()
);
create index on today.knowledge_unit (source_type);
create index on today.knowledge_unit (rag_eligible, in_corpus);

create table today.knowledge_chunk (
  chunk_id     text primary key,
  owner_id     uuid not null default auth.uid(),
  unit_id      text not null references today.knowledge_unit(unit_id) on delete cascade,
  ordinal      integer not null,
  text         text not null,
  content_hash text
);
create index on today.knowledge_chunk (unit_id);

create table today.note_mirror (
  notes_id      text primary key,
  owner_id      uuid not null default auth.uid(),
  folder        text,
  title         text,
  body_text     text,
  content_hash  text,
  body_status   text not null default 'ok',
  mirror_not_sot boolean not null default true,
  updated_at    timestamptz not null default now()
);

create table today.source_pointer (
  id            text primary key,
  owner_id      uuid not null default auth.uid(),
  source_type   text not null,
  external_id   text not null,
  title         text,
  scope         text not null default 'personal',
  notes_id      text,
  vault_rel_path text,
  updated_at    timestamptz not null default now(),
  unique (source_type, external_id)
);

-- 검색: fts_docs 대체. unit 1:1 유지 (C-6)
create table today.search_doc (
  doc_id      text primary key,
  owner_id    uuid not null default auth.uid(),
  source_type text not null,
  title       text,
  body        text,
  tsv tsvector generated always as (
    to_tsvector('simple', coalesce(title,'') || ' ' || coalesce(body,''))
  ) stored
);
-- gin_trgm_ops 는 extensions 스키마에 설치된 pg_trgm 의 것이다(000). search_path 에
-- extensions 가 있는지에 기대지 않고 명시한다.
create index search_doc_tsv_idx    on today.search_doc using gin (tsv);
create index search_doc_title_trgm on today.search_doc using gin (title extensions.gin_trgm_ops);
create index search_doc_body_trgm  on today.search_doc using gin (body  extensions.gin_trgm_ops);

-- diet: diet.json → 테이블화
-- id는 text (원본이 UUID 문자열 또는 'hk-workout-<uuid>'/'hk-sleep-<date>' 혼재)
create table today.diet_meal (
  id text primary key, owner_id uuid not null default auth.uid(),
  ts timestamptz not null, note text, items jsonb not null default '[]',
  kcal numeric, protein_g numeric
);
create table today.diet_workout (
  id text primary key, owner_id uuid not null default auth.uid(),
  ts timestamptz not null, kind text, minutes integer, intensity text
);
create table today.diet_metric (
  id text primary key, owner_id uuid not null default auth.uid(),
  ts timestamptz not null, weight_kg numeric, sleep_h numeric
);
-- goals / profile은 단일 행이므로 settings 테이블에 jsonb로 저장한다
-- (key='diet.goals', key='diet.profile') — 별도 테이블 금지: 스키마 증식 방지

-- D-3 확정: default-deny 상태기계 적용 대상 ①
create table today.inbox_item (
  id uuid primary key default gen_random_uuid(), owner_id uuid not null default auth.uid(),
  ts timestamptz not null default now(),
  text text not null,
  status text not null default 'open',        -- open|promoting|promoted|promote_failed
  promoted_path text,
  attempts integer not null default 0,
  error_code text,
  heartbeat_at timestamptz,
  updated_at timestamptz not null default now()
);

-- D-3 확정: default-deny 상태기계 적용 대상 ②
create table today.ingest_job (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid(),
  kind text not null,                         -- 'corpus_sync' | 'search_reindex'
  status text not null default 'queued',      -- queued|running|done|failed
  attempts integer not null default 0,
  error_code text,
  heartbeat_at timestamptz,
  detail jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index on today.ingest_job (status, heartbeat_at);

-- 상태 전이 감사 로그 (원본 pipeline_events의 축소 계승)
create table today.state_event (
  id bigserial primary key,
  owner_id uuid not null default auth.uid(),
  subject_kind text not null,                 -- 'inbox_item' | 'ingest_job'
  subject_id text not null,
  ts timestamptz not null default now(),
  from_status text, to_status text not null,
  rule text,
  error_code text
);
create index on today.state_event (subject_kind, subject_id);

create table today.llm_answer_cache (
  cache_key   text primary key,
  owner_id    uuid not null default auth.uid(),
  question    text not null,
  answer      jsonb not null,
  provider    text,
  created_at  timestamptz not null default now()
);
create index on today.llm_answer_cache (created_at);
