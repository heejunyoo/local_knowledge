import { describe, it, expect } from "vitest";
import * as diet from "@/lib/domain/diet-read";

const EMPTY_DAY = diet.buildDaySnapshot("2026-07-27", [], [], []);
const EMPTY_YESTERDAY = diet.buildDaySnapshot("2026-07-26", [], [], []);
const GOALS: diet.Goals = { targetKcal: 2185, targetProteinG: 138, weeklyWorkouts: 4, targetWorkoutMinutesPerDay: 40 };

describe("dayKey / seoulHour", () => {
  it("buckets by Asia/Seoul calendar date regardless of server TZ", () => {
    // 2026-07-27T15:30:00Z = 2026-07-28 00:30 KST
    expect(diet.dayKey(new Date("2026-07-27T15:30:00Z"))).toBe("2026-07-28");
  });

  it("extracts the Asia/Seoul hour including midnight as 0", () => {
    expect(diet.seoulHour(new Date("2026-07-27T15:00:00Z"))).toBe(0); // 00:00 KST
    expect(diet.seoulHour(new Date("2026-07-27T09:00:00Z"))).toBe(18); // 18:00 KST
  });
});

describe("buildDaySnapshot / daySummaryDict — golden zero-state parity", () => {
  it("matches the captured empty-day shape", () => {
    expect(diet.daySummaryDict(EMPTY_DAY)).toEqual({
      date: "2026-07-27",
      meals: [],
      workouts: [],
      metrics: [],
      totals: { kcal: 0, protein_g: 0, workout_minutes: 0, meal_count: 0, workout_count: 0 },
      summary_text: "2026-07-27: 식사·운동 기록이 없어요.",
    });
  });

  it("formats a non-empty day the way the Swift original did", () => {
    const day = diet.buildDaySnapshot(
      "2026-07-27",
      [{ id: "m1", ts: "2026-07-27T12:00:00Z", items: ["김밥"], kcal: 500, proteinG: 20, note: null }],
      [{ id: "w1", ts: "2026-07-27T18:00:00Z", kind: "달리기", minutes: 30, intensity: null }],
      [],
    );
    expect(day.summaryText).toBe("2026-07-27: 식사 1회 (김밥) · 500 kcal · 단백질 20g 운동 1회 (달리기) · 30분");
  });
});

describe("missingLogChecklist", () => {
  it("reproduces the golden gaps at evening hour with no logs", () => {
    const gaps = diet.missingLogChecklist(new Date("2026-07-27T10:00:00Z"), EMPTY_DAY, EMPTY_YESTERDAY); // 19:00 KST
    expect(gaps).toEqual([
      { kind: "meal", slot: "아침", label: "아침 기록이 없어요", priority: 1 },
      { kind: "meal", slot: "점심", label: "점심 기록이 없어요", priority: 2 },
      { kind: "workout", label: "오늘 운동 기록이 없어요", priority: 4 },
    ]);
  });

  it("does not flag dinner before 20:00 KST", () => {
    const gaps = diet.missingLogChecklist(new Date("2026-07-27T09:00:00Z"), EMPTY_DAY, EMPTY_YESTERDAY); // 18:00 KST
    expect(gaps.some((g) => g.label === "저녁 기록이 없어요")).toBe(false);
  });

  it("flags missing sleep before noon when yesterday has none", () => {
    const gaps = diet.missingLogChecklist(new Date("2026-07-27T01:00:00Z"), EMPTY_DAY, EMPTY_YESTERDAY); // 10:00 KST
    expect(gaps.some((g) => g.kind === "sleep")).toBe(true);
  });
});

describe("suggestedAction", () => {
  it("suggests dinner in the evening window when no dinner logged (golden capture time)", () => {
    const action = diet.suggestedAction(new Date("2026-07-27T10:00:00Z"), EMPTY_DAY); // 19:00 KST
    expect(action).toEqual({ title: "저녁을 기록해 주세요", subtitle: "단백질 목표에 도움이 돼요", slot: "저녁" });
  });
});

