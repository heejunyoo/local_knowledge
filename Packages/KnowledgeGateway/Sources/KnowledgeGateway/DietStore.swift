import Foundation

/// Minimal local Diet SoT (M4 stub). File-backed JSON under knowledge root.
/// Full product may move to `~/Knowledge/services/diet/` + separate process.
public final class DietStore: @unchecked Sendable {
    public struct Meal: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var ts: String
        public var items: [String]
        public var kcal: Double?
        public var proteinG: Double?
        public var note: String?

        enum CodingKeys: String, CodingKey {
            case id, ts, items, note
            case kcal
            case proteinG = "protein_g"
        }
    }

    public struct Workout: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var ts: String
        public var kind: String
        public var minutes: Int
        public var intensity: String?
    }

    public struct Metric: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var ts: String
        public var weightKg: Double?
        public var sleepH: Double?

        enum CodingKeys: String, CodingKey {
            case id, ts
            case weightKg = "weight_kg"
            case sleepH = "sleep_h"
        }
    }

    private struct FileModel: Codable {
        var meals: [Meal]
        var workouts: [Workout]
        var metrics: [Metric]
    }

    private let url: URL
    private let lock = NSLock()
    private var model: FileModel

    public init(knowledgeRoot: URL) {
        let dir = knowledgeRoot.appendingPathComponent("services/diet", isDirectory: true)
        self.url = dir.appendingPathComponent("diet.json")
        if let data = try? Data(contentsOf: url),
           let m = try? JSONDecoder().decode(FileModel.self, from: data) {
            self.model = m
        } else {
            self.model = FileModel(meals: [], workouts: [], metrics: [])
        }
    }

    public func logMeal(
        items: [String],
        kcal: Double?,
        proteinG: Double?,
        note: String?,
        ts: Date = Date()
    ) throws -> Meal {
        lock.lock(); defer { lock.unlock() }
        let meal = Meal(
            id: UUID().uuidString,
            ts: iso(ts),
            items: items,
            kcal: kcal,
            proteinG: proteinG,
            note: note
        )
        model.meals.append(meal)
        try persist()
        return meal
    }

    public func logWorkout(
        kind: String,
        minutes: Int,
        intensity: String?,
        ts: Date = Date()
    ) throws -> Workout {
        lock.lock(); defer { lock.unlock() }
        let w = Workout(
            id: UUID().uuidString,
            ts: iso(ts),
            kind: kind.isEmpty ? "workout" : kind,
            minutes: max(0, minutes),
            intensity: intensity
        )
        model.workouts.append(w)
        try persist()
        return w
    }

    public func logMetric(weightKg: Double?, sleepH: Double?, ts: Date = Date()) throws -> Metric {
        lock.lock(); defer { lock.unlock() }
        let m = Metric(id: UUID().uuidString, ts: iso(ts), weightKg: weightKg, sleepH: sleepH)
        model.metrics.append(m)
        try persist()
        return m
    }

    /// Day summary for local calendar day (device TZ).
    public func daySummary(day: Date = Date()) -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        let key = dayKey(day)
        let meals = model.meals.filter { $0.ts.hasPrefix(key) }
        let workouts = model.workouts.filter { $0.ts.hasPrefix(key) }
        let metrics = model.metrics.filter { $0.ts.hasPrefix(key) }
        let kcal = meals.compactMap(\.kcal).reduce(0, +)
        let protein = meals.compactMap(\.proteinG).reduce(0, +)
        let minutes = workouts.map(\.minutes).reduce(0, +)
        return [
            "date": key,
            "meals": meals.map { mealDict($0) },
            "workouts": workouts.map { workoutDict($0) },
            "metrics": metrics.map { metricDict($0) },
            "totals": [
                "kcal": kcal,
                "protein_g": protein,
                "workout_minutes": minutes,
                "meal_count": meals.count,
                "workout_count": workouts.count,
            ] as [String: Any],
            "summary_text": dayText(key: key, meals: meals, workouts: workouts, kcal: kcal, protein: protein, minutes: minutes),
        ]
    }

    public func weekReview(reference: Date = Date()) -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        let cal = Calendar.current
        let end = cal.startOfDay(for: reference)
        guard let start = cal.date(byAdding: .day, value: -6, to: end) else {
            return ["error": "bad date"]
        }
        var days: [[String: Any]] = []
        var totalKcal = 0.0
        var totalProtein = 0.0
        var totalMin = 0
        var mealCount = 0
        var workoutCount = 0
        for offset in 0..<7 {
            guard let d = cal.date(byAdding: .day, value: offset, to: start) else { continue }
            // re-enter without deadlock: compute inline
            let key = dayKey(d)
            let meals = model.meals.filter { $0.ts.hasPrefix(key) }
            let workouts = model.workouts.filter { $0.ts.hasPrefix(key) }
            let kcal = meals.compactMap(\.kcal).reduce(0, +)
            let protein = meals.compactMap(\.proteinG).reduce(0, +)
            let minutes = workouts.map(\.minutes).reduce(0, +)
            totalKcal += kcal
            totalProtein += protein
            totalMin += minutes
            mealCount += meals.count
            workoutCount += workouts.count
            days.append([
                "date": key,
                "kcal": kcal,
                "protein_g": protein,
                "workout_minutes": minutes,
                "meals": meals.count,
                "workouts": workouts.count,
            ])
        }
        let text = """
        최근 7일: 식사 \(mealCount)회 · 운동 \(workoutCount)회 · \(totalMin)분
        칼로리 합 \(Int(totalKcal)) kcal · 단백질 합 \(Int(totalProtein)) g
        """
        return [
            "from": dayKey(start),
            "to": dayKey(end),
            "days": days,
            "totals": [
                "kcal": totalKcal,
                "protein_g": totalProtein,
                "workout_minutes": totalMin,
                "meal_count": mealCount,
                "workout_count": workoutCount,
            ] as [String: Any],
            "summary_text": text.trimmingCharacters(in: .whitespacesAndNewlines),
        ]
    }

    /// Lightweight coach reply (no LLM) from aggregates + optional free text.
    public func coach(message: String?) -> [String: Any] {
        let day = daySummary()
        let totals = day["totals"] as? [String: Any] ?? [:]
        let kcal = totals["kcal"] as? Double ?? 0
        let protein = totals["protein_g"] as? Double ?? 0
        let minutes = totals["workout_minutes"] as? Int ?? 0
        let mealCount = totals["meal_count"] as? Int ?? 0

        var lines: [String] = []
        lines.append(day["summary_text"] as? String ?? "오늘 기록이 없어요.")
        if mealCount == 0 {
            lines.append("아직 식사 기록이 없어요. “점심 닭가슴살 200kcal”처럼 남겨 보세요.")
        } else if kcal > 0 && kcal < 1200 {
            lines.append("오늘 기록 칼로리가 낮은 편이에요. 빠진 끼니가 있는지 확인해 보세요.")
        } else if kcal >= 2800 {
            lines.append("오늘 칼로리 기록이 높은 편이에요. 목표와 비교해 보세요.")
        }
        if minutes == 0 {
            lines.append("오늘 운동 기록이 없어요. 짧게라도 걸어 두시면 좋아요.")
        } else if minutes >= 30 {
            lines.append("운동 \(minutes)분 — 좋은 페이스예요.")
        }
        if protein > 0 && protein < 50 && mealCount > 0 {
            lines.append("단백질이 \(Int(protein))g로 적을 수 있어요.")
        }
        if let msg = message?.trimmingCharacters(in: .whitespacesAndNewlines), !msg.isEmpty {
            lines.append("질문 메모: \(msg)")
        }
        return [
            "answer": lines.joined(separator: "\n"),
            "engine": "diet-rules/v1",
            "day": day,
        ]
    }

    // MARK: - private

    private func dayText(
        key: String,
        meals: [Meal],
        workouts: [Workout],
        kcal: Double,
        protein: Double,
        minutes: Int
    ) -> String {
        if meals.isEmpty && workouts.isEmpty {
            return "\(key): 식사·운동 기록이 없어요."
        }
        var parts: [String] = ["\(key):"]
        if !meals.isEmpty {
            let names = meals.flatMap(\.items).prefix(6).joined(separator: ", ")
            parts.append("식사 \(meals.count)회 (\(names)) · \(Int(kcal)) kcal · 단백질 \(Int(protein))g")
        }
        if !workouts.isEmpty {
            let kinds = workouts.map(\.kind).joined(separator: ", ")
            parts.append("운동 \(workouts.count)회 (\(kinds)) · \(minutes)분")
        }
        return parts.joined(separator: " ")
    }

    private func mealDict(_ m: Meal) -> [String: Any] {
        var d: [String: Any] = ["id": m.id, "ts": m.ts, "items": m.items]
        if let k = m.kcal { d["kcal"] = k }
        if let p = m.proteinG { d["protein_g"] = p }
        if let n = m.note { d["note"] = n }
        return d
    }

    private func workoutDict(_ w: Workout) -> [String: Any] {
        var d: [String: Any] = ["id": w.id, "ts": w.ts, "kind": w.kind, "minutes": w.minutes]
        if let i = w.intensity { d["intensity"] = i }
        return d
    }

    private func metricDict(_ m: Metric) -> [String: Any] {
        var d: [String: Any] = ["id": m.id, "ts": m.ts]
        if let w = m.weightKg { d["weight_kg"] = w }
        if let s = m.sleepH { d["sleep_h"] = s }
        return d
    }

    private func persist() throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(model).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func iso(_ d: Date) -> String {
        ISO8601DateFormatter().string(from: d)
    }

    private func dayKey(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
}
