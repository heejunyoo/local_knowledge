import { describe, it, expect } from "vitest";
import * as diet from "@/lib/domain/diet-read";

const PROFILE: diet.Profile = {
  heightCm: 170,
  weightKg: 85.2,
  age: 39,
  sex: "male",
  targetWeightKg: 75,
  activity: "moderate",
};

const GOALS: diet.Goals = {
  targetKcal: 2185,
  targetProteinG: 138,
  weeklyWorkouts: 4,
  targetWorkoutMinutesPerDay: 40,
};

function emptyDay(date: string): diet.DaySnapshot {
  return diet.buildDaySnapshot(date, [], [], []);
}

describe("planSummary — DietProfile.planSummary 1:1", () => {
  it("감량 목표: bmr/tdee/recommended 값과 daily_deficit·ETA 문구를 재현한다", () => {
    const plan = diet.planSummary(PROFILE, null, GOALS.targetKcal);
    expect(plan.bmr).toBe(1725); // 10*85.2+6.25*170-5*39+5 = 1724.5 → round
    expect(plan.tdee).toBe(Math.round(1724.5 * 1.55));
    expect(plan.recommendedKcal).toBe(diet.recommendedKcal(PROFILE));
    expect(plan.recommendedProteinG).toBe(diet.recommendedProteinG(PROFILE));
    expect(plan.paceText).toContain("감량 페이스");
    expect(plan.etaText).toContain("목표 체중 근처예요");
    expect(plan.daysToGoal).toBeGreaterThan(0);
    expect(plan.weeksToGoal).toBeGreaterThan(0);
    expect(plan.avgIntakeUsed).toBeNull();
  });

  it("목표 체중 근접(0.3kg 이내)이면 '유지' 페이스를 반환한다", () => {
    const near: diet.Profile = { ...PROFILE, weightKg: 75.2, targetWeightKg: 75 };
    const plan = diet.planSummary(near, null, GOALS.targetKcal);
    expect(plan.paceText).toBe("유지");
    expect(plan.daysToGoal).toBe(0);
    expect(plan.weeksToGoal).toBe(0);
  });

  it("실제 섭취가 유지 칼로리에 가까워도 계획된 적자(maintenance-goalKcal)로 대체된다", () => {
    // 원본 quirk 1:1 재현: delta>0.3(감량)이고 raw daily_deficit<100이면
    // max(100, maintenance-goalKcal)로 강제 대체된다 — 이 대체값은 항상 100
    // 이상이라 "정체" 분기(daily_deficit<=50)는 이 경로에서 사실상 도달 불가능
    // (감량 분기는 abs(delta)<0.3이 아닌 이상 항상 delta>0.3이라 대체가 걸린다).
    const plan = diet.planSummary(PROFILE, Math.round(diet.tdee(PROFILE)) - 10, GOALS.targetKcal);
    expect(plan.dailyDeficit).toBeGreaterThanOrEqual(100);
    expect(plan.paceText).toContain("감량 페이스");
  });

  it("증량 목표: surplus 기반 ETA/페이스 문구를 만든다", () => {
    const gaining: diet.Profile = { ...PROFILE, weightKg: 60, targetWeightKg: 70 };
    const plan = diet.planSummary(gaining, null, 3000);
    expect(plan.paceText).toContain("증량 페이스");
    expect(plan.etaText).toContain("목표 체중 근처예요");
  });

  it("plannedKcal<=0이면 recommendedKcal을 목표로 대체한다", () => {
    const plan = diet.planSummary(PROFILE, null, 0);
    // effectiveIntake가 recommendedKcal로 대체되므로 avgIntakeUsed는 여전히 null
    expect(plan.avgIntakeUsed).toBeNull();
  });
});

describe("planProjectionDict — 옵셔널 필드는 존재할 때만 포함된다", () => {
  it("weeksToGoal/daysToGoal이 null이면 dict에 해당 키가 없다", () => {
    // planSummary()가 실제로 이 상태를 만들지는 않지만(정체 분기는 원본의
    // 대체 로직상 도달 불가) asDict()의 옵셔널 처리 자체는 별도로 검증한다.
    const plan = { ...diet.planSummary(PROFILE, null, GOALS.targetKcal), weeksToGoal: null, daysToGoal: null };
    const dict = diet.planProjectionDict(plan);
    expect("weeks_to_goal" in dict).toBe(false);
    expect("days_to_goal" in dict).toBe(false);
    expect(dict.engine).toBe("diet-rules/mifflin-7700");
    expect(dict.plan_uses_ai).toBe(false);
  });

  it("avg_intake_kcal은 avgDailyIntakeKcal이 있을 때만 포함된다", () => {
    const plan = diet.planSummary(PROFILE, 2000, GOALS.targetKcal);
    expect(diet.planProjectionDict(plan).avg_intake_kcal).toBe(2000);
  });
});

