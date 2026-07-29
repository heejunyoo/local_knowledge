// 검색은 P1이 확정한 방식(search_docs() RPC + search_doc 조인, doc-level) 그대로
// 재사용한다 — 원본 LocalRetrieve(BM25+구조+이웃+MMR, chunk-level)는 재이식하지
// 않는다(액션플랜 §P6-5, D-4 "게이트는 동등, 튜닝 금지"와 일치).
import { createClient } from "@/lib/supabase/server";
import { searchDocs } from "@/lib/db/search";

export interface Citation {
  unitId: string;
  title: string;
  sourceType: string;
  snippet: string;
  score: number;
}

/**
 * knowledge_search(RPC)와 knowledge.ask/askFast가 공유하는 검색+조인 헬퍼.
 * snippet은 ask() LLM 컨텍스트/synthesize용으로 knowledge_search의 UI용
 * 160자보다 길게(600자) 자른다 — 응답 스니펫 계약(160자)은 핸들러 쪽에 남긴다.
 */
export async function fetchCitations(q: string, opts: { limit: number }): Promise<Citation[]> {
  const hits = await searchDocs(q, { limit: opts.limit });
  if (hits.length === 0) return [];

  const supabase = await createClient();
  const { data: docs, error } = await supabase
    .from("search_doc")
    .select("doc_id,source_type,title,body")
    .in(
      "doc_id",
      hits.map((h) => h.docId),
    );
  if (error) throw error;
  const byId = new Map((docs ?? []).map((d) => [d.doc_id, d]));

  return hits.map((h) => {
    const doc = byId.get(h.docId);
    const body: string = doc?.body ?? "";
    return {
      unitId: h.docId,
      title: doc?.title ?? "",
      sourceType: doc?.source_type ?? "unknown",
      snippet: body.slice(0, 600),
      score: h.rank,
    };
  });
}
