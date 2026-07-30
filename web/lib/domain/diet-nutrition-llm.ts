// C3(웹 신규 기능 — Swift 원본에 대응물 없음): 규칙 기반 카탈로그
// (diet-nutrition-calc.ts, 30종)가 못 맞춘 음식의 영양값을 LLM으로 메운다.
//
// LLM에는 **100g/100ml 기준값만** 묻는다. 분량을 곱하는 산술은 여기서 한다:
// (1) 프롬프트가 음식명+단위에만 의존해 "된장찌개 200g"과 "된장찌개 350g"이
//     같은 캐시 키를 쓰고, (2) 검증이 숫자 두 개의 범위 체크로 끝난다.
//
// 이 파일은 순수 함수만 둔다. 라우터·스토어 배선은 lib/diet/nutrition-enrich.ts.
import { Estimate, NutritionUnit } from "./diet-nutrition-calc";

export interface Per100 {
  /** 100g(또는 100ml)당 kcal */
  kcal: number;
  /** 100g(또는 100ml)당 단백질(g) */
  proteinG: number;
}

/** 카탈로그 최대치(올리브오일 884kcal/100ml)를 조금 넘는 선 — 순수 지방이 상한. */
const MAX_KCAL_PER_100 = 900;
const MAX_PROTEIN_PER_100 = 100;
/** 단백질 1g = 4kcal. 열량보다 단백질 열량이 큰 값은 물리적으로 불가능하다
 *  (카탈로그 30종 전부 이 부등식을 만족한다 — 여유 20은 반올림·수분 보정분). */
const PROTEIN_KCAL_SLACK = 20;

export function nutritionPrompt(food: string, unit: NutritionUnit): string {
  const basis = unit === "ml" ? "100ml" : "100g";
  return `당신은 영양 정보 도우미입니다. 음식 이름을 받아 ${basis} 기준 열량과 단백질을 추정하세요.
JSON 객체 하나만 출력하세요. 설명·단위 문자열·코드펜스를 붙이지 마세요.

형식: {"kcal_per_100": 숫자, "protein_g_per_100": 숫자}
kcal_per_100은 0~${MAX_KCAL_PER_100}, protein_g_per_100은 0~${MAX_PROTEIN_PER_100} 범위의 숫자입니다.
정확히 모르면 같은 종류 음식의 일반적인 값으로 추정하세요.

### 음식
${food.trim()} (${basis} 기준)

### 답변
`;
}

/** 코드펜스·앞뒤 잡설을 걷어내고 첫 JSON 객체만 취한다(작은 모델 대비). */
function extractJsonObject(text: string): string | null {
  const start = text.indexOf("{");
  if (start < 0) return null;
  const end = text.indexOf("}", start);
  if (end < 0) return null;
  return text.slice(start, end + 1);
}

function finiteNumber(v: unknown): number | null {
  const n = typeof v === "string" ? Number(v) : v;
  return typeof n === "number" && Number.isFinite(n) ? n : null;
}

/** LLM 응답 → 검증된 Per100. 형식·범위·물리적 정합 중 하나라도 어긋나면 null. */
export function parsePer100(text: string): Per100 | null {
  const json = extractJsonObject(text);
  if (!json) return null;

  let raw: unknown;
  try {
    raw = JSON.parse(json);
  } catch {
    return null;
  }
  if (raw == null || typeof raw !== "object") return null;
  const obj = raw as Record<string, unknown>;

  const kcal = finiteNumber(obj.kcal_per_100);
  const proteinG = finiteNumber(obj.protein_g_per_100);
  if (kcal == null || proteinG == null) return null;
  if (kcal < 0 || kcal > MAX_KCAL_PER_100) return null;
  if (proteinG < 0 || proteinG > MAX_PROTEIN_PER_100) return null;
  if (proteinG * 4 > kcal + PROTEIN_KCAL_SLACK) return null;

  return { kcal, proteinG };
}

/** 규칙 기반 일반식 추정치를 LLM의 100단위 값으로 재계산한다(분량·단위·이름은 유지). */
export function applyPer100(e: Estimate, per100: Per100): Estimate {
  const factor = e.amount / 100.0;
  return {
    ...e,
    kcal: Math.max(0, Math.round(per100.kcal * factor * 10) / 10),
    proteinG: Math.max(0, Math.round(per100.proteinG * factor * 10) / 10),
    // 카탈로그에 여전히 없다 — matched의 의미(카탈로그 수록 여부)는 바꾸지 않는다.
    matchedCatalog: false,
    note: `AI 추정 · 약 ${Math.round(per100.kcal)}kcal/100${e.unit} · kcal을 직접 고칠 수 있어요.`,
  };
}
