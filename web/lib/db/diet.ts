import { createClient } from "@/lib/supabase/server";
import * as dietRead from "@/lib/domain/diet-read";

type SupabaseClient = Awaited<ReturnType<typeof createClient>>;

interface MealRow {
  id: string;
  ts: string;
  items: string[] | null;
  kcal: number | null;
  protein_g: number | null;
  note: string | null;
  sugar_g: number | null;
  sodium_mg: number | null;
  satfat_g: number | null;
}

interface WorkoutRow {
  id: string;
  ts: string;
  kind: string | null;
  minutes: number | null;
  intensity: string | null;
}

interface MetricRow {
  id: string;
  ts: string;
  weight_kg: number | null;
  sleep_h: number | null;
  context: string | null;
  steps: number | null;
  active_energy_kcal: number | null;
}

function toMeal(r: MealRow): dietRead.Meal {
  return {
    id: r.id,
    ts: r.ts,
    items: r.items ?? [],
    kcal: r.kcal,
    proteinG: r.protein_g,
    note: r.note,
    sugarG: r.sugar_g,
    sodiumMg: r.sodium_mg,
    satFatG: r.satfat_g,
  };
}

function toWorkout(r: WorkoutRow): dietRead.Workout {
  return { id: r.id, ts: r.ts, kind: r.kind ?? "", minutes: r.minutes ?? 0, intensity: r.intensity };
}

function toMetric(r: MetricRow): dietRead.Metric {
  return {
    id: r.id,
    ts: r.ts,
    weightKg: r.weight_kg,
    sleepH: r.sleep_h,
    context: r.context,
    steps: r.steps,
    activeEnergyKcal: r.active_energy_kcal,
  };
}

async function fetchWindow(supabase: SupabaseClient, sinceISO: string) {
  const [mealsRes, workoutsRes, metricsRes] = await Promise.all([
    supabase
      .from("diet_meal")
      .select("id,ts,items,kcal,protein_g,note,sugar_g,sodium_mg,satfat_g")
      .gte("ts", sinceISO)
      .order("ts"),
    supabase.from("diet_workout").select("id,ts,kind,minutes,intensity").gte("ts", sinceISO).order("ts"),
    supabase
      .from("diet_metric")
      .select("id,ts,weight_kg,sleep_h,context,steps,active_energy_kcal")
      .gte("ts", sinceISO)
      .order("ts"),
  ]);
  if (mealsRes.error) throw mealsRes.error;
  if (workoutsRes.error) throw workoutsRes.error;
  if (metricsRes.error) throw metricsRes.error;
  return {
    meals: ((mealsRes.data ?? []) as MealRow[]).map(toMeal),
    workouts: ((workoutsRes.data ?? []) as WorkoutRow[]).map(toWorkout),
    metrics: ((metricsRes.data ?? []) as MetricRow[]).map(toMetric),
  };
}

/**
 * daysBack일 전부터 지금까지의 일별 스냅샷을 오늘이 먼저 오도록(today-first)
 * 반환한다. daysBack=0이면 오늘 하루, daysBack=6이면 최근 7일(주간 리뷰),
 * daysBack=29면 activityStreak(최대 30일 스캔)에 쓴다.
 */
export async function fetchRecentDietSnapshots(
  daysBack: number,
  now: Date = new Date(),
): Promise<dietRead.DaySnapshot[]> {
  const supabase = await createClient();
  // dayKey는 Asia/Seoul 기준이라 UTC 하루를 더 여유 있게 잡아 경계를 놓치지 않는다.
  const since = new Date(now.getTime() - (daysBack + 2) * 24 * 60 * 60 * 1000);
  const { meals, workouts, metrics } = await fetchWindow(supabase, since.toISOString());

  const snapshots: dietRead.DaySnapshot[] = [];
  for (let offset = 0; offset <= daysBack; offset++) {
    const d = new Date(now.getTime() - offset * 24 * 60 * 60 * 1000);
    const key = dietRead.dayKey(d);
    snapshots.push(
      dietRead.buildDaySnapshot(
        key,
        meals.filter((m) => dietRead.dayKey(new Date(m.ts)) === key),
        workouts.filter((w) => dietRead.dayKey(new Date(w.ts)) === key),
        metrics.filter((m) => dietRead.dayKey(new Date(m.ts)) === key),
      ),
    );
  }
  return snapshots;
}