describe("planProjectionWithSuffixes — diet.plan RPC 전용 접미사", () => {
  it("단식 활성 + 체중 참고값이면 접미사 2개 + AI 미사용 문구가 항상 붙는다", () => {
    const plan = diet.planProjectionWithSuffixes(PROFILE, null, GOALS.targetKcal, true, 14, true);
    expect(plan.etaText).toContain("간헐적 단식 14h 진행 중");
    expect(plan.etaText).toContain("체중은 건강 참고값");
    expect(plan.etaText.endsWith("· 규칙 계산(AI 아님)")).toBe(true);
  });

  it("단식 비활성 + 체중 정상이면 마지막 AI 문구만 붙는다", () => {
    const plan = diet.planProjectionWithSuffixes(PROFILE, null, GOALS.targetKcal, false, 14, false);
    expect(plan.etaText).not.toContain("간헐적 단식");
    expect(plan.etaText).not.toContain("건강 참고값");
    expect(plan.etaText.endsWith("· 규칙 계산(AI 아님)")).toBe(true);
  });
});

describe("weightForPlan — 우선순위: morning_fasted/fasted > user > healthkit_ref", () => {
  it("morning_fasted 컨텍스트가 있으면 최우선", () => {
    const metrics: diet.Metric[] = [
      { id: "1", ts: "2026-07-20T00:00:00Z", weightKg: 80, sleepH: null, context: null },
      { id: "hk-2", ts: "2026-07-21T00:00:00Z", weightKg: 79, sleepH: null, context: null },
      { id: "3", ts: "2026-07-22T00:00:00Z", weightKg: 81, sleepH: null, context: "morning_fasted" },
    ];
    expect(diet.weightForPlan(metrics)).toEqual({ kg: 81, source: "morning_fasted", isReferenceOnly: false });
  });

  it("morning_fasted가 없으면 가장 최근 user 체중", () => {
    const metrics: diet.Metric[] = [
      { id: "1", ts: "2026-07-20T00:00:00Z", weightKg: 80, sleepH: null, context: null },
      { id: "hk-2", ts: "2026-07-21T00:00:00Z", weightKg: 79, sleepH: null, context: null },
      { id: "3", ts: "2026-07-22T00:00:00Z", weightKg: 81, sleepH: null, context: null },
    ];
    expect(diet.weightForPlan(metrics)).toEqual({ kg: 81, source: "user", isReferenceOnly: false });
  });

  it("user 체중이 전혀 없으면 healthkit을 참고값으로 반환", () => {
    const metrics: diet.Metric[] = [{ id: "hk-1", ts: "2026-07-20T00:00:00Z", weightKg: 79, sleepH: null, context: null }];
    expect(diet.weightForPlan(metrics)).toEqual({ kg: 79, source: "healthkit_ref", isReferenceOnly: true });
  });

  it("체중 기록이 전혀 없으면 null", () => {
    expect(diet.weightForPlan([])).toBeNull();
  });
});

describe("localDayTimeLabels — Seoul 고정, 한국어 상대 요일어", () => {
  it("오늘/내일 라벨과 오전·오후 시각 포맷을 만든다", () => {
    const now = new Date("2026-07-27T05:00:00Z"); // 2026-07-27 14:00 KST
    const start = now;
    const end = new Date("2026-07-27T15:05:00Z"); // 2026-07-28 00:05 KST (내일)
    const labels = diet.localDayTimeLabels(start, end, now);
    expect(labels.startLabel).toBe("오늘 오후 2:00");
    expect(labels.endLabel).toBe("내일 오전 12:05");
    expect(labels.endDayWord).toBe("내일");
  });

  it("이틀 뒤는 '모레', 하루 전은 '어제'다", () => {
    const now = new Date("2026-07-27T05:00:00Z");
    const moreLabel = diet.localDayTimeLabels(now, new Date("2026-07-29T05:00:00Z"), now).endDayWord;
    const yesterdayLabel = diet.localDayTimeLabels(now, new Date("2026-07-26T05:00:00Z"), now).endDayWord;
    expect(moreLabel).toBe("모레");
    expect(yesterdayLabel).toBe("어제");
  });
});

