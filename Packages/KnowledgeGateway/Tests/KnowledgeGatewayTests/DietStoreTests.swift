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

    func testIntermittentFastingAndMorningWeight() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("diet-if-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = DietStore(knowledgeRoot: dir)

        // Preview end time for 14h
        let preview = store.fastingEndPreview(targetHours: 14)
        XCTAssertEqual(preview["target_hours"] as? Double, 14)
        XCTAssertNotNil(preview["ends_at_label"] as? String)
        XCTAssertTrue((preview["preview_line"] as? String ?? "").contains("끝나요"))

        let session = try store.startFast(targetHours: 16)
        XCTAssertEqual(session.targetHours, 16)
        let st = store.fastingStatus()
        XCTAssertEqual(st["active"] as? Bool, true)
        XCTAssertEqual(st["plan_uses_ai"] as? Bool, false)
        XCTAssertNotNil(st["ends_at_label"] as? String)
        let href = st["health_reference"] as? [String: Any]
        XCTAssertEqual(href?["role"] as? String, "reference_only")

        _ = try store.logMetric(weightKg: 86.2, sleepH: nil, context: "morning_fasted")
        // HealthKit weight is reference only — user morning still preferred
        _ = try store.logMetric(
            weightKg: 90.0,
            sleepH: nil,
            preferredId: "hk-weight-test",
            context: "healthkit"
        )
        XCTAssertEqual(store.dashboard().latestWeightKg, 86.2)

        // Meal ends fast
        _ = try store.logMeal(items: ["점심"], kcal: 500, proteinG: 30, note: nil)
        let after = store.fastingStatus()
        XCTAssertEqual(after["active"] as? Bool, false)

        // Profile + plan is rules-only
        try store.setProfile(DietProfile(
            heightCm: 170, weightKg: 86.2, age: 39, sex: .male,
            targetWeightKg: 75, activity: .moderate
        ))
        let plan = store.planProjection()
        XCTAssertNotNil(plan)
        let dict = plan!.asDict()
        XCTAssertEqual(dict["plan_uses_ai"] as? Bool, false)
        XCTAssertEqual(dict["engine"] as? String, "diet-rules/mifflin-7700")
    }
}