describe("activityStreak", () => {
  it("is 0 when today and yesterday are both empty", () => {
    expect(diet.activityStreak([EMPTY_DAY, EMPTY_YESTERDAY])).toBe(0);
  });

  it("counts today plus consecutive non-empty days before it", () => {
    const nonEmpty = diet.buildDaySnapshot(
      "d",
      [{ id: "m", ts: "t", items: ["x"], kcal: 1, proteinG: 1, note: null }],
      [],
      [],
    );
    expect(diet.activityStreak([nonEmpty, nonEmpty, nonEmpty, EMPTY_YESTERDAY])).toBe(3);
  });

  it("does not count today toward the streak when today is empty", () => {
    const nonEmpty = diet.buildDaySnapshot(
      "d",
      [{ id: "m", ts: "t", items: ["x"], kcal: 1, proteinG: 1, note: null }],
      [],
      [],
    );
    expect(diet.activityStreak([EMPTY_DAY, nonEmpty, nonEmpty])).toBe(2);
  });
});

describe("latestSleepHours / sleepCoachHint", () => {
  it("returns null and no hint when nothing logged", () => {
    expect(diet.latestSleepHours([EMPTY_DAY, EMPTY_YESTERDAY])).toBeNull();
    expect(diet.sleepCoachHint(null)).toBeNull();
  });

  it("finds the most recent day with a sleep metric", () => {
    const withSleep = diet.buildDaySnapshot("d", [], [], [
      { id: "hk-1", ts: "t", weightKg: null, sleepH: 5.2, context: null },
    ]);
    expect(diet.latestSleepHours([EMPTY_DAY, withSleep])).toBe(5.2);
    expect(diet.sleepCoachHint(5.2)).toContain("칼로리·운동 목표를 조금 낮춰도");
    expect(diet.sleepCoachHint(8.5)).toContain("회복 좋음");
    expect(diet.sleepCoachHint(7.0)).toBe("최근 수면 7.0시간.");
  });
});

describe("weekReview — golden zero-state parity", () => {
  it("matches diet.week_review shape for an all-empty week", () => {
    const bars = Array.from({ length: 7 }, (_, i) =>
      diet.dayBarFrom(diet.buildDaySnapshot(`d${i}`, [], [], [])),
    );
    const result = diet.weekReview(bars, GOALS);
    expect(result.totals).toEqual({ kcal: 0, protein_g: 0, workout_minutes: 0, meal_count: 0, workout_count: 0 });
    expect(result.goals).toEqual({
      target_kcal: 2185,
      target_protein_g: 138,
      weekly_workouts: 4,
      target_workout_minutes_per_day: 40,
    });
    expect(result.summary_text).toBe("최근 7일: 식사 0회 · 운동 0회 · 0분\n칼로리 합 0 kcal");
  });
});

describe("buildAssistantWeekReview", () => {
  it("adds narrative without sleep_hint/review_pending noise when there is none", () => {
    const bars = Array.from({ length: 7 }, (_, i) =>
      diet.dayBarFrom(diet.buildDaySnapshot(`d${i}`, [], [], [])),
    );
    const result = diet.buildAssistantWeekReview(bars, GOALS, 0, null, 0);
    expect(result.narrative_lines).toEqual([
      "최근 7일: 식사 0회 · 운동 0회 · 0분\n칼로리 합 0 kcal",
      "연속 기록 0일",
    ]);
    expect(result.review_pending).toBe(0);
    expect("sleep_hint" in result).toBe(false);
  });
});

describe("profileDict — Mifflin–St Jeor parity with golden diet.profile.get", () => {
  it("reproduces bmr/tdee/recommended_kcal/recommended_protein_g exactly", () => {
    const profile: diet.Profile = {
      heightCm: 170,
      weightKg: 86,
      age: 39,
      sex: "male",
      targetWeightKg: 75,
      activity: "moderate",
    };
    expect(diet.profileDict(profile)).toEqual({
      height_cm: 170,
      weight_kg: 86,
      age: 39,
      sex: "male",
      target_weight_kg: 75,
      activity: "moderate",
      bmr: 1733,
      tdee: 2685,
      recommended_kcal: 2185,
      recommended_protein_g: 138,
    });
  });
});
