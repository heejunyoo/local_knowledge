// ingreed_detail 의 nutrition jsonb + 1회 섭취량 → 식단 기록용 영양값(순수 함수).
// spec: .claude/specs/ingreed-diet-nutrition/spec.md §2, §4(D1~D3, D8)
//
// 이 파일이 없으면 안 되는 이유: nutrition jsonb 는 100g/100mL 기준값이라
// 그대로 기록하면 사용자가 실제로 먹은 양과 안 맞는다. 1회량은
// lib/domain/serving-size.ts 의 declaredServingG 로 구하고(D1), 못 구하면
// null 을 돌려줘야 한다(D2) — 임의 값을 채우면 기록이 거짓말을 한다.
// grade·score 는 여기서 다루지 않는다(D8) — 하루 채점은 2단계.

import { declaredServingG, grams } from "@/lib/domain/serving-size";

export type IngreedNutritionUnit = "g" | "ml";

/** ingreed_detail 이 돌려주는 product.nutrition jsonb. 필드가 통째로 없을 수 있다(§2). */
export interface IngreedNutrition {
  basis?: string | null;
  basisAmount?: number | null;
  servingSize?: string | null;
  foodWeight?: string | null;
  energyKcal?: number | null;
  proteinG?: number | null;
  sugarG?: number | null;
  satFatG?: number | null;
  sodiumMg?: number | null;
  carbG?: number | null;
  fatG?: number | null;
  transFatG?: number | null;
  cholesterolMg?: number | null;
}

/** toServingNutrition 이 필요로 하는 product 의 부분 집합. */
export interface IngreedProductNutrition {
  reportNo: string;
  name: string;
  category: string;
  nutrition?: IngreedNutrition | null;
}

/** 1회량(수량 배수 적용 후) 기준으로 환산한 영양 기록. */
export interface ServingNutrition {
  servingG: number | null;
  unit: IngreedNutritionUnit | null;
  kcal: number | null;
  proteinG: number | null;
  sugarG: number | null;
  sodiumMg: number | null;
  satFatG: number | null;
  itemLine: string;
}

function fmtAmount(a: number): string {
  return a === Math.round(a) ? String(Math.trunc(a)) : a.toFixed(1);
}

function unitFromBasis(basis: string | null | undefined): IngreedNutritionUnit | null {
  if (!basis) return null;
  const b = basis.toLowerCase();
  if (b.includes("ml")) return "ml";
  if (b.includes("g")) return "g";
  return null;
}

/** g 단위 값: diet-nutrition-calc.ts estimateAsDict 관례와 동일하게 소수 1자리. */
function scaleDecimal(value: number | null | undefined, factor: number): number | null {
  if (value === null || value === undefined || !Number.isFinite(value)) return null;
  return Math.round(value * factor * 10) / 10;
}

/** kcal·mg 단위 값: 정수. */
function scaleInt(value: number | null | undefined, factor: number): number | null {
  if (value === null || value === undefined || !Number.isFinite(value)) return null;
  return Math.round(value * factor);
}

/**
 * nutrition(100g/100mL 기준) + 1회량 + 수량 배수 → 기록용 영양값.
 *
 * 1회량(servingG)은 declaredServingG(servingSize, category, name)로 구한다(D1).
 * foodWeight(총 내용량)가 그보다 작으면 총 내용량을 쓴다 — 한 봉지를 다 먹는 경우다.
 * 1회량을 못 구하면 servingG=null 을 담아 반환하고 영양값을 채우지 않는다(D2).
 * basisAmount 를 못 구하면(비정상 데이터) 환산 배수를 계산할 수 없으므로 마찬가지로
 * 영양값을 null 로 둔다 — basisAmount 는 실측 100 고정이지만 여기서 100 을
 * 하드코딩하지 않는다.
 */
export function toServingNutrition(
  product: IngreedProductNutrition,
  quantity: number,
  servingGOverride?: number | null,
): ServingNutrition {
  const n = product.nutrition ?? null;
  const unit = unitFromBasis(n?.basis);

  let servingG: number | null = null;
  if (typeof servingGOverride === "number" && Number.isFinite(servingGOverride) && servingGOverride > 0) {
    // 사용자가 직접 넣은 양(D2). 신고 1회량을 못 구했을 때 쓴다 — 이때도 환산은
    // ingreed 의 100g 기준 실측값으로 한다. LLM 추정으로 바꿔치기하지 않는다.
    servingG = servingGOverride;
  } else if (n) {
    const declared = declaredServingG(n.servingSize, product.category ?? "", product.name);
    if (declared !== null) {
      const foodWeightG = grams(n.foodWeight);
      servingG = foodWeightG !== null && foodWeightG < declared ? foodWeightG : declared;
    }
  }

  if (!n || servingG === null) {
    return {
      servingG: null,
      unit,
      kcal: null,
      proteinG: null,
      sugarG: null,
      sodiumMg: null,
      satFatG: null,
      itemLine: product.name,
    };
  }

  const basisAmount = n.basisAmount;
  const canScale = typeof basisAmount === "number" && Number.isFinite(basisAmount) && basisAmount > 0;
  const factor = canScale ? (servingG / basisAmount) * quantity : null;
  const amount = servingG * quantity;

  return {
    servingG,
    unit,
    kcal: factor === null ? null : scaleInt(n.energyKcal, factor),
    proteinG: factor === null ? null : scaleDecimal(n.proteinG, factor),
    sugarG: factor === null ? null : scaleDecimal(n.sugarG, factor),
    sodiumMg: factor === null ? null : scaleInt(n.sodiumMg, factor),
    satFatG: factor === null ? null : scaleDecimal(n.satFatG, factor),
    itemLine: `${product.name} ${fmtAmount(amount)}${unit ?? ""}`,
  };
}
