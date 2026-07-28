import { describe, it, expect } from "vitest";
import { MEAL_PRESETS, WORKOUT_PRESETS, scaledMealPreset } from "@/lib/domain/diet-presets";

describe("diet-presets", () => {
  it("식사 10종·운동 5종 프리셋을 원본과 동일하게 유지한다", () => {
    expect(MEAL_PRESETS).toHaveLength(10);
    expect(WORKOUT_PRESETS).toHaveLength(5);
    expect(MEAL_PRESETS.map((p) => p.name)).toEqual([
      "밥·반찬", "샐러드", "닭가슴살", "계란", "단백질 쉐이크", "커피", "과일", "우유", "두부", "요거트",
    ]);
  });

  it("scaledMealPreset: 정수 배율은 정확히 스케일된다", () => {
    const chicken = MEAL_PRESETS.find((p) => p.name === "닭가슴살")!;
    const result = scaledMealPreset(chicken, 200);
    expect(result).toEqual({ kcal: 220, proteinG: 46, line: "닭가슴살 200g" });
  });

  it("scaledMealPreset: 비정수 amount는 소수 1자리로 라인에 표기된다", () => {
    const chicken = MEAL_PRESETS.find((p) => p.name === "닭가슴살")!;
    const result = scaledMealPreset(chicken, 150.5);
    expect(result.line).toBe("닭가슴살 150.5g");
  });

  it("scaledMealPreset: 결과 kcal/protein은 소수 1자리로 반올림된다", () => {
    const milk = MEAL_PRESETS.find((p) => p.name === "우유")!;
    // factor = 130/200 = 0.65 → kcal 84*0.65=54.6, protein 6.8*0.65=4.42
    const result = scaledMealPreset(milk, 130);
    expect(result.kcal).toBe(54.6);
    expect(result.proteinG).toBe(4.4);
  });

  it("scaledMealPreset: 음수 amount는 0으로 클램프된다", () => {
    const coffee = MEAL_PRESETS.find((p) => p.name === "커피")!;
    const result = scaledMealPreset(coffee, -10);
    expect(result).toEqual({ kcal: 0, proteinG: 0, line: "커피 0ml" });
  });
});
