// Swift 원본: Packages/KnowledgeCore/Sources/KnowledgeCore/DietStore.swift, DietProfile.swift
// P4a 스코프: 조회에 필요한 순수 계산만 이식한다(assistant.*, timeline.list,
// diet.day_summary/week_review/goals/profile.get/ping). diet.dashboard·
// diet.fasting.status(Mifflin 플랜 투영·HealthKit 참고값·요일상대 문구 생성)는
// 도메인 로직 본체 규모라 별도 세션으로 미룬다 — REFACTOR_STATUS.md 참고.
//
// 순수 함수만 둔다 — DB 접근은 lib/db/diet.ts.

const SEOUL_TZ = "Asia/Seoul";

export interface Meal {
  id: string;
  ts: string;
  items: string[];
  kcal: number | null;
  proteinG: number | null;
  note: string | null;
}

export interface Workout {
  id: string;
  ts: string;
  kind: string;
  minutes: number;
  intensity: string | null;
}

export interface Metric {
  id: string;
  ts: string;
  weightKg: number | null;
  sleepH: number | null;
}

export interface DaySnapshot {
  date: string;
  meals: Meal[];
  workouts: Workout[];
  metrics: Metric[];
  kcal: number;
  proteinG: number;
  workoutMinutes: number;
  summaryText: string;
}

export interface Goals {
  targetKcal: number;
  targetProteinG: number;
  weeklyWorkouts: number;
  targetWorkoutMinutesPerDay: number;
}

export const DEFAULT_GOALS: Goals = {
  targetKcal: 2000,
  targetProteinG: 100,
  weeklyWorkouts: 4,
  targetWorkoutMinutesPerDay: 30,
};

export type Sex = "male" | "female";
export type Activity = "sedentary" | "light" | "moderate" | "active";

export interface Profile {
  heightCm: number;
  weightKg: number;
  age: number;
  sex: Sex;
  targetWeightKg: number;
  activity: Activity;
}

const ACTIVITY_FACTOR: Record<Activity, number> = {
  sedentary: 1.2,
  light: 1.375,
  moderate: 1.55,
  active: 1.725,
};

/** "yyyy-MM-dd" — 서버 로케일과 무관하게 Asia/Seoul 기준으로 고정한다(단일 테넌트, 한국어 개인 앱). */
export function dayKey(d: Date): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: SEOUL_TZ,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(d);
}

export function seoulHour(d: Date): number {
  const s = new Intl.DateTimeFormat("en-GB", {
    timeZone: SEOUL_TZ,
    hour: "2-digit",
    hourCycle: "h23",
  }).format(d);
  return Number(s);
}

function dayText(
  key: string,
  meals: Meal[],
  workouts: Workout[],
  kcal: number,
  protein: number,
  minutes: number,
): string {
  if (meals.length === 0 && workouts.length === 0) {
    return `${key}: 식사·운동 기록이 없어요.`;
  }
  const parts: string[] = [`${key}:`];
  if (meals.length > 0) {
    const names = meals.flatMap((m) => m.items).slice(0, 6).join(", ");
    parts.push(`식사 ${meals.length}회 (${names}) · ${Math.trunc(kcal)} kcal · 단백질 ${Math.trunc(protein)}g`);
  }
  if (workouts.length > 0) {
    const kinds = workouts.map((w) => w.kind).join(", ");
    parts.push(`운동 ${workouts.length}회 (${kinds}) · ${minutes}분`);
  }
  return parts.join(" ");
}

export function buildDaySnapshot(
  key: string,
  meals: Meal[],
  workouts: Workout[],
  metrics: Metric[],
): DaySnapshot {
  const kcal = meals.reduce((s, m) => s + (m.kcal ?? 0), 0);
  const proteinG = meals.reduce((s, m) => s + (m.proteinG ?? 0), 0);
  const workoutMinutes = workouts.reduce((s, w) => s + w.minutes, 0);
  return {
    date: key,
    meals,
    workouts,
    metrics,
    kcal,
    proteinG,
    workoutMinutes,
    summaryText: dayText(key, meals, workouts, kcal, proteinG, workoutMinutes),
  };
}

