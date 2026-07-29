// G6-1/G6-3: knowledge.ask/askFast 실제 DB 스모크 — 실 Supabase 프로젝트 대상
// (web/.env.local 필요). 로컬 환경에 클라우드 LLM 키가 없으므로 자연히
// 클라우드 캐스케이드가 스킵되고 extractive(1급 경로)로 응답한다 — G6-3의
// "전면 실패/부재 시에도 정상 응답(에러 아님)"을 실 DB로 재확인한다.
import { describe, it, expect, vi } from "vitest";
import { testSupabaseClient } from "./test-client";

vi.mock("@/lib/supabase/server", () => ({
  createClient: () => testSupabaseClient(),
}));

const { ask, askFast } = await import("@/lib/rag/ask");

describe("G6-1/G6-3: knowledge.ask/askFast (실 DB)", () => {
  it("askFast는 실제 검색 데이터로 citations에 unit_id를 채워 반환한다", async () => {
    const result = await askFast("food");
    expect(result.citations.length).toBeGreaterThan(0);
    for (const c of result.citations) {
      expect(c.unitId).toBeTruthy();
    }
    expect(result.answer.length).toBeGreaterThan(0);
    expect(result.engine).toContain("extractive-rag");
  });

  it("ask()는 클라우드 키 부재 시에도 에러 없이 extractive로 응답한다(G6-3)", async () => {
    const result = await ask("food");
    expect(result.citations.length).toBeGreaterThan(0);
    expect(result.answer.length).toBeGreaterThan(0);
    // 클라우드 키가 로컬에 없으므로 refine()이 항상 실패해 extractive로 떨어진다.
    expect(result.engine).toBe("extractive-rag/v2");
  });

  it("검색 결과가 없는 질의는 안내 문구를 반환한다(에러 아님)", async () => {
    const result = await askFast("존재하지않을가능성이매우높은고유토큰문자열Zzyzx9999");
    expect(result.citations).toEqual([]);
    expect(result.answer).toContain("찾지 못했어요");
  });

  it("빈 질문은 안내 문구를 반환한다", async () => {
    const result = await askFast("   ");
    expect(result.citations).toEqual([]);
    expect(result.answer).toBe("질문을 입력해 주세요.");
  });
});
