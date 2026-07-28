// Swift 원본: Packages/KnowledgeCore/Sources/KnowledgeCore/DietNutritionCalc.swift
// 1:1 번역 — 이름 정리·리팩토링 금지. 자유 입력에서 kcal을 대략 추정하는
// 홈쿡 카탈로그(전체 영양 DB 아님).

export type NutritionUnit = "g" | "ml";

export interface Food {
  name: string;
  aliases: string[];
  unit: NutritionUnit;
  kcalPer100: number;
  proteinPer100: number;
}

export interface Estimate {
  foodName: string;
  amount: number;
  unit: NutritionUnit;
  kcal: number;
  proteinG: number;
  matchedCatalog: boolean;
  note: string;
}

function fmtAmount(a: number): string {
  return a === Math.round(a) ? String(Math.trunc(a)) : a.toFixed(1);
}

export function itemLine(e: Pick<Estimate, "foodName" | "amount" | "unit">): string {
  return `${e.foodName} ${fmtAmount(e.amount)}${e.unit}`;
}

export function estimateAsDict(e: Estimate) {
  return {
    food: e.foodName,
    amount: e.amount,
    unit: e.unit,
    kcal: Math.round(e.kcal),
    protein_g: Math.round(e.proteinG * 10) / 10,
    matched: e.matchedCatalog,
    note: e.note,
    item_line: itemLine(e),
  };
}

/** 카탈로그 값은 100g 또는 100ml 기준 대략값(집밥 추정치). */
export const CATALOG: Food[] = [
  { name: "밥·반찬", aliases: ["밥", "흰밥", "공기밥", "집밥", "반찬"], unit: "g", kcalPer100: 173, proteinPer100: 6 },
  { name: "현미밥", aliases: ["잡곡밥"], unit: "g", kcalPer100: 160, proteinPer100: 3.5 },
  { name: "샐러드", aliases: [" greensalad"], unit: "g", kcalPer100: 60, proteinPer100: 2.5 },
  { name: "닭가슴살", aliases: ["닭가슴", "닭살", "chicken breast"], unit: "g", kcalPer100: 110, proteinPer100: 23 },
  { name: "닭다리", aliases: ["닭정육", "치킨"], unit: "g", kcalPer100: 180, proteinPer100: 18 },
  { name: "계란", aliases: ["달걀", "egg", "계란프라이", "삶은계란"], unit: "g", kcalPer100: 140, proteinPer100: 12 },
  { name: "단백질 쉐이크", aliases: ["프로틴", "쉐이크", "protein", "whey"], unit: "g", kcalPer100: 400, proteinPer100: 80 },
  { name: "두부", aliases: ["순두부"], unit: "g", kcalPer100: 76, proteinPer100: 8 },
  { name: "돼지고기", aliases: ["삼겹살", "목살", "돼지"], unit: "g", kcalPer100: 240, proteinPer100: 17 },
  { name: "소고기", aliases: ["한우", "우둔", "국거리"], unit: "g", kcalPer100: 200, proteinPer100: 20 },
  { name: "생선", aliases: ["고등어", "연어", "참치", "생선구이"], unit: "g", kcalPer100: 150, proteinPer100: 20 },
  { name: "과일", aliases: ["사과", "바나나", "오렌지", "과일샐러드"], unit: "g", kcalPer100: 53, proteinPer100: 0.7 },
  { name: "바나나", aliases: [], unit: "g", kcalPer100: 89, proteinPer100: 1.1 },
  { name: "사과", aliases: [], unit: "g", kcalPer100: 52, proteinPer100: 0.3 },
  { name: "요거트", aliases: ["그릭요거트", "yogurt"], unit: "g", kcalPer100: 70, proteinPer100: 4 },
  { name: "그릭요거트", aliases: [], unit: "g", kcalPer100: 97, proteinPer100: 9 },
  { name: "빵", aliases: ["식빵", "토스트", "베이글"], unit: "g", kcalPer100: 265, proteinPer100: 9 },
  { name: "라면", aliases: ["컵라면", "인스턴트"], unit: "g", kcalPer100: 450, proteinPer100: 9 },
  { name: "김치", aliases: [], unit: "g", kcalPer100: 20, proteinPer100: 2 },
  { name: "치즈", aliases: [], unit: "g", kcalPer100: 350, proteinPer100: 22 },
  { name: "견과", aliases: ["아몬드", "호두", "땅콩"], unit: "g", kcalPer100: 600, proteinPer100: 20 },
  { name: "올리브오일", aliases: ["식용유", "기름"], unit: "ml", kcalPer100: 884, proteinPer100: 0 },
  { name: "커피", aliases: ["아메리카노", "에스프레소", "블랙커피"], unit: "ml", kcalPer100: 2.5, proteinPer100: 0 },
  { name: "라떼", aliases: ["카페라떼", "밀크커피"], unit: "ml", kcalPer100: 45, proteinPer100: 2.5 },
  { name: "우유", aliases: ["흰우유", "milk"], unit: "ml", kcalPer100: 42, proteinPer100: 3.4 },
  { name: "두유", aliases: [], unit: "ml", kcalPer100: 54, proteinPer100: 3.3 },
  { name: "주스", aliases: ["오렌지주스", "과일주스"], unit: "ml", kcalPer100: 45, proteinPer100: 0.5 },
  { name: "맥주", aliases: ["소주", "술"], unit: "ml", kcalPer100: 43, proteinPer100: 0.5 },
  { name: "물", aliases: ["생수", "water"], unit: "ml", kcalPer100: 0, proteinPer100: 0 },
  // generic fallbacks (name 미상이나 unit은 아는 경우)
  { name: "일반 음식", aliases: ["음식", "meal", "기타"], unit: "g", kcalPer100: 150, proteinPer100: 8 },
  { name: "음료", aliases: ["드링크", "drink"], unit: "ml", kcalPer100: 30, proteinPer100: 0 },
];