export function daySummaryDict(day: DaySnapshot) {
  return {
    date: day.date,
    meals: day.meals.map(mealDict),
    workouts: day.workouts.map(workoutDict),
    metrics: day.metrics.map(metricDict),
    totals: {
      kcal: day.kcal,
      protein_g: day.proteinG,
      workout_minutes: day.workoutMinutes,
      meal_count: day.meals.length,
      workout_count: day.workouts.length,
    },
    summary_text: day.summaryText,
  };
}

function mealDict(m: Meal) {
  const d: Record<string, unknown> = { id: m.id, ts: m.ts, items: m.items };
  if (m.kcal != null) d.kcal = m.kcal;
  if (m.proteinG != null) d.protein_g = m.proteinG;
  if (m.note != null) d.note = m.note;
  return d;
}

function workoutDict(w: Workout) {
  const d: Record<string, unknown> = { id: w.id, ts: w.ts, kind: w.kind, minutes: w.minutes };
  if (w.intensity != null) d.intensity = w.intensity;
  return d;
}

function metricDict(m: Metric) {
  const d: Record<string, unknown> = { id: m.id, ts: m.ts };
  if (m.weightKg != null) d.weight_kg = m.weightKg;
  if (m.sleepH != null) d.sleep_h = m.sleepH;
  return d;
}

function eventSource(id: string, intensity: string | null): string {
  if (id.startsWith("hk-")) return "healthkit";
  if (intensity === "healthkit") return "healthkit";
  return "user";
}

export interface TimelineEvent {
  ts: string;
  type: "meal" | "workout" | "metric";
  title: string;
  source: string;
  id: string;
}

export function timelineEvents(day: DaySnapshot): TimelineEvent[] {
  const events: TimelineEvent[] = [];
  for (const m of day.meals) {
    events.push({ ts: m.ts, type: "meal", title: m.items.join(" · "), source: eventSource(m.id, null), id: m.id });
  }
  for (const w of day.workouts) {
    events.push({
      ts: w.ts,
      type: "workout",
      title: `${w.kind} · ${w.minutes}분`,
      source: eventSource(w.id, w.intensity),
      id: w.id,
    });
  }
  for (const m of day.metrics) {
    const parts: string[] = [];
    if (m.weightKg != null) parts.push(`${m.weightKg.toFixed(1)}kg`);
    if (m.sleepH != null) parts.push(`수면 ${m.sleepH.toFixed(1)}h`);
    events.push({
      ts: m.ts,
      type: "metric",
      title: parts.length > 0 ? parts.join(" · ") : "지표",
      source: eventSource(m.id, null),
      id: m.id,
    });
  }
  return events.sort((a, b) => a.ts.localeCompare(b.ts));
}

export interface Gap {
  kind: "meal" | "workout" | "sleep";
  label: string;
  priority: number;
  slot?: string;
}

/** today는 오늘, yesterday는 어제(수면 체크용) 스냅샷. */
export function missingLogChecklist(now: Date, today: DaySnapshot, yesterday: DaySnapshot): Gap[] {
  const hour = seoulHour(now);
  const mealText = today.meals.flatMap((m) => m.items).join(" ");
  const has = (words: string[]) => words.some((w) => mealText.includes(w));
  const gaps: Gap[] = [];

  if (hour >= 9 && !has(["아침", "조식", "breakfast"])) {
    gaps.push({ kind: "meal", slot: "아침", label: "아침 기록이 없어요", priority: 1 });
  }
  if (hour >= 14 && !has(["점심", "중식", "lunch"])) {
    gaps.push({ kind: "meal", slot: "점심", label: "점심 기록이 없어요", priority: 2 });
  }
  if (hour >= 20 && !has(["저녁", "석식", "dinner"])) {
    gaps.push({ kind: "meal", slot: "저녁", label: "저녁 기록이 없어요", priority: 3 });
  }
  if (hour >= 12 && today.workoutMinutes === 0) {
    gaps.push({ kind: "workout", label: "오늘 운동 기록이 없어요", priority: 4 });
  }
  if (hour < 12) {
    const hasSleep = yesterday.metrics.some((m) => (m.sleepH ?? 0) > 0);
    if (!hasSleep) {
      gaps.push({ kind: "sleep", label: "어제 수면이 없어요", priority: 5 });
    }
  }
  return gaps.sort((a, b) => a.priority - b.priority);
}

