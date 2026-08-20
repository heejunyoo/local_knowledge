import { describe, it, expect } from "vitest";
import {
  DEFAULT_THRESHOLDS,
  thresholdsFor,
  satFatLimitG,
} from "@/lib/domain/day-grade-thresholds";
import { recommendedKcal, type Profile } from "@/lib/domain/diet-read";

// 골든 프로필 — tests/domain/diet-read.test.ts 의 "profileDict — Mifflin–St Jeor parity"
// 테스트와 같은 값이다. recommendedKcal(profile) === 2185 가 거기서 이미 검증됐다.
const PROFILE: Profile = {
  heightCm: 170,
  weightKg: 86,
  age: 39,
  sex: "male",
  targetWeightKg: 75,
  activity: "moderate",
};

describe("day-grade-thresholds", () => {
  describe("고정값 — 프로필과 무관", () => {
    it("회복(수면) 하한은 7시간이고, 상한 필드가 없다(D-N)", () => {
      expect(DEFAULT_THRESHOLDS.recovery.sleepMinHours).toBe(7);
      expect(Object.keys(DEFAULT_THRESHOLDS.recovery)).toEqual(["sleepMinHours"]);
    });

    it("활동은 최근 7일 누적 중강도 150분을 목표로 한다(D-J, WHO 2020)", () => {
      expect(DEFAULT_THRESHOLDS.activity.weeklyModerateMinutesTarget).toBe(150);
    });

    it("당·나트륨 상한, 포화지방 비율이 조사된 값과 같다", () => {
      expect(DEFAULT_THRESHOLDS.intake.sugarGLimit).toBe(100);
      expect(DEFAULT_THRESHOLDS.intake.sodiumMgLimit).toBe(2000);
      expect(DEFAULT_THRESHOLDS.intake.satFatEnergyRatio).toBeCloseTo(0.07, 5);
    });

    it("등급 컷은 A90/B75/C60/D40 이다(D-O)", () => {
      expect(DEFAULT_THRESHOLDS.cuts.cuts).toEqual([
        [90, "A"],
        [75, "B"],
        [60, "C"],
        [40, "D"],
      ]);
    });

    it("thresholdsFor 가 돌려주는 고정값은 프로필과 무관하게 DEFAULT_THRESHOLDS 와 같다", () => {
      const t = thresholdsFor(PROFILE);
      expect(t.recovery).toEqual(DEFAULT_THRESHOLDS.recovery);
      expect(t.activity).toEqual(DEFAULT_THRESHOLDS.activity);
      expect(t.intake.sugarGLimit).toBe(DEFAULT_THRESHOLDS.intake.sugarGLimit);
      expect(t.intake.sodiumMgLimit).toBe(DEFAULT_THRESHOLDS.intake.sodiumMgLimit);
      expect(t.intake.satFatEnergyRatio).toBe(DEFAULT_THRESHOLDS.intake.satFatEnergyRatio);
      expect(t.cuts).toEqual(DEFAULT_THRESHOLDS.cuts);
    });
  });

  describe("프로필 의존값 — thresholdsFor(profile)", () => {
    it("kcalTarget 은 diet-read.ts 의 recommendedKcal 을 그대로 호출한 값이다", () => {
      const t = thresholdsFor(PROFILE);
      expect(t.intake.kcalTarget).toBe(recommendedKcal(PROFILE));
      expect(t.intake.kcalTarget).toBe(2185); // 골든값 — diet-read.test.ts 와 대조
    });

    it("proteinGTarget 은 체중 × 0.91 이다(D-I, KDRIs 0.91 — 코드의 1.6 이 아니다)", () => {
      const t = thresholdsFor(PROFILE);
      expect(t.intake.proteinGTarget).toBeCloseTo(86 * 0.91, 1); // 78.3
      // 식단 화면 개인 목표(체중×1.6 = 137.6→138)와는 다른 숫자여야 한다.
      expect(t.intake.proteinGTarget).not.toBeCloseTo(86 * 1.6, 1);
    });

    it("프로필이 다르면 kcalTarget·proteinGTarget 도 달라진다", () => {
      const other: Profile = { ...PROFILE, weightKg: 60, age: 28, sex: "female", targetWeightKg: 55 };
      const a = thresholdsFor(PROFILE);
      const b = thresholdsFor(other);
      expect(a.intake.kcalTarget).not.toBe(b.intake.kcalTarget);
      expect(a.intake.proteinGTarget).not.toBe(b.intake.proteinGTarget);
      expect(b.intake.proteinGTarget).toBeCloseTo(60 * 0.91, 1);
    });
  });

  describe("satFatLimitG — 비율→그램 환산, 0으로 나누지 않는다(D-P)", () => {
    it("그날 kcal 이 있으면 총에너지의 7% 를 9kcal/g 로 나눈 그램값을 돌려준다", () => {
      const t = thresholdsFor(PROFILE);
      // 2000kcal 의 7% = 140kcal, 지방 9kcal/g → 15.555...g
      expect(satFatLimitG(2000, t)).toBeCloseTo((2000 * 0.07) / 9, 5);
    });

    it("kcal 이 0이면 null 이다(분모 없음 — 결측으로 다룬다)", () => {
      const t = thresholdsFor(PROFILE);
      expect(satFatLimitG(0, t)).toBeNull();
    });

    it("kcal 이 null·undefined 여도 null 이다", () => {
      const t = thresholdsFor(PROFILE);
      expect(satFatLimitG(null, t)).toBeNull();
      expect(satFatLimitG(undefined, t)).toBeNull();
    });

    it("음수 kcal 은 없다고 가정하지 않는다 — 0 초과일 때만 정상 계산한다는 계약을 확인", () => {
      const t = thresholdsFor(PROFILE);
      // 방어적 계약 확인용: 정상 입력(양수)에서는 항상 유한한 양수를 돌려준다.
      const g = satFatLimitG(1800, t);
      expect(g).not.toBeNull();
      expect(g!).toBeGreaterThan(0);
      expect(Number.isFinite(g!)).toBe(true);
    });
  });
});
