import { describe, it, expect, vi, beforeEach } from "vitest";
import type * as dietRead from "@/lib/domain/diet-read";

// day.grade는 lib/db/diet.ts(fetchRecentDietSnapshots·fetchDietProfile)를 통해서만
// 데이터를 읽는다. 실 Supabase에 붙지 않도록 이 계층에서 끊는다 — handlers.ts가
// import하는 두 함수만 vi.fn()으로 대체하고, 각 테스트가 반환값을 직접 채운다
// (tests/domain/ingest.test.ts·settings.test.ts와 같은 vi.mock("@/lib/supabase/server")
// 패턴을 쓰면 lib/settings.ts의 모듈 스코프 캐시가 테스트 간에 새는 문제가 있어,
// handlers.ts가 실제로 의존하는 더 얕은 경계에서 mock한다).
const fetchRecentDietSnapshots = vi.fn();
const fetchDietProfile = vi.fn();
const fetchDietGoals = vi.fn();

vi.mock("@/lib/db/diet", () => ({
  fetchRecentDietSnapshots: (...args: unknown[]) => fetchRecentDietSnapshots(...args),
  fetchDietProfile: (...args: unknown[]) => fetchDietProfile(...args),
  fetchDietGoals: (...args: unknown[]) => fetchDietGoals(...args),
}));

const { day_grade } = await import("@/lib/rpc/handlers");

const PROFILE: dietRead.Profile = {
  heightCm: 175,
  weightKg: 70,
  age: 30,
  sex: "male",
  targetWeightKg: 68,
  activity: "moderate",
};

function emptySnapshot(date: string): dietRead.DaySnapshot {
  return {
    date,
    meals: [],
    workouts: [],
    metrics: [],
    kcal: 0,
    proteinG: 0,
    workoutMinutes: 0,
    summaryText: "",
  };
}

/** today-first 7일 스냅샷. today는 override로 덮어쓰고 나머지 6일은 빈 날로 채운다. */
function sevenDaySnapshots(today: Partial<dietRead.DaySnapshot>, otherWorkoutMinutes: number[] = [0, 0, 0, 0, 0, 0]): dietRead.DaySnapshot[] {
  const rest = otherWorkoutMinutes.map((min, i) => ({ ...emptySnapshot(`2026-08-${10 + i}`), workoutMinutes: min }));
  return [{ ...emptySnapshot("2026-08-20"), ...today }, ...rest];
}

beforeEach(() => {
  vi.clearAllMocks();
  fetchDietProfile.mockResolvedValue(PROFILE);
  fetchDietGoals.mockResolvedValue({
    targetKcal: 2000,
    targetProteinG: 100,
    weeklyWorkouts: 4,
    targetWorkoutMinutesPerDay: 30,
  });
});

describe("day.grade RPC — closed 판정(D-K)", () => {
  it("요청 date를 생략하면 오늘로 간주되어 closed=false, grade=null이다", async () => {
    fetchRecentDietSnapshots.mockResolvedValue(sevenDaySnapshots({ workoutMinutes: 40 }));
    const result = (await day_grade({})) as Record<string, unknown>;
    expect(result.closed).toBe(false);
    expect(result.grade).toBeNull();
    expect(result.ratable).toBe(false);
  });

  it("지난 날짜를 요청하면 closed=true이고 등급이 나온다", async () => {
    fetchRecentDietSnapshots.mockResolvedValue(
      sevenDaySnapshots({
        workoutMinutes: 40,
        metrics: [{ id: "m1", ts: "2026-08-19T22:00:00Z", weightKg: null, sleepH: 7.5, context: null }],
        meals: [{ id: "meal1", ts: "2026-08-19T12:00:00Z", items: ["점심"], kcal: 600, proteinG: 40, note: null }],
        kcal: 600,
        proteinG: 40,
      }),
    );
    const result = (await day_grade({ date: "2020-01-01" })) as Record<string, unknown>;
    expect(result.closed).toBe(true);
    expect(result.date).toBe("2020-01-01");
    expect(typeof result.grade).toBe("string");
    expect(["A", "B", "C", "D", "E"]).toContain(result.grade);
  });
});

describe("day.grade RPC — 활동 축은 7일 누적(D-J)이지 하루치가 아니다", () => {
  it("weekly_minutes는 7개 스냅샷 workoutMinutes의 합이다", async () => {
    // today=40, 나머지 6일 = 10,20,30,5,0,15 → 합 120
    fetchRecentDietSnapshots.mockResolvedValue(sevenDaySnapshots({ workoutMinutes: 40 }, [10, 20, 30, 5, 0, 15]));
    const result = (await day_grade({ date: "2020-01-01" })) as Record<string, unknown>;
    const activity = result.activity as Record<string, unknown>;
    expect(activity.weekly_minutes).toBe(120);
    // 하루치(40)가 아니라 누적(120) 기준으로 채점됐는지도 확인한다
    const breakdown = result.breakdown as Array<{ id: string; score: number | null; reason: string }>;
    const activityAxis = breakdown.find((b) => b.id === "activity")!;
    expect(activityAxis.reason).toContain("120분");
    expect(activityAxis.score).toBe(80); // 120/150 목표 → 80
  });
});