/** daysDesc[0]=오늘 매트릭, [1]=어제 ... 최대 3일. 가장 최근에 수면 기록된 값. */
export function latestSleepHours(daysDesc: DaySnapshot[]): number | null {
  for (const day of daysDesc) {
    const last = [...day.metrics].reverse().find((m) => (m.sleepH ?? 0) > 0);
    if (last) return last.sleepH as number;
  }
  return null;
}

export function sleepCoachHint(recentSleepH: number | null): string | null {
  if (recentSleepH == null) return null;
  const h = recentSleepH.toFixed(1);
  if (recentSleepH < 6) return `최근 수면 ${h}시간 — 오늘은 칼로리·운동 목표를 조금 낮춰도 괜찮아요.`;
  if (recentSleepH >= 8) return `최근 수면 ${h}시간 — 회복 좋음, 단백질 목표 유지해 보세요.`;
  return `최근 수면 ${h}시간.`;
}

/**
 * daysDesc[0]=오늘 ... 이후 과거로. Swift 원본의 이중 루프(오늘이 비어있으면
 * 어제부터 재계산)는 결과적으로 "오늘 기록 여부(+1) + 어제부터 연속 기록일수"와
 * 동치라 단순화했다.
 */
export function activityStreak(daysDesc: DaySnapshot[]): number {
  let streak = 0;
  const today = daysDesc[0];
  const todayEmpty = !today || (today.meals.length === 0 && today.workouts.length === 0);
  if (!todayEmpty) streak += 1;
  for (let i = 1; i < daysDesc.length; i++) {
    const d = daysDesc[i];
    if (d.meals.length === 0 && d.workouts.length === 0) break;
    streak += 1;
  }
  return streak;
}

export interface SuggestedAction {
  title: string;
  subtitle: string;
  slot: string | null;
}

export function suggestedAction(now: Date, today: DaySnapshot): SuggestedAction {
  const hour = seoulHour(now);
  const mealText = today.meals.flatMap((m) => m.items).join(" ");
  const has = (words: string[]) => words.some((w) => mealText.includes(w));

  if (hour < 11 && !has(["아침", "조식", "breakfast"])) {
    return { title: "아침을 남겨 볼까요?", subtitle: "한 줄로 빠르게 기록해요", slot: "아침" };
  }
  if (hour >= 11 && hour < 15 && !has(["점심", "중식", "lunch"])) {
    return { title: "점심은 어떠셨나요?", subtitle: "kcal만 적어도 충분해요", slot: "점심" };
  }
  if (hour >= 17 && hour < 22 && !has(["저녁", "석식", "dinner"])) {
    return { title: "저녁을 기록해 주세요", subtitle: "단백질 목표에 도움이 돼요", slot: "저녁" };
  }
  if (today.workoutMinutes === 0 && hour >= 12) {
    return { title: "오늘 운동은요?", subtitle: "걷기 20분만 남겨도 좋아요", slot: null };
  }
  if (today.meals.length === 0) {
    return { title: "오늘 첫 기록을 남겨 보세요", subtitle: "식사·운동 모두 한 줄로 가능해요", slot: "점심" };
  }
  return { title: "오늘도 잘하고 있어요", subtitle: today.summaryText, slot: null };
}

export function goalsDict(g: Goals) {
  return {
    target_kcal: g.targetKcal,
    target_protein_g: g.targetProteinG,
    weekly_workouts: g.weeklyWorkouts,
    target_workout_minutes_per_day: g.targetWorkoutMinutesPerDay,
  };
}

