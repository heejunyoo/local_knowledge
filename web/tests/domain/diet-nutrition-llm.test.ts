import { describe, it, expect } from "vitest";
import { applyPer100, nutritionPrompt, parsePer100 } from "@/lib/domain/diet-nutrition-llm";
import { estimate, Estimate } from "@/lib/domain/diet-nutrition-calc";
import { CompleteFn, enrichWithLlm } from "@/lib/diet/nutrition-enrich";

function unmatched(food: string, amount: number, unit: "g" | "ml" = "g"): Estimate {
  const e = estimate(food, amount, unit);
  if (!e) throw new Error("fixture: estimate가 null");
  expect(e.matchedCatalog).toBe(false);
  return e;
}

function reply(text: string): CompleteFn {
  return async () => ({ text, engine: "cloud/fake/model" });
}

describe("nutritionPrompt", () => {
  it("단위에 맞는 기준(100g/100ml)과 음식명을 담는다", () => {
    const p = nutritionPrompt("된장찌개", "g");
    expect(p).toContain("100g");
    expect(p).toContain("된장찌개");
    expect(p).toContain("kcal_per_100");
    expect(p).not.toContain("100ml");
  });

  it("ml 단위는 100ml 기준으로 묻는다", () => {
    expect(nutritionPrompt("식혜", "ml")).toContain("100ml");
  });

  it("분량에 의존하지 않는다 — 같은 음식/단위면 프롬프트가 동일하다(캐시 적중 조건)", () => {
    expect(nutritionPrompt("된장찌개", "g")).toBe(nutritionPrompt(" 된장찌개 ", "g"));
  });
});

describe("parsePer100", () => {
  it("순수 JSON을 파싱한다", () => {
    expect(parsePer100('{"kcal_per_100": 65, "protein_g_per_100": 4.2}')).toEqual({
      kcal: 65,
      proteinG: 4.2,
    });
  });

  it("코드펜스와 앞뒤 설명이 섞여도 첫 JSON 객체를 취한다", () => {
    const text = '알겠습니다.\n```json\n{"kcal_per_100": 120, "protein_g_per_100": 8}\n```\n도움이 되었길!';
    expect(parsePer100(text)).toEqual({ kcal: 120, proteinG: 8 });
  });

  it("숫자가 문자열로 와도 받는다", () => {
    expect(parsePer100('{"kcal_per_100": "150", "protein_g_per_100": "9"}')).toEqual({
      kcal: 150,
      proteinG: 9,
    });
  });

  it.each([
    ["JSON이 아예 없음", "잘 모르겠습니다"],
    ["깨진 JSON", '{"kcal_per_100": 100,'],
    ["필드 누락", '{"kcal_per_100": 100}'],
    ["숫자 아님", '{"kcal_per_100": "많음", "protein_g_per_100": 3}'],
    ["kcal 음수", '{"kcal_per_100": -10, "protein_g_per_100": 3}'],
    ["kcal 상한 초과", '{"kcal_per_100": 1200, "protein_g_per_100": 3}'],
    ["단백질 상한 초과", '{"kcal_per_100": 800, "protein_g_per_100": 150}'],
    ["물리적 불가(단백질 열량 > 총 열량)", '{"kcal_per_100": 20, "protein_g_per_100": 50}'],
  ])("%s → null", (_label, text) => {
    expect(parsePer100(text)).toBeNull();
  });

  it("카탈로그 실측값(단백질 쉐이크 400kcal/80g)은 물리 정합 검사를 통과한다", () => {
    expect(parsePer100('{"kcal_per_100": 400, "protein_g_per_100": 80}')).not.toBeNull();
  });
});

describe("applyPer100", () => {
  it("100단위 값을 분량만큼 스케일링한다", () => {
    const applied = applyPer100(unmatched("된장찌개", 200), { kcal: 65, proteinG: 4.2 });
    expect(applied.kcal).toBe(130);
    expect(applied.proteinG).toBe(8.4);
    expect(applied.amount).toBe(200);
    expect(applied.foodName).toBe("된장찌개");
  });

  it("matched(카탈로그 수록 여부)의 의미는 바꾸지 않는다", () => {
    const applied = applyPer100(unmatched("된장찌개", 200), { kcal: 65, proteinG: 4.2 });
    expect(applied.matchedCatalog).toBe(false);
    expect(applied.note).toContain("AI 추정");
  });
});

describe("enrichWithLlm", () => {
  it("카탈로그가 맞춘 추정치는 LLM을 호출하지 않는다", async () => {
    const matched = estimate("닭가슴살", 150, "g")!;
    expect(matched.matchedCatalog).toBe(true);
    let calls = 0;
    const spy: CompleteFn = async () => {
      calls++;
      return null;
    };

    const out = await enrichWithLlm(matched, spy);
    expect(calls).toBe(0);
    expect(out.source).toBe("catalog");
    expect(out.estimate).toBe(matched);
  });

  it("미매칭 음식은 LLM 값으로 보강한다", async () => {
    const out = await enrichWithLlm(
      unmatched("된장찌개", 200),
      reply('{"kcal_per_100": 65, "protein_g_per_100": 4.2}'),
    );
    expect(out.source).toBe("llm");
    expect(out.estimate.kcal).toBe(130);
  });

  it("LLM이 null(키 없음·스로틀 차단·전면 실패)이면 규칙 기반 추정치 그대로", async () => {
    const base = unmatched("된장찌개", 200);
    const out = await enrichWithLlm(base, async () => null);
    expect(out.source).toBe("generic");
    expect(out.estimate).toBe(base);
  });

  it("LLM 응답이 파싱/검증에 실패해도 에러가 아니라 폴백이다", async () => {
    const base = unmatched("된장찌개", 200);
    const out = await enrichWithLlm(base, reply("잘 모르겠습니다"));
    expect(out.source).toBe("generic");
    expect(out.estimate).toBe(base);
  });

  it("라우터가 예외를 던져도 폴백한다", async () => {
    const base = unmatched("된장찌개", 200);
    const out = await enrichWithLlm(base, async () => {
      throw new Error("network");
    });
    expect(out.source).toBe("generic");
    expect(out.estimate).toBe(base);
  });
});
