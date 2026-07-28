// P1-4: 검색 골든(FTS5) 대비 신규 search_docs() 3모드 recall/precision 비교
// docs/REFACTOR_ACTION_PLAN_WEB_2026-07.md §P1-4, G1-3/G1-4
//
// 게이트는 "현행 대비 recall 하락 0"(tsvector 모드)이지 품질 개선이 아니다 (D-4).
// trgm/hybrid는 리포트 참고용으로만 기록한다.

import path from "node:path";
import fs from "node:fs";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import dotenv from "dotenv";

dotenv.config({ path: path.join(__dirname, "..", ".env.local") });

// 004_rls.sql(P3)로 search_doc에 owner_all RLS가 걸리면서 anon 키 단독 호출은
// auth.uid() 없이 전부 필터링돼 빈 배열만 돌아온다(200 OK라 조용히 통과) —
// tests/regression/test-client.ts와 같은 admin.generateLink+verifyOtp로 실 세션을
// 발급해 호출해야 골든 대비 비교가 의미를 가진다.
const OWNER_EMAIL = "naheejun87@gmail.com";

const GOLDEN_DIR = path.resolve(__dirname, "../tests/golden/search");
const queries = JSON.parse(fs.readFileSync(path.join(GOLDEN_DIR, "queries.json"), "utf8")) as {
  id: string; category: string; q: string;
}[];

function requireEnv(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`missing env ${name} (check web/.env.local)`);
  return v;
}

async function authenticate(): Promise<SupabaseClient> {
  const url = requireEnv("NEXT_PUBLIC_SUPABASE_URL");
  const anonKey = requireEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY");
  const serviceKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");

  const admin = createClient(url, serviceKey);
  const { data: linkData, error: linkError } = await admin.auth.admin.generateLink({
    type: "magiclink",
    email: OWNER_EMAIL,
  });
  if (linkError || !linkData.properties?.hashed_token) {
    throw new Error(`generateLink failed: ${linkError?.message ?? "no hashed_token"}`);
  }

  const anon = createClient(url, anonKey);
  const { data: verified, error: verifyError } = await anon.auth.verifyOtp({
    type: "magiclink",
    token_hash: linkData.properties.hashed_token,
  });
  if (verifyError || !verified.session) {
    throw new Error(`verifyOtp failed: ${verifyError?.message ?? "no session"}`);
  }
  return anon;
}

async function searchDocs(client: SupabaseClient, q: string, mode: string): Promise<string[]> {
  const { data, error } = await client.rpc("search_docs", { q, search_mode: mode, match_limit: 20 });
  if (error) throw new Error(`search_docs(${mode}) failed: ${error.message}`);
  const rows = data as { doc_id: string; rank: number }[];
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
  const client = await authenticate();

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
      searchDocs(client, query.q, "tsvector"),
      searchDocs(client, query.q, "trgm"),
      searchDocs(client, query.q, "hybrid"),
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
