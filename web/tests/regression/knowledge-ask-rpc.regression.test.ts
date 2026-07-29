// G6-1: knowledge.ask/askFast RPC 핸들러가 citations를 unit_id 등 원본 계약
// 필드명으로 변환해 반환하는지 실 DB로 확인.
import { describe, it, expect, vi } from "vitest";
import { testSupabaseClient } from "./test-client";

vi.mock("@/lib/supabase/server", () => ({
  createClient: () => testSupabaseClient(),
}));

const { knowledge_ask_fast, knowledge_ask } = await import("@/lib/rpc/handlers");
const { dispatch } = await import("@/lib/rpc/dispatch");

describe("G6-1: knowledge.ask RPC 계약", () => {
  it("knowledge_ask_fast는 citations[].unit_id/title/source_type/snippet/score를 채운다", async () => {
    const result = (await knowledge_ask_fast({ q: "food" })) as {
      answer: string;
      engine: string;
      citations: { unit_id: string; title: string; source_type: string; snippet: string; score: number }[];
    };
    expect(result.citations.length).toBeGreaterThan(0);
    expect(result.citations.length).toBeLessThanOrEqual(8);
    for (const c of result.citations) {
      expect(c.unit_id).toBeTruthy();
      expect(typeof c.title).toBe("string");
      expect(typeof c.source_type).toBe("string");
      expect(typeof c.snippet).toBe("string");
      expect(typeof c.score).toBe("number");
    }
  });

  it("dispatch('knowledge.ask', ...)가 등록되어 있다", async () => {
    const outcome = await dispatch("knowledge.ask", { q: "food" });
    expect(outcome.error).toBeUndefined();
    expect(outcome.result).toBeDefined();
  });

  it("dispatch('knowledge.ask.fast', ...)가 등록되어 있다", async () => {
    const outcome = await dispatch("knowledge.ask.fast", { q: "food" });
    expect(outcome.error).toBeUndefined();
    expect(outcome.result).toBeDefined();
  });

  it("limit은 8건으로 상한된다(원본 citations 최대 8개 계약)", async () => {
    const result = (await knowledge_ask({ q: "food", limit: 20, use_llama: false })) as {
      citations: unknown[];
    };
    expect(result.citations.length).toBeLessThanOrEqual(8);
  });
});