export async function fetchDietGoals(): Promise<dietRead.Goals> {
  const { getSetting } = await import("@/lib/settings");
  const stored = await getSetting<Partial<Record<string, number>>>("diet.goals");
  if (!stored) return dietRead.DEFAULT_GOALS;
  return {
    targetKcal: stored.target_kcal ?? dietRead.DEFAULT_GOALS.targetKcal,
    targetProteinG: stored.target_protein_g ?? dietRead.DEFAULT_GOALS.targetProteinG,
    weeklyWorkouts: stored.weekly_workouts ?? dietRead.DEFAULT_GOALS.weeklyWorkouts,
    targetWorkoutMinutesPerDay:
      stored.target_workout_minutes_per_day ?? dietRead.DEFAULT_GOALS.targetWorkoutMinutesPerDay,
  };
}

export async function fetchDietProfile(): Promise<dietRead.Profile | null> {
  const { getSetting } = await import("@/lib/settings");
  const stored = await getSetting<{
    height_cm: number;
    weight_kg: number;
    age: number;
    sex: dietRead.Sex;
    target_weight_kg: number;
    activity: dietRead.Activity;
  }>("diet.profile");
  if (!stored) return null;
  return {
    heightCm: stored.height_cm,
    weightKg: stored.weight_kg,
    age: stored.age,
    sex: stored.sex,
    targetWeightKg: stored.target_weight_kg,
    activity: stored.activity,
  };
}

/** 전체 이력, ts 오름차순 — weightForPlan()/healthReference()가 필요로 하는 전체 스캔용(개인 앱이라 무제한 조회 허용). */
export async function fetchAllMetrics(): Promise<dietRead.Metric[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("diet_metric")
    .select("id,ts,weight_kg,sleep_h,context,steps,active_energy_kcal")
    .order("ts");
  if (error) throw error;
  return ((data ?? []) as MetricRow[]).map(toMetric);
}

/** 전체 이력, ts 오름차순 */
export async function fetchAllWorkouts(): Promise<dietRead.Workout[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.from("diet_workout").select("id,ts,kind,minutes,intensity").order("ts");
  if (error) throw error;
  return ((data ?? []) as WorkoutRow[]).map(toWorkout);
}

export async function fetchLastMeal(): Promise<dietRead.Meal | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("diet_meal")
    .select("id,ts,items,kcal,protein_g,note,sugar_g,sodium_mg,satfat_g")
    .order("ts", { ascending: false })
    .limit(1);
  if (error) throw error;
  const row = (data ?? [])[0] as MealRow | undefined;
  return row ? toMeal(row) : null;
}

interface StoredFastingSession {
  id: string;
  started_at: string;
  target_hours: number;
  ended_at: string | null;
  end_reason: string | null;
}

interface StoredFastingPrefs {
  target_hours: number;
  prefer_morning_weight: boolean;
  active: StoredFastingSession | null;
  completed_count: number;
}

function toFastingSession(s: StoredFastingSession): dietRead.FastingSession {
  return { id: s.id, startedAt: s.started_at, targetHours: s.target_hours, endedAt: s.ended_at, endReason: s.end_reason };
}

function fastingSessionRow(s: dietRead.FastingSession): StoredFastingSession {
  return { id: s.id, started_at: s.startedAt, target_hours: s.targetHours, ended_at: s.endedAt, end_reason: s.endReason };
}

export async function fetchFastingPrefs(): Promise<dietRead.FastingPrefs> {
  const { getSetting } = await import("@/lib/settings");
  const stored = await getSetting<StoredFastingPrefs>("diet.fasting");
  if (!stored) return dietRead.DEFAULT_FASTING_PREFS;
  return {
    targetHours: stored.target_hours ?? dietRead.DEFAULT_FASTING_PREFS.targetHours,
    preferMorningWeight: stored.prefer_morning_weight ?? dietRead.DEFAULT_FASTING_PREFS.preferMorningWeight,
    active: stored.active ? toFastingSession(stored.active) : null,
    completedCount: stored.completed_count ?? 0,
  };
}

