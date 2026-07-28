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

// Swift 원본 SourceIngest.truncate()의 상한(200,000자)을 계승.
const MAX_BODY_CHARS = 200_000;

/**
 * search.reindex 워커 (ingest_job kind='search_reindex'). knowledge_unit 중
 * search_doc에 아직 없는 항목만 knowledge_chunk를 이어붙여 upsert한다 —
 * 기존 골든 행(P1 이관분)은 건드리지 않으므로 G4a-1/G4a-6 회귀 위험이 없다.
 * GitHub 불필요 — G4a-4 검증에 이 워커를 쓴다.
 */
export async function reindexMissingSearchDocs(): Promise<{ inserted: number }> {
  const supabase = await createClient();

  const [unitsRes, docsRes] = await Promise.all([
    supabase.from("knowledge_unit").select("unit_id,source_type,title"),
    supabase.from("search_doc").select("doc_id"),
  ]);
  if (unitsRes.error) throw unitsRes.error;
  if (docsRes.error) throw docsRes.error;

  const existing = new Set((docsRes.data ?? []).map((d) => d.doc_id));
  const missing = (unitsRes.data ?? []).filter((u) => !existing.has(u.unit_id));
  if (missing.length === 0) return { inserted: 0 };

  const { data: chunks, error: chunksError } = await supabase
    .from("knowledge_chunk")
    .select("unit_id,ordinal,text")
    .in(
      "unit_id",
      missing.map((u) => u.unit_id),
    )
    .order("ordinal", { ascending: true });
  if (chunksError) throw chunksError;

  const bodyByUnit = new Map<string, string[]>();
  for (const chunk of chunks ?? []) {
    const parts = bodyByUnit.get(chunk.unit_id) ?? [];
    parts.push(chunk.text);
    bodyByUnit.set(chunk.unit_id, parts);
  }

  const rows = missing.map((u) => ({
    doc_id: u.unit_id,
    source_type: u.source_type,
    title: u.title,
    body: (bodyByUnit.get(u.unit_id) ?? []).join("\n\n").slice(0, MAX_BODY_CHARS),
  }));

  const { error: insertError } = await supabase.from("search_doc").insert(rows);
  if (insertError) throw insertError;
  return { inserted: rows.length };
}
