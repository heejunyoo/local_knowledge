import { describe, it, expect } from "vitest";
import { declaredServingG, isServingTable, grams, CUP_NOODLE } from "@/lib/domain/serving-size";

// 원본: ~/ingreed/packages/scoring/test/serving.test.ts
//
// 이 파일이 존재하는 이유는 조용히 틀린 값 두 개다(spec.md §3):
//  ⑴ 다중 표기 — 유탕면의 servingSize 가 "면류" 1회량 표 전체를 담고 있어,
//     첫 숫자(생·숙면 200g)를 집으면 유탕면 자신의 값(봉지 120 · 용기 80)이 아닌
//     엉뚱한 숫자가 나온다.
//  ⑵ 단위 없는 표기 — "1식" 처럼 단위가 없는 값을 1g 으로 읽으면 환산값이
//     100분의 1이 되어 조용히 틀린다. 둘 다 예외를 던지지 않는다.
describe("serving-size", () => {
  const NOODLE_TABLE = "생·숙면 200g, 건면 100g, 당면 30g, 유탕면(봉지)120g, 유탕면(용기)80g";

  describe("declaredServingG — 유탕면 다중 표기", () => {
    it("표 문자열에서 첫 숫자(생·숙면 200g)를 집지 않고 봉지 값(120)을 반환한다", () => {
      expect(declaredServingG(NOODLE_TABLE, "유탕면", "진라면 매운맛")).toBe(120);
      expect(declaredServingG(NOODLE_TABLE, "유탕면", "진라면 매운맛")).not.toBe(200);
    });

    it("용기면(제품명으로 판별)은 같은 문자열의 용기 값(80)을 반환한다", () => {
      for (const name of ["육개장 사발면", "왕뚜껑 큰컵", "컵누들 매콤한맛"]) {
        expect(declaredServingG(NOODLE_TABLE, "유탕면", name)).toBe(80);
      }
    });

    it("자기 값만 신고한 제품은 표가 아니므로 그대로 읽는다", () => {
      expect(declaredServingG("120g", "유탕면", "아무거나")).toBe(120);
      expect(declaredServingG("30g", "과자", "새우깡")).toBe(30);
    });

    it("갈라 읽는 카테고리(유탕면) 밖에서는 표를 손대지 않고 첫 숫자를 그대로 반환한다", () => {
      expect(declaredServingG("드레싱 15g, 덮밥소스 165g", "소스", "발사믹 드레싱")).toBe(15);
    });
  });

  describe("단위 없는 표기는 null", () => {
    it("'1식'은 1g 이 아니라 모르는 값(null)이다", () => {
      expect(grams("1식")).toBeNull();
      expect(declaredServingG("1식", "즉석섭취식품", "아무거나")).toBeNull();
    });

    it("단위가 없으면 숫자가 있어도 null 이다", () => {
      expect(grams("200")).toBeNull();
    });
  });

  describe("단위 환산", () => {
    it("정상 'ml' 표기는 그대로 읽는다", () => {
      expect(grams("200ml")).toBe(200);
      expect(grams("200 mL")).toBe(200);
    });

    it("'g' 표기는 그대로 읽는다", () => {
      expect(grams("70g")).toBe(70);
    });

    it("kg 은 g 로 환산한다(×1000)", () => {
      expect(grams("1kg")).toBe(1000);
      expect(grams("0.2kg")).toBe(200);
    });

    it("l 은 ml 로 환산한다(×1000)", () => {
      expect(grams("1l")).toBe(1000);
      expect(grams("1L")).toBe(1000);
    });
  });

  describe("isServingTable", () => {
    it("숫자+단위가 두 번 이상이면 표로 본다", () => {
      expect(isServingTable(NOODLE_TABLE)).toBe(true);
      expect(isServingTable("드레싱 15g, 덮밥소스 165g")).toBe(true);
    });

    it("단일 값이거나 단위가 없으면 표가 아니다", () => {
      expect(isServingTable("120g")).toBe(false);
      expect(isServingTable("1식")).toBe(false);
      expect(isServingTable(undefined)).toBe(false);
    });
  });

  describe("CUP_NOODLE", () => {
    it("컵·사발·용기·보울 계열 이름에 매치된다", () => {
      expect(CUP_NOODLE.test("육개장 사발면")).toBe(true);
      expect(CUP_NOODLE.test("왕뚜껑 큰컵")).toBe(true);
      expect(CUP_NOODLE.test("컵누들 매콤한맛")).toBe(true);
    });

    it("봉지형 이름에는 매치되지 않는다", () => {
      expect(CUP_NOODLE.test("진라면 매운맛")).toBe(false);
    });
  });
});
