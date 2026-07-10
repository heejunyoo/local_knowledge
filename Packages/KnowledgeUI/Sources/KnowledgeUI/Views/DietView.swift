import SwiftUI
import KnowledgeCore

/// Diet hub — time-aware CTA, meal slots, quick chips, NL, swipe delete.
public struct DietView: View {
    private let knowledgeRoot: URL
    @State private var store: DietStore
    @State private var dash: DietStore.Dashboard
    @State private var suggest: (title: String, subtitle: String, slot: DietStore.MealSlot?)
    @State private var flash: String?
    @State private var sheet: DietSheet?
    @State private var selectedSlot: DietStore.MealSlot? = .lunch

    @State private var quickLine = ""
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

    // Profile (beginner)
    @State private var pHeight = "165"
    @State private var pWeight = "65"
    @State private var pAge = "30"
    @State private var pSex: DietProfile.Sex = .female
    @State private var pTarget = "60"
    @State private var pActivity: DietProfile.Activity = .light

    private let mealPresets = DietMealPreset.all
    private let workoutPresets = DietWorkoutPreset.all

    private enum DietSheet: Identifiable {
        case log, week, goals, profile
        var id: String {
            switch self {
            case .log: return "log"
            case .week: return "week"
            case .goals: return "goals"
            case .profile: return "profile"
            }
        }
    }

    public init(knowledgeRoot: URL) {
        self.knowledgeRoot = knowledgeRoot
        let s = DietStore(knowledgeRoot: knowledgeRoot)
        _store = State(initialValue: s)
        _dash = State(initialValue: s.dashboard())
        _suggest = State(initialValue: s.suggestedAction())
    }

    public var body: some View {
        ZStack(alignment: .top) {
            TossColor.grey100.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: TossSpace.x5) {
                    header.tossAppear()
                    planCard
                    suggestCard
                    todayHero
                    slotChips
                    quickNL
                    mealPresetRow
                    workoutPresetRow
                    ForEach(Array(dash.analysisLines.prefix(3).enumerated()), id: \.offset) { _, line in
                        insightCard(line)
                    }
                    todayList
                    secondaryActions
                    Spacer(minLength: TossSpace.x8)
                }
                .padding(.horizontal, TossSpace.x6)
                .padding(.top, TossSpace.x6)
                .animation(TossMotion.soft, value: dash.day.meals.count)
            }

