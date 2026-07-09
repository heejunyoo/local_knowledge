import SwiftUI
import KnowledgeCore

/// Diet hub — depth 1: today + one CTA. Depth 2: sheets for log / week / goals.
public struct DietView: View {
    private let knowledgeRoot: URL
    @State private var store: DietStore
    @State private var dash: DietStore.Dashboard
    @State private var flash: String?
    @State private var sheet: DietSheet?

    // Forms
    @State private var mealItems = ""
    @State private var mealKcal = ""
    @State private var mealProtein = ""
    @State private var workoutKind = "걷기"
    @State private var workoutMinutes = "30"
    @State private var weightKg = ""
    @State private var sleepH = ""
    @State private var goalKcal = "2000"
    @State private var goalProtein = "100"
    @State private var goalWeeklyWO = "4"
    @State private var goalDayMin = "30"

    private enum DietSheet: Identifiable {
        case log, week, goals
        var id: String {
            switch self {
            case .log: return "log"
            case .week: return "week"
            case .goals: return "goals"
            }
        }
    }

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
                VStack(alignment: .leading, spacing: TossSpace.x6) {
                    header
                    todayHero
                    if let line = dash.analysisLines.first {
                        insightCard(line)
                    }
                    quickActions
                    todayList
                    if let flash {
                        Text(flash)
                            .font(TossFont.caption())
                            .fontWeight(.semibold)
                            .foregroundStyle(TossColor.blue500)
                    }
                    Spacer(minLength: TossSpace.x8)
                }
                .padding(.horizontal, TossSpace.x6)
                .padding(.top, TossSpace.x6)
            }
        }
        .sheet(item: $sheet) { kind in
            switch kind {
            case .log: logSheet
            case .week: weekSheet
            case .goals: goalsSheet
            }
        }
        .onAppear { refresh() }
    }

    // MARK: Depth 1

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: TossSpace.x2) {
                Text("식단")
                    .font(TossFont.title())
                    .foregroundStyle(TossColor.grey900)
                Text("오늘만 보면 돼요")
                    .font(TossFont.body())
                    .foregroundStyle(TossColor.grey500)
            }
            Spacer()
            Button("목표") {
                loadGoalsForm()
                sheet = .goals
            }
            .font(TossFont.body())
            .fontWeight(.semibold)
            .foregroundStyle(TossColor.blue500)
            .buttonStyle(.plain)
        }
    }

    private var todayHero: some View {
        TossCard {
            VStack(alignment: .leading, spacing: TossSpace.x4) {
                Text(dash.day.date)
                    .font(TossFont.caption())
                    .foregroundStyle(TossColor.grey500)
                HStack(spacing: TossSpace.x4) {
                    metricPill(
                        title: "칼로리",
                        value: "\(Int(dash.day.kcal))",
                        sub: "목표 \(Int(dash.goals.targetKcal))",
                        progress: dash.kcalProgress
                    )
                    metricPill(
                        title: "단백질",
                        value: "\(Int(dash.day.proteinG))g",
                        sub: "목표 \(Int(dash.goals.targetProteinG))g",
                        progress: dash.proteinProgress
                    )
                    metricPill(
                        title: "운동",
                        value: "\(dash.day.workoutMinutes)분",
                        sub: "목표 \(dash.goals.targetWorkoutMinutesPerDay)분",
                        progress: dash.workoutProgress
                    )
                }
                // Single progress for weekly workouts
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("이번 주 운동")
                            .font(TossFont.caption())
                            .foregroundStyle(TossColor.grey700)
                        Spacer()
                        Text("\(dash.weekWorkoutCount)/\(dash.goals.weeklyWorkouts)회")
                            .font(TossFont.caption())
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
                    .frame(height: 8)
                }
            }
        }
    }

    private func metricPill(title: String, value: String, sub: String, progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(TossFont.caption())
                .foregroundStyle(TossColor.grey500)
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(TossColor.grey900)
            Text("\(Int((min(1.5, max(0, progress)) * 100).rounded()))% · \(sub)")
                .font(.system(size: 11))
                .foregroundStyle(TossColor.grey500)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func insightCard(_ line: String) -> some View {
        HStack(alignment: .top, spacing: TossSpace.x3) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(TossColor.blue500)
            Text(line)
                .font(TossFont.body())
                .foregroundStyle(TossColor.grey900)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(TossSpace.x4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TossColor.blue50)
        .clipShape(RoundedRectangle(cornerRadius: TossRadius.card, style: .continuous))
    }

    private var quickActions: some View {
        VStack(spacing: TossSpace.x3) {
            TossPrimaryButton("기록 남기기") { sheet = .log }
            HStack(spacing: TossSpace.x3) {
                Button {
                    sheet = .week
                } label: {
                    Text("주간 보기")
                        .font(TossFont.button())
                        .foregroundStyle(TossColor.grey900)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(TossColor.white)
                        .clipShape(RoundedRectangle(cornerRadius: TossRadius.button, style: .continuous))
                }
                .buttonStyle(.plain)
                Button {
                    refresh()
                    flash = "새로고침했어요"
                } label: {
                    Text("새로고침")
                        .font(TossFont.button())
                        .foregroundStyle(TossColor.grey900)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(TossColor.white)
                        .clipShape(RoundedRectangle(cornerRadius: TossRadius.button, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var todayList: some View {
        VStack(alignment: .leading, spacing: TossSpace.x3) {
            Text("오늘 기록")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(TossColor.grey500)
            TossCard(padded: false) {
                if dash.day.meals.isEmpty && dash.day.workouts.isEmpty {
                    Text("아직 없어요. 위에서 남겨 보세요.")
                        .font(TossFont.body())
                        .foregroundStyle(TossColor.grey500)
                        .padding(TossSpace.x5)
                } else {
                    VStack(spacing: 0) {
                        ForEach(dash.day.meals) { m in
                            row(
                                icon: "fork.knife",
                                title: m.items.joined(separator: ", "),
                                sub: [m.kcal.map { "\(Int($0)) kcal" }, m.proteinG.map { "P\(Int($0))g" }]
                                    .compactMap { $0 }.joined(separator: " · ")
                            )
                        }
                        ForEach(dash.day.workouts) { w in
                            row(icon: "figure.walk", title: w.kind, sub: "\(w.minutes)분")
                        }
                    }
                }
            }
        }
    }

    private func row(icon: String, title: String, sub: String) -> some View {
        HStack(spacing: TossSpace.x3) {
            Image(systemName: icon).foregroundStyle(TossColor.blue500).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(TossFont.body()).fontWeight(.medium).foregroundStyle(TossColor.grey900)
                if !sub.isEmpty {
                    Text(sub).font(TossFont.caption()).foregroundStyle(TossColor.grey500)
                }
            }
            Spacer()
        }
        .padding(.horizontal, TossSpace.x5)
        .padding(.vertical, TossSpace.x3)
    }

    // MARK: Sheets

    private var logSheet: some View {
        NavigationStack {
            Form {
                Section("식사") {
                    TextField("음식 (쉼표 구분)", text: $mealItems)
                    TextField("kcal", text: $mealKcal)
                    TextField("단백질 g", text: $mealProtein)
                    Button("식사 저장") { saveMeal(); sheet = nil }
                        .disabled(mealItems.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Section("운동") {
                    TextField("종류", text: $workoutKind)
                    TextField("분", text: $workoutMinutes)
                    Button("운동 저장") { saveWorkout(); sheet = nil }
                }
                Section("체중 · 수면") {
                    TextField("체중 kg", text: $weightKg)
                    TextField("수면 h", text: $sleepH)
                    Button("지표 저장") { saveMetric(); sheet = nil }
                        .disabled(weightKg.isEmpty && sleepH.isEmpty)
                }
            }
            .navigationTitle("기록 남기기")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { sheet = nil }
                }
            }
        }
        .frame(minWidth: 380, minHeight: 480)
    }

    private var weekSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TossSpace.x4) {
                    let maxK = max(dash.weekBars.map(\.kcal).max() ?? 1, dash.goals.targetKcal, 1)
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(dash.weekBars) { bar in
                            VStack(spacing: 6) {
                                Text(bar.kcal > 0 ? "\(Int(bar.kcal))" : "·")
                                    .font(.system(size: 10))
                                    .foregroundStyle(TossColor.grey500)
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(bar.date == dash.day.date ? TossColor.blue500 : TossColor.blue50)
                                    .frame(height: max(8, CGFloat(bar.kcal / maxK) * 120))
                                Text(bar.label)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(TossColor.grey700)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 180)
                    .padding()
                    ForEach(Array(dash.analysisLines.enumerated()), id: \.offset) { _, line in
                        Text("· \(line)")
                            .font(TossFont.body())
                            .foregroundStyle(TossColor.grey900)
                    }
                }
                .padding()
            }
            .navigationTitle("주간")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { sheet = nil }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 420)
    }

    private var goalsSheet: some View {
        NavigationStack {
            Form {
                TextField("하루 kcal", text: $goalKcal)
                TextField("하루 단백질 g", text: $goalProtein)
                TextField("주간 운동 횟수", text: $goalWeeklyWO)
                TextField("하루 운동 분", text: $goalDayMin)
                Button("저장") {
                    saveGoals()
                    sheet = nil
                }
            }
            .navigationTitle("목표")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { sheet = nil }
                }
            }
        }
        .frame(minWidth: 360, minHeight: 360)
    }

    // MARK: Actions

    private func refresh() {
        store.reload()
        dash = store.dashboard()
    }

    private func saveMeal() {
        let items = mealItems.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !items.isEmpty else { return }
        _ = try? store.logMeal(items: items, kcal: Double(mealKcal), proteinG: Double(mealProtein), note: nil)
        mealItems = ""; mealKcal = ""; mealProtein = ""
        flash = "식사 저장했어요"
        refresh()
    }

    private func saveWorkout() {
        _ = try? store.logWorkout(kind: workoutKind, minutes: Int(workoutMinutes) ?? 0, intensity: nil)
        flash = "운동 저장했어요"
        refresh()
    }

    private func saveMetric() {
        _ = try? store.logMetric(weightKg: Double(weightKg), sleepH: Double(sleepH))
        weightKg = ""; sleepH = ""
        flash = "지표 저장했어요"
        refresh()
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
        try? store.setGoals(g)
        flash = "목표 저장했어요"
        refresh()
    }
}
