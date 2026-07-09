import SwiftUI
import KnowledgeCore

/// Diet hub: progress rings, week bars, analysis, meal/workout/metric input.
public struct DietView: View {
    private let knowledgeRoot: URL
    @State private var store: DietStore
    @State private var dash: DietStore.Dashboard
    @State private var flash: String?
    @State private var showGoals = false

    // Meal form
    @State private var mealItems = ""
    @State private var mealKcal = ""
    @State private var mealProtein = ""
    @State private var mealNote = ""

    // Workout form
    @State private var workoutKind = "걷기"
    @State private var workoutMinutes = "30"
    @State private var workoutIntensity = "보통"

    // Metric form
    @State private var weightKg = ""
    @State private var sleepH = ""

    // Goals edit
    @State private var goalKcal = "2000"
    @State private var goalProtein = "100"
    @State private var goalWeeklyWO = "4"
    @State private var goalDayMin = "30"

    public init(knowledgeRoot: URL) {
        self.knowledgeRoot = knowledgeRoot
        let s = DietStore(knowledgeRoot: knowledgeRoot)
        _store = State(initialValue: s)
        _dash = State(initialValue: s.dashboard())
    }

    public var body: some View {
        ZStack {
            TossColor.grey100.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: TossSpace.x8) {
                    header
                    progressBlock
                    weekBlock
                    analysisBlock
                    mealInputBlock
                    workoutInputBlock
                    metricInputBlock
                    todayLogBlock
                    if let flash {
                        Text(flash)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(TossColor.blue500)
                    }
                    Spacer().frame(height: TossSpace.x6)
                }
                .padding(.horizontal, TossSpace.x6)
                .padding(.top, TossSpace.x6)
            }
        }
        .sheet(isPresented: $showGoals) { goalsSheet }
        .onAppear { refresh() }
    }

    // MARK: - Blocks

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: TossSpace.x2) {
                Text("식단 · 운동")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(TossColor.grey900)
                Text(dash.day.date)
                    .font(.system(size: 15))
                    .foregroundStyle(TossColor.grey500)
            }
            Spacer()
            Button {
                loadGoalsForm()
                showGoals = true
            } label: {
                Text("목표")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(TossColor.blue500)
            }
            .buttonStyle(.plain)
            Button {
                refresh()
                flash = "새로고침했어요"
            } label: {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(TossColor.grey700)
            }
            .buttonStyle(.plain)
        }
    }

    private var progressBlock: some View {
        VStack(alignment: .leading, spacing: TossSpace.x3) {
            Text("오늘 진행")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(TossColor.grey500)
            HStack(spacing: TossSpace.x4) {
                progressRing(
                    title: "칼로리",
                    value: "\(Int(dash.day.kcal))",
                    unit: "/ \(Int(dash.goals.targetKcal))",
                    progress: dash.kcalProgress,
                    color: TossColor.blue500
                )
                progressRing(
                    title: "단백질",
                    value: "\(Int(dash.day.proteinG))",
                    unit: "g",
                    progress: dash.proteinProgress,
                    color: TossColor.green500
                )
                progressRing(
                    title: "운동",
                    value: "\(dash.day.workoutMinutes)",
                    unit: "분",
                    progress: dash.workoutProgress,
                    color: Color(hex: 0xF59E0B)
                )
            }
            // Weekly workout bar
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("주간 운동")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(TossColor.grey700)
                    Spacer()
                    Text("\(dash.weekWorkoutCount) / \(dash.goals.weeklyWorkouts)회 · \(dash.weekWorkoutMinutes)분")
                        .font(.system(size: 13))
                        .foregroundStyle(TossColor.grey500)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(TossColor.grey200)
                        Capsule()
                            .fill(TossColor.blue500)
                            .frame(width: geo.size.width * CGFloat(min(1, max(0, dash.weeklyWorkoutProgress))))
                    }
                }
                .frame(height: 10)
            }
            .padding(TossSpace.x4)
            .background(TossColor.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            if let w = dash.latestWeightKg {
                Text("최근 체중 \(String(format: "%.1f", w)) kg")
                    .font(.system(size: 14))
                    .foregroundStyle(TossColor.grey700)
            }
        }
    }

    private func progressRing(title: String, value: String, unit: String, progress: Double, color: Color) -> some View {
        let p = min(1.2, max(0, progress))
        return VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(TossColor.grey200, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(min(1, p)))
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text(value)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(TossColor.grey900)
                    Text(unit)
                        .font(.system(size: 10))
                        .foregroundStyle(TossColor.grey500)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(width: 88, height: 88)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(TossColor.grey700)
            Text("\(Int((progress * 100).rounded()))%")
                .font(.system(size: 12))
                .foregroundStyle(TossColor.grey500)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TossSpace.x4)
        .background(TossColor.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var weekBlock: some View {
        VStack(alignment: .leading, spacing: TossSpace.x3) {
            Text("최근 7일 칼로리")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(TossColor.grey500)
            let maxK = max(dash.weekBars.map(\.kcal).max() ?? 1, dash.goals.targetKcal, 1)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(dash.weekBars) { bar in
                    VStack(spacing: 6) {
                        Text(bar.kcal > 0 ? "\(Int(bar.kcal))" : "·")
                            .font(.system(size: 10))
                            .foregroundStyle(TossColor.grey500)
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(bar.date == dash.day.date ? TossColor.blue500 : TossColor.blue50)
                            .frame(height: max(8, CGFloat(bar.kcal / maxK) * 100))
                        Text(bar.label)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(TossColor.grey700)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(TossSpace.x5)
            .frame(maxWidth: .infinity)
            .frame(height: 160)
            .background(TossColor.white)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private var analysisBlock: some View {
        VStack(alignment: .leading, spacing: TossSpace.x3) {
            Text("분석")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(TossColor.grey500)
            VStack(alignment: .leading, spacing: TossSpace.x3) {
                ForEach(Array(dash.analysisLines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(TossColor.blue500)
                            .frame(width: 6, height: 6)
                            .padding(.top, 6)
                        Text(line)
                            .font(.system(size: 15))
                            .foregroundStyle(TossColor.grey900)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(TossSpace.x5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TossColor.white)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private var mealInputBlock: some View {
        inputCard(title: "식사 기록") {
            field("음식 (쉼표로 구분)", text: $mealItems)
            HStack {
                field("kcal", text: $mealKcal)
                field("단백질 g", text: $mealProtein)
            }
            field("메모 (선택)", text: $mealNote)
            TossPrimaryButton("식사 저장") { saveMeal() }
                .disabled(mealItems.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var workoutInputBlock: some View {
        inputCard(title: "운동 기록") {
            field("종류", text: $workoutKind)
            HStack {
                field("분", text: $workoutMinutes)
                field("강도", text: $workoutIntensity)
            }
            TossPrimaryButton("운동 저장") { saveWorkout() }
        }
    }

    private var metricInputBlock: some View {
        inputCard(title: "체중 · 수면") {
            HStack {
                field("체중 kg", text: $weightKg)
                field("수면 시간", text: $sleepH)
            }
            TossPrimaryButton("지표 저장") { saveMetric() }
                .disabled(weightKg.isEmpty && sleepH.isEmpty)
        }
    }

    private var todayLogBlock: some View {
        VStack(alignment: .leading, spacing: TossSpace.x3) {
            Text("오늘 기록")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(TossColor.grey500)
            VStack(alignment: .leading, spacing: 0) {
                if dash.day.meals.isEmpty && dash.day.workouts.isEmpty {
                    Text("아직 없어요. 위에서 입력해 보세요.")
                        .font(.system(size: 14))
                        .foregroundStyle(TossColor.grey500)
                        .padding(TossSpace.x5)
                }
                ForEach(dash.day.meals) { m in
                    logRow(
                        icon: "fork.knife",
                        title: m.items.joined(separator: ", "),
                        subtitle: [
                            m.kcal.map { "\(Int($0)) kcal" },
                            m.proteinG.map { "P \(Int($0))g" },
                            m.note,
                        ].compactMap { $0 }.joined(separator: " · ")
                    )
                }
                ForEach(dash.day.workouts) { w in
                    logRow(
                        icon: "figure.walk",
                        title: w.kind,
                        subtitle: "\(w.minutes)분" + (w.intensity.map { " · \($0)" } ?? "")
                    )
                }
            }
            .background(TossColor.white)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func logRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: TossSpace.x3) {
            Image(systemName: icon)
                .foregroundStyle(TossColor.blue500)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(TossColor.grey900)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(TossColor.grey500)
                }
            }
            Spacer()
        }
        .padding(.horizontal, TossSpace.x5)
        .padding(.vertical, TossSpace.x3)
    }

    private func inputCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: TossSpace.x3) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(TossColor.grey500)
            VStack(alignment: .leading, spacing: TossSpace.x3) {
                content()
            }
            .padding(TossSpace.x5)
            .background(TossColor.white)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .padding(12)
            .background(TossColor.grey100)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var goalsSheet: some View {
        VStack(alignment: .leading, spacing: TossSpace.x5) {
            Text("목표 설정")
                .font(.system(size: 22, weight: .bold))
            field("하루 칼로리 kcal", text: $goalKcal)
            field("하루 단백질 g", text: $goalProtein)
            field("주간 운동 횟수", text: $goalWeeklyWO)
            field("하루 운동 목표 분", text: $goalDayMin)
            TossPrimaryButton("저장") {
                saveGoals()
                showGoals = false
            }
            Button("닫기") { showGoals = false }
                .buttonStyle(.plain)
                .foregroundStyle(TossColor.grey500)
            Spacer()
        }
        .padding(TossSpace.x6)
        .frame(width: 360, height: 420)
    }

    // MARK: - Actions

    private func refresh() {
        store.reload()
        dash = store.dashboard()
    }

    private func saveMeal() {
        let items = mealItems.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !items.isEmpty else { return }
        do {
            _ = try store.logMeal(
                items: items,
                kcal: Double(mealKcal),
                proteinG: Double(mealProtein),
                note: mealNote.isEmpty ? nil : mealNote
            )
            mealItems = ""; mealKcal = ""; mealProtein = ""; mealNote = ""
            flash = "식사 저장했어요"
            refresh()
        } catch {
            flash = "저장 실패"
        }
    }

    private func saveWorkout() {
        do {
            _ = try store.logWorkout(
                kind: workoutKind,
                minutes: Int(workoutMinutes) ?? 0,
                intensity: workoutIntensity.isEmpty ? nil : workoutIntensity
            )
            flash = "운동 저장했어요"
            refresh()
        } catch {
            flash = "저장 실패"
        }
    }

    private func saveMetric() {
        do {
            _ = try store.logMetric(
                weightKg: Double(weightKg),
                sleepH: Double(sleepH)
            )
            weightKg = ""; sleepH = ""
            flash = "지표 저장했어요"
            refresh()
        } catch {
            flash = "저장 실패"
        }
    }

    private func loadGoalsForm() {
        let g = store.goals()
        goalKcal = "\(Int(g.targetKcal))"
        goalProtein = "\(Int(g.targetProteinG))"
        goalWeeklyWO = "\(g.weeklyWorkouts)"
        goalDayMin = "\(g.targetWorkoutMinutesPerDay)"
    }

    private func saveGoals() {
        var g = store.goals()
        if let v = Double(goalKcal) { g.targetKcal = v }
        if let v = Double(goalProtein) { g.targetProteinG = v }
        if let v = Int(goalWeeklyWO) { g.weeklyWorkouts = v }
        if let v = Int(goalDayMin) { g.targetWorkoutMinutesPerDay = v }
        do {
            try store.setGoals(g)
            flash = "목표 저장했어요"
            refresh()
        } catch {
            flash = "목표 저장 실패"
        }
    }
}
