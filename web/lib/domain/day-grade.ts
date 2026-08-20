// 하루 등급 — 순수 채점 함수.
//
// 설계 원본: docs/DAILY_GRADE_AND_IA_2026-08.md · .claude/specs/daily-grade/spec.md
//
// ⭐ 이 파일의 존재 이유는 D-A 하나다: **결측을 두 종류로 가른다.**
//
//   구조적(워치 미착용) → 분모에서 뺀다.   사용자가 골라서 감출 수 없기 때문이다.
//   행동적(기록 안 함)  → 0점, 분모에 남긴다. 안 그러면 기록을 안 할수록 등급이 오른다.
//
// 후자를 완화하면 이 제품은 자기기만 기계가 된다. `tests/domain/day-grade.test.ts` 의
// "기록 안 한 날이 나쁘게 먹고 기록한 날보다 높지 않다"가 그 방어선이다.
//
// 임계값은 주입받는다(day-grade-thresholds.ts). 여기에 숫자를 박지 않는다 —
// 원문으로 확인한 값만 임계값이 될 수 있고, 그 확인은 이 파일의 일이 아니다.

export const RULESET_VERSION = "day-grade-1";

export type Grade = "A" | "B" | "C" | "D" | "E";

/**
 * 축의 상태. `absent_structural` 과 `absent_behavioral` 의 차이가 이 모듈의 전부다.
 */
export type AxisState = "present" | "absent_structural" | "absent_behavioral";

export type AxisId = "recovery" | "activity" | "intake";

/** 자동 수집 축은 결측이 구조적, 수동 입력 축은 행동적이다. */
export const AXIS_SUPPLY: Record<AxisId, "auto" | "manual"> = {
  recovery: "auto",
  activity: "auto",
  intake: "manual",
};

export interface AxisResult {
  id: AxisId;
  state: AxisState;
  /** 0~100. state 가 present 가 아니면 null (행동적 결측은 채점에서 0으로 쓰이되 '값을 안다'는 뜻이 아니다) */
  score: number | null;
  /** 사실 진술 한 줄. "수면 5.2h · 권장 7~9h" 처럼 값만 쓴다 */
  reason: string;
}

export interface DayGradeResult {
  /** 채점 가능한 축이 하나도 없으면 null */
  score: number | null;
  grade: Grade | null;
  /** 다른 날과 같은 잣대로 비교할 수 있는가. 행동적 결측이 있으면 false */
  ratable: boolean;
  /** 0~1. 전체 축 중 실제로 값을 아는 축의 비중 */
  confidence: number;
  breakdown: AxisResult[];
  reasons: string[];
  rulesetVersion: string;
}

export interface GradeCuts {
  /** [최소점수, 등급] 내림차순. 어느 것에도 못 미치면 E */
  cuts: [number, Grade][];
}

/** 축별 원점수를 만드는 함수들. 임계값을 이미 적용한 결과를 준다. */
export interface AxisInput {
  state: AxisState;
  score: number | null;
  reason: string;
}

export interface DayGradeInput {
  recovery: AxisInput;
  activity: AxisInput;
  intake: AxisInput;
}

export interface GradeDayOptions {
  /**
   * 하루가 끝났는가. 판정(Asia/Seoul 자정 경계) 자체는 이 함수의 일이 아니다 —
   * 호출자(RPC 핸들러)가 이미 판정한 결과를 넘긴다. 여기서 new Date() 를 부르지 않는다.
   */
  closed: boolean;
}

const AXIS_ORDER: AxisId[] = ["recovery", "activity", "intake"];

/**
 * 축 가중치는 **동일**하다(spec.md D-B). 어느 축이 더 중요한지 댈 수 있는 외부
 * 근거가 없다. 근거 없는 가중치는 숫자로 위장한 직관이라 넣지 않는다.
 * 근거가 생기면 그때 바꾸고 이유를 남긴다.
 */
const WEIGHT: Record<AxisId, number> = { recovery: 1, activity: 1, intake: 1 };

export function toGrade(score: number, cuts: GradeCuts): Grade {
  for (const [min, g] of cuts.cuts) {
    if (score >= min) return g;
  }
  return "E";
}

/**
 * 하루 등급을 매긴다.
 *
 * 분모 규칙 — 여기가 핵심이다.
 *   present            → 분모에 넣고 자기 점수를 쓴다
 *   absent_structural  → **분모에서 뺀다**
 *   absent_behavioral  → **분모에 넣고 0점으로 쓴다**
 */