describe("day.grade RPC — metrics 여러 행 집계(D-M)", () => {
  it("sleepH는 그날 최신 1건, steps는 최댓값 1건을 쓴다", async () => {
    fetchRecentDietSnapshots.mockResolvedValue(
      sevenDaySnapshots({
        workoutMinutes: 0,
        metrics: [
          { id: "m1", ts: "2026-08-20T00:00:00Z", weightKg: null, sleepH: 6.0, context: null, steps: 1000 },
          { id: "m2", ts: "2026-08-20T06:00:00Z", weightKg: null, sleepH: 7.5, context: null, steps: 5000 },
          { id: "m3", ts: "2026-08-20T12:00:00Z", weightKg: null, sleepH: null, context: null, steps: 3000 },
          { id: "m4", ts: "2026-08-20T18:00:00Z", weightKg: null, sleepH: 8.0, context: null, steps: null },
        ],
      }),
    );
    const result = (await day_grade({ date: "2020-01-01" })) as Record<string, unknown>;
    const breakdown = result.breakdown as Array<{ id: string; score: number | null; reason: string }>;
    const recovery = breakdown.find((b) => b.id === "recovery")!;
    // 최신 수면 기록은 m4(8.0h) — m1(6.0h, 첫 기록)도 평균(약 7.16h)도 아니다
    expect(recovery.reason).toContain("8h");
    expect(recovery.score).toBe(100); // 7h 이상 하한 충족

    const activity = result.activity as Record<string, unknown>;
    // steps는 최댓값(5000) — 합(9000)도 마지막 기록(null→무시)도 아니다
    expect(activity.steps).toBe(5000);
  });
});

describe("day.grade RPC — 프로필 미완성(D-Q)", () => {
  it("섭취 축이 absent_behavioral이고 이유 문구가 드러난다", async () => {
    fetchDietProfile.mockResolvedValue(null);
    fetchRecentDietSnapshots.mockResolvedValue(
      sevenDaySnapshots({
        workoutMinutes: 0,
        meals: [{ id: "meal1", ts: "2026-08-20T12:00:00Z", items: ["점심"], kcal: 600, proteinG: 40, note: null }],
        kcal: 600,
        proteinG: 40,
      }),
    );
    const result = (await day_grade({ date: "2020-01-01" })) as Record<string, unknown>;
    const breakdown = result.breakdown as Array<{ id: string; state: string; score: number | null; reason: string }>;
    const intake = breakdown.find((b) => b.id === "intake")!;
    expect(intake.state).toBe("absent_behavioral");
    // axisResultDict는 score!=null일 때만 키를 넣는다(D-Q) — 결측이면 키 자체가 없다
    expect("score" in intake).toBe(false);
    expect(intake.reason).toBe("프로필 미완성 — 섭취 목표를 계산할 수 없음");
  });
});

describe("day.grade RPC — 포화지방 상한(D-P)", () => {
  it("그날 kcal이 0이면 포화지방 하위항목만 빠지고 나머지 섭취 채점은 계속된다", async () => {
    fetchRecentDietSnapshots.mockResolvedValue(
      sevenDaySnapshots({
        workoutMinutes: 0,
        meals: [
          {
            id: "meal1",
            ts: "2026-08-20T12:00:00Z",
            items: ["기록"],
            kcal: 0,
            proteinG: 0,
            note: null,
            sugarG: 20,
            sodiumMg: 500,
            satFatG: 5,
          },
        ],
        kcal: 0,
        proteinG: 0,
      }),
    );
    const result = (await day_grade({ date: "2020-01-01" })) as Record<string, unknown>;
    const breakdown = result.breakdown as Array<{ id: string; state: string; score: number | null; reason: string }>;
    const intake = breakdown.find((b) => b.id === "intake")!;
    // 섭취 축 자체는 채점을 계속한다(absent가 아니다) — kcal=0인데도 결측 취급되지 않는다
    expect(intake.state).toBe("present");
    expect(intake.score).not.toBeNull();
    // 포화지방 하위항목만 빠진다 — 당·나트륨은 여전히 반영된다
    expect(intake.reason).not.toContain("포화지방");
    expect(intake.reason).toContain("당 20g");
    expect(intake.reason).toContain("나트륨 500mg");
  });
});
