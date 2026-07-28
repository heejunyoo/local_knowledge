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
}

function toMeal(r: MealRow): dietRead.Meal {
  return { id: r.id, ts: r.ts, items: r.items ?? [], kcal: r.kcal, proteinG: r.protein_g, note: r.note };
}

function toWorkout(r: WorkoutRow): dietRead.Workout {
  return { id: r.id, ts: r.ts, kind: r.kind ?? "", minutes: r.minutes ?? 0, intensity: r.intensity };
}

function toMetric(r: MetricRow): dietRead.Metric {
  return { id: r.id, ts: r.ts, weightKg: r.weight_kg, sleepH: r.sleep_h };
}

async function fetchWindow(supabase: SupabaseClient, sinceISO: string) {
  const [mealsRes, workoutsRes, metricsRes] = await Promise.all([
    supabase.from("diet_meal").select("id,ts,items,kcal,protein_g,note").gte("ts", sinceISO).order("ts"),
    supabase.from("diet_workout").select("id,ts,kind,minutes,intensity").gte("ts", sinceISO).order("ts"),
    supabase.from("diet_metric").select("id,ts,weight_kg,sleep_h").gte("ts", sinceISO).order("ts"),
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
