import XCTest
import KnowledgeCore
@testable import KnowledgeGateway

final class DietStoreTests: XCTestCase {
    func testMealAndDaySummary() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("diet-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = DietStore(knowledgeRoot: dir)
        _ = try store.logMeal(items: ["닭가슴살"], kcal: 200, proteinG: 40, note: nil)
        _ = try store.logWorkout(kind: "걷기", minutes: 25, intensity: "easy")
        let day = store.daySummary()
        let totals = day["totals"] as? [String: Any]
        XCTAssertEqual(totals?["meal_count"] as? Int, 1)
        XCTAssertEqual(totals?["workout_count"] as? Int, 1)
        XCTAssertEqual(totals?["kcal"] as? Double, 200)
        XCTAssertEqual(totals?["workout_minutes"] as? Int, 25)
        let coach = store.coach(message: "어때?")
        XCTAssertFalse((coach["answer"] as? String ?? "").isEmpty)
        let dash = store.dashboard()
        XCTAssertGreaterThan(dash.kcalProgress, 0)
        try store.setGoals(DietStore.Goals(targetKcal: 2000, targetProteinG: 120, weeklyWorkouts: 5, targetWorkoutMinutesPerDay: 40))
        XCTAssertEqual(store.goals().targetProteinG, 120)
    }
}