async function setFastingPrefs(prefs: dietRead.FastingPrefs): Promise<void> {
  const { setSetting } = await import("@/lib/settings");
  const row: StoredFastingPrefs = {
    target_hours: prefs.targetHours,
    prefer_morning_weight: prefs.preferMorningWeight,
    active: prefs.active ? fastingSessionRow(prefs.active) : null,
    completed_count: prefs.completedCount,
  };
  await setSetting("diet.fasting", row);
}

async function writeProfileSetting(p: dietRead.Profile): Promise<void> {
  const { setSetting } = await import("@/lib/settings");
  await setSetting("diet.profile", {
    height_cm: p.heightCm,
    weight_kg: p.weightKg,
    age: p.age,
    sex: p.sex,
    target_weight_kg: p.targetWeightKg,
    activity: p.activity,
  });
}

export async function setDietGoals(g: dietRead.Goals): Promise<void> {
  const { setSetting } = await import("@/lib/settings");
  await setSetting("diet.goals", {
    target_kcal: g.targetKcal,
    target_protein_g: g.targetProteinG,
    weekly_workouts: g.weeklyWorkouts,
    target_workout_minutes_per_day: g.targetWorkoutMinutesPerDay,
  });
}

async function insertMetricRow(m: dietRead.Metric): Promise<void> {
  const supabase = await createClient();
  const { error } = await supabase
    .from("diet_metric")
    .insert({ id: m.id, ts: m.ts, weight_kg: m.weightKg, sleep_h: m.sleepH, context: m.context });
  if (error) throw error;
}

/**
 * 원본 setProfile(_:): 프로필 저장 후 weightKg>0이면 항상 새 Metric을
 * append한다(코멘트는 "빈 이력일 때만"이라 적혀 있지만 실제 조건 없음 — 1:1
 * 유지, diet-read.ts의 코멘트 참고). insertMetric()과 달리 dedup/context
 * 자동태깅/프로필 재동기화를 거치지 않는 원본의 raw append를 그대로 재현한다.
 */
export async function setDietProfile(p: dietRead.Profile): Promise<void> {
  await writeProfileSetting(p);
  if (p.weightKg > 0) {
    await insertMetricRow({
      id: crypto.randomUUID(),
      ts: new Date().toISOString(),
      weightKg: p.weightKg,
      sleepH: null,
      context: null,
    });
  }
}

/** 원본 applyRecommendedGoalsFromProfile(): 프로필이 완전할 때만 목표를 덮어쓴다. */
export async function applyRecommendedGoalsFromProfile(p: dietRead.Profile): Promise<dietRead.Goals> {
  const current = await fetchDietGoals();
  if (!dietRead.profileIsComplete(p)) return current;
  const updated: dietRead.Goals = {
    targetKcal: dietRead.recommendedKcal(p),
    targetProteinG: dietRead.recommendedProteinG(p),
    weeklyWorkouts: dietRead.recommendedWeeklyWorkouts(p.activity),
    targetWorkoutMinutesPerDay: dietRead.recommendedWorkoutMinutesPerDay(p.activity),
  };
  await setDietGoals(updated);
  return updated;
}