describe("clampFastHours", () => {
  it("8~36시간 범위로 클램프하고 반올림한다", () => {
    expect(diet.clampFastHours(5)).toBe(8);
    expect(diet.clampFastHours(40)).toBe(36);
    expect(diet.clampFastHours(14.6)).toBe(15);
  });
});

describe("fastingStatus — 대기/활성 두 분기", () => {
  const healthRefInput = (now: Date): diet.HealthReferenceInput => ({
    now,
    metricsAsc: [],
    workoutsAsc: [],
    lastMeal: null,
    profile: null,
    avgDailyIntakeKcal: null,
  });

  it("활성 세션이 없으면 대기 상태 라벨과 프리뷰를 반환한다", () => {
    const now = new Date("2026-07-27T05:00:00Z");
    const result = diet.fastingStatus({
      now,
      previewHours: null,
      prefs: diet.DEFAULT_FASTING_PREFS,
      healthReferenceInput: healthRefInput(now),
    });
    expect(result.active).toBe(false);
    expect(result.label).toBe("간헐적 단식 대기");
    expect(result.target_hours).toBe(14);
    expect(result.hour_presets).toEqual([12, 14, 16, 18, 20]);
    expect(typeof result.starts_at_label).toBe("string");
  });

  it("활성 세션이 있으면 경과·잔여 시간을 계산한다", () => {
    const now = new Date("2026-07-27T12:00:00Z");
    const startedAt = new Date("2026-07-27T05:00:00Z").toISOString(); // 7시간 전
    const prefs: diet.FastingPrefs = {
      ...diet.DEFAULT_FASTING_PREFS,
      active: { id: "s1", startedAt, targetHours: 14, endedAt: null, endReason: null },
    };
    const result = diet.fastingStatus({
      now,
      previewHours: null,
      prefs,
      healthReferenceInput: healthRefInput(now),
    });
    expect(result.active).toBe(true);
    expect(result.elapsed_hours).toBe(7);
    expect(result.remaining_hours).toBe(7);
    expect(result.goal_met).toBe(false);
    expect(result.progress).toBeCloseTo(0.5, 5);
  });

  it("목표 시간을 채우면 goal_met=true", () => {
    const now = new Date("2026-07-27T20:00:00Z");
    const startedAt = new Date("2026-07-27T05:00:00Z").toISOString(); // 15시간 전, 목표 14h
    const prefs: diet.FastingPrefs = {
      ...diet.DEFAULT_FASTING_PREFS,
      active: { id: "s1", startedAt, targetHours: 14, endedAt: null, endReason: null },
    };
    const result = diet.fastingStatus({
      now,
      previewHours: null,
      prefs,
      healthReferenceInput: healthRefInput(now),
    });
    expect(result.goal_met).toBe(true);
    expect(result.remaining_hours).toBe(0);
  });
});

describe("healthReference — 각 필드는 데이터가 있을 때만 채워진다", () => {
  it("아무 기록도 없으면 available=false, lines가 빈 배열", () => {
    const result = diet.healthReference({
      now: new Date(),
      metricsAsc: [],
      workoutsAsc: [],
      lastMeal: null,
      profile: null,
      avgDailyIntakeKcal: null,
    });
    expect(result.available).toBe(false);
    expect(result.lines).toEqual([]);
    expect(result.summary).toContain("아직 없어요");
  });

  it("HK 체중/사용자 체중/수면/프로필/최근 식사가 모두 있으면 각 필드가 채워진다", () => {
    const now = new Date("2026-07-27T12:00:00Z");
    const result = diet.healthReference({
      now,
      metricsAsc: [
        { id: "hk-1", ts: "2026-07-20T00:00:00Z", weightKg: 86, sleepH: null, context: null },
        { id: "u-1", ts: "2026-07-25T00:00:00Z", weightKg: 85.2, sleepH: null, context: null },
        { id: "hk-2", ts: "2026-07-26T00:00:00Z", weightKg: null, sleepH: 7.1, context: null },
      ],
      workoutsAsc: [],
      lastMeal: { id: "m1", ts: "2026-07-27T09:00:00Z", items: ["아침"], kcal: 400, proteinG: 20, note: null },
      profile: PROFILE,
      avgDailyIntakeKcal: 1800,
    });
    expect(result.available).toBe(true);
    expect(result.hk_weight_kg).toBe(86);
    expect(result.user_weight_kg).toBe(85.2);
    expect(result.recent_sleep_h).toBe(7.1);
    expect(result.sleep_source).toBe("healthkit_ref");
    expect(result.tdee).toBe(Math.round(diet.tdee(PROFILE)));
    expect(result.hours_since_last_meal).toBe(3);
    expect(result.plan_weight_kg).toBe(85.2);
    expect(result.plan_weight_source).toBe("user");
    expect(result.avg_intake_kcal_7d).toBe(1800);
  });
});

