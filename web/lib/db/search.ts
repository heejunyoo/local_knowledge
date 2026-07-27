// P1-4: 검색 3모드 (D-4 확정 — 기본 tsvector, trgm/hybrid는 대기 경로만 구축)
// docs/REFACTOR_ACTION_PLAN_WEB_2026-07.md §P1-4
//
// 실제 랭킹/필터 로직은 전부 Postgres 함수 search_docs()에 있다
// (web/supabase/migrations/002_search_functions.sql, 003 수정 포함).
// 이 모듈은 그 함수를 호출하는 얇은 래퍼다 — 품질 튜닝은 여기서 하지 않는다.
//
// 비교 리포트: docs/FTS_COMPARISON_2026-07.md (게이트 아님, P5 판단 근거).

export type SearchMode = "tsvector" | "trgm" | "hybrid";

export interface SearchHit {
  docId: string;
  rank: number;
}

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;

const DEFAULT_OWNER_ID = "00000000-0000-0000-0000-000000000001";

/** settings['search.mode']를 읽는다. 없으면 D-4 기본값(tsvector). */
export async function getSearchMode(ownerId: string = DEFAULT_OWNER_ID): Promise<SearchMode> {
  const url = `${SUPABASE_URL}/rest/v1/settings?owner_id=eq.${ownerId}&key=eq.search.mode&select=value`;
  const res = await fetch(url, {
    headers: { apikey: SUPABASE_ANON_KEY, Authorization: `Bearer ${SUPABASE_ANON_KEY}` },
  });
  if (!res.ok) return "tsvector";
  const rows = (await res.json()) as { value: SearchMode }[];
  return rows[0]?.value ?? "tsvector";
}

/**
 * search_docs() RPC 호출. mode를 명시하지 않으면 settings['search.mode']를 조회한다.
 * P1에서는 tsvector가 게이트 대상이고 trgm/hybrid는 대기 경로이므로,
 * settings 기본값도 tsvector로 고정되어 있다 (migrate-from-sqlite.ts).
 */
export async function searchDocs(
  query: string,
  opts: { mode?: SearchMode; limit?: number; ownerId?: string } = {}
): Promise<SearchHit[]> {
  const mode = opts.mode ?? (await getSearchMode(opts.ownerId));
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/search_docs`, {
    method: "POST",
    headers: {
      apikey: SUPABASE_ANON_KEY,
      Authorization: `Bearer ${SUPABASE_ANON_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ q: query, search_mode: mode, match_limit: opts.limit ?? 20 }),
  });
  if (!res.ok) {
    throw new Error(`searchDocs failed: ${res.status} ${await res.text()}`);
  }
  const rows = (await res.json()) as { doc_id: string; rank: number }[];
  return rows.map((r) => ({ docId: r.doc_id, rank: r.rank }));
}