export async function insertMeal(params: {
  items: string[];
  kcal: number | null;
  proteinG: number | null;
  note: string | null;
  ts?: Date;
  /** ingreed 제품 조회로 얻은 영양 스냅샷(선택) — 마이그레이션 008. 기존 호출부는 안 넘겨도 된다. */
  sugarG?: number | null;
  sodiumMg?: number | null;
  satFatG?: number | null;
  /** 레코드 출처: 'ingreed' | 'catalog' | 'llm' | 'generic' 등. 기록 시점 스냅샷(D7) — grade는 저장하지 않는다(D8). */
  source?: string | null;
  ingreedReportNo?: string | null;
}): Promise<dietRead.Meal> {
  const supabase = await createClient();
  const ts = params.ts ?? new Date();
  const meal: dietRead.Meal = {
    id: crypto.randomUUID(),
    ts: ts.toISOString(),
    items: params.items,
    kcal: params.kcal,
    proteinG: params.proteinG,
    note: params.note,
  };
  /**
   * 008 컬럼은 **넘길 값이 있을 때만** 페이로드에 넣는다.
   *
   * 항상 넣으면 마이그레이션 008 이 적용되기 전에는 PostgREST 가 컬럼을 못 찾아
   * `insertMeal` 전체가 실패한다 — ingreed 경로뿐 아니라 **기존 자유입력 식사 기록까지**
   * 같이 죽는다. 새 기능이 옛 경로를 끌고 들어가면 안 된다.
   * 008 이 적용되기 전에 ingreed 경로를 쓰면 그때는 소리내어 실패하는 것이 맞다.
   */
  const nutritionCols =
    params.sugarG != null || params.sodiumMg != null || params.satFatG != null ||
    params.source != null || params.ingreedReportNo != null
      ? {
          sugar_g: params.sugarG ?? null,
          sodium_mg: params.sodiumMg ?? null,
          satfat_g: params.satFatG ?? null,
          source: params.source ?? null,
          ingreed_report_no: params.ingreedReportNo ?? null,
        }
      : {};
  const { error } = await supabase.from("diet_meal").insert({
    id: meal.id,
    ts: meal.ts,
    items: meal.items,
    kcal: meal.kcal,
    protein_g: meal.proteinG,
    note: meal.note,
    ...nutritionCols,
  });
  if (error) throw error;
  // 원본 logMeal(): 첫 식사가 활성 단식을 자동 종료시킨다(공복 창 종료).
  await endActiveFastIfDue("meal", ts);
  return meal;
}

export async function insertWorkout(params: {
  kind: string;
  minutes: number;
  intensity: string | null;
  ts?: Date;
  preferredId?: string | null;
}): Promise<dietRead.Workout> {
  const supabase = await createClient();
  const trimmedId = params.preferredId?.trim();
  const id = trimmedId ? trimmedId : crypto.randomUUID();
  if (trimmedId) {
    const { data, error } = await supabase
      .from("diet_workout")
      .select("id,ts,kind,minutes,intensity")
      .eq("id", id)
      .maybeSingle();
    if (error) throw error;
    if (data) return toWorkout(data as WorkoutRow);
  }
  const ts = params.ts ?? new Date();
  const workout: dietRead.Workout = {
    id,
    ts: ts.toISOString(),
    kind: params.kind || "workout",
    minutes: Math.max(0, params.minutes),
    intensity: params.intensity,
  };
  const { error } = await supabase
    .from("diet_workout")
    .insert({ id: workout.id, ts: workout.ts, kind: workout.kind, minutes: workout.minutes, intensity: workout.intensity });
  if (error) throw error;
  return workout;
}

/**
 * 원본 logMetric(): preferredId가 이미 존재하면 그대로 반환(idempotent —
 * ingestHealthSamples 중복 방지의 기반). context 미지정 + 체중 있음 +
 * 활성 단식 있음이면 "morning_fasted" 자동 태깅(명시적 태그는 덮어쓰지 않음).
 * 체중 기록 시 프로필의 현재 weightKg도 동기화.
 */
export async function insertMetric(params: {
  weightKg: number | null;
  sleepH: number | null;
  ts?: Date;
  preferredId?: string | null;
  context?: string | null;
}): Promise<dietRead.Metric> {
  const supabase = await createClient();
  const trimmedId = params.preferredId?.trim();
  const id = trimmedId ? trimmedId : crypto.randomUUID();
  if (trimmedId) {
    const { data, error } = await supabase
      .from("diet_metric")
      .select("id,ts,weight_kg,sleep_h,context,steps,active_energy_kcal")
      .eq("id", id)
      .maybeSingle();
    if (error) throw error;
    if (data) return toMetric(data as MetricRow);
  }

  let ctx = params.context ?? null;
  if (ctx == null && params.weightKg != null) {
    const prefs = await fetchFastingPrefs();
    if (prefs.active && prefs.active.endedAt == null) ctx = "morning_fasted";
  }
  const ts = params.ts ?? new Date();
  const metric: dietRead.Metric = { id, ts: ts.toISOString(), weightKg: params.weightKg, sleepH: params.sleepH, context: ctx };
  await insertMetricRow(metric);

  if (metric.weightKg != null) {
    const profile = await fetchDietProfile();
    if (profile) await writeProfileSetting({ ...profile, weightKg: metric.weightKg });
  }
  return metric;
}

