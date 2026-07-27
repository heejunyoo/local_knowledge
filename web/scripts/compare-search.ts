// P1-4: 검색 골든(FTS5) 대비 신규 search_docs() 3모드 recall/precision 비교
// docs/REFACTOR_ACTION_PLAN_WEB_2026-07.md §P1-4, G1-3/G1-4
//
// 게이트는 "현행 대비 recall 하락 0"(tsvector 모드)이지 품질 개선이 아니다 (D-4).
// trgm/hybrid는 리포트 참고용으로만 기록한다.

import path from "node:path";
import fs from "node:fs";

const SUPABASE_URL = "https://gppklwzcmfuuhsefdeik.supabase.co";
const ANON_KEY =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdwcGtsd3pjbWZ1dWhzZWZkZWlrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODUxMzcyNTcsImV4cCI6MjEwMDcxMzI1N30.pQ9gmWSZdMfIqkbunwffgEj-cOTUZKBalq7KIW8smjA";

const GOLDEN_DIR = path.resolve(__dirname, "../tests/golden/search");
const queries = JSON.parse(fs.readFileSync(path.join(GOLDEN_DIR, "queries.json"), "utf8")) as {
  id: string; category: string; q: string;
}[];

async function searchDocs(q: string, mode: string): Promise<string[]> {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/search_docs`, {
    method: "POST",
    headers: {
      apikey: ANON_KEY,
      Authorization: `Bearer ${ANON_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ q, search_mode: mode, match_limit: 20 }),
  });
  if (!res.ok) throw new Error(`search_docs(${mode}) failed: ${res.status} ${await res.text()}`);
  const rows = (await res.json()) as { doc_id: string; rank: number }[];
  return rows.map((r) => r.doc_id);
}

function recallPrecision(golden: string[], candidate: string[]) {
  if (golden.length === 0) {
    return { recall: candidate.length === 0 ? 1 : 1, missed: 0, note: candidate.length > 0 ? "zero_hit인데 결과 발생" : "" };
  }
  const cSet = new Set(candidate);
  const hit = golden.filter((id) => cSet.has(id)).length;
  return { recall: hit / golden.length, missed: golden.length - hit, note: "" };
}

async function main() {
  const rows: string[] = [];
  rows.push("| id | category | q | golden# | tsvector recall | tsvector missed | trgm# | hybrid# |");
  rows.push("|---|---|---|---|---|---|---|---|");

  let worstRecall = 1;
  const missedQueries: string[] = [];

  for (const query of queries) {
    const goldenPath = path.join(GOLDEN_DIR, "results", `${query.id}.json`);
    const golden = JSON.parse(fs.readFileSync(goldenPath, "utf8")) as { doc_ids: string[] };
    const goldenIds = golden.doc_ids ?? [];

    const [tsv, trgm, hybrid] = await Promise.all([
      searchDocs(query.q, "tsvector"),
      searchDocs(query.q, "trgm"),
      searchDocs(query.q, "hybrid"),
    ]);

    const { recall, missed } = recallPrecision(goldenIds, tsv);
    if (recall < worstRecall) worstRecall = recall;
    if (missed > 0) missedQueries.push(`${query.id}(${query.q})`);

    rows.push(
      `| ${query.id} | ${query.category} | ${query.q} | ${goldenIds.length} | ${(recall * 100).toFixed(0)}% | ${missed} | ${trgm.length} | ${hybrid.length} |`
    );
  }

  console.log(rows.join("\n"));
  console.log(`\nworst tsvector recall: ${(worstRecall * 100).toFixed(1)}%`);
  console.log(missedQueries.length === 0 ? "G1-3 PASS: recall 하락 0건" : `G1-3 FAIL: 누락 쿼리 ${missedQueries.join(", ")}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
