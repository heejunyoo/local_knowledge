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
  /** e.g. "morning_fasted"/"healthkit" — weightForPlan() 우선순위 판정에만 쓰이고 일별 요약에는 노출 안 됨(원본 metricDict과 동일). */
  context: string | null;
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

const RECOMMENDED_WEEKLY_WORKOUTS: Record<Activity, number> = {
  sedentary: 3, light: 3, moderate: 4, active: 5,
};

const RECOMMENDED_WORKOUT_MINUTES_PER_DAY: Record<Activity, number> = {
  sedentary: 20, light: 30, moderate: 40, active: 45,
};

export function recommendedWeeklyWorkouts(activity: Activity): number {
  return RECOMMENDED_WEEKLY_WORKOUTS[activity];
}

export function recommendedWorkoutMinutesPerDay(activity: Activity): number {
  return RECOMMENDED_WORKOUT_MINUTES_PER_DAY[activity];
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

export function profileIsComplete(p: Profile): boolean {
  return (
    p.heightCm > 100 && p.heightCm < 250 &&
    p.weightKg > 30 && p.weightKg < 300 &&
    p.age >= 14 && p.age <= 100 &&
    p.targetWeightKg > 30 && p.targetWeightKg < 300
  );
}

// ---------------------------------------------------------------------------
// P4b: diet.dashboard / diet.fasting.status — Swift 원본: DietProfile.swift
// (planSummary), DietStore.swift (fastingStatus/healthReferenceLocked/
// dashboard/weightForPlanLocked/localDayTimeLabels). 1:1 번역.
// ---------------------------------------------------------------------------

const KCAL_PER_KG = 7700;

export interface PlanProjection {
  bmr: number;
  tdee: number;
  recommendedKcal: number;
  recommendedProteinG: number;
  dailyDeficit: number;
  weeksToGoal: number | null;
  daysToGoal: number | null;
  etaText: string;
  paceText: string;
  avgIntakeUsed: number | null;
}

/** 원본: DietProfile.planSummary(avgDailyIntakeKcal:plannedKcal:) */
export function planSummary(p: Profile, avgDailyIntakeKcal: number | null, plannedKcal: number): PlanProjection {
  const delta = p.weightKg - p.targetWeightKg;
  const goalKcal = plannedKcal > 0 ? plannedKcal : recommendedKcal(p);
  const maintenance = tdee(p);
  const effectiveIntake = avgDailyIntakeKcal ?? goalKcal;
  let dailyDeficit = maintenance - effectiveIntake;

  if (delta > 0.3 && dailyDeficit < 100) {
    dailyDeficit = Math.max(100, maintenance - goalKcal);
  }
  if (delta < -0.3 && dailyDeficit > -100) {
    dailyDeficit = Math.min(-100, maintenance - goalKcal);
  }

  const base = {
    bmr: Math.round(bmr(p)),
    tdee: Math.round(maintenance),
    recommendedKcal: recommendedKcal(p),
    recommendedProteinG: recommendedProteinG(p),
    dailyDeficit,
    avgIntakeUsed: avgDailyIntakeKcal,
  };

  if (Math.abs(delta) < 0.3) {
    return {
      ...base,
      weeksToGoal: 0,
      daysToGoal: 0,
      etaText: "목표 체중에 거의 도달했어요. 유지 칼로리로 관리하면 돼요.",
      paceText: "유지",
    };
  }

  if (delta > 0) {
    // 원본 그대로: delta>0.3일 때 위 대체식이 dailyDeficit을 항상 100 이상으로
    // 강제하므로("정체" 분기, <=50) 이 가지는 사실상 도달 불가능하다 — 방어적
    // 코드를 "고치지" 않고 그대로 옮긴다(diet-dashboard.test.ts에 근거 있음).
    if (!(dailyDeficit > 50)) {
      return {
        ...base,
        weeksToGoal: null,
        daysToGoal: null,
        etaText: `지금 섭취가 유지 칼로리와 비슷해요. 목표 칼로리(${Math.trunc(goalKcal)}kcal)에 맞춰 먹으면 감량이 시작돼요.`,
        paceText: "정체",
      };
    }
    const totalDeficitNeeded = delta * KCAL_PER_KG;
    const d = totalDeficitNeeded / dailyDeficit;
    const days = Math.max(1, Math.round(d));
    const weeks = d / 7;
    return {
      ...base,
      weeksToGoal: weeks,
      daysToGoal: days,
      etaText: `지금 페이스(하루 약 ${Math.trunc(dailyDeficit)}kcal 부족)면 약 ${days}일(${weeks.toFixed(1)}주) 뒤 목표 체중 근처예요.`,
      paceText: `주 ${((dailyDeficit * 7) / KCAL_PER_KG).toFixed(2)}kg 감량 페이스`,
    };
  }

  const surplus = -dailyDeficit;
  if (!(surplus > 50)) {
    return {
      ...base,
      weeksToGoal: null,
      daysToGoal: null,
      etaText: `증량이 목표인데 섭취가 부족해 보여요. 목표 ${Math.trunc(goalKcal)}kcal 근처로 올려 보세요.`,
      paceText: "정체",
    };
  }
  const need = Math.abs(delta) * KCAL_PER_KG;
  const d = need / surplus;
  const days = Math.max(1, Math.round(d));
  const weeks = d / 7;
  return {
    ...base,
    weeksToGoal: weeks,
    daysToGoal: days,
    etaText: `지금 페이스면 약 ${days}일(${weeks.toFixed(1)}주) 뒤 목표 체중 근처예요.`,
    paceText: `주 ${((surplus * 7) / KCAL_PER_KG).toFixed(2)}kg 증량 페이스`,
  };
}

export function planProjectionDict(p: PlanProjection): Record<string, unknown> {
  const d: Record<string, unknown> = {
    bmr: p.bmr,
    tdee: p.tdee,
    recommended_kcal: p.recommendedKcal,
    recommended_protein_g: p.recommendedProteinG,
    daily_deficit: p.dailyDeficit,
    eta_text: p.etaText,
    pace_text: p.paceText,
    engine: "diet-rules/mifflin-7700",
    plan_uses_ai: false,
  };
  if (p.weeksToGoal != null) d.weeks_to_goal = p.weeksToGoal;
  if (p.daysToGoal != null) d.days_to_goal = p.daysToGoal;
  if (p.avgIntakeUsed != null) d.avg_intake_kcal = p.avgIntakeUsed;
  return d;
}

/**
 * 원본: DietStore.planProjection() (게이트웨이 `diet.plan` 전용 — 대시보드에
 * 내장되는 plan과 달리 접미사 3종이 항상/조건부로 붙는다). dashboard()의 plan은
 * planSummary()를 직접 쓰고 이 함수를 쓰지 않는다(fasting 접미사만 조건부 적용).
 */
export function planProjectionWithSuffixes(
  profile: Profile,
  avgDailyIntakeKcal: number | null,
  plannedKcal: number,
  fastingActive: boolean,
  fastingHours: number,
  weightIsReferenceOnly: boolean,
): PlanProjection {
  const plan = planSummary(profile, avgDailyIntakeKcal, plannedKcal);
  let etaText = plan.etaText;
  if (fastingActive) etaText += ` · 간헐적 단식 ${Math.trunc(fastingHours)}h 진행 중`;
  if (weightIsReferenceOnly) etaText += " · 체중은 건강 참고값(직접 공복 입력이 더 정확)";
  etaText += " · 규칙 계산(AI 아님)";
  return { ...plan, etaText };
}

/** 7일 스냅샷 중 식사가 있는 날만 평균(원본: averageDailyKcalLocked). 순서 무관. */
export function averageDailyKcal(sevenDaySnapshots: DaySnapshot[]): number | null {
  const totals = sevenDaySnapshots.filter((d) => d.meals.length > 0).map((d) => d.kcal);
  if (totals.length === 0) return null;
  return totals.reduce((s, x) => s + x, 0) / totals.length;
}

export interface FastingSession {
  id: string;
  startedAt: string;
  targetHours: number;
  endedAt: string | null;
  endReason: string | null;
  /** 목표 시간 도달(goal_met) 리마인더 이메일 발송 시각. 웹 이관 시 신규 추가(원본엔 없음) — 중복 발송 방지용. */
  reminderSentAt: string | null;
}

export interface FastingPrefs {
  targetHours: number;
  preferMorningWeight: boolean;
  active: FastingSession | null;
  completedCount: number;
}

export const DEFAULT_FASTING_PREFS: FastingPrefs = {
  targetHours: 14,
  preferMorningWeight: true,
  active: null,
  completedCount: 0,
};

export const FASTING_HOUR_PRESETS = [12, 14, 16, 18, 20];

export function clampFastHours(h: number): number {
  return Math.max(8, Math.min(36, Math.round(h)));
}

export function isHealthKitMetric(m: Metric): boolean {
  return m.id.startsWith("hk-") || m.context === "healthkit";
}

export function isHealthKitWorkout(w: Workout): boolean {
  return w.id.startsWith("hk-") || w.intensity === "healthkit";
}

export interface WeightPick {
  kg: number;
  source: "morning_fasted" | "user" | "healthkit_ref";
  isReferenceOnly: boolean;
}

/**
 * 원본: weightForPlanLocked(). metricsAsc는 ts 오름차순(가장 최근값이 배열
 * 끝)이어야 한다 — 원본의 `.reversed().first(where:)`(최신 우선 탐색)와 동치.
 */
export function weightForPlan(metricsAsc: Metric[]): WeightPick | null {
  for (let i = metricsAsc.length - 1; i >= 0; i--) {
    const m = metricsAsc[i];
    if (
      m.weightKg != null &&
      (m.context === "morning_fasted" || m.context === "fasted") &&
      !isHealthKitMetric(m)
    ) {
      return { kg: m.weightKg, source: "morning_fasted", isReferenceOnly: false };
    }
  }
  for (let i = metricsAsc.length - 1; i >= 0; i--) {
    const m = metricsAsc[i];
    if (m.weightKg != null && !isHealthKitMetric(m)) {
      return { kg: m.weightKg, source: "user", isReferenceOnly: false };
    }
  }
  for (let i = metricsAsc.length - 1; i >= 0; i--) {
    const m = metricsAsc[i];
    if (m.weightKg != null && isHealthKitMetric(m)) {
      return { kg: m.weightKg, source: "healthkit_ref", isReferenceOnly: true };
    }
  }
  return null;
}

/** "yyyy-MM-dd"(Seoul) 문자열을 정오 UTC로 앵커링 — 날짜 간 일수 차이·요일 계산 전용(실제 시각 아님). */
function seoulDateAnchor(d: Date): Date {
  return new Date(`${dayKey(d)}T12:00:00Z`);
}

function dayWord(date: Date, now: Date): string {
  const diffDays = Math.round((seoulDateAnchor(date).getTime() - seoulDateAnchor(now).getTime()) / 86_400_000);
  switch (diffDays) {
    case 0: return "오늘";
    case 1: return "내일";
    case 2: return "모레";
    case -1: return "어제";
    default: {
      const parts = new Intl.DateTimeFormat("ko-KR", { timeZone: SEOUL_TZ, month: "numeric", day: "numeric" }).formatToParts(date);
      const month = parts.find((p) => p.type === "month")?.value ?? "";
      const day = parts.find((p) => p.type === "day")?.value ?? "";
      return `${month}월 ${day}일`;
    }
  }
}

const SEOUL_TIME_FMT = new Intl.DateTimeFormat("ko-KR", {
  timeZone: SEOUL_TZ,
  hour: "numeric",
  minute: "2-digit",
  hour12: true,
});

/**
 * 원본: localDayTimeLabels(start:end:now:) — 원본은 디바이스 로컬(Calendar.current)
 * 이지만 이 프로젝트는 단일 테넌트라 Asia/Seoul로 고정한다(dayKey()와 동일 근거).
 */
export function localDayTimeLabels(
  start: Date,
  end: Date,
  now: Date = new Date(),
): { startLabel: string; endLabel: string; endDayWord: string } {
  const startWord = dayWord(start, now);
  const endWord = dayWord(end, now);
  return {
    startLabel: `${startWord} ${SEOUL_TIME_FMT.format(start)}`,
    endLabel: `${endWord} ${SEOUL_TIME_FMT.format(end)}`,
    endDayWord: endWord,
  };
}

function fastingPreviewFields(hours: number, from: Date, now: Date): Record<string, unknown> {
  const clamped = clampFastHours(hours);
  const end = new Date(from.getTime() + clamped * 3_600_000);
  const labels = localDayTimeLabels(from, end, now);
  return {
    starts_at: from.toISOString(),
    ends_at: end.toISOString(),
    starts_at_label: labels.startLabel,
    ends_at_label: labels.endLabel,
    ends_day_word: labels.endDayWord,
    preview_line: `${Math.trunc(clamped)}시간 하면 ${labels.endLabel}에 끝나요`,
    detail_line: `${labels.startLabel} 시작 → ${labels.endLabel} 목표 완료`,
  };
}

/** diet.fasting.preview RPC 전용 — 원본: fastingEndPreview(targetHours:from:) (target_hours 키 포함). */
export function fastingEndPreview(targetHours: number, from: Date, now: Date = from): Record<string, unknown> {
  return { target_hours: clampFastHours(targetHours), ...fastingPreviewFields(targetHours, from, now) };
}

export interface HealthReferenceInput {
  now: Date;
  /** 전체 이력, ts 오름차순 */
  metricsAsc: Metric[];
  /** 전체 이력, ts 오름차순 */
  workoutsAsc: Workout[];
  lastMeal: Meal | null;
  profile: Profile | null;
  avgDailyIntakeKcal: number | null;
}

/** 원본: healthReferenceLocked(now:) */
export function healthReference(input: HealthReferenceInput): Record<string, unknown> {
  const { now, metricsAsc, workoutsAsc, lastMeal, profile, avgDailyIntakeKcal } = input;
  const lines: string[] = [];
  const fields: Record<string, unknown> = {
    available: false,
    role: "reference_only",
    disclaimer: "건강(워치) 데이터는 있을 때만 참고합니다. 없어도 단식·목표 도달 예상은 직접 기록만으로 동작해요.",
  };

  const hkWeights = metricsAsc.filter((m) => m.weightKg != null && isHealthKitMetric(m));
  const userWeights = metricsAsc.filter((m) => m.weightKg != null && !isHealthKitMetric(m));
  const hkSleep = metricsAsc.filter((m) => m.sleepH != null && isHealthKitMetric(m));
  const anySleep = metricsAsc.filter((m) => m.sleepH != null);
  const hkWorkouts = workoutsAsc.filter(isHealthKitWorkout);
  const weekAgoMs = now.getTime() - 7 * 86_400_000;

  const lastHK = hkWeights[hkWeights.length - 1];
  if (lastHK?.weightKg != null) {
    fields.hk_weight_kg = lastHK.weightKg;
    fields.hk_weight_ts = lastHK.ts;
    lines.push(`건강 체중 참고 ${lastHK.weightKg.toFixed(1)}kg`);
    fields.available = true;
  }
  const lastUser = userWeights[userWeights.length - 1];
  if (lastUser?.weightKg != null) {
    fields.user_weight_kg = lastUser.weightKg;
    fields.user_weight_context = lastUser.context ?? null;
    lines.push(`직접 체중 ${lastUser.weightKg.toFixed(1)}kg${lastUser.context === "morning_fasted" ? " (공복)" : ""}`);
    fields.available = true;
  }
  const sleepPick = hkSleep[hkSleep.length - 1] ?? anySleep[anySleep.length - 1];
  if (sleepPick?.sleepH != null) {
    fields.recent_sleep_h = sleepPick.sleepH;
    fields.sleep_source = isHealthKitMetric(sleepPick) ? "healthkit_ref" : "user";
    lines.push(`최근 수면 참고 ${sleepPick.sleepH.toFixed(1)}시간`);
    fields.available = true;
  }
  const recentHkWo = hkWorkouts.filter((w) => new Date(w.ts).getTime() >= weekAgoMs);
  if (recentHkWo.length > 0) {
    const mins = recentHkWo.reduce((s, w) => s + w.minutes, 0);
    fields.hk_workout_count_7d = recentHkWo.length;
    fields.hk_workout_minutes_7d = mins;
    const kinds = Array.from(new Set(recentHkWo.map((w) => w.kind))).slice(0, 3).join("·");
    lines.push(`건강 운동 7일 ${recentHkWo.length}회 · ${mins}분${kinds ? ` (${kinds})` : ""}`);
    fields.available = true;
  }
  const userWo = workoutsAsc.filter((w) => !isHealthKitWorkout(w) && new Date(w.ts).getTime() >= weekAgoMs);
  if (userWo.length > 0) {
    fields.user_workout_count_7d = userWo.length;
    fields.user_workout_minutes_7d = userWo.reduce((s, w) => s + w.minutes, 0);
    lines.push(`직접 운동 7일 ${userWo.length}회`);
    fields.available = true;
  }
  if (avgDailyIntakeKcal != null) {
    const rounded = Math.round(avgDailyIntakeKcal);
    fields.avg_intake_kcal_7d = rounded;
    lines.push(`최근 식사 평균 ${rounded}kcal/일`);
    fields.available = true;
  }
  if (profile && profileIsComplete(profile)) {
    fields.tdee = Math.round(tdee(profile));
    fields.bmr = Math.round(bmr(profile));
    lines.push(`유지 칼로리 약 ${Math.round(tdee(profile))}kcal (프로필)`);
    fields.available = true;
  }
  if (lastMeal) {
    const gapH = (now.getTime() - new Date(lastMeal.ts).getTime()) / 3_600_000;
    if (gapH >= 0) {
      fields.hours_since_last_meal = Math.round(gapH * 10) / 10;
      lines.push(`마지막 식사 후 ${gapH.toFixed(1)}시간`);
      fields.available = true;
    }
  }
  const pick = weightForPlan(metricsAsc);
  if (pick) {
    fields.plan_weight_kg = pick.kg;
    fields.plan_weight_source = pick.source;
    fields.plan_weight_is_reference_only = pick.isReferenceOnly;
    if (pick.isReferenceOnly) {
      lines.push("목표 계산 체중은 건강 참고값(직접 공복 입력이 더 정확)");
    }
  }

  fields.lines = lines;
  fields.line_count = lines.length;
  fields.summary =
    lines.length === 0
      ? "참고할 건강·기록이 아직 없어요. 없어도 단식은 시작할 수 있어요."
      : `참고 ${lines.length}항목 (필수 아님)`;
  return fields;
}

export interface FastingStatusInput {
  now: Date;
  previewHours: number | null;
  prefs: FastingPrefs;
  healthReferenceInput: HealthReferenceInput;
}

/** 원본: fastingStatus(now:previewHours:) */
export function fastingStatus(input: FastingStatusInput): Record<string, unknown> {
  const { now, previewHours, prefs } = input;
  const defaultHours = clampFastHours(previewHours ?? prefs.targetHours);
  const out: Record<string, unknown> = {
    engine: "diet-rules/v1",
    target_hours: defaultHours,
    prefer_morning_weight: prefs.preferMorningWeight,
    completed_count: prefs.completedCount,
    active: false,
    plan_uses_ai: false,
    plan_note: "목표 도달 예상은 Mifflin–St Jeor + 적자(약 7700kcal≈1kg) 규칙 계산입니다. AI API를 쓰지 않아요.",
    hour_presets: FASTING_HOUR_PRESETS,
  };
  out.health_reference = healthReference(input.healthReferenceInput);

  const active = prefs.active;
  if (!active || active.endedAt != null) {
    const preview = fastingPreviewFields(defaultHours, now, now);
    out.label = "간헐적 단식 대기";
    out.hint = "시간을 고른 뒤 「단식 시작」. 첫 식사 기록 시 자동 종료.";
    out.weight_prompt = "매일 아침 공복 체중(직접 입력)이 목표 도달 예상의 기준이에요. 건강 데이터는 참고만 해요.";
    Object.assign(out, preview);
    return out;
  }

  const start = new Date(active.startedAt);
  const end = new Date(start.getTime() + active.targetHours * 3_600_000);
  const labels = localDayTimeLabels(start, end, now);
  const elapsed = (now.getTime() - start.getTime()) / 3_600_000;
  const target = active.targetHours;
  const remaining = Math.max(0, target - elapsed);
  const progress = Math.min(1, Math.max(0, elapsed / Math.max(target, 0.1)));
  const met = elapsed >= target;
  out.active = true;
  out.session_id = active.id;
  out.target_hours = target;
  out.started_at = active.startedAt;
  out.ends_at = end.toISOString();
  out.starts_at_label = labels.startLabel;
  out.ends_at_label = labels.endLabel;
  out.ends_day_word = labels.endDayWord;
  out.preview_line = met
    ? `목표 ${Math.trunc(target)}h 달성 · ${labels.endLabel} 기준`
    : `${labels.endLabel}에 끝나요`;
  out.detail_line = `${labels.startLabel} 시작 → ${labels.endLabel} 목표`;
  out.elapsed_hours = Math.round(elapsed * 10) / 10;
  out.remaining_hours = Math.round(remaining * 10) / 10;
  out.progress = progress;
  out.goal_met = met;
  out.label = met
    ? `목표 ${Math.trunc(target)}h 달성 · 공복 ${elapsed.toFixed(1)}h`
    : `공복 ${elapsed.toFixed(1)}h / 목표 ${Math.trunc(target)}h · ${labels.endLabel} 종료`;
  out.hint = met
    ? "목표 공복을 채웠어요. 식사 창을 열거나 「단식 종료」를 누르세요."
    : `약 ${remaining.toFixed(1)}시간 남음 · ${labels.endLabel}에 목표. 식사 기록하면 단식이 끝나요.`;
  out.weight_prompt = "아침·공복 체중을 직접 입력하면 목표 도달 예상이 갱신돼요. 건강 체중은 참고만.";
  const pick = weightForPlan(input.healthReferenceInput.metricsAsc);
  if (pick) {
    out.preferred_weight_kg = pick.kg;
    out.weight_source = pick.source;
    out.weight_is_reference_only = pick.isReferenceOnly;
  }
  return out;
}

function pct(r: number): string {
  return `${Math.round(r * 100)}%`;
}

function analysisLines(
  day: DaySnapshot,
  goals: Goals,
  weekWorkoutCount: number,
  weekMinutes: number,
  kcalProgress: number,
  proteinProgress: number,
  workoutProgress: number,
  weeklyWorkoutProgress: number,
): string[] {
  const lines: string[] = [day.summaryText];

  if (day.meals.length === 0) {
    lines.push("아직 식사 기록이 없어요. 아래 입력으로 남겨 보세요.");
  } else if (kcalProgress < 0.55) {
    lines.push(`칼로리가 목표의 ${pct(kcalProgress)}예요. 끼니가 빠졌는지 확인해 보세요.`);
  } else if (kcalProgress > 1.15) {
    lines.push(`칼로리가 목표를 ${pct(kcalProgress - 1)} 넘었어요.`);
  } else {
    lines.push(`칼로리 페이스 양호 (${pct(kcalProgress)} / 목표 ${Math.trunc(goals.targetKcal)} kcal).`);
  }

  if (day.proteinG > 0) {
    if (proteinProgress < 0.6) {
      lines.push(`단백질 ${Math.trunc(day.proteinG)}g — 목표 ${Math.trunc(goals.targetProteinG)}g의 ${pct(proteinProgress)}.`);
    } else {
      lines.push(`단백질 ${Math.trunc(day.proteinG)}g (${pct(proteinProgress)}).`);
    }
  }

  if (day.workoutMinutes === 0) {
    lines.push(`오늘 운동 기록이 없어요. 목표 ${goals.targetWorkoutMinutesPerDay}분.`);
  } else {
    lines.push(`오늘 운동 ${day.workoutMinutes}분 (${pct(workoutProgress)}).`);
  }

  lines.push(
    `주간 운동 ${weekWorkoutCount}회 / 목표 ${goals.weeklyWorkouts}회 · 총 ${weekMinutes}분 (${pct(weeklyWorkoutProgress)}).`,
  );
  return lines;
}

/** 대시보드 주간 바 하나(요일 라벨 포함) — 원본 DayBar.label(ko_KR "E" 포맷, Seoul 고정). */
function dashboardDayBarFrom(s: DaySnapshot): DayBar & { label: string } {
  const label = new Intl.DateTimeFormat("ko-KR", { timeZone: SEOUL_TZ, weekday: "short" }).format(
    new Date(`${s.date}T12:00:00Z`),
  );
  return { ...dayBarFrom(s), label };
}

export interface DashboardInput {
  goals: Goals;
  today: DaySnapshot;
  /** 최근 7일 스냅샷(순서 무관 — 내부에서 오래된 순으로 정렬한다). */
  sevenDaySnapshots: DaySnapshot[];
  profile: Profile | null;
  /** 전체 이력, ts 오름차순 */
  metricsAsc: Metric[];
  fastingPrefs: FastingPrefs;
}

export interface DashboardResult {
  day: DaySnapshot;
  weekBars: (DayBar & { label: string })[];
  goals: Goals;
  kcalProgress: number;
  proteinProgress: number;
  workoutProgress: number;
  weeklyWorkoutProgress: number;
  weekKcalTotal: number;
  weekWorkoutCount: number;
  weekWorkoutMinutes: number;
  analysisLines: string[];
  latestWeightKg: number | null;
  profile: Profile | null;
  plan: PlanProjection | null;
}

/** 원본: dashboard(reference:). fasting 필드는 포함하지 않는다 — 호출부가 fastingStatus()로 별도 조립. */
export function dashboard(input: DashboardInput): DashboardResult {
  const { goals, today: day, profile } = input;
  const weekAsc = [...input.sevenDaySnapshots].sort((a, b) => a.date.localeCompare(b.date));
  const bars = weekAsc.map(dashboardDayBarFrom);
  const weekKcal = weekAsc.reduce((s, d) => s + d.kcal, 0);
  const weekWO = weekAsc.reduce((s, d) => s + d.workouts.length, 0);
  const weekMin = weekAsc.reduce((s, d) => s + d.workoutMinutes, 0);

  const kcalP = goals.targetKcal > 0 ? day.kcal / goals.targetKcal : 0;
  const proteinP = goals.targetProteinG > 0 ? day.proteinG / goals.targetProteinG : 0;
  const workP = goals.targetWorkoutMinutesPerDay > 0 ? day.workoutMinutes / goals.targetWorkoutMinutesPerDay : 0;
  const weekWP = goals.weeklyWorkouts > 0 ? weekWO / goals.weeklyWorkouts : 0;

  const latestWeight = weightForPlan(input.metricsAsc)?.kg ?? null;
  const lines = analysisLines(day, goals, weekWO, weekMin, kcalP, proteinP, workP, weekWP);

  const avg = averageDailyKcal(weekAsc);
  let plan: PlanProjection | null = null;
  if (profile && profileIsComplete(profile)) {
    const planProfile: Profile = latestWeight != null ? { ...profile, weightKg: latestWeight } : profile;
    plan = planSummary(planProfile, avg, goals.targetKcal);
    if (input.fastingPrefs.active) {
      plan = { ...plan, etaText: `${plan.etaText} · 간헐적 단식 ${Math.trunc(input.fastingPrefs.targetHours)}h 진행 중` };
    }
  }

  if (plan) {
    lines.unshift(plan.etaText);
    if (plan.paceText) {
      lines.splice(
        1,
        0,
        `유지 칼로리 약 ${Math.trunc(plan.tdee)}kcal · 권장 섭취 ${Math.trunc(plan.recommendedKcal)}kcal · ${plan.paceText} · 규칙 계산(AI 아님)`,
      );
    }
  } else {
    lines.unshift("키·몸무게·나이·성별·목표 체중을 입력하면 목표 칼로리와 도달 시점을 자동으로 알려 드려요. (규칙 계산, AI 아님)");
  }

  return {
    day,
    weekBars: bars,
    goals,
    kcalProgress: kcalP,
    proteinProgress: proteinP,
    workoutProgress: workP,
    weeklyWorkoutProgress: weekWP,
    weekKcalTotal: weekKcal,
    weekWorkoutCount: weekWO,
    weekWorkoutMinutes: weekMin,
    analysisLines: lines,
    latestWeightKg: latestWeight,
    profile,
    plan,
  };
}

/** 원본: dashboardJSON(reference:) — fastingStatusResult는 호출부가 fastingStatus()로 만들어 넘긴다. */
export function dashboardDict(d: DashboardResult, fastingStatusResult: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {
    day: daySummaryDict(d.day),
    goals: goalsDict(d.goals),
    progress: {
      kcal: d.kcalProgress,
      protein: d.proteinProgress,
      workout: d.workoutProgress,
      weekly_workouts: d.weeklyWorkoutProgress,
    },
    week: {
      bars: d.weekBars.map((b) => ({
        date: b.date,
        label: b.label,
        kcal: b.kcal,
        protein_g: b.proteinG,
        workout_minutes: b.workoutMinutes,
        meals: b.mealCount,
        workouts: b.workoutCount,
      })),
      kcal_total: d.weekKcalTotal,
      workout_count: d.weekWorkoutCount,
      workout_minutes: d.weekWorkoutMinutes,
    },
    analysis: d.analysisLines,
    summary_text: d.day.summaryText,
    needs_profile: d.profile == null || !profileIsComplete(d.profile),
  };
  if (d.latestWeightKg != null) out.latest_weight_kg = d.latestWeightKg;
  if (d.profile) out.profile = profileDict(d.profile);
  if (d.plan) out.plan = planProjectionDict(d.plan);
  out.fasting = fastingStatusResult;
  return out;
}