export async function deleteMeal(id: string): Promise<boolean> {
  const supabase = await createClient();
  const { data, error } = await supabase.from("diet_meal").delete().eq("id", id).select("id");
  if (error) throw error;
  return (data ?? []).length > 0;
}

export async function deleteWorkout(id: string): Promise<boolean> {
  const supabase = await createClient();
  const { data, error } = await supabase.from("diet_workout").delete().eq("id", id).select("id");
  if (error) throw error;
  return (data ?? []).length > 0;
}

export async function deleteMetric(id: string): Promise<boolean> {
  const supabase = await createClient();
  const { data, error } = await supabase.from("diet_metric").delete().eq("id", id).select("id");
  if (error) throw error;
  return (data ?? []).length > 0;
}

/** 원본 startFast(): 이미 활성 세션이 있으면 idempotent하게 그대로 반환. */
export async function startFast(targetHours: number | null, at: Date = new Date()): Promise<dietRead.FastingSession> {
  const prefs = await fetchFastingPrefs();
  if (prefs.active && prefs.active.endedAt == null) {
    return prefs.active;
  }
  const hours = dietRead.clampFastHours(targetHours ?? prefs.targetHours);
  const session: dietRead.FastingSession = {
    id: crypto.randomUUID(),
    startedAt: at.toISOString(),
    targetHours: hours,
    endedAt: null,
    endReason: null,
  };
  await setFastingPrefs({ ...prefs, targetHours: hours, active: session });
  return session;
}

/** 원본 endActiveFastLocked(): elapsedH+0.05>=target이면 completedCount+1(약 3분 여유). */
export async function endActiveFastIfDue(reason: string, at: Date): Promise<dietRead.FastingSession | null> {
  const prefs = await fetchFastingPrefs();
  const active = prefs.active;
  if (!active || active.endedAt != null) return null;
  const elapsedH = (at.getTime() - new Date(active.startedAt).getTime()) / 3_600_000;
  const ended: dietRead.FastingSession = { ...active, endedAt: at.toISOString(), endReason: reason };
  const completedCount = elapsedH + 0.05 >= active.targetHours ? prefs.completedCount + 1 : prefs.completedCount;
  await setFastingPrefs({ ...prefs, active: null, completedCount });
  return ended;
}

export async function endFast(reason = "manual", at: Date = new Date()): Promise<dietRead.FastingSession | null> {
  return endActiveFastIfDue(reason, at);
}

/**
 * 채널별 마지막 유입 시각 — 유입이 살아 있는지 판정하는 데만 쓴다
 * (lib/domain/health-freshness.ts).
 *
 * 값이 있는 행만 센다. `diet_metric` 한 행에 수면만 있고 걸음수는 null 인 경우가
 * 정상이라(단축어가 항목별로 따로 POST 한다) 행의 존재가 아니라 **칼럼의 값**을
 * 기준으로 봐야 한다. 그래서 채널마다 `.not(col, "is", null)` 로 따로 묻는다.
 *
 * workout 은 값 칼럼이 아니라 행 자체가 유입 단위라 최신 1건이면 된다.
 */
export async function fetchHealthLastSeen(): Promise<{ id: string; lastTs: string | null }[]> {
  const supabase = await createClient();

  async function latestMetricTs(column: string): Promise<string | null> {
    const { data, error } = await supabase
      .from("diet_metric")
      .select("ts")
      .not(column, "is", null)
      .order("ts", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (error) throw error;
    return (data as { ts: string } | null)?.ts ?? null;
  }

  const [sleep, steps, activeEnergy, weight, workout] = await Promise.all([
    latestMetricTs("sleep_h"),
    latestMetricTs("steps"),
    latestMetricTs("active_energy_kcal"),
    latestMetricTs("weight_kg"),
    (async () => {
      const { data, error } = await supabase
        .from("diet_workout")
        .select("ts")
        .order("ts", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (error) throw error;
      return (data as { ts: string } | null)?.ts ?? null;
    })(),
  ]);

  return [
    { id: "sleep", lastTs: sleep },
    { id: "steps", lastTs: steps },
    { id: "active_energy", lastTs: activeEnergy },
    { id: "weight", lastTs: weight },
    { id: "workout", lastTs: workout },
  ];
}
