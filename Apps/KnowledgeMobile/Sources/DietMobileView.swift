import SwiftUI

/// Dedicated Diet tab: progress, week chart, analysis, inputs (via Core gateway).
struct DietMobileView: View {
    @EnvironmentObject var core: CoreClient

    @State private var dashboard: [String: Any] = [:]
    @State private var busy = false
    @State private var err: String?
    @State private var flash: String?

    // forms
    @State private var mealItems = ""
    @State private var mealKcal = ""
    @State private var mealProtein = ""
    @State private var workoutKind = "걷기"
    @State private var workoutMin = "30"
    @State private var weightKg = ""
    @State private var sleepH = ""

    @State private var showGoals = false
    @State private var goalKcal = "2000"
    @State private var goalProtein = "100"
    @State private var goalWeekly = "4"
    @State private var goalDayMin = "30"

    private let accent = Color(red: 0.19, green: 0.51, blue: 0.96)
    private let green = Color(red: 0.01, green: 0.70, blue: 0.42)

    var body: some View {
        NavigationStack {
            List {
                if let err {
                    Section { Text(err).foregroundStyle(.red).font(.caption) }
                }
                if let flash {
                    Section { Text(flash).foregroundStyle(accent).font(.subheadline) }
                }

                progressSection
                weekSection
                analysisSection
                mealSection
                workoutSection
                metricSection
                todaySection
            }
            .navigationTitle("식단 · 운동")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("목표") {
                        loadGoalsFromDash()
                        showGoals = true
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await reload() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .refreshable { await reload() }
            .task { await reload() }
            .sheet(isPresented: $showGoals) { goalsSheet }
        }
    }

    // MARK: Sections

    private var progressSection: some View {
        Section("오늘 진행") {
            let prog = dashboard["progress"] as? [String: Any] ?? [:]
            let goals = dashboard["goals"] as? [String: Any] ?? [:]
            let day = dashboard["day"] as? [String: Any] ?? [:]
            let totals = day["totals"] as? [String: Any] ?? [:]

            HStack(spacing: 12) {
                ring(
                    title: "kcal",
                    value: intVal(totals["kcal"]),
                    target: intVal(goals["target_kcal"]),
                    progress: doubleVal(prog["kcal"]),
                    color: accent
                )
                ring(
                    title: "단백질",
                    value: intVal(totals["protein_g"]),
                    target: intVal(goals["target_protein_g"]),
                    progress: doubleVal(prog["protein"]),
                    color: green
                )
                ring(
                    title: "운동분",
                    value: intVal(totals["workout_minutes"]),
                    target: intVal(goals["target_workout_minutes_per_day"]),
                    progress: doubleVal(prog["workout"]),
                    color: Color.orange
                )
            }
            .padding(.vertical, 4)

            let week = dashboard["week"] as? [String: Any] ?? [:]
            let wp = doubleVal(prog["weekly_workouts"])
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("주간 운동")
                    Spacer()
                    Text("\(intVal(week["workout_count"])) / \(intVal(goals["weekly_workouts"]))회")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                ProgressView(value: min(1, max(0, wp)))
                    .tint(accent)
            }
            if let w = dashboard["latest_weight_kg"] as? Double {
                Text("최근 체중 \(String(format: "%.1f", w)) kg")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func ring(title: String, value: Int, target: Int, progress: Double, color: Color) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(Color(.systemGray5), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: CGFloat(min(1, max(0, progress))))
                    .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(value)")
                        .font(.system(size: 14, weight: .bold))
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 72, height: 72)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("/ \(target)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var weekSection: some View {
        Section("7일 칼로리") {
            let week = dashboard["week"] as? [String: Any] ?? [:]
            let bars = week["bars"] as? [[String: Any]] ?? []
            let maxK = max(bars.map { doubleVal($0["kcal"]) }.max() ?? 1, 1)
            if bars.isEmpty {
                Text("데이터 없음").foregroundStyle(.secondary)
            } else {
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(Array(bars.enumerated()), id: \.offset) { _, b in
                        let k = doubleVal(b["kcal"])
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(accent.opacity(k > 0 ? 1 : 0.25))
                                .frame(height: max(6, CGFloat(k / maxK) * 80))
                            Text((b["label"] as? String) ?? "")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 110)
            }
        }
    }

    private var analysisSection: some View {
        Section("분석") {
            let lines = dashboard["analysis"] as? [String] ?? []
            if lines.isEmpty {
                Text("기록을 남기면 분석이 생겨요.").foregroundStyle(.secondary)
            } else {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.subheadline)
                }
            }
        }
    }

