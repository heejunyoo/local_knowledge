-- P1-4: 검색 3모드 (D-4 확정 — 기본 tsvector, trgm/hybrid는 대기 경로만 구축)
-- docs/REFACTOR_ACTION_PLAN_WEB_2026-07.md §P1-4
-- 품질 튜닝 금지: 게이트는 "현행 대비 recall 하락 0"(동등)이지 개선이 아니다.

create or replace function search_docs(q text, search_mode text default 'tsvector', match_limit int default 20)
returns table(doc_id text, rank real)
language plpgsql
stable
as $$
begin
  if search_mode = 'tsvector' then
    return query
      select sd.doc_id, ts_rank(sd.tsv, plainto_tsquery('simple', q))::real as rank
      from search_doc sd
      where sd.tsv @@ plainto_tsquery('simple', q)
      order by rank desc
      limit match_limit;
  elsif search_mode = 'trgm' then
    return query
      select sd.doc_id,
             greatest(similarity(coalesce(sd.title, '')::text, q), similarity(coalesce(sd.body, '')::text, q))::real as rank
      from search_doc sd
      where coalesce(sd.title, '') % q or coalesce(sd.body, '') % q
      order by rank desc
      limit match_limit;
  elsif search_mode = 'hybrid' then
    return query
      select combined.doc_id, max(combined.rank) as rank
      from (
        select sd.doc_id, ts_rank(sd.tsv, plainto_tsquery('simple', q))::real as rank
        from search_doc sd
        where sd.tsv @@ plainto_tsquery('simple', q)
        union all
        select sd.doc_id,
               greatest(similarity(coalesce(sd.title, '')::text, q), similarity(coalesce(sd.body, '')::text, q))::real as rank
        from search_doc sd
        where coalesce(sd.title, '') % q or coalesce(sd.body, '') % q
      ) combined
      group by combined.doc_id
      order by rank desc
      limit match_limit;
  else
    raise exception 'unknown search_mode: %', search_mode;
  end if;
end;
$$;
