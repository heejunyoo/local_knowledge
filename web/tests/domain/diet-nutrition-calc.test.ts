import { describe, it, expect } from "vitest";
import { estimate, parse, matchFood, itemLine, estimateAsDict } from "@/lib/domain/diet-nutrition-calc";

// 원본: Packages/KnowledgeCore/Tests/KnowledgeCoreTests/DietNutritionCalcTests.swift
describe("diet-nutrition-calc", () => {
  it("닭가슴살 150g은 100g 기준값에서 비례 스케일된다", () => {
    const e = estimate("닭가슴살", 150, "g");
    expect(e).not.toBeNull();
    expect(e!.kcal).toBeCloseTo(165, 1); // 110 * 1.5
    expect(e!.proteinG).toBeCloseTo(34.5, 1);
    expect(e!.matchedCatalog).toBe(true);
    expect(itemLine(e!)).toContain("150g");
  });

  it("아메리카노는 커피로 매칭되고 ml 기준으로 계산된다", () => {
    const e = estimate("아메리카노", 300, "ml");
    expect(e).not.toBeNull();
    expect(e!.foodName).toBe("커피");
    expect(e!.kcal).toBeCloseTo(7.5, 1);
  });

  it("parse: '점심 닭가슴살 150g'에서 슬롯 단어를 제거하고 g로 파싱한다", () => {
    const e = parse("점심 닭가슴살 150g");
    expect(e).not.toBeNull();
    expect(e!.unit).toBe("g");
    expect(e!.amount).toBe(150);
    expect(e!.kcal).toBeGreaterThan(100);
  });

  it("parse: '우유 250ml'은 ml로 파싱된다", () => {
    const e = parse("우유 250ml");
    expect(e).not.toBeNull();
    expect(e!.unit).toBe("ml");
    expect(e!.amount).toBe(250);
  });

  it("parse: kg 단위는 g로 환산(×1000)된다", () => {
    const e = parse("소고기 0.2kg");
    expect(e).not.toBeNull();
    expect(e!.unit).toBe("g");
    expect(e!.amount).toBe(200);
  });

  it("카탈로그에 없는 음식도 unit 기반 평균으로 대략 추정한다", () => {
    const e = estimate("수제 샌드위치", 200, "g");
    expect(e).not.toBeNull();
    expect(e!.matchedCatalog).toBe(false);
    expect(e!.kcal).toBeGreaterThan(0);
  });

  it("matchFood: 완전일치는 카탈로그 순서상 먼저 나오는 항목이 우선한다 (원본 그대로의 특성)", () => {
    // "과일"(index 11)의 별칭에 "사과"/"바나나"가 포함돼 있고, 전용 "사과"(13)/
    // "바나나"(12) 항목보다 배열에서 먼저 나온다 — 원본 Swift 루프도 이름/별칭
    // 구분 없이 배열 순서상 첫 매치를 반환하므로 동일하게 "과일"이 매칭된다.
    expect(matchFood("사과")?.name).toBe("과일");
    expect(matchFood("바나나")?.name).toBe("과일");
    expect(matchFood("치즈")?.name).toBe("치즈"); // 별칭 충돌이 없는 항목은 정상적으로 완전일치
  });

  it("matchFood: 포함매칭 중 카탈로그 순서와 무관하게 가장 긴 키가 승리한다", () => {
    // "반찬"(밥·반찬의 별칭, 길이2, 카탈로그 index0)보다 "샐러드"(index2, 길이3)가
    // 늦게 나오지만 더 길기 때문에 승리해야 한다.
    expect(matchFood("반찬이랑 샐러드 먹음")?.name).toBe("샐러드");
  });

  it("estimateAsDict: kcal은 정수, protein_g은 소수 1자리로 반올림된다", () => {
    const e = estimate("닭가슴살", 150, "g")!;
    const dict = estimateAsDict(e);
    expect(Number.isInteger(dict.kcal)).toBe(true);
    expect(dict.protein_g).toBeCloseTo(34.5, 1);
  });

  it("estimate: amount가 0 이하이거나 50000 이상이면 null", () => {
    expect(estimate("닭가슴살", 0, "g")).toBeNull();
    expect(estimate("닭가슴살", 50_000, "g")).toBeNull();
  });
});