export function matchFood(query: string): Food | null {
  const q = query.trim().toLowerCase();
  if (!q) return null;
  // 원본 그대로: 이름/별칭 구분 없이 카탈로그 배열 순서상 첫 매치를 반환한다.
  // "과일"의 별칭에 "사과"/"바나나"가 있어 전용 항목보다 먼저 매칭되는 것도
  // 원본의 동작이라 그대로 유지한다(diet-nutrition-calc.test.ts에 케이스 있음).
  for (const f of CATALOG) {
    if (f.name.toLowerCase() === q) return f;
    if (f.aliases.some((a) => a.toLowerCase() === q)) return f;
  }
  let best: Food | null = null;
  let bestLen = 0;
  for (const f of CATALOG) {
    for (const k of [f.name, ...f.aliases]) {
      const kl = k.toLowerCase();
      if (kl.length < 2) continue;
      if ((q.includes(kl) || kl.includes(q)) && kl.length > bestLen) {
        best = f;
        bestLen = kl.length;
      }
    }
  }
  return best;
}

export function estimate(foodQuery: string, amount: number, unit: NutritionUnit): Estimate | null {
  if (!(amount > 0) || !(amount < 50_000)) return null;
  const q = foodQuery.trim();
  if (!q) return null;

  const food = matchFood(q);
  if (food) {
    const factor = amount / 100.0;
    const kcal = (Math.round(food.kcalPer100 * factor * 10) / 10);
    const protein = (Math.round(food.proteinPer100 * factor * 10) / 10);
    let note = `${food.name} 기준 약 ${Math.trunc(Math.round(food.kcalPer100))}kcal/100${food.unit}`;
    if (food.unit !== unit) note += ` · 단위 ${unit}로 환산(대략)`;
    return {
      foodName: food.name,
      amount,
      unit,
      kcal: Math.max(0, kcal),
      proteinG: Math.max(0, protein),
      matchedCatalog: true,
      note,
    };
  }

  const generic = unit === "ml"
    ? CATALOG.find((f) => f.name === "음료")!
    : CATALOG.find((f) => f.name === "일반 음식")!;
  const factor = amount / 100.0;
  return {
    foodName: q,
    amount,
    unit,
    kcal: Math.max(0, Math.round(generic.kcalPer100 * factor * 10) / 10),
    proteinG: Math.max(0, Math.round(generic.proteinPer100 * factor * 10) / 10),
    matchedCatalog: false,
    note: `목록에 없는 음식 · ${unit === "ml" ? "음료" : "일반 음식"} 평균으로 대략 계산. kcal을 직접 고칠 수 있어요.`,
  };
}

const MEAL_SLOTS = ["아침", "점심", "저녁", "간식"];

/** 자유 텍스트 파싱: "닭가슴살 150g", "커피 300ml", "150g 닭가슴살", "우유 200" */
export function parse(text: string, defaultUnit: NutritionUnit | null = null): Estimate | null {
  const raw = text.trim();
  if (!raw) return null;

  // 명시적 단위 우선 (ml → g → kg 순서 고정 — 원본과 동일)
  const patterns: { re: RegExp; unit: NutritionUnit; kgToG: boolean }[] = [
    { re: /(\d+(?:\.\d+)?)\s*(ml|mL|ML|밀리|밀리리터)/i, unit: "ml", kgToG: false },
    { re: /(\d+(?:\.\d+)?)\s*(g|G|그램|그람)/i, unit: "g", kgToG: false },
    { re: /(\d+(?:\.\d+)?)\s*(kg|KG|킬로)/i, unit: "g", kgToG: true },
  ];
  for (const { re, unit, kgToG } of patterns) {
    const m = re.exec(raw);
    if (!m) continue;
    let amount = Number(m[1]);
    if (kgToG) amount *= 1000;
    if (!(amount > 0)) continue;

    let name = raw.slice(0, m.index) + raw.slice(m.index + m[0].length);
    name = name.replace(/,/g, " ").trim();
    for (const slot of MEAL_SLOTS) name = name.split(slot).join("");
    name = name.trim();
    if (!name) name = unit === "ml" ? "음료" : "일반 음식";
    return estimate(name, amount, unit);
  }

  // 단위 없음: defaultUnit + 말미 숫자 ("닭가슴살 150")
  if (defaultUnit) {
    const m = /^(.*?)(\d+(?:\.\d+)?)\s*$/.exec(raw);
    if (m) {
      const amount = Number(m[2]);
      const name = m[1].trim();
      if (amount > 0 && name) return estimate(name, amount, defaultUnit);
    }
  }
  return null;
}
