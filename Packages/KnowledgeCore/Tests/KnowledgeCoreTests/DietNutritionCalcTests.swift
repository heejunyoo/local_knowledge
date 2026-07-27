import XCTest
@testable import KnowledgeCore

final class DietNutritionCalcTests: XCTestCase {
    func testChicken150gScalesFromPer100() {
        let e = DietNutritionCalc.estimate(foodQuery: "닭가슴살", amount: 150, unit: .g)
        XCTAssertNotNil(e)
        XCTAssertEqual(e!.kcal, 165, accuracy: 0.1) // 110 * 1.5
        XCTAssertEqual(e!.proteinG, 34.5, accuracy: 0.1)
        XCTAssertTrue(e!.matchedCatalog)
        XCTAssertTrue(e!.itemLine.contains("150g"))
    }

    func testCoffeeMl() {
        let e = DietNutritionCalc.estimate(foodQuery: "아메리카노", amount: 300, unit: .ml)
        XCTAssertNotNil(e)
        XCTAssertEqual(e!.foodName, "커피")
        XCTAssertEqual(e!.kcal, 7.5, accuracy: 0.2)
    }

    func testParseKoreanLine() {
        let e = DietNutritionCalc.parse("점심 닭가슴살 150g")
        XCTAssertNotNil(e)
        XCTAssertEqual(e!.unit, .g)
        XCTAssertEqual(e!.amount, 150)
        XCTAssertGreaterThan(e!.kcal, 100)
    }

    func testParseMl() {
        let e = DietNutritionCalc.parse("우유 250ml")
        XCTAssertNotNil(e)
        XCTAssertEqual(e!.unit, .ml)
        XCTAssertEqual(e!.amount, 250)
    }

    func testUnknownFoodStillEstimates() {
        let e = DietNutritionCalc.estimate(foodQuery: "수제 샌드위치", amount: 200, unit: .g)
        XCTAssertNotNil(e)
        XCTAssertFalse(e!.matchedCatalog)
        XCTAssertGreaterThan(e!.kcal, 0)
    }

    func testPresetScaled() {
        let p = DietMealPreset(name: "닭가슴살", grams: 100, kcal: 110, proteinG: 23)
        let s = p.scaled(to: 200)
        XCTAssertEqual(s.kcal, 220, accuracy: 0.1)
        XCTAssertEqual(s.proteinG, 46, accuracy: 0.1)
    }
}