    private var mealSection: some View {
        Section("식사 기록") {
            TextField("음식 (쉼표 구분)", text: $mealItems)
            HStack {
                TextField("kcal", text: $mealKcal)
                    .keyboardType(.decimalPad)
                TextField("단백질 g", text: $mealProtein)
                    .keyboardType(.decimalPad)
            }
            Button {
                Task { await saveMeal() }
            } label: {
                if busy { ProgressView() } else { Text("식사 저장").fontWeight(.semibold) }
            }
            .disabled(busy || mealItems.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var workoutSection: some View {
        Section("운동 기록") {
            TextField("종류", text: $workoutKind)
            TextField("분", text: $workoutMin)
                .keyboardType(.numberPad)
            Button {
                Task { await saveWorkout() }
            } label: {
                Text("운동 저장").fontWeight(.semibold)
            }
            .disabled(busy)
        }
    }

    private var metricSection: some View {
        Section("체중 · 수면") {
            HStack {
                TextField("체중 kg", text: $weightKg).keyboardType(.decimalPad)
                TextField("수면 h", text: $sleepH).keyboardType(.decimalPad)
            }
            Button {
                Task { await saveMetric() }
            } label: {
                Text("지표 저장").fontWeight(.semibold)
            }
            .disabled(busy || (weightKg.isEmpty && sleepH.isEmpty))
        }
    }

    private var todaySection: some View {
        Section("오늘 기록") {
            let day = dashboard["day"] as? [String: Any] ?? [:]
            let meals = day["meals"] as? [[String: Any]] ?? []
            let workouts = day["workouts"] as? [[String: Any]] ?? []
            if meals.isEmpty && workouts.isEmpty {
                Text("아직 없어요").foregroundStyle(.secondary)
            }
            ForEach(Array(meals.enumerated()), id: \.offset) { _, m in
                let items = (m["items"] as? [String])?.joined(separator: ", ") ?? "식사"
                let kcal = m["kcal"] as? Double
                VStack(alignment: .leading, spacing: 2) {
                    Text(items).font(.headline)
                    if let kcal {
                        Text("\(Int(kcal)) kcal").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(Array(workouts.enumerated()), id: \.offset) { _, w in
                let kind = w["kind"] as? String ?? "운동"
                let min = w["minutes"] as? Int ?? 0
                Text("\(kind) · \(min)분")
            }
        }
    }

    private var goalsSheet: some View {
        NavigationStack {
            Form {
                TextField("하루 kcal", text: $goalKcal).keyboardType(.numberPad)
                TextField("하루 단백질 g", text: $goalProtein).keyboardType(.numberPad)
                TextField("주간 운동 횟수", text: $goalWeekly).keyboardType(.numberPad)
                TextField("하루 운동 분", text: $goalDayMin).keyboardType(.numberPad)
                Button("저장") {
                    Task { await saveGoals() }
                }
            }
            .navigationTitle("목표")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { showGoals = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: Actions

    private func reload() async {
        busy = true
        err = nil
        defer { busy = false }
        do {
            dashboard = try await core.dietDashboard()
            await core.refreshDietLine()
        } catch {
            err = error.localizedDescription
        }
    }

    private func saveMeal() async {
        busy = true
        defer { busy = false }
        let items = mealItems.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        do {
            try await core.dietLogMeal(
                items: items,
                kcal: Double(mealKcal),
                proteinG: Double(mealProtein),
                note: nil
            )
            mealItems = ""; mealKcal = ""; mealProtein = ""
            flash = "식사 저장"
            await reload()
        } catch {
            err = error.localizedDescription
        }
    }

    private func saveWorkout() async {
        busy = true
        defer { busy = false }
        do {
            try await core.dietLogWorkout(
                kind: workoutKind,
                minutes: Int(workoutMin) ?? 0,
                intensity: nil
            )
            flash = "운동 저장"
            await reload()
        } catch {
            err = error.localizedDescription
        }
    }

    private func saveMetric() async {
        busy = true
        defer { busy = false }
        do {
            try await core.dietLogMetric(weightKg: Double(weightKg), sleepH: Double(sleepH))
            weightKg = ""; sleepH = ""
            flash = "지표 저장"
            await reload()
        } catch {
            err = error.localizedDescription
        }
    }

    private func loadGoalsFromDash() {
        let g = dashboard["goals"] as? [String: Any] ?? [:]
        goalKcal = "\(intVal(g["target_kcal"]))"
        goalProtein = "\(intVal(g["target_protein_g"]))"
        goalWeekly = "\(intVal(g["weekly_workouts"]))"
        goalDayMin = "\(intVal(g["target_workout_minutes_per_day"]))"
    }

    private func saveGoals() async {
        do {
            try await core.dietSetGoals(
                kcal: Double(goalKcal) ?? 2000,
                protein: Double(goalProtein) ?? 100,
                weeklyWorkouts: Int(goalWeekly) ?? 4,
                dayMinutes: Int(goalDayMin) ?? 30
            )
            showGoals = false
            flash = "목표 저장"
            await reload()
        } catch {
            err = error.localizedDescription
        }
    }

    private func intVal(_ any: Any?) -> Int {
        if let i = any as? Int { return i }
        if let d = any as? Double { return Int(d) }
        if let s = any as? String, let i = Int(s) { return i }
        return 0
    }

    private func doubleVal(_ any: Any?) -> Double {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let s = any as? String, let d = Double(s) { return d }
        return 0
    }
}
