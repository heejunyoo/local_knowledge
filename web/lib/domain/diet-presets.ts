// Swift 원본: Packages/KnowledgeCore/Sources/KnowledgeCore/DietPresets.swift
// 1:1 번역 — 이름 정리·리팩토링 금지.

export interface DietMealPreset {
  name: string;
  /** 기본 1인분 무게(g) 또는 부피(ml). */
  grams: number;
  kcal: number;
  proteinG: number;
  /** UI 단위 라벨: "g" | "ml" */
  unit: string;
}

export interface DietWorkoutPreset {
  name: string;
  minutes: number;
}

export const MEAL_PRESETS: DietMealPreset[] = [
  { name: "밥·반찬", grams: 300, kcal: 520, proteinG: 18, unit: "g" },
  { name: "샐러드", grams: 200, kcal: 120, proteinG: 5, unit: "g" },
  { name: "닭가슴살", grams: 100, kcal: 110, proteinG: 23, unit: "g" },
  { name: "계란", grams: 50, kcal: 70, proteinG: 6, unit: "g" },
  { name: "단백질 쉐이크", grams: 30, kcal: 120, proteinG: 24, unit: "g" },
  { name: "커피", grams: 200, kcal: 5, proteinG: 0, unit: "ml" },
  { name: "과일", grams: 150, kcal: 80, proteinG: 1, unit: "g" },
  { name: "우유", grams: 200, kcal: 84, proteinG: 6.8, unit: "ml" },
  { name: "두부", grams: 150, kcal: 114, proteinG: 12, unit: "g" },
  { name: "요거트", grams: 150, kcal: 105, proteinG: 6, unit: "g" },
];

export const WORKOUT_PRESETS: DietWorkoutPreset[] = [
  { name: "걷기", minutes: 20 },
  { name: "계단오르기", minutes: 10 },
  { name: "러닝", minutes: 30 },
  { name: "헬스", minutes: 45 },
  { name: "스트레칭", minutes: 10 },
];

/** 기본 1인분을 amount(g/ml)로 스케일한다 — 원본 DietMealPreset.scaled(to:). */
export function scaledMealPreset(
  preset: DietMealPreset,
  amount: number,
): { kcal: number; proteinG: number; line: string } {
  const a = Math.max(0, amount);
  const factor = preset.grams > 0 ? a / preset.grams : 1;
  const kcal = Math.round(preset.kcal * factor * 10) / 10;
  const proteinG = Math.round(preset.proteinG * factor * 10) / 10;
  const aStr = a === Math.round(a) ? String(Math.trunc(a)) : a.toFixed(1);
  return { kcal, proteinG, line: `${preset.name} ${aStr}${preset.unit}` };
}
