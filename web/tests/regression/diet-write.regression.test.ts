// G4b-3: diet 쓰기 왕복 — log_meal → day_summary 총합 반영 확인 →
// delete_meal → 원복 확인. 실제 Supabase 프로젝트 대상(web/.env.local 필요).
import { describe, it, expect, vi } from "vitest";
import { testSupabaseClient } from "./test-client";

vi.mock("@/lib/supabase/server", () => ({
  createClient: () => testSupabaseClient(),
}));

const { diet_log_meal, diet_day_summary, diet_delete_meal } = await import("@/lib/rpc/handlers");

interface DaySummary {
  totals: { kcal: number; protein_g: number; meal_count: number; workout_minutes: number; workout_count: number };
  meals: { id: string; items: string[]; kcal?: number; protein_g?: number; note?: string }[];
}

describe("G4b-3: diet.log_meal → day_summary 반영 → delete_meal → 원복 (실 DB)", () => {
  it("log_meal 직후 오늘 총합에 반영되고, delete_meal 후 원래 상태로 되돌아온다", async () => {
    const before = (await diet_day_summary()) as unknown as DaySummary;

    const meal = (await diet_log_meal({
      items: ["[diet-write.regression.test.ts] 테스트 식사"],
      kcal: 321,
      protein_g: 12,
      note: "회귀 테스트",
    })) as { id: string; ts: string; items: string[]; kcal: number; protein_g: number; note: string };

    expect(meal.id).toBeTruthy();
    expect(meal.kcal).toBe(321);
    expect(meal.protein_g).toBe(12);

    try {
      const after = (await diet_day_summary()) as unknown as DaySummary;
      expect(after.totals.kcal).toBe(before.totals.kcal + 321);
      expect(after.totals.protein_g).toBe(before.totals.protein_g + 12);
      expect(after.totals.meal_count).toBe(before.totals.meal_count + 1);
      expect(after.meals.some((m) => m.id === meal.id)).toBe(true);
      // 무관한 값(운동)은 이 쓰기로 영향받지 않아야 한다.
      expect(after.totals.workout_minutes).toBe(before.totals.workout_minutes);
      expect(after.totals.workout_count).toBe(before.totals.workout_count);
    } finally {
      const deleted = (await diet_delete_meal({ id: meal.id })) as { deleted: boolean; id: string };
      expect(deleted).toEqual({ deleted: true, id: meal.id });
    }

    const restored = (await diet_day_summary()) as unknown as DaySummary;
    expect(restored).toEqual(before);
  });

  it("존재하지 않는 id를 delete_meal하면 deleted:false를 반환하고(부작용 없음) id는 그대로 돌려준다", async () => {
    const result = (await diet_delete_meal({ id: "no-such-meal-id" })) as { deleted: boolean; id: string };
    expect(result).toEqual({ deleted: false, id: "no-such-meal-id" });
  });
});