export function gradeDay(input: DayGradeInput, cuts: GradeCuts, opts: GradeDayOptions): DayGradeResult {
  const breakdown: AxisResult[] = AXIS_ORDER.map((id) => {
    const a = input[id];
    return {
      id,
      state: a.state,
      score: a.state === "present" ? a.score : null,
      reason: a.reason,
    };
  });

  let weighted = 0;
  let denominator = 0;
  let knownWeight = 0;
  let presentCount = 0;
  let hasBehavioralGap = false;

  for (const id of AXIS_ORDER) {
    const a = input[id];
    const w = WEIGHT[id];

    if (a.state === "present") {
      const s = a.score ?? 0;
      weighted += clamp(s) * w;
      denominator += w;
      knownWeight += w;
      presentCount += 1;
      continue;
    }
    if (a.state === "absent_behavioral") {
      // 0점이지만 분모에는 남는다. 빼면 "기록 안 할수록 좋은 날"이 된다.
      denominator += w;
      hasBehavioralGap = true;
      continue;
    }
    // absent_structural — 분모에서 빠진다. 감출 수 없는 결측이므로 벌하지 않는다.
  }

  const totalWeight = AXIS_ORDER.reduce((s, id) => s + WEIGHT[id], 0);
  const confidence = round2(knownWeight / totalWeight);

  if (denominator === 0) {
    // 채점할 축이 하나도 없다. 등급을 지어내지 않는다.
    return {
      score: null,
      grade: null,
      ratable: false,
      confidence,
      breakdown,
      reasons: breakdown.map((b) => b.reason).filter(Boolean),
      rulesetVersion: RULESET_VERSION,
    };
  }

  /**
   * 소수 1자리까지 남긴다. **정수로 반올림하면 기록의 이득이 지워진다** —
   * 섭취 1점(66.67)과 미기록(66.67)이 둘 다 67 로 뭉개져 "기록해도 같다"가 된다.
   * 반올림은 표시의 문제지 채점의 문제가 아니다(화면에서 정수로 보이면 된다).
   */
  const score = round1(weighted / denominator);

  if (!opts.closed) {
    // 진행 중인 하루 — 등급을 매기지 않는다. 아직 안 끝난 하루는 다른 날과 비교할 수
    // 없다(자정까지 남은 시간만큼 낮은 점수로 보일 수 있어서). score 는 참고값으로
    // 남기되(예: 진행 중 화면 표시용) grade·ratable 은 강제로 미확정 상태다.
    // pro-rate(경과 비율로 목표를 깎는 안)는 기각됐다 — 하지 않는다.
    return {
      score,
      grade: null,
      ratable: false,
      confidence,
      breakdown,
      reasons: breakdown.map((b) => b.reason).filter(Boolean),
      rulesetVersion: RULESET_VERSION,
    };
  }

  return {
    score,
    grade: toGrade(score, cuts),
    // 행동적 결측이 있거나 아는 축이 1개뿐이면 다른 날과 나란히 놓을 수 없다.
    ratable: !hasBehavioralGap && presentCount >= 2,
    confidence,
    breakdown,
    reasons: breakdown.map((b) => b.reason).filter(Boolean),
    rulesetVersion: RULESET_VERSION,
  };
}

function clamp(n: number): number {
  return Math.max(0, Math.min(100, n));
}

function round2(n: number): number {
  return Math.round(n * 100) / 100;
}

function round1(n: number): number {
  return Math.round(n * 10) / 10;
}

// ── 축 점수의 형태 (spec.md D-C) ────────────────────────────────────────
// 값이 아니라 **모양**만 여기 둔다. 임계값은 전부 인자다.

/**
 * 범위형 — 회복(수면). 범위 안이면 100, 벗어난 만큼 선형 감점.
 * 너무 적게 자도, 너무 많이 자도 좋지 않기 때문에 상한도 벌한다.
 */
export function rangeScore(value: number, min: number, max: number, fullPenaltyAt: number): number {
  if (value >= min && value <= max) return 100;
  const gap = value < min ? min - value : value - max;
  if (fullPenaltyAt <= 0) return 0;
  return clamp(100 - (gap / fullPenaltyAt) * 100);
}

/**
 * 달성률형 — 활동. 목표 대비 비율, 100 상한.
 * 많이 움직여서 나쁠 것이 없으므로 초과를 벌하지 않는다.
 */
export function attainmentScore(actual: number, target: number): number {
  if (target <= 0) return 100;
  return clamp((actual / target) * 100);
}

/**
 * 상한형 — 당·나트륨·포화지방. 상한 이하면 100, 초과분에 비례해 감점.
 * `overBy` 는 "상한의 몇 배까지 초과하면 0점인가".
 */
export function limitScore(actual: number, limit: number, overBy = 1): number {
  if (limit <= 0) return 100;
  if (actual <= limit) return 100;
  const excessRatio = (actual - limit) / (limit * overBy);
  return clamp(100 - excessRatio * 100);
}
