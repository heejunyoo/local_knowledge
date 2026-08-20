import { describe, it, expect } from "vitest";
import {
  gradeDay, toGrade, rangeScore, attainmentScore, limitScore,
  RULESET_VERSION, type DayGradeInput, type GradeCuts, type AxisInput,
} from "@/lib/domain/day-grade";

const CUTS: GradeCuts = { cuts: [[90, "A"], [75, "B"], [60, "C"], [45, "D"]] };

const present = (score: number, reason = "x"): AxisInput => ({ state: "present", score, reason });
const structural = (reason = "데이터 없음"): AxisInput => ({ state: "absent_structural", score: null, reason });
const behavioral = (reason = "기록 없음"): AxisInput => ({ state: "absent_behavioral", score: null, reason });

const day = (r: AxisInput, a: AxisInput, i: AxisInput): DayGradeInput =>
  ({ recovery: r, activity: a, intake: i });

describe("day-grade", () => {
  /**
   * ⭐ 이 설계의 존재 이유. 이게 깨지면 제품이 자기기만 기계가 된다.
   * 절대 완화하지 말 것 — 완화하려면 docs/DAILY_GRADE_AND_IA_2026-08.md §2.2 부터 다시 읽는다.
   */
  describe("행동적 결측은 이득이 되지 않는다", () => {
    it("식사를 기록하지 않은 날이 나쁘게 먹고 기록한 날보다 높은 점수를 받지 않는다", () => {
      const notLogged = gradeDay(day(present(100), present(100), behavioral()), CUTS);
      const loggedBadly = gradeDay(day(present(100), present(100), present(20)), CUTS);

      expect(notLogged.score).not.toBeNull();
      expect(loggedBadly.score).not.toBeNull();
      expect(notLogged.score!).toBeLessThan(loggedBadly.score!);
    });

    it("아주 나쁘게 먹어도(1점) 기록한 쪽이 여전히 높다", () => {
      const notLogged = gradeDay(day(present(100), present(100), behavioral()), CUTS);
      const loggedBadly = gradeDay(day(present(100), present(100), present(1)), CUTS);
      expect(notLogged.score!).toBeLessThan(loggedBadly.score!);
    });

    it("섭취 0~100 전 구간에서 기록한 쪽이 한 번도 더 낮지 않다", () => {
      const notLogged = gradeDay(day(present(100), present(100), behavioral()), CUTS).score!;
      for (let s = 0; s <= 100; s++) {
        const logged = gradeDay(day(present(100), present(100), present(s)), CUTS).score!;
        expect(logged, `섭취 ${s}점에서 뒤집혔다`).toBeGreaterThanOrEqual(notLogged);
      }
    });

    it("다른 축이 어떤 값이어도 뒤집히지 않는다", () => {
      for (const r of [0, 37, 100]) {
        for (const a of [0, 58, 100]) {
          const notLogged = gradeDay(day(present(r), present(a), behavioral()), CUTS).score!;
          for (const s of [0, 1, 50, 99, 100]) {
            const logged = gradeDay(day(present(r), present(a), present(s)), CUTS).score!;
            expect(logged, `회복 ${r} · 활동 ${a} · 섭취 ${s}`).toBeGreaterThanOrEqual(notLogged);
          }
        }
      }
    });

    it("행동적 결측 축은 분모에 남는다 — 재정규화되지 않는다", () => {
      // 100·100·(0) / 3 = 66.7 → 67.  재정규화했다면 100 이 됐을 것이다.
      const r = gradeDay(day(present(100), present(100), behavioral()), CUTS);
      expect(r.score).toBe(66.7);
      expect(r.score).not.toBe(100);
    });

    it("행동적 결측이 있으면 ratable 이 false 다", () => {
      expect(gradeDay(day(present(100), present(100), behavioral()), CUTS).ratable).toBe(false);
    });
  });

  describe("구조적 결측은 재정규화된다", () => {
    it("워치를 안 찬 날은 그 축이 분모에서 빠진다", () => {
      // 활동·섭취만 100 → 100. 회복을 0으로 셌다면 67 이었을 것이다.
      const r = gradeDay(day(structural(), present(100), present(100)), CUTS);
      expect(r.score).toBe(100);
      expect(r.grade).toBe("A");
    });

    it("구조적 결측만으로는 ratable 이 유지된다 (남은 축이 2개 이상이면)", () => {
      expect(gradeDay(day(structural(), present(80), present(80)), CUTS).ratable).toBe(true);
    });

    it("아는 축이 1개뿐이면 ratable 이 false 다", () => {
      expect(gradeDay(day(structural(), structural(), present(100)), CUTS).ratable).toBe(false);
    });

    it("모든 축이 구조적 결측이면 등급을 지어내지 않는다", () => {
      const r = gradeDay(day(structural(), structural(), structural()), CUTS);
      expect(r.score).toBeNull();
      expect(r.grade).toBeNull();
      expect(r.ratable).toBe(false);
    });
  });

  describe("confidence", () => {
    it("전 축을 알면 1", () => {
      expect(gradeDay(day(present(50), present(50), present(50)), CUTS).confidence).toBe(1);
    });

    it("결측이 늘면 단조 감소한다 — 구조적이든 행동적이든", () => {
      const all = gradeDay(day(present(50), present(50), present(50)), CUTS).confidence;
      const one = gradeDay(day(structural(), present(50), present(50)), CUTS).confidence;
      const two = gradeDay(day(structural(), structural(), present(50)), CUTS).confidence;
      expect(all).toBeGreaterThan(one);
      expect(one).toBeGreaterThan(two);
    });

    it("행동적 결측도 confidence 를 깎는다 — 0점인 것과 값을 아는 것은 다르다", () => {
      const known = gradeDay(day(present(100), present(100), present(0)), CUTS).confidence;
      const unknown = gradeDay(day(present(100), present(100), behavioral()), CUTS).confidence;
      expect(unknown).toBeLessThan(known);
    });
  });

  describe("breakdown · reasons", () => {
    it("결측 축의 score 는 null 이다 — 0 이 아니다", () => {
      const r = gradeDay(day(behavioral(), structural(), present(70)), CUTS);
      expect(r.breakdown.find((b) => b.id === "recovery")!.score).toBeNull();
      expect(r.breakdown.find((b) => b.id === "activity")!.score).toBeNull();
      expect(r.breakdown.find((b) => b.id === "intake")!.score).toBe(70);
    });

    it("룰셋 버전을 담는다", () => {
      expect(gradeDay(day(present(50), present(50), present(50)), CUTS).rulesetVersion).toBe(RULESET_VERSION);
    });

    it("등급을 LLM 으로 만들지 않으므로 같은 입력에 같은 출력이다", () => {
      const input = day(present(73), structural(), present(41));
      expect(gradeDay(input, CUTS)).toEqual(gradeDay(input, CUTS));
    });
  });

  describe("등급 컷", () => {
    it("컷 경계값은 그 등급에 포함된다", () => {
      expect(toGrade(90, CUTS)).toBe("A");
      expect(toGrade(89, CUTS)).toBe("B");
      expect(toGrade(45, CUTS)).toBe("D");
      expect(toGrade(44, CUTS)).toBe("E");
      expect(toGrade(0, CUTS)).toBe("E");
    });
  });

  describe("축 점수의 형태", () => {
    it("범위형 — 안이면 100, 밖이면 양쪽 다 감점", () => {
      expect(rangeScore(8, 7, 9, 3)).toBe(100);
      expect(rangeScore(7, 7, 9, 3)).toBe(100);
      expect(rangeScore(5.5, 7, 9, 3)).toBe(50);
      expect(rangeScore(10.5, 7, 9, 3)).toBe(50); // 너무 많이 자도 벌한다
      expect(rangeScore(3, 7, 9, 3)).toBe(0);
    });

    it("달성률형 — 초과해도 100 을 넘지 않는다", () => {
      expect(attainmentScore(75, 150)).toBe(50);
      expect(attainmentScore(150, 150)).toBe(100);
      expect(attainmentScore(600, 150)).toBe(100);
      expect(attainmentScore(0, 150)).toBe(0);
    });

    it("상한형 — 이하면 100, 초과분에 비례해 감점", () => {
      expect(limitScore(1500, 2000)).toBe(100);
      expect(limitScore(2000, 2000)).toBe(100);
      expect(limitScore(3000, 2000)).toBe(50);
      expect(limitScore(4000, 2000)).toBe(0);
      expect(limitScore(9000, 2000)).toBe(0);
    });
  });
});