export interface DayBar {
  date: string;
  kcal: number;
  proteinG: number;
  workoutMinutes: number;
  mealCount: number;
  workoutCount: number;
}

export function dayBarFrom(s: DaySnapshot): DayBar {
  return {
    date: s.date,
    kcal: s.kcal,
    proteinG: s.proteinG,
    workoutMinutes: s.workoutMinutes,
    mealCount: s.meals.length,
    workoutCount: s.workouts.length,
  };
}

/** diet.week_review 그대로 (내러티브 없음) — bars는 오래된 날짜가 먼저 오도록 정렬해서 넘긴다. */
export function weekReview(bars: DayBar[], goals: Goals) {
  const mealCount = bars.reduce((s, b) => s + b.mealCount, 0);
  const workoutCount = bars.reduce((s, b) => s + b.workoutCount, 0);
  const workoutMinutes = bars.reduce((s, b) => s + b.workoutMinutes, 0);
  const kcalTotal = bars.reduce((s, b) => s + b.kcal, 0);
  const proteinTotal = bars.reduce((s, b) => s + b.proteinG, 0);
  return {
    from: bars[0]?.date ?? "",
    to: bars[bars.length - 1]?.date ?? "",
    days: bars.map((b) => ({
      date: b.date,
      kcal: b.kcal,
      protein_g: b.proteinG,
      workout_minutes: b.workoutMinutes,
      meals: b.mealCount,
      workouts: b.workoutCount,
    })),
    totals: {
      kcal: kcalTotal,
      protein_g: proteinTotal,
      workout_minutes: workoutMinutes,
      meal_count: mealCount,
      workout_count: workoutCount,
    },
    summary_text:
      `최근 7일: 식사 ${mealCount}회 · 운동 ${workoutCount}회 · ${workoutMinutes}분\n` +
      `칼로리 합 ${Math.trunc(kcalTotal)} kcal`,
    goals: goalsDict(goals),
  };
}

/** assistant.week_review — diet.week_review + 내러티브. F-1(미팅 전면 폐기)로 review_pending은 항상 0. */
export function buildAssistantWeekReview(
  bars: DayBar[],
  goals: Goals,
  streak: number,
  sleepHint: string | null,
  inboxOpen: number,
) {
  const week = weekReview(bars, goals);
  const narrative: string[] = [week.summary_text, `연속 기록 ${streak}일`];
  if (sleepHint) narrative.push(sleepHint);
  return {
    ...week,
    streak_days: streak,
    narrative: narrative.join("\n"),
    narrative_lines: narrative,
    review_pending: 0,
    inbox_open: inboxOpen,
    ...(sleepHint ? { sleep_hint: sleepHint } : {}),
  };
}

export function bmr(p: Profile): number {
  const base = 10 * p.weightKg + 6.25 * p.heightCm - 5 * p.age;
  return p.sex === "male" ? base + 5 : base - 161;
}

export function tdee(p: Profile): number {
  return bmr(p) * ACTIVITY_FACTOR[p.activity];
}

export function recommendedKcal(p: Profile): number {
  const delta = p.weightKg - p.targetWeightKg;
  const t = tdee(p);
  if (delta > 0.3) {
    const floor = p.sex === "female" ? 1200 : 1500;
    return Math.max(floor, Math.round(t - 500));
  }
  if (delta < -0.3) return Math.round(t + 300);
  return Math.round(t);
}

export function recommendedProteinG(p: Profile): number {
  return Math.round(p.weightKg * 1.6);
}

/** diet.profile.get — Mifflin–St Jeor BMR/TDEE만 포함(플랜 투영은 diet.dashboard 몫, 별도 세션). */
export function profileDict(p: Profile) {
  return {
    height_cm: p.heightCm,
    weight_kg: p.weightKg,
    age: p.age,
    sex: p.sex,
    target_weight_kg: p.targetWeightKg,
    activity: p.activity,
    bmr: Math.round(bmr(p)),
    tdee: Math.round(tdee(p)),
    recommended_kcal: recommendedKcal(p),
    recommended_protein_g: recommendedProteinG(p),
  };
}