describe("dashboard — 분석 라인 조립과 plan 임베딩", () => {
  it("프로필이 없으면 plan은 null이고 프로필 유도 문구가 맨 앞에 온다", () => {
    const today = emptyDay("2026-07-27");
    const result = diet.dashboard({
      goals: GOALS,
      today,
      sevenDaySnapshots: [today],
      profile: null,
      metricsAsc: [],
      fastingPrefs: diet.DEFAULT_FASTING_PREFS,
    });
    expect(result.plan).toBeNull();
    expect(result.analysisLines[0]).toContain("키·몸무게·나이·성별·목표 체중을 입력하면");
  });

  it("프로필이 완전하면 plan.eta_text와 pace 라인이 앞 2줄에 삽입된다", () => {
    const today = emptyDay("2026-07-27");
    const result = diet.dashboard({
      goals: GOALS,
      today,
      sevenDaySnapshots: [today],
      profile: PROFILE,
      metricsAsc: [{ id: "u1", ts: "2026-07-20T00:00:00Z", weightKg: 85.2, sleepH: null, context: null }],
      fastingPrefs: diet.DEFAULT_FASTING_PREFS,
    });
    expect(result.plan).not.toBeNull();
    expect(result.analysisLines[0]).toBe(result.plan!.etaText);
    expect(result.analysisLines[1]).toContain("유지 칼로리 약");
    expect(result.analysisLines[1]).toContain("규칙 계산(AI 아님)");
    expect(result.latestWeightKg).toBe(85.2);
  });

  it("단식이 활성 상태면 plan.eta_text에 진행 중 접미사가 붙는다(대시보드는 이 접미사만 조건부 적용)", () => {
    const today = emptyDay("2026-07-27");
    const active: diet.FastingSession = {
      id: "s1", startedAt: "2026-07-27T00:00:00Z", targetHours: 14, endedAt: null, endReason: null,
    };
    const result = diet.dashboard({
      goals: GOALS,
      today,
      sevenDaySnapshots: [today],
      profile: PROFILE,
      metricsAsc: [],
      fastingPrefs: { ...diet.DEFAULT_FASTING_PREFS, active },
    });
    expect(result.plan!.etaText).toContain("간헐적 단식 14h 진행 중");
    expect(result.plan!.etaText).not.toContain("규칙 계산(AI 아님)"); // 대시보드는 이 접미사를 붙이지 않는다
  });

  it("주간 바에 요일 라벨이 Seoul 기준으로 붙는다", () => {
    const days = ["2026-07-21", "2026-07-22", "2026-07-23", "2026-07-24", "2026-07-25", "2026-07-26", "2026-07-27"];
    const snapshots = days.map(emptyDay);
    const result = diet.dashboard({
      goals: GOALS,
      today: snapshots[snapshots.length - 1],
      sevenDaySnapshots: snapshots,
      profile: null,
      metricsAsc: [],
      fastingPrefs: diet.DEFAULT_FASTING_PREFS,
    });
    expect(result.weekBars.map((b) => b.label)).toEqual(["화", "수", "목", "금", "토", "일", "월"]);
  });
});

describe("dashboardDict — RPC 응답 키 구조", () => {
  it("plan/latest_weight_kg/profile은 값이 있을 때만 키가 존재한다", () => {
    const today = emptyDay("2026-07-27");
    const d = diet.dashboard({
      goals: GOALS,
      today,
      sevenDaySnapshots: [today],
      profile: null,
      metricsAsc: [],
      fastingPrefs: diet.DEFAULT_FASTING_PREFS,
    });
    const dict = diet.dashboardDict(d, { active: false });
    expect("plan" in dict).toBe(false);
    expect("latest_weight_kg" in dict).toBe(false);
    expect("profile" in dict).toBe(false);
    expect(dict.needs_profile).toBe(true);
    expect(dict.fasting).toEqual({ active: false });
  });
});
