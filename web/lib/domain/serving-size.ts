// 원본: ~/ingreed/scripts/hieng_rules.ts — 1회 섭취참고량 파서만 이식(읽기 전용 원본, 수정 없음).
// 이식하지 않은 것: roundsUpTo30g · SNACK_STANDARD · MEAL_STANDARD · perServing.
// 이유(원본 주석): 그건 어린이 기호식품 고시(HIENG) 판정용 "규제 환산"이다. 우리가
// 재는 것은 사용자가 실제로 먹은 양이므로 30g 올림 등을 적용하면 안 먹은 당·나트륨이
// 기록된다 — .claude/specs/ingreed-diet-nutrition/spec.md §3.
//
// 이 파서가 존재하는 이유는 조용히 틀린 값 두 개다(원본이 실측으로 잡아낸 함정).
// 둘 다 예외를 던지지 않고 그럴듯한 숫자를 준다 — 그래서 회귀 테스트로 값의 성질을
// 못박는다(tests/domain/serving-size.test.ts).

/**
 * 컵/봉지 판별 — hieng_rules.ts:170
 *
 * 「식품등의 표시기준」 별표 1 의 "면류(용기면만 해당한다)" 단서가 여기에 걸린다.
 * `product_type` 은 데이터상 전부 '유탕면'이라 유형으로 갈리지 않는다 — 이름 매칭은
 * 근사지만, 원본이 라벨률로 교차검증한 값이다(용기 73% vs 봉지 26%).
 */
export const CUP_NOODLE = /컵|사발|용기|보울|bowl|cup/i;

/**
 * 중량 표기에서 g 을 뽑는다. **단위가 없으면 값이 아니다.** — hieng_rules.ts:267
 *
 * ⚠ 단위를 선택으로 두면(예: `(g|ml|kg|l)?` · 없으면 g 으로 간주) 단위 없는 표기
 * (예: "1식")가 1g 으로 읽힌다. 1회량이 1g 이면 환산값이 100분의 1이라 어떤 값도
 * 정상적으로 비교되지 않는다. 모르는 것은 `null` 로 두어 판정/기록에서 빠지게 한다 —
 * 1g 으로 읽어 조용히 틀리는 것보다 정직하다. 이 정규식을 "관대하게" 고치지 않는다.
 */
export function grams(v: unknown): number | null {
  const m = String(v ?? "").match(/([\d.]+)\s*(g|ml|kg|l)\b/i);
  if (!m) return null;
  const unit = m[2].toLowerCase();
  const n = parseFloat(m[1]) * (unit === "kg" || unit === "l" ? 1000 : 1);
  return Number.isFinite(n) && n > 0 ? n : null;
}

/**
 * 1회량 표기가 여러 유형의 표를 통째로 담고 있는가 — hieng_rules.ts:202
 * (숫자+단위가 두 번 이상 나오면 표로 본다)
 */
export function isServingTable(raw: unknown): boolean {
  return (String(raw ?? "").match(/[\d.]+\s*(g|ml)\b/gi) ?? []).length > 1;
}

/**
 * 신고 1회 섭취참고량(g). **다중 표기 문자열을 카테고리로 갈라 읽는다.** — hieng_rules.ts:191
 *
 * ⚠ 제조사가 자기 값 대신 「식품등의 표시기준」 1회 섭취참고량 표의 행을 통째로
 * 신고하는 카테고리가 있다. 유탕면은 원본 실측에서 754건 중 729건(97%)이 이 문자열이다:
 *
 *     "생·숙면 200g, 건면 100g, 당면 30g, 유탕면(봉지)120g, 유탕면(용기)80g"
 *
 * 첫 숫자만 집으면 200(생·숙면)이 유탕면의 1회량으로 잘못 읽힌다. 유탕면의 값은
 * 같은 문자열 안에 있다 — 봉지 120 · 용기 80. 컵/봉지는 품목유형이 아니라 제품명
 * 정규식(`CUP_NOODLE`)으로 가른다.
 */
export function declaredServingG(raw: unknown, category: string, name: string): number | null {
  const s = String(raw ?? "");
  if (category === "유탕면") {
    const cup = /유탕면\s*\(\s*용기\s*\)\s*([\d.]+)\s*g/.exec(s);
    const bag = /유탕면\s*\(\s*봉지\s*\)\s*([\d.]+)\s*g/.exec(s);
    if (cup && bag) return Number(CUP_NOODLE.test(name) ? cup[1] : bag[1]);
  }
  return grams(s);
}
