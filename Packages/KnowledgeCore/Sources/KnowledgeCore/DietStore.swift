import Foundation

/// Local Diet SoT — file-backed JSON under knowledge root.
/// Shared by Mac UI (direct) and Core gateway (mobile RPC).
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

    public struct Goals: Codable, Equatable, Sendable {
        public var targetKcal: Double
        public var targetProteinG: Double
        public var weeklyWorkouts: Int
        public var targetWorkoutMinutesPerDay: Int

        enum CodingKeys: String, CodingKey {
            case targetKcal = "target_kcal"
            case targetProteinG = "target_protein_g"
            case weeklyWorkouts = "weekly_workouts"
            case targetWorkoutMinutesPerDay = "target_workout_minutes_per_day"
        }

        public static let `default` = Goals(
            targetKcal: 2000,
            targetProteinG: 100,
            weeklyWorkouts: 4,
            targetWorkoutMinutesPerDay: 30
        )

        public init(
            targetKcal: Double = 2000,
            targetProteinG: Double = 100,
            weeklyWorkouts: Int = 4,
            targetWorkoutMinutesPerDay: Int = 30
        ) {
            self.targetKcal = targetKcal
            self.targetProteinG = targetProteinG
            self.weeklyWorkouts = weeklyWorkouts
            self.targetWorkoutMinutesPerDay = targetWorkoutMinutesPerDay
        }
    }

    /// Typed day snapshot for UI (avoid [String: Any] in views).
    public struct DaySnapshot: Equatable, Sendable {
        public var date: String
        public var meals: [Meal]
        public var workouts: [Workout]
        public var metrics: [Metric]
        public var kcal: Double
        public var proteinG: Double
        public var workoutMinutes: Int
        public var summaryText: String
    }

    public struct DayBar: Equatable, Sendable, Identifiable {
        public var id: String { date }
        public var date: String
        public var label: String
        public var kcal: Double
        public var proteinG: Double
        public var workoutMinutes: Int
        public var mealCount: Int
        public var workoutCount: Int
    }

    public struct Dashboard: Equatable, Sendable {
        public var day: DaySnapshot
        public var weekBars: [DayBar]
        public var goals: Goals
        public var kcalProgress: Double      // 0...1+
        public var proteinProgress: Double
        public var workoutProgress: Double
        public var weeklyWorkoutProgress: Double
        public var weekKcalTotal: Double
        public var weekWorkoutCount: Int
        public var weekWorkoutMinutes: Int
        public var analysisLines: [String]
        public var latestWeightKg: Double?
    }

    private struct FileModel: Codable {
        var meals: [Meal]
        var workouts: [Workout]
        var metrics: [Metric]
        var goals: Goals?

        enum CodingKeys: String, CodingKey {
            case meals, workouts, metrics, goals
        }
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
            self.model = FileModel(meals: [], workouts: [], metrics: [], goals: .default)
        }
        if model.goals == nil { model.goals = .default }
    }

    /// Re-read from disk (another process may have written).
    public func reload() {
        lock.lock(); defer { lock.unlock() }
        if let data = try? Data(contentsOf: url),
           let m = try? JSONDecoder().decode(FileModel.self, from: data) {
            model = m
            if model.goals == nil { model.goals = .default }
        }
    }

    public func goals() -> Goals {
        lock.lock(); defer { lock.unlock() }
        return model.goals ?? .default
    }

    public func setGoals(_ g: Goals) throws {
        lock.lock(); defer { lock.unlock() }
        model.goals = g
        try persist()
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

    public func deleteMeal(id: String) throws {
        lock.lock(); defer { lock.unlock() }
        model.meals.removeAll { $0.id == id }
        try persist()
    }

    public func deleteWorkout(id: String) throws {
        lock.lock(); defer { lock.unlock() }
        model.workouts.removeAll { $0.id == id }
        try persist()
    }

    /// Morning / lunch / dinner / snack for UX chips.
    public enum MealSlot: String, CaseIterable, Sendable {
        case breakfast = "아침"
        case lunch = "점심"
        case dinner = "저녁"
        case snack = "간식"
    }

    /// Suggest next action from local hour (device TZ).
    public func suggestedAction(now: Date = Date()) -> (title: String, subtitle: String, slot: MealSlot?) {
        let hour = Calendar.current.component(.hour, from: now)
        let day = daySnapshot(day: now)
        let mealText = day.meals.map { $0.items.joined(separator: " ") }.joined(separator: " ")
        func has(_ words: [String]) -> Bool {
            words.contains { mealText.contains($0) }
        }
        if hour < 11, !has(["아침", "조식", "breakfast"]) {
            return ("아침을 남겨 볼까요?", "한 줄로 빠르게 기록해요", .breakfast)
        }
        if hour >= 11, hour < 15, !has(["점심", "중식", "lunch"]) {
            return ("점심은 어떠셨나요?", "kcal만 적어도 충분해요", .lunch)
        }
        if hour >= 17, hour < 22, !has(["저녁", "석식", "dinner"]) {
            return ("저녁을 기록해 주세요", "단백질 목표에 도움이 돼요", .dinner)
        }
        if day.workoutMinutes == 0, hour >= 12 {
            return ("오늘 운동은요?", "걷기 20분만 남겨도 좋아요", nil)
        }
        if day.meals.isEmpty {
            return ("오늘 첫 기록을 남겨 보세요", "식사·운동 모두 한 줄로 가능해요", .lunch)
        }
        return ("오늘도 잘하고 있어요", day.summaryText, nil)
    }

    public func logMealWithSlot(
        slot: MealSlot?,
        items: [String],
        kcal: Double?,
        proteinG: Double?,
        note: String?
    ) throws -> Meal {
        var labeled = items
        if let slot, let first = labeled.first, !first.contains(slot.rawValue) {
            labeled[0] = "\(slot.rawValue) \(first)"
        } else if let slot, labeled.isEmpty {
            labeled = [slot.rawValue]
        }
        return try logMeal(items: labeled, kcal: kcal, proteinG: proteinG, note: note)
    }

    public func daySnapshot(day: Date = Date()) -> DaySnapshot {
        lock.lock(); defer { lock.unlock() }
        return daySnapshotLocked(day: day)
    }

    /// Day summary for JSON-RPC / mobile.
    public func daySummary(day: Date = Date()) -> [String: Any] {
        let s = daySnapshot(day: day)
        return [
            "date": s.date,
            "meals": s.meals.map { mealDict($0) },
            "workouts": s.workouts.map { workoutDict($0) },
            "metrics": s.metrics.map { metricDict($0) },
            "totals": [
                "kcal": s.kcal,
                "protein_g": s.proteinG,
                "workout_minutes": s.workoutMinutes,
                "meal_count": s.meals.count,
                "workout_count": s.workouts.count,
            ] as [String: Any],
            "summary_text": s.summaryText,
        ]
    }

    public func weekReview(reference: Date = Date()) -> [String: Any] {
        let dash = dashboard(reference: reference)
        return [
            "from": dash.weekBars.first?.date ?? "",
            "to": dash.weekBars.last?.date ?? "",
            "days": dash.weekBars.map { bar -> [String: Any] in
                [
                    "date": bar.date,
                    "kcal": bar.kcal,
                    "protein_g": bar.proteinG,
                    "workout_minutes": bar.workoutMinutes,
                    "meals": bar.mealCount,
                    "workouts": bar.workoutCount,
                ]
            },
            "totals": [
                "kcal": dash.weekKcalTotal,
                "protein_g": dash.weekBars.map(\.proteinG).reduce(0, +),
                "workout_minutes": dash.weekWorkoutMinutes,
                "meal_count": dash.weekBars.map(\.mealCount).reduce(0, +),
                "workout_count": dash.weekWorkoutCount,
            ] as [String: Any],
            "summary_text": """
            최근 7일: 식사 \(dash.weekBars.map(\.mealCount).reduce(0, +))회 · 운동 \(dash.weekWorkoutCount)회 · \(dash.weekWorkoutMinutes)분
            칼로리 합 \(Int(dash.weekKcalTotal)) kcal
            """.trimmingCharacters(in: .whitespacesAndNewlines),
            "goals": goalsDict(dash.goals),
        ]
    }

    public func coach(message: String?) -> [String: Any] {
        let dash = dashboard()
        var lines = dash.analysisLines
        if let msg = message?.trimmingCharacters(in: .whitespacesAndNewlines), !msg.isEmpty {
            lines.append("질문 메모: \(msg)")
        }
        return [
            "answer": lines.joined(separator: "\n"),
            "engine": "diet-rules/v1",
            "day": daySummary(),
            "progress": [
                "kcal": dash.kcalProgress,
                "protein": dash.proteinProgress,
                "workout": dash.workoutProgress,
                "weekly_workouts": dash.weeklyWorkoutProgress,
            ] as [String: Any],
        ]
    }

    public func dashboard(reference: Date = Date()) -> Dashboard {
        lock.lock(); defer { lock.unlock() }
        let goals = model.goals ?? .default
        let day = daySnapshotLocked(day: reference)
        let cal = Calendar.current
        let end = cal.startOfDay(for: reference)
        var bars: [DayBar] = []
        var weekKcal = 0.0
        var weekWO = 0
        var weekMin = 0
        let df = DateFormatter()
        df.locale = Locale(identifier: "ko_KR")
        df.dateFormat = "E"
        for offset in 0..<7 {
            guard let d = cal.date(byAdding: .day, value: offset - 6, to: end) else { continue }
            let snap = daySnapshotLocked(day: d)
            weekKcal += snap.kcal
            weekWO += snap.workouts.count
            weekMin += snap.workoutMinutes
            bars.append(DayBar(
                date: snap.date,
                label: df.string(from: d),
                kcal: snap.kcal,
                proteinG: snap.proteinG,
                workoutMinutes: snap.workoutMinutes,
                mealCount: snap.meals.count,
                workoutCount: snap.workouts.count
            ))
        }
        let kcalP = goals.targetKcal > 0 ? day.kcal / goals.targetKcal : 0
        let proteinP = goals.targetProteinG > 0 ? day.proteinG / goals.targetProteinG : 0
        let workP = goals.targetWorkoutMinutesPerDay > 0
            ? Double(day.workoutMinutes) / Double(goals.targetWorkoutMinutesPerDay) : 0
        let weekWP = goals.weeklyWorkouts > 0
            ? Double(weekWO) / Double(goals.weeklyWorkouts) : 0

        var latestWeight: Double?
        for m in model.metrics.reversed() {
            if let w = m.weightKg { latestWeight = w; break }
        }

        let lines = analysisLocked(
            day: day,
            goals: goals,
            weekWorkoutCount: weekWO,
            weekMinutes: weekMin,
            kcalProgress: kcalP,
            proteinProgress: proteinP,
            workoutProgress: workP,
            weeklyWorkoutProgress: weekWP
        )

        return Dashboard(
            day: day,
            weekBars: bars,
            goals: goals,
            kcalProgress: kcalP,
            proteinProgress: proteinP,
            workoutProgress: workP,
            weeklyWorkoutProgress: weekWP,
            weekKcalTotal: weekKcal,
            weekWorkoutCount: weekWO,
            weekWorkoutMinutes: weekMin,
            analysisLines: lines,
            latestWeightKg: latestWeight
        )
    }

    public func goalsDict(_ g: Goals? = nil) -> [String: Any] {
        let x = g ?? goals()
        return [
            "target_kcal": x.targetKcal,
            "target_protein_g": x.targetProteinG,
            "weekly_workouts": x.weeklyWorkouts,
            "target_workout_minutes_per_day": x.targetWorkoutMinutesPerDay,
        ]
    }

    public func dashboardJSON(reference: Date = Date()) -> [String: Any] {
        let d = dashboard(reference: reference)
        var out: [String: Any] = [
            "day": daySummary(day: reference),
            "goals": goalsDict(d.goals),
            "progress": [
                "kcal": d.kcalProgress,
                "protein": d.proteinProgress,
                "workout": d.workoutProgress,
                "weekly_workouts": d.weeklyWorkoutProgress,
            ] as [String: Any],
            "week": [
                "bars": d.weekBars.map { b -> [String: Any] in
                    [
                        "date": b.date,
                        "label": b.label,
                        "kcal": b.kcal,
                        "protein_g": b.proteinG,
                        "workout_minutes": b.workoutMinutes,
                        "meals": b.mealCount,
                        "workouts": b.workoutCount,
                    ]
                },
                "kcal_total": d.weekKcalTotal,
                "workout_count": d.weekWorkoutCount,
                "workout_minutes": d.weekWorkoutMinutes,
            ] as [String: Any],
            "analysis": d.analysisLines,
            "summary_text": d.day.summaryText,
        ]
        if let w = d.latestWeightKg {
            out["latest_weight_kg"] = w
        }
        return out
    }

    // MARK: - private

    private func daySnapshotLocked(day: Date) -> DaySnapshot {
        let key = dayKey(day)
        let meals = model.meals.filter { $0.ts.hasPrefix(key) }
        let workouts = model.workouts.filter { $0.ts.hasPrefix(key) }
        let metrics = model.metrics.filter { $0.ts.hasPrefix(key) }
        let kcal = meals.compactMap(\.kcal).reduce(0, +)
        let protein = meals.compactMap(\.proteinG).reduce(0, +)
        let minutes = workouts.map(\.minutes).reduce(0, +)
        return DaySnapshot(
            date: key,
            meals: meals,
            workouts: workouts,
            metrics: metrics,
            kcal: kcal,
            proteinG: protein,
            workoutMinutes: minutes,
            summaryText: dayText(key: key, meals: meals, workouts: workouts, kcal: kcal, protein: protein, minutes: minutes)
        )
    }

    private func analysisLocked(
        day: DaySnapshot,
        goals: Goals,
        weekWorkoutCount: Int,
        weekMinutes: Int,
        kcalProgress: Double,
        proteinProgress: Double,
        workoutProgress: Double,
        weeklyWorkoutProgress: Double
    ) -> [String] {
        var lines: [String] = []
        lines.append(day.summaryText)

        if day.meals.isEmpty {
            lines.append("아직 식사 기록이 없어요. 아래 입력으로 남겨 보세요.")
        } else if kcalProgress < 0.55 {
            lines.append("칼로리가 목표의 \(pct(kcalProgress))예요. 끼니가 빠졌는지 확인해 보세요.")
        } else if kcalProgress > 1.15 {
            lines.append("칼로리가 목표를 \(pct(kcalProgress - 1)) 넘었어요.")
        } else {
            lines.append("칼로리 페이스 양호 (\(pct(kcalProgress)) / 목표 \(Int(goals.targetKcal)) kcal).")
        }

        if day.proteinG > 0 {
            if proteinProgress < 0.6 {
                lines.append("단백질 \(Int(day.proteinG))g — 목표 \(Int(goals.targetProteinG))g의 \(pct(proteinProgress)).")
            } else {
                lines.append("단백질 \(Int(day.proteinG))g (\(pct(proteinProgress))).")
            }
        }

        if day.workoutMinutes == 0 {
            lines.append("오늘 운동 기록이 없어요. 목표 \(goals.targetWorkoutMinutesPerDay)분.")
        } else {
            lines.append("오늘 운동 \(day.workoutMinutes)분 (\(pct(workoutProgress))).")
        }

        lines.append(
            "주간 운동 \(weekWorkoutCount)회 / 목표 \(goals.weeklyWorkouts)회 · 총 \(weekMinutes)분 (\(pct(weeklyWorkoutProgress)))."
        )
        return lines
    }

    private func pct(_ r: Double) -> String {
        "\(Int((r * 100).rounded()))%"
    }

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
