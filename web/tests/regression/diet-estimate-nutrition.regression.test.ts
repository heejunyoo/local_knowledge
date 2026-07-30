// C3: diet.estimate_nutrition LLM 보강의 실 DB 경로 확인.
//
// 핸들러가 `lib/diet/nutrition-enrich.ts` → `lib/llm/router.complete()`를 타면
// 첫 단계가 `DbLlmAnswerCacheStore.get()`(llm_answer_cache 실 조회)이다. 로컬에는
// 클라우드 키가 없으므로 그 뒤 캐스케이드는 자연히 전면 부재 케이스가 되고,
// 결과는 **에러가 아니라** 규칙 기반 일반식 추정치여야 한다(G6-3과 같은 원칙).
import { describe, it, expect, vi, afterAll } from "vitest";
import { testSupabaseClient } from "./test-client";

vi.mock("@/lib/supabase/server", () => ({
  createClient: () => testSupabaseClient(),
}));

const { diet_estimate_nutrition } = await import("@/lib/rpc/handlers");
const { enrichWithLlm } = await import("@/lib/diet/nutrition-enrich");
const { nutritionPrompt } = await import("@/lib/domain/diet-nutrition-llm");
const { estimate } = await import("@/lib/domain/diet-nutrition-calc");
const { complete: routerComplete } = await import("@/lib/llm/router");
const { DbLlmAnswerCacheStore } = await import("@/lib/llm/db-cache-store");
const { cacheKey } = await import("@/lib/llm/cache");

interface EstimateDict {
  food: string;
  amount: number;
  unit: string;
  kcal: number;
  protein_g: number;
  matched: boolean;
  source: string;
  note: string;
}

describe("C3: diet.estimate_nutrition (실 DB)", () => {
  it("카탈로그가 맞춘 음식은 LLM 경로를 타지 않는다(source=catalog)", async () => {
    const r = (await diet_estimate_nutrition({ food: "닭가슴살", amount: 150, unit: "g" })) as unknown as EstimateDict;
    expect(r.matched).toBe(true);
    expect(r.source).toBe("catalog");
    expect(r.kcal).toBe(165); // 110kcal/100g × 1.5
  });

  it("미매칭 음식은 클라우드 키가 없어도 에러 없이 일반식 평균으로 떨어진다(source=generic)", async () => {
    // 카탈로그 30종의 이름·별칭 어느 것도 부분문자열로 포함하지 않는 음식이어야 한다
    // (matchFood는 2자 이상 키의 부분문자열 매칭까지 한다 — "…음식"류는 "음식" 별칭에 걸린다).
    const r = (await diet_estimate_nutrition({
      food: "된장찌개",
      amount: 200,
      unit: "g",
    })) as unknown as EstimateDict;
    expect(r.matched).toBe(false);
    expect(r.source).toBe("generic");
    expect(r.kcal).toBe(300); // 일반 음식 150kcal/100g × 2
  });

  it("자유 텍스트 경로도 동일하게 동작한다", async () => {
    const r = (await diet_estimate_nutrition({ text: "우유 250ml" })) as unknown as EstimateDict;
    expect(r.source).toBe("catalog");
    expect(r.unit).toBe("ml");
    expect(r.amount).toBe(250);
  });
});

// 실 provider 키(B3)가 아직 없어 클라우드 응답 자체는 스텁한다. 스텁 대상은
// fetch 하나뿐이고 라우터·프로바이더 파싱·실 DB 캐시(llm_answer_cache)·검증·
// 스케일링은 전부 실제 코드가 돈다 — 즉 "실 provider가 이 형식으로 답하면"까지가
// 미검증이고 그 뒤 체인은 검증된다.
describe("C3: LLM 보강 경로 (fetch만 스텁, 캐시는 실 DB)", () => {
  const MAX_TOKENS = 80;
  const FOOD = "된장찌개";
  const PROMPT = nutritionPrompt(FOOD, "g");
  const KEY = cacheKey(PROMPT, MAX_TOKENS);
  const originalGroqKey = process.env.GROQ_API_KEY;

  afterAll(async () => {
    if (originalGroqKey === undefined) delete process.env.GROQ_API_KEY;
    else process.env.GROQ_API_KEY = originalGroqKey;
    const supabase = await testSupabaseClient();
    await supabase.from("llm_answer_cache").delete().eq("cache_key", KEY);
  });

  it("클라우드 응답을 100단위 값으로 읽어 보강하고(source=llm), 2회차는 캐시로 처리한다", async () => {
    process.env.GROQ_API_KEY = "c3-regression-stub-key";
    const supabase = await testSupabaseClient();
    await supabase.from("llm_answer_cache").delete().eq("cache_key", KEY);

    let fetchCalls = 0;
    const fakeFetch = (async () => {
      fetchCalls++;
      return {
        ok: true,
        json: async () => ({
          choices: [{ message: { content: '{"kcal_per_100": 65, "protein_g_per_100": 4.2}' } }],
        }),
      };
    }) as unknown as typeof fetch;

    // 스로틀은 오너 settings를 건드리지 않도록 인메모리 스텁을 쓴다(P6 G6-4가 실 구현을 이미 검증).
    const throttleStore = { blockReason: async () => null, record: async () => {} };
    const completeFn = (prompt: string, maxTokens: number) =>
      routerComplete({
        prompt,
        maxTokens,
        cacheStore: new DbLlmAnswerCacheStore(),
        throttleStore,
        fetchImpl: fakeFetch,
      });

    const base = estimate(FOOD, 200, "g")!;
    expect(base.matchedCatalog).toBe(false);

    const first = await enrichWithLlm(base, completeFn);
    expect(first.source).toBe("llm");
    expect(first.estimate.kcal).toBe(130); // 65 × 2.0
    expect(first.estimate.proteinG).toBe(8.4); // 4.2 × 2.0
    expect(fetchCalls).toBe(1);

    // 같은 음식·단위면 분량이 달라도 프롬프트가 같다 → 캐시 적중(클라우드 호출 0회)
    const second = await enrichWithLlm(estimate(FOOD, 350, "g")!, completeFn);
    expect(second.source).toBe("llm");
    expect(second.estimate.kcal).toBe(227.5); // 65 × 3.5
    expect(fetchCalls).toBe(1);
  });
});
