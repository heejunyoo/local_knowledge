// P1-4: 검색 3모드 (D-4 확정 — 기본 tsvector, trgm/hybrid는 대기 경로만 구축)
// docs/REFACTOR_ACTION_PLAN_WEB_2026-07.md §P1-4
//
// 실제 랭킹/필터 로직은 전부 Postgres 함수 search_docs()에 있다
// (web/supabase/migrations/002_search_functions.sql, 003 수정 포함).
// 이 모듈은 그 함수를 호출하는 얇은 래퍼다 — 품질 튜닝은 여기서 하지 않는다.
//
// 비교 리포트: docs/FTS_COMPARISON_2026-07.md (게이트 아님, P5 판단 근거).
//
// P4a: RLS가 켜진 뒤(004_rls.sql)라 P1 당시의 anon key + 하드코드 owner_id
// REST 직접 호출은 더 이상 동작하지 않는다. 세션 클라이언트 + settings 캐시로
// 교체했다.
import { createClient } from "@/lib/supabase/server";
import { getSetting } from "@/lib/settings";

export type SearchMode = "tsvector" | "trgm" | "hybrid";

export interface SearchHit {
  docId: string;
  rank: number;
}

/** settings['search.mode']를 읽는다. 없으면 D-4 기본값(tsvector). */
export async function getSearchMode(): Promise<SearchMode> {
  return (await getSetting<SearchMode>("search.mode")) ?? "tsvector";
}

/**
 * search_docs() RPC 호출. mode를 명시하지 않으면 settings['search.mode']를 조회한다.
 */
export async function searchDocs(
  query: string,
  opts: { mode?: SearchMode; limit?: number } = {},
): Promise<SearchHit[]> {
  const mode = opts.mode ?? (await getSearchMode());
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("search_docs", {
    q: query,
    search_mode: mode,
    match_limit: opts.limit ?? 20,
  });
  if (error) throw error;
  return ((data ?? []) as { doc_id: string; rank: number }[]).map((r) => ({ docId: r.doc_id, rank: r.rank }));
}
