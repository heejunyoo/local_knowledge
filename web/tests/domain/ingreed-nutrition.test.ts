import { describe, it, expect } from "vitest";
import { toServingNutrition, type IngreedProductNutrition } from "@/lib/domain/ingreed-nutrition";

// 실측 페이로드: .claude/specs/ingreed-diet-nutrition/spec.md §2 (ingreed_detail 실호출)
describe("ingreed-nutrition", () => {
  describe("toServingNutrition", () => {
    it("basis 100mL 와 1회량으로 정상 환산한다(quantity=1)", () => {
      const product: IngreedProductNutrition = {
        reportNo: "20030473071214",
        name: "탄산음료",
        category: "탄산음료",
        nutrition: {
          basis: "100mL",
          basisAmount: 100,
          servingSize: "200ml",
          foodWeight: "500ml",
          energyKcal: 45,
          proteinG: 0,
          sugarG: 10.5,
          satFatG: 0,
          sodiumMg: 20,
          carbG: 11,
          fatG: 0,
          transFatG: 0,
          cholesterolMg: 0,
        },
      };
      const r = toServingNutrition(product, 1);
      expect(r.servingG).toBe(200);
      expect(r.unit).toBe("ml");
      // factor = 200/100 = 2
      expect(r.kcal).toBe(90);
      expect(r.proteinG).toBe(0);
      expect(r.sugarG).toBe(21);
      expect(r.sodiumMg).toBe(40);
      expect(r.satFatG).toBe(0);
      expect(r.itemLine).toBe("탄산음료 200ml");
    });

    it("spec.md §2 실측 페이로드 그대로 — 영양값이 전부 0이면 0으로 환산한다(null 아님)", () => {
      const product: IngreedProductNutrition = {
        reportNo: "20030473071214",
        name: "실측 제품",
        category: "탄산음료",
        nutrition: {
          basis: "100mL",
          basisAmount: 100,
          servingSize: "200ml",
          foodWeight: "350ml",
          energyKcal: 0,
          proteinG: 0,
          sugarG: 0,
          satFatG: 0,
          sodiumMg: 0,
          carbG: 0,
          fatG: 0,
          transFatG: 0,
          cholesterolMg: 0,
        },
      };
      const r = toServingNutrition(product, 1);
      expect(r.servingG).toBe(200); // foodWeight(350) > servingSize(200) → declared 값 그대로
      expect(r.kcal).toBe(0);
      expect(r.proteinG).toBe(0);
      expect(r.sugarG).toBe(0);
      expect(r.sodiumMg).toBe(0);
      expect(r.satFatG).toBe(0);
    });

    it("servingSize 를 못 구하면 servingG=null 이고 영양값을 임의로 만들지 않는다", () => {
      const product: IngreedProductNutrition = {
        reportNo: "1",
        name: "1식 제품",
        category: "즉석섭취식품",
        nutrition: {
          basis: "100g",
          basisAmount: 100,
          servingSize: "1식", // 단위 없음 → grams()가 null
          foodWeight: null,
          energyKcal: 300,
          proteinG: 10,
          sugarG: 5,
          satFatG: 2,
          sodiumMg: 500,
        },
      };
      const r = toServingNutrition(product, 1);
      expect(r.servingG).toBeNull();
      expect(r.kcal).toBeNull();
      expect(r.proteinG).toBeNull();
      expect(r.sugarG).toBeNull();
      expect(r.sodiumMg).toBeNull();
      expect(r.satFatG).toBeNull();
      expect(r.itemLine).toBe("1식 제품");
    });

    it("nutrition 자체가 없는 제품도 servingG=null 로 안전하게 반환한다", () => {
      const product: IngreedProductNutrition = {
        reportNo: "2",
        name: "영양정보 없음",
        category: "기타가공품",
        nutrition: null,
      };
      const r = toServingNutrition(product, 1);
      expect(r.servingG).toBeNull();
      expect(r.unit).toBeNull();
      expect(r.kcal).toBeNull();
      expect(r.itemLine).toBe("영양정보 없음");
    });

    it("영양 필드가 통째로 빠지면(결측) 0 이 아니라 null 로 남는다", () => {
      const product: IngreedProductNutrition = {
        reportNo: "3",
        name: "일부 결측 제품",
        category: "과자",
        nutrition: {
          basis: "100g",
          basisAmount: 100,
          servingSize: "30g",
          foodWeight: "90g",
          energyKcal: 150,
          // proteinG, sugarG, satFatG, sodiumMg 필드 자체가 없음
        },
      };
      const r = toServingNutrition(product, 1);
      expect(r.servingG).toBe(30);
      expect(r.kcal).toBe(45); // 150 * (30/100)
      expect(r.proteinG).toBeNull();
      expect(r.sugarG).toBeNull();
      expect(r.sodiumMg).toBeNull();
      expect(r.satFatG).toBeNull();
    });

    it("quantity 0.5배 — 반 봉지", () => {
      const product: IngreedProductNutrition = {
        reportNo: "4",
        name: "봉지과자",
        category: "과자",
        nutrition: {
          basis: "100g",
          basisAmount: 100,
          servingSize: "100g",
          foodWeight: "200g",
          energyKcal: 500,
          proteinG: 10,
          sugarG: 20,
          satFatG: 5,
          sodiumMg: 400,
        },
      };
      const r = toServingNutrition(product, 0.5);
      // servingG = 100(declared), factor = 100/100 * 0.5 = 0.5
      expect(r.servingG).toBe(100);
      expect(r.kcal).toBe(250);
      expect(r.proteinG).toBe(5);
      expect(r.sugarG).toBe(10);
      expect(r.satFatG).toBe(2.5);
      expect(r.sodiumMg).toBe(200);
      expect(r.itemLine).toBe("봉지과자 50g");
    });

    it("quantity 2배 — 두 개", () => {
      const product: IngreedProductNutrition = {
        reportNo: "5",
        name: "컵라면",
        category: "유탕면",
        nutrition: {
          basis: "100g",
          basisAmount: 100,
          servingSize: "생·숙면 200g, 건면 100g, 당면 30g, 유탕면(봉지)120g, 유탕면(용기)80g",
          foodWeight: "80g",
          energyKcal: 400,
          proteinG: 8,
          sugarG: 2,
          satFatG: 6,
          sodiumMg: 900,
        },
      };
      const r = toServingNutrition(product, 2);
      // 용기(제품명에 "컵") → declared 80, foodWeight(80)는 더 작지 않음(같음) → 80 유지
      expect(r.servingG).toBe(80);
      // factor = 80/100 * 2 = 1.6
      expect(r.kcal).toBe(640);
      expect(r.proteinG).toBe(12.8);
      expect(r.sodiumMg).toBe(1440);
      expect(r.itemLine).toBe("컵라면 160g");
    });

    it("foodWeight 가 declaredServingG 보다 작으면 총 내용량을 1회량으로 쓴다(D1) — 한 봉지를 다 먹는 경우", () => {
      const product: IngreedProductNutrition = {
        reportNo: "6",
        name: "미니과자",
        category: "과자",
        nutrition: {
          basis: "100g",
          basisAmount: 100,
          servingSize: "200g",
          foodWeight: "150g", // 총 내용량이 1회 참고량보다 작다
          energyKcal: 500,
          proteinG: 10,
          sugarG: 30,
          satFatG: 8,
          sodiumMg: 600,
        },
      };
      const r = toServingNutrition(product, 1);
      expect(r.servingG).toBe(150);
      // factor = 150/100 = 1.5
      expect(r.kcal).toBe(750);
      expect(r.proteinG).toBe(15);
      expect(r.sugarG).toBe(45);
      expect(r.satFatG).toBe(12);
      expect(r.sodiumMg).toBe(900);
      expect(r.itemLine).toBe("미니과자 150g");
    });

    it("grade·score 는 반환값에 없다(D8)", () => {
      const product: IngreedProductNutrition = {
        reportNo: "7",
        name: "등급무관 제품",
        category: "과자",
        nutrition: {
          basis: "100g",
          basisAmount: 100,
          servingSize: "50g",
          foodWeight: "100g",
          energyKcal: 200,
        },
      };
      const r = toServingNutrition(product, 1);
      expect(r).not.toHaveProperty("grade");
      expect(r).not.toHaveProperty("score");
    });
  });

  /**
   * D2 — 신고 1회량이 없는 제품은 사용자가 양을 직접 넣는다. 그때도 환산은
   * ingreed 의 100g 실측값으로 한다. 여기가 무너지면 화면이 LLM 추정으로
   * 되돌아가고, 기성식품을 조회하는 의미가 사라진다.
   */
  describe("servingGOverride", () => {
    /** servingSize 가 단위 없는 "1식" — grams() 가 null 을 주는 실제 케이스(즉석섭취식품 717건). */
    const noServing: IngreedProductNutrition = {
      reportNo: "X",
      name: "도시락",
      category: "즉석섭취식품",
      nutrition: {
        basis: "100g",
        basisAmount: 100,
        servingSize: "1식",
        foodWeight: null,
        energyKcal: 150,
        proteinG: 5,
        sugarG: 3,
        satFatG: 1.5,
        sodiumMg: 400,
      },
    };

    it("override 없이는 1회량을 못 구해 영양값이 전부 null 이다", () => {
      const r = toServingNutrition(noServing, 1);
      expect(r.servingG).toBeNull();
      expect(r.kcal).toBeNull();
      expect(r.sodiumMg).toBeNull();
    });

    it("사용자가 넣은 g 으로 ingreed 실측값을 환산한다", () => {
      const r = toServingNutrition(noServing, 1, 300);
      expect(r.servingG).toBe(300);
      expect(r.kcal).toBe(450); // 150 × 3
      expect(r.sodiumMg).toBe(1200); // 400 × 3
      expect(r.satFatG).toBe(4.5);
      expect(r.itemLine).toBe("도시락 300g");
    });

    it("override 와 quantity 가 함께 곱해진다", () => {
      const r = toServingNutrition(noServing, 2, 300);
      expect(r.kcal).toBe(900);
      expect(r.itemLine).toBe("도시락 600g");
    });

    it("0·음수·NaN override 는 무시하고 기존 경로로 돌아간다", () => {
      for (const bad of [0, -100, NaN]) {
        expect(toServingNutrition(noServing, 1, bad).servingG).toBeNull();
      }
    });

    it("신고 1회량이 있으면 override 가 그것을 덮어쓴다(사용자가 실제로 먹은 양이 우선)", () => {
      const withServing: IngreedProductNutrition = {
        ...noServing,
        nutrition: { ...noServing.nutrition!, servingSize: "200g" },
      };
      expect(toServingNutrition(withServing, 1).servingG).toBe(200);
      expect(toServingNutrition(withServing, 1, 50).servingG).toBe(50);
    });
  });
});