            if let flash {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: flash.contains("실패") || flash.contains("확인")
                          ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(
                            flash.contains("실패") || flash.contains("확인")
                            ? TossColor.red500 : TossColor.blue500
                        )
                    Text(flash)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(TossColor.grey900)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button { self.flash = nil } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(TossColor.grey500)
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.1), radius: 10, y: 3)
                .padding(.horizontal, TossSpace.x6)
                .padding(.top, TossSpace.x4)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(20)
            }
        }
        .animation(TossMotion.soft, value: flash)
        .sheet(item: $sheet) { kind in
            switch kind {
            case .log: logSheet
            case .week: weekSheet
            case .goals: goalsSheet
            case .profile: profileSheet
            }
        }
        .onAppear { refresh() }
    }

    private func notify(_ text: String) {
        flash = text
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if flash == text { flash = nil }
        }
    }

    private func runStore(_ label: String, _ body: () throws -> Void) {
        do {
            try body()
            notify(label)
            refresh()
        } catch {
            notify("실패: \(error.localizedDescription)")
        }
    }

    private var planCard: some View {
        Group {
            if let plan = dash.plan {
                TossCard {
                    VStack(alignment: .leading, spacing: TossSpace.x3) {
                        HStack {
                            Text("목표 도달 예상")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(TossColor.grey500)
                            Spacer()
                            Button("내 정보") {
                                loadProfileForm()
                                sheet = .profile
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(TossColor.blue500)
                            .buttonStyle(.plain)
                        }
                        Text(plan.etaText)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(TossColor.grey900)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("기초대사 \(Int(plan.bmr)) · 유지 \(Int(plan.tdee))kcal · 권장 섭취 \(Int(plan.recommendedKcal))kcal · 단백질 \(Int(plan.recommendedProteinG))g")
                            .font(TossFont.caption())
                            .foregroundStyle(TossColor.grey500)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(plan.paceText)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(TossColor.blue500)
                        if let avg = plan.avgIntakeUsed {
                            Text("최근 기록 평균 섭취 약 \(Int(avg))kcal/일 기준으로 계산했어요.")
                                .font(.system(size: 11))
                                .foregroundStyle(TossColor.grey500)
                        } else {
                            Text("식사 기록이 쌓이면 실제 섭취 기준으로 더 정확해져요. 지금은 권장 칼로리 기준 예상이에요.")
                                .font(.system(size: 11))
                                .foregroundStyle(TossColor.grey500)
                        }
                    }
                }
            } else {
                Button {
                    loadProfileForm()
                    sheet = .profile
                } label: {
                    HStack(spacing: TossSpace.x3) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 28))
                            .foregroundStyle(TossColor.blue500)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("건강 정보 입력하기")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(TossColor.grey900)
                            Text("키·몸무게·나이·성별·목표 체중만 넣으면 칼로리·단백질·도달 시점을 알아서 잡아 줘요.")
                                .font(TossFont.caption())
                                .foregroundStyle(TossColor.grey500)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(TossColor.grey200)
                    }
                    .padding(TossSpace.x5)
                    .background(TossColor.white)
                    .clipShape(RoundedRectangle(cornerRadius: TossRadius.card, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Header / suggest

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: TossSpace.x2) {
                Text("식단")
                    .font(TossFont.title())
                    .foregroundStyle(TossColor.grey900)
                Text("가볍게, 매일")
                    .font(TossFont.body())
                    .foregroundStyle(TossColor.grey500)
            }
            Spacer()
            Button("내 정보") {
                loadProfileForm()
                sheet = .profile
            }
            .font(TossFont.body())
            .fontWeight(.semibold)
            .foregroundStyle(TossColor.blue500)
            .buttonStyle(.plain)
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

    private var suggestCard: some View {
        Button {
            if let slot = suggest.slot {
                selectedSlot = slot
                sheet = .log
            } else if suggest.title.contains("운동") {
                sheet = .log
            } else {
                sheet = .log
            }
        } label: {
            HStack(spacing: TossSpace.x4) {
                ZStack {
                    Circle().fill(TossColor.blue50).frame(width: 48, height: 48)
                    Image(systemName: suggest.slot != nil ? "fork.knife" : "figure.walk")
                        .foregroundStyle(TossColor.blue500)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(suggest.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(TossColor.grey900)
                    Text(suggest.subtitle)
                        .font(TossFont.caption())
                        .foregroundStyle(TossColor.grey500)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(TossColor.grey200)
            }
            .padding(TossSpace.x5)
            .background(TossColor.white)
            .clipShape(RoundedRectangle(cornerRadius: TossRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var todayHero: some View {
        TossCard {
            VStack(alignment: .leading, spacing: TossSpace.x4) {
                Text(dash.day.date)
                    .font(TossFont.caption())
                    .foregroundStyle(TossColor.grey500)
                HStack(spacing: TossSpace.x3) {
                    ring(
                        title: "칼로리",
                        hint: "오늘 먹은 열량",
                        value: Int(dash.day.kcal),
                        goal: Int(dash.goals.targetKcal),
                        unit: "kcal",
                        p: dash.kcalProgress,
                        color: TossColor.blue500
                    )
                    ring(
                        title: "단백질",
                        hint: "오늘 단백질",
                        value: Int(dash.day.proteinG),
                        goal: Int(dash.goals.targetProteinG),
                        unit: "g",
                        p: dash.proteinProgress,
                        color: TossColor.green500
                    )
                    ring(
                        title: "운동",
                        hint: "오늘 운동 시간",
                        value: dash.day.workoutMinutes,
                        goal: dash.goals.targetWorkoutMinutesPerDay,
                        unit: "분",
                        p: dash.workoutProgress,
                        color: Color(hex: 0xF59E0B)
                    )
                }
                Text("% = 오늘 기록 ÷ 목표. 목표는 우측 상단에서 바꿀 수 있어요.")
                    .font(.system(size: 11))
                    .foregroundStyle(TossColor.grey500)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("주간 운동 횟수 (목표 대비)")
                            .font(TossFont.caption())
                            .foregroundStyle(TossColor.grey700)
                        Spacer()
                        Text("\(dash.weekWorkoutCount)/\(dash.goals.weeklyWorkouts)회 · \(dash.weekWorkoutMinutes)분")
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

    private func ring(
        title: String,
        hint: String,
        value: Int,
        goal: Int,
        unit: String,
        p: Double,
        color: Color
    ) -> some View {
        let frac = min(1, max(0, p))
        return VStack(spacing: 6) {
            ZStack {
                Circle().stroke(TossColor.grey200, lineWidth: 7)
                Circle()
                    .trim(from: 0, to: CGFloat(frac))
                    .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(value)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(TossColor.grey900)
                    Text(unit)
                        .font(.system(size: 9))
                        .foregroundStyle(TossColor.grey500)
                }
            }
            .frame(width: 76, height: 76)
            .help(hint)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(TossColor.grey700)
            Text("목표 \(goal)\(unit)")
                .font(.system(size: 10))
                .foregroundStyle(TossColor.grey500)
                .multilineTextAlignment(.center)
            Text("\(Int(frac * 100))%")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("\(title) \(value)\(unit), 목표 \(goal)\(unit), \(Int(frac * 100))퍼센트")
    }

    private var slotChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TossSpace.x2) {
                ForEach(DietStore.MealSlot.allCases, id: \.rawValue) { slot in
                    let on = selectedSlot == slot
                    Button {
                        selectedSlot = slot
                        sheet = .log
                    } label: {
                        Text(slot.rawValue)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(on ? TossColor.onPrimary : TossColor.grey900)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(on ? TossColor.blue500 : TossColor.white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var quickNL: some View {
        TossCard {
            VStack(alignment: .leading, spacing: TossSpace.x3) {
                Text("한 줄로 남기기")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(TossColor.grey500)
                HStack(spacing: TossSpace.x3) {
                    TextField(placeholderNL, text: $quickLine)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(TossColor.grey100)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .onSubmit { commitQuickLine() }
                    Button("추가") { commitQuickLine() }
                        .font(TossFont.body())
                        .fontWeight(.semibold)
                        .foregroundStyle(quickLine.trimmingCharacters(in: .whitespaces).isEmpty ? TossColor.grey200 : TossColor.blue500)
                        .buttonStyle(.plain)
                        .disabled(quickLine.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var placeholderNL: String {
        if let s = selectedSlot { return "예: \(s.rawValue) 샐러드 350kcal" }
        return "예: 운동 걷기 30분"
    }

    private var mealPresetRow: some View {
        VStack(alignment: .leading, spacing: TossSpace.x2) {
            Text("빠른 식사 (기본 분량·대략 kcal)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(TossColor.grey500)
            Text("그램은 대략값이에요. 나중에 한 줄로 수정해도 됩니다.")
                .font(.system(size: 11))
                .foregroundStyle(TossColor.grey500)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: TossSpace.x2) {
                    ForEach(mealPresets) { p in
                        Button {
                            quickAddMeal(p)
                        } label: {
                            VStack(spacing: 2) {
                                Text(p.chipTitle)
                                    .font(.system(size: 13, weight: .semibold))
                                Text("~\(Int(p.kcal))kcal · P\(Int(p.proteinG))g")
                                    .font(.system(size: 10))
                                    .opacity(0.85)
                            }
                            .foregroundStyle(TossColor.blue500)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(TossColor.blue50)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help("\(p.name) 기본 \(p.grams)\(p.unit), 약 \(Int(p.kcal))kcal, 단백질 \(Int(p.proteinG))g")
                    }
                }
            }
        }
    }

    private var workoutPresetRow: some View {
        VStack(alignment: .leading, spacing: TossSpace.x2) {
            Text("빠른 운동 (기본 시간)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(TossColor.grey500)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: TossSpace.x2) {
                    ForEach(workoutPresets) { item in
                        Button {
                            runStore("\(item.chipTitle) 저장됐어요") {
                                _ = try store.logWorkout(kind: item.name, minutes: item.minutes, intensity: nil)
                            }
                        } label: {
                            Text(item.chipTitle)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(TossColor.grey900)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(TossColor.white)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func insightCard(_ line: String) -> some View {
        HStack(alignment: .top, spacing: TossSpace.x3) {
            Image(systemName: "lightbulb.fill").foregroundStyle(TossColor.blue500)
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

    private var todayList: some View {
        VStack(alignment: .leading, spacing: TossSpace.x3) {
            Text("오늘 기록")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(TossColor.grey500)
            TossCard(padded: false) {
                if dash.day.meals.isEmpty && dash.day.workouts.isEmpty {
                    TossEmptyState(
                        systemImage: "fork.knife",
                        title: "아직 없어요",
                        message: "끼니 칩이나 한 줄 입력으로 시작해 보세요.",
                        actionTitle: "기록하기"
                    ) { sheet = .log }
                } else {
                    VStack(spacing: 0) {
                        ForEach(dash.day.meals) { m in
                            row(
                                icon: "fork.knife",
                                title: m.items.joined(separator: ", "),
                                sub: [m.kcal.map { "\(Int($0)) kcal" }, m.proteinG.map { "P\(Int($0))g" }]
                                    .compactMap { $0 }.joined(separator: " · ")
                            ) {
                                do {
                                    let ok = try store.deleteMeal(id: m.id)
                                    notify(ok ? "식사 삭제됐어요" : "이미 없는 기록이에요")
                                    refresh()
                                } catch {
                                    notify("삭제 실패: \(error.localizedDescription)")
                                }
                            }
                        }
                        ForEach(dash.day.workouts) { w in
                            row(icon: "figure.walk", title: w.kind, sub: "\(w.minutes)분") {
                                do {
                                    let ok = try store.deleteWorkout(id: w.id)
                                    notify(ok ? "운동 삭제됐어요" : "이미 없는 기록이에요")
                                    refresh()
                                } catch {
                                    notify("삭제 실패: \(error.localizedDescription)")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func row(icon: String, title: String, sub: String, onDelete: @escaping () -> Void) -> some View {
        HStack(spacing: TossSpace.x3) {
            Image(systemName: icon).foregroundStyle(TossColor.blue500).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(TossFont.body()).fontWeight(.medium).foregroundStyle(TossColor.grey900)
                if !sub.isEmpty {
                    Text(sub).font(TossFont.caption()).foregroundStyle(TossColor.grey500)
                }
            }
            Spacer()
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundStyle(TossColor.grey500)
            }
            .buttonStyle(.plain)
            .help("삭제")
        }
        .padding(.horizontal, TossSpace.x5)
        .padding(.vertical, TossSpace.x3)
    }

    private var secondaryActions: some View {
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
                notify("새로고침했어요")
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

    // MARK: Sheets

    private var logSheet: some View {
        NavigationStack {
            Form {
                Section("끼니") {
                    Picker("구분", selection: Binding(
                        get: { selectedSlot ?? .lunch },
                        set: { selectedSlot = $0 }
                    )) {
                        ForEach(DietStore.MealSlot.allCases, id: \.rawValue) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                    TextField("음식", text: $mealItems)
                    TextField("kcal", text: $mealKcal)
                    TextField("단백질 g", text: $mealProtein)
                    Button("식사 저장") {
                        saveMeal()
                        sheet = nil
                    }
                    .disabled(mealItems.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Section("운동") {
                    TextField("종류", text: $workoutKind)
                    TextField("분", text: $workoutMinutes)
                    Button("운동 저장") {
                        saveWorkout()
                        sheet = nil
                    }
                }
                Section("체중 · 수면") {
                    TextField("체중 kg", text: $weightKg)
                    TextField("수면 h", text: $sleepH)
                    Button("지표 저장") {
                        saveMetric()
                        sheet = nil
                    }
                    .disabled(weightKg.isEmpty && sleepH.isEmpty)
                }
            }
            .navigationTitle("기록")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { sheet = nil }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 480)
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
                Section {
                    Text("다이어트 초보라면 「내 정보」에서 키·몸무게만 넣으면 여기 숫자가 자동으로 채워져요. 직접 고쳐도 됩니다.\n\n링의 % = 오늘 기록 ÷ 이 목표")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("내 정보로 자동 계산") {
                        loadProfileForm()
                        sheet = .profile
                    }
                }
                Section {
                    TextField("숫자", text: $goalKcal)
                    Text("하루 목표 칼로리 (kcal) — 오늘 먹을 열량 목표")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("칼로리")
                }
                Section {
                    TextField("숫자", text: $goalProtein)
                    Text("하루 목표 단백질 (g)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("단백질")
                }
                Section {
                    TextField("횟수", text: $goalWeeklyWO)
                    Text("일주일에 운동할 횟수 목표 (주간 바)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("주간 운동 횟수")
                }
                Section {
                    TextField("분", text: $goalDayMin)
                    Text("하루 운동 시간(분) 목표")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("하루 운동 시간")
                }
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
        .frame(minWidth: 380, minHeight: 520)
    }

    private var profileSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Text("키·몸무게·나이·성별·목표 체중을 넣으면 목표 칼로리·단백질을 자동으로 잡고, 지금 먹는 페이스로 언제쯤 목표에 닿을지 알려 줘요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("기본") {
                    TextField("키 (cm)", text: $pHeight)
                    TextField("지금 몸무게 (kg)", text: $pWeight)
                    TextField("나이", text: $pAge)
                    Picker("성별", selection: $pSex) {
                        Text("여성").tag(DietProfile.Sex.female)
                        Text("남성").tag(DietProfile.Sex.male)
                    }
                    .pickerStyle(.segmented)
                }
                Section("목표") {
                    TextField("목표 몸무게 (kg)", text: $pTarget)
                    Picker("평소 활동", selection: $pActivity) {
                        ForEach(DietProfile.Activity.allCases, id: \.rawValue) { a in
                            Text(a.labelKO).tag(a)
                        }
                    }
                }
                if let h = Double(pHeight), let w = Double(pWeight), let t = Double(pTarget),
                   let age = Int(pAge), h > 100, w > 30 {
                    let preview = DietProfile(
                        heightCm: h, weightKg: w, age: age, sex: pSex,
                        targetWeightKg: t, activity: pActivity
                    )
                    Section("자동 계산 미리보기") {
                        Text("유지 칼로리 약 \(Int(preview.tdee))kcal")
                        Text("권장 섭취 \(Int(preview.recommendedKcal))kcal / 단백질 \(Int(preview.recommendedProteinG))g")
                        Text(preview.planSummary(avgDailyIntakeKcal: nil, plannedKcal: preview.recommendedKcal).etaText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Button("저장하고 목표 자동 적용") {
                    saveProfile(applyGoals: true)
                    sheet = nil
                }
            }
            .navigationTitle("내 정보")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { sheet = nil }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 560)
    }

    private func loadProfileForm() {
        if let p = store.profile() {
            pHeight = "\(Int(p.heightCm))"
            pWeight = String(format: "%.1f", p.weightKg)
            pAge = "\(p.age)"
            pSex = p.sex
            pTarget = String(format: "%.1f", p.targetWeightKg)
            pActivity = p.activity
        }
    }

    private func saveProfile(applyGoals: Bool) {
        guard let h = Double(pHeight), let w = Double(pWeight),
              let age = Int(pAge), let t = Double(pTarget) else {
            notify("숫자를 확인해 주세요")
            return
        }
        let p = DietProfile(
            heightCm: h, weightKg: w, age: age, sex: pSex,
            targetWeightKg: t, activity: pActivity
        )
        do {
            try store.setProfile(p)
            if applyGoals { try store.applyRecommendedGoalsFromProfile() }
            let g = store.goals()
            notify("저장됐어요 · 목표 \(Int(g.targetKcal))kcal · 단백질 \(Int(g.targetProteinG))g")
            refresh()
            sheet = nil
        } catch {
            notify("저장 실패: \(error.localizedDescription)")
        }
    }

    // MARK: Actions

    private func refresh() {
        store.reload()
        dash = store.dashboard()
        suggest = store.suggestedAction()
        if let s = suggest.slot { selectedSlot = s }
    }

    private func quickAddMeal(_ p: DietMealPreset) {
        runStore("\(p.chipTitle) · ~\(Int(p.kcal))kcal 저장됐어요") {
            _ = try store.logMealWithSlot(
                slot: selectedSlot ?? .lunch,
                items: [p.logItem],
                kcal: p.kcal,
                proteinG: p.proteinG,
                note: "기본 \(p.grams)\(p.unit)"
            )
        }
    }

    private func commitQuickLine() {
        let line = quickLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        let lower = line.lowercased()
        if line.contains("운동") || lower.contains("workout") {
            let minutes = Int(line.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) ?? 20
            var kind = line.replacingOccurrences(of: "운동", with: "")
            if let re = try? NSRegularExpression(pattern: "\\d+\\s*분") {
                kind = re.stringByReplacingMatches(in: kind, range: NSRange(kind.startIndex..., in: kind), withTemplate: "")
            }
            kind = kind.trimmingCharacters(in: .whitespacesAndNewlines)
            runStore("운동 \(minutes)분 저장됐어요") {
                _ = try store.logWorkout(
                    kind: kind.isEmpty ? "workout" : kind,
                    minutes: minutes,
                    intensity: nil
                )
            }
        } else {
            let kcal: Double? = {
                if let r = try? NSRegularExpression(pattern: "(\\d+(?:\\.\\d+)?)"),
                   let m = r.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                   let rr = Range(m.range(at: 1), in: line) {
                    return Double(line[rr])
                }
                return nil
            }()
            runStore("식사 저장됐어요") {
                _ = try store.logMealWithSlot(
                    slot: selectedSlot,
                    items: [line],
                    kcal: kcal,
                    proteinG: nil,
                    note: line
                )
            }
        }
        quickLine = ""
    }

    private func saveMeal() {
        let items = mealItems.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !items.isEmpty else {
            notify("음식 이름을 입력해 주세요")
            return
        }
        runStore("식사 저장됐어요") {
            _ = try store.logMealWithSlot(
                slot: selectedSlot,
                items: items,
                kcal: Double(mealKcal),
                proteinG: Double(mealProtein),
                note: nil
            )
            mealItems = ""; mealKcal = ""; mealProtein = ""
            sheet = nil
        }
    }

    private func saveWorkout() {
        runStore("운동 저장됐어요") {
            _ = try store.logWorkout(kind: workoutKind, minutes: Int(workoutMinutes) ?? 0, intensity: nil)
            sheet = nil
        }
    }

    private func saveMetric() {
        guard Double(weightKg) != nil || Double(sleepH) != nil else {
            notify("체중 또는 수면을 입력해 주세요")
            return
        }
        runStore("지표 저장됐어요") {
            _ = try store.logMetric(weightKg: Double(weightKg), sleepH: Double(sleepH))
            weightKg = ""; sleepH = ""
            sheet = nil
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
        guard let kcal = Double(goalKcal), let protein = Double(goalProtein),
              kcal > 500, protein > 0 else {
            notify("칼로리·단백질 숫자를 확인해 주세요")
            return
        }
        g.targetKcal = kcal
        g.targetProteinG = protein
        if let v = Int(goalWeeklyWO) { g.weeklyWorkouts = v }
        if let v = Int(goalDayMin) { g.targetWorkoutMinutesPerDay = v }
        runStore("목표 저장됐어요 · \(Int(kcal))kcal · 단백질 \(Int(protein))g") {
            try store.setGoals(g)
            sheet = nil
        }
    }
}
