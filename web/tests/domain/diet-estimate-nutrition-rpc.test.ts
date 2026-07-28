import { describe, it, expect } from "vitest";
import { diet_estimate_nutrition } from "@/lib/rpc/handlers";

describe("diet_estimate_nutrition RPC", () => {
  it("food/amount/unit이 주어지면 카탈로그 기준으로 추정한다", async () => {
    const result = (await diet_estimate_nutrition({ food: "닭가슴살", amount: 150, unit: "g" })) as Record<
      string,
      unknown
    >;
    expect(result.matched).toBe(true);
    expect(result.food).toBe("닭가슴살");
  });

  it("text가 있고 amount<=0이면 자유 텍스트 파싱 경로를 탄다", async () => {
    const result = (await diet_estimate_nutrition({ text: "우유 250ml" })) as Record<string, unknown>;
    expect(result.matched).toBe(true);
    expect(result.unit).toBe("ml");
    expect(result.amount).toBe(250);
  });

  it("매칭 실패 시 {matched:false}만 반환한다", async () => {
    const result = await diet_estimate_nutrition({ food: "", amount: 0 });
    expect(result).toEqual({ matched: false });
  });
});
