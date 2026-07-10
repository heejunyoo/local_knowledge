import SwiftUI

/// Diet hub — suggest, slots, chips, rings, NL, delete. Aligned with Mac DietView.
struct DietMobileView: View {
    @EnvironmentObject var core: CoreClient

    @State private var dashboard: [String: Any] = [:]
    @State private var suggestTitle = "오늘 기록을 남겨 보세요"
    @State private var suggestSub = "한 줄이면 충분해요"
    @State private var suggestSlot: String?
    @State private var selectedSlot = "점심"
    @State private var err: String?
    @State private var flash: String?
    @State private var showLog = false
    @State private var showWeek = false
    @State private var showGoals = false
    @State private var showProfile = false
    @State private var quickLine = ""
    @State private var mealItems = ""
    @State private var mealKcal = ""
    @State private var mealProtein = ""
    @State private var workoutKind = "걷기"
    @State private var workoutMin = "30"
    @State private var weightKg = ""
    @State private var sleepH = ""
    @State private var goalKcal = "2000"
    @State private var goalProtein = "100"
    @State private var goalWeekly = "4"
    @State private var goalDayMin = "30"
    @State private var pHeight = "165"
    @State private var pWeight = "65"
    @State private var pAge = "30"
    @State private var pSex = "female"
    @State private var pTarget = "60"
    @State private var pActivity = "light"
    @State private var planEta: String?
    @State private var planDetail: String?
    @State private var needsProfile = true

    private let slots = ["아침", "점심", "저녁", "간식"]
    /// name, grams, unit, kcal, protein — default serving (approx)
    private let mealPresets: [(String, Int, String, Double, Double)] = [
        ("밥·반찬", 300, "g", 520, 18),
        ("샐러드", 200, "g", 120, 5),
        ("닭가슴살", 100, "g", 110, 23),
        ("계란", 50, "g", 70, 6),
        ("단백질 쉐이크", 30, "g", 120, 24),
        ("커피", 200, "ml", 5, 0),
        ("과일", 150, "g", 80, 1),
    ]
    private let workoutPresets: [(String, Int)] = [
        ("걷기", 20), ("계단오르기", 10), ("러닝", 30), ("헬스", 45), ("스트레칭", 10),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                KPageBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: KSpace.x5) {
                        header
                        planCard
                        suggestCard
                        todayHero
                        slotChips
                        quickNL
                        mealPresetRow
                        chipRowWorkouts
                        if let tip = analysisFirst { insight(tip) }
                        todayList
                        HStack(spacing: KSpace.x3) {
                            secondaryBtn("주간") { showWeek = true }
                            secondaryBtn("목표") { loadGoals(); showGoals = true }
                        }
                        if let flash {
                            Text(flash).font(.caption).fontWeight(.semibold).foregroundStyle(KColor.blue500)
                        }
                        if let err {
                            Text(err).font(.caption).foregroundStyle(KColor.red500)
                        }
                    }
                    .padding(.horizontal, KSpace.x6)
                    .padding(.vertical, KSpace.x4)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await reload() }
            .task { await reload() }
            .sheet(isPresented: $showLog) { logSheet }
            .sheet(isPresented: $showWeek) { weekSheet }
            .sheet(isPresented: $showGoals) { goalsSheet }
            .sheet(isPresented: $showProfile) { profileSheet }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("완료") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("식단")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(KColor.grey900)
                Text("가볍게, 매일")
                    .font(.system(size: 15))
                    .foregroundStyle(KColor.grey500)
            }
            Spacer()
            Button("내 정보") { showProfile = true }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(KColor.blue500)
        }
    }

    private var planCard: some View {
        Group {
            if needsProfile {
                Button { showProfile = true } label: {
                    HStack(spacing: KSpace.x3) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 28))
                            .foregroundStyle(KColor.blue500)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("건강 정보 입력")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(KColor.grey900)
                            Text("키·몸무게·나이·성별·목표 체중만 넣으면 칼로리·단백질·도달 시점을 알아서 잡아요.")
                                .font(.caption)
                                .foregroundStyle(KColor.grey500)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(KColor.grey200)
                    }
                    .padding(KSpace.x4)
                    .background(KColor.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            } else if let planEta {
                KCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("목표 도달 예상")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(KColor.grey500)
                        Text(planEta)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(KColor.grey900)
                        if let planDetail {
                            Text(planDetail)
                                .font(.caption)
                                .foregroundStyle(KColor.grey500)
                        }
                        Button("정보 수정") { showProfile = true }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(KColor.blue500)
                    }
                }
            }
        }
    }

    private var suggestCard: some View {
        Button {
            if let s = suggestSlot { selectedSlot = s }
            showLog = true
        } label: {
            HStack(spacing: KSpace.x3) {
                ZStack {
                    Circle().fill(KColor.blue50).frame(width: 44, height: 44)
                    Image(systemName: suggestSlot != nil ? "fork.knife" : "figure.walk")
                        .foregroundStyle(KColor.blue500)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(KColor.grey900)
                    Text(suggestSub)
                        .font(.system(size: 13))
                        .foregroundStyle(KColor.grey500)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(KColor.grey200)
            }
            .padding(KSpace.x4)
            .background(KColor.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var todayHero: some View {
        let prog = dashboard["progress"] as? [String: Any] ?? [:]
        let goals = dashboard["goals"] as? [String: Any] ?? [:]
        let day = dashboard["day"] as? [String: Any] ?? [:]
        let totals = day["totals"] as? [String: Any] ?? [:]
        let week = dashboard["week"] as? [String: Any] ?? [:]

        return KCard {
            VStack(alignment: .leading, spacing: KSpace.x4) {
                Text((day["date"] as? String) ?? "")
                    .font(.caption)
                    .foregroundStyle(KColor.grey500)
                HStack {
                    ring("칼로리", "오늘 열량", "kcal", intVal(totals["kcal"]), intVal(goals["target_kcal"]), doubleVal(prog["kcal"]), KColor.blue500)
                    ring("단백질", "오늘 단백질", "g", intVal(totals["protein_g"]), intVal(goals["target_protein_g"]), doubleVal(prog["protein"]), KColor.green500)
                    ring("운동", "오늘 운동", "분", intVal(totals["workout_minutes"]), intVal(goals["target_workout_minutes_per_day"]), doubleVal(prog["workout"]), Color.orange)
                }
                Text("% = 오늘 기록 ÷ 목표 (목표는 아래 「목표」)")
                    .font(.system(size: 11))
                    .foregroundStyle(KColor.grey500)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("주간 운동 횟수 (목표 대비)").font(.caption).foregroundStyle(KColor.grey700)
                        Spacer()
                        Text("\(intVal(week["workout_count"]))/\(intVal(goals["weekly_workouts"]))회")
                            .font(.caption).foregroundStyle(KColor.grey500)
                    }
                    ProgressView(value: min(1, max(0, doubleVal(prog["weekly_workouts"]))))
                        .tint(KColor.blue500)
                }
            }
        }
    }

    private func ring(_ title: String, _ hint: String, _ unit: String, _ value: Int, _ goal: Int, _ p: Double, _ color: Color) -> some View {
        let frac = min(1, max(0, p))
        return VStack(spacing: 4) {
            ZStack {
                Circle().stroke(KColor.grey200, lineWidth: 6)
                Circle()
                    .trim(from: 0, to: CGFloat(frac))
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(value)").font(.system(size: 13, weight: .bold)).foregroundStyle(KColor.grey900)
                    Text(unit).font(.system(size: 9)).foregroundStyle(KColor.grey500)
                }
            }
            .frame(width: 70, height: 70)
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(KColor.grey700)
            Text("목표 \(goal)\(unit)").font(.system(size: 9)).foregroundStyle(KColor.grey500).multilineTextAlignment(.center)
            Text("\(Int(frac * 100))%").font(.system(size: 11, weight: .semibold)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("\(hint) \(value)\(unit), 목표 \(goal)\(unit)")
    }

    private var slotChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(slots, id: \.self) { s in
                    let on = selectedSlot == s
                    Button {
                        selectedSlot = s
                        showLog = true
                    } label: {
                        Text(s)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(on ? KColor.onPrimary : KColor.grey900)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(on ? KColor.blue500 : KColor.white)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private var quickNL: some View {
        KCard {
            VStack(alignment: .leading, spacing: KSpace.x3) {
                Text("한 줄로 남기기")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(KColor.grey500)
                HStack {
                    TextField("예: \(selectedSlot) 샐러드 400kcal", text: $quickLine)
                        .textInputAutocapitalization(.never)
                        .padding(12)
                        .background(KColor.grey100)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .onSubmit { Task { await commitQuick() } }
                    Button("추가") { Task { await commitQuick() } }
                        .fontWeight(.semibold)
                        .foregroundStyle(KColor.blue500)
                        .disabled(quickLine.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var mealPresetRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("빠른 식사 (기본 분량 · 대략 kcal)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(KColor.grey500)
            Text("그램은 대략값이에요. 정확히 몰라도 탭만 하면 됩니다.")
                .font(.system(size: 11))
                .foregroundStyle(KColor.grey500)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(mealPresets.enumerated()), id: \.offset) { _, p in
                        let (name, grams, unit, kcal, protein) = p
                        Button {
                            Task { await quickMeal(name: name, grams: grams, unit: unit, kcal: kcal, protein: protein) }
                        } label: {
                            VStack(spacing: 2) {
                                Text("\(name) \(grams)\(unit)")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("~\(Int(kcal))kcal · P\(Int(protein))g")
                                    .font(.system(size: 10))
                                    .opacity(0.9)
                            }
                            .foregroundStyle(KColor.blue500)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(KColor.blue50)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }
        }
    }

    private var chipRowWorkouts: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("빠른 운동 (기본 시간)").font(.system(size: 13, weight: .semibold)).foregroundStyle(KColor.grey500)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(workoutPresets, id: \.0) { item in
                        Button("\(item.0) \(item.1)분") {
                            Task {
                                try? await core.dietLogWorkout(kind: item.0, minutes: item.1, intensity: nil)
                                kHapticSuccess()
                                flash = "\(item.0) \(item.1)분 저장"
                                await reload()
                            }
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(KColor.grey900)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(KColor.white)
                        .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private var analysisFirst: String? {
        (dashboard["analysis"] as? [String])?.first
    }

    private func insight(_ t: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb.fill").foregroundStyle(KColor.blue500)
            Text(t).font(.system(size: 15)).foregroundStyle(KColor.grey900)
        }
        .padding(KSpace.x4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KColor.blue50)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func secondaryBtn(_ t: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Text(t)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(KColor.grey900)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(KColor.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var todayList: some View {
        let day = dashboard["day"] as? [String: Any] ?? [:]
        let meals = day["meals"] as? [[String: Any]] ?? []
        let workouts = day["workouts"] as? [[String: Any]] ?? []
        return VStack(alignment: .leading, spacing: KSpace.x3) {
            Text("오늘 기록")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(KColor.grey500)
            KCard {
                if meals.isEmpty && workouts.isEmpty {
                    KEmptyState(
                        systemImage: "fork.knife",
                        title: "아직 없어요",
                        message: "끼니 칩이나 한 줄로 시작해 보세요.",
                        actionTitle: "기록하기"
                    ) { showLog = true }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(meals.enumerated()), id: \.offset) { _, m in
                            let id = m["id"] as? String ?? ""
                            let items = (m["items"] as? [String])?.joined(separator: ", ") ?? "식사"
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(items).font(.system(size: 15, weight: .medium)).foregroundStyle(KColor.grey900)
                                    if let k = m["kcal"] as? Double {
                                        Text("\(Int(k)) kcal").font(.caption).foregroundStyle(KColor.grey500)
                                    }
                                }
                                Spacer()
                                if !id.isEmpty {
                                    Button {
                                        Task {
                                            try? await core.dietDeleteMeal(id: id)
                                            flash = "삭제"
                                            await reload()
                                        }
                                    } label: {
                                        Image(systemName: "trash").font(.caption).foregroundStyle(KColor.grey500)
                                    }
                                }
                            }
                        }
                        ForEach(Array(workouts.enumerated()), id: \.offset) { _, w in
                            let id = w["id"] as? String ?? ""
                            HStack {
                                Text("\((w["kind"] as? String) ?? "운동") · \(w["minutes"] as? Int ?? 0)분")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(KColor.grey900)
                                Spacer()
                                if !id.isEmpty {
                                    Button {
                                        Task {
                                            try? await core.dietDeleteWorkout(id: id)
                                            flash = "삭제"
                                            await reload()
                                        }
                                    } label: {
                                        Image(systemName: "trash").font(.caption).foregroundStyle(KColor.grey500)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var logSheet: some View {
        NavigationStack {
            Form {
                Section("식사") {
                    Picker("끼니", selection: $selectedSlot) {
                        ForEach(slots, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    TextField("음식", text: $mealItems)
                    TextField("kcal", text: $mealKcal).keyboardType(.decimalPad)
                    TextField("단백질 g", text: $mealProtein).keyboardType(.decimalPad)
                    Button("식사 저장") { Task { await saveMeal() } }
                }
                Section("운동") {
                    TextField("종류", text: $workoutKind)
                    TextField("분", text: $workoutMin).keyboardType(.numberPad)
                    Button("운동 저장") { Task { await saveWorkout() } }
                }
                Section("체중 · 수면") {
                    TextField("kg", text: $weightKg).keyboardType(.decimalPad)
                    TextField("수면 h", text: $sleepH).keyboardType(.decimalPad)
                    Button("지표 저장") { Task { await saveMetric() } }
                }
            }
            .navigationTitle("기록")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { showLog = false } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("완료") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var weekSheet: some View {
        NavigationStack {
            List {
                let week = dashboard["week"] as? [String: Any] ?? [:]
                let bars = week["bars"] as? [[String: Any]] ?? []
                if !bars.isEmpty {
                    Section("7일 칼로리") {
                        HStack(alignment: .bottom, spacing: 6) {
                            let maxK = max(bars.map { doubleVal($0["kcal"]) }.max() ?? 1, 1)
                            ForEach(Array(bars.enumerated()), id: \.offset) { _, b in
                                let k = doubleVal(b["kcal"])
                                VStack(spacing: 4) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(KColor.blue500.opacity(k > 0 ? 1 : 0.25))
                                        .frame(height: max(6, CGFloat(k / maxK) * 80))
                                    Text((b["label"] as? String) ?? "").font(.system(size: 10))
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(height: 100)
                    }
                }
                Section("분석") {
                    ForEach(Array((dashboard["analysis"] as? [String] ?? []).enumerated()), id: \.offset) { _, line in
                        Text(line).font(.subheadline)
                    }
                }
            }
            .navigationTitle("주간")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { showWeek = false } } }
        }
        .presentationDetents([.medium, .large])
    }

    private var goalsSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Text("초보라면 「내 정보」에서 키·몸무게만 넣으면 여기가 자동으로 채워져요.\n% = 오늘 기록 ÷ 목표")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("내 정보로 자동 계산") { showGoals = false; showProfile = true }
                }
                Section {
                    TextField("숫자", text: $goalKcal).keyboardType(.numberPad)
                    Text("하루 목표 칼로리 (kcal)")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Text("칼로리") }
                Section {
                    TextField("숫자", text: $goalProtein).keyboardType(.numberPad)
                    Text("하루 목표 단백질 (g)")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Text("단백질") }
                Section {
                    TextField("횟수", text: $goalWeekly).keyboardType(.numberPad)
                } header: { Text("주간 운동 횟수") }
                Section {
                    TextField("분", text: $goalDayMin).keyboardType(.numberPad)
                } header: { Text("하루 운동 시간") }
                Button("저장") { Task { await saveGoals() } }
            }
            .navigationTitle("목표")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { showGoals = false } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("완료") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var profileSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Text("다이어트 막 시작할 때 쓰는 최소 정보예요. 저장하면 목표 칼로리·단백질을 자동으로 넣고, 도달 시점도 계산해요.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("기본") {
                    TextField("키 (cm)", text: $pHeight).keyboardType(.decimalPad)
                    TextField("지금 몸무게 (kg)", text: $pWeight).keyboardType(.decimalPad)
                    TextField("나이", text: $pAge).keyboardType(.numberPad)
                    Picker("성별", selection: $pSex) {
                        Text("여성").tag("female")
                        Text("남성").tag("male")
                    }
                    .pickerStyle(.segmented)
                }
                Section("목표") {
                    TextField("목표 몸무게 (kg)", text: $pTarget).keyboardType(.decimalPad)
                    Picker("평소 활동", selection: $pActivity) {
                        Text("거의 안 함").tag("sedentary")
                        Text("조금 (주 1–3)").tag("light")
                        Text("보통 (주 3–5)").tag("moderate")
                        Text("많이 (주 6–7)").tag("active")
                    }
                }
                Button("저장하고 목표 자동 적용") {
                    Task { await saveProfile() }
                }
            }
            .navigationTitle("내 정보")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { showProfile = false } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("완료") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func reload() async {
        err = nil
        do {
            dashboard = try await core.dietDashboard()
            needsProfile = (dashboard["needs_profile"] as? Bool) ?? (dashboard["profile"] == nil)
            if let plan = dashboard["plan"] as? [String: Any] {
                planEta = plan["eta_text"] as? String
                let tdee = plan["tdee"] as? Double
                let rec = plan["recommended_kcal"] as? Double
                let prot = plan["recommended_protein_g"] as? Double
                if let tdee, let rec, let prot {
                    planDetail = "유지 \(Int(tdee))kcal · 권장 \(Int(rec))kcal · 단백질 \(Int(prot))g · \(plan["pace_text"] as? String ?? "")"
                } else {
                    planDetail = plan["pace_text"] as? String
                }
            } else {
                planEta = nil
                planDetail = nil
            }
            if let s = try? await core.dietSuggest() {
                suggestTitle = s.title
                suggestSub = s.subtitle
                suggestSlot = s.slot
                if let slot = s.slot { selectedSlot = slot }
            }
            await core.refreshDietLine()
        } catch {
            err = error.localizedDescription
        }
    }

    private func saveProfile() async {
        guard let h = Double(pHeight), let w = Double(pWeight),
              let age = Int(pAge), let t = Double(pTarget) else {
            err = "숫자를 확인해 주세요"
            return
        }
        do {
            _ = try await core.dietSetProfile(
                heightCm: h, weightKg: w, age: age, sex: pSex,
                targetWeightKg: t, activity: pActivity, applyGoals: true
            )
            kHapticSuccess()
            flash = "프로필 저장 · 목표 적용"
            showProfile = false
            await reload()
        } catch {
            err = error.localizedDescription
        }
    }

    private func quickMeal(name: String, grams: Int, unit: String, kcal: Double, protein: Double) async {
        do {
            let item = "\(selectedSlot) \(name) \(grams)\(unit)"
            try await core.dietLogMeal(
                items: [item],
                kcal: kcal,
                proteinG: protein,
                note: "기본 \(grams)\(unit)"
            )
            kHapticSuccess()
            flash = "\(name) \(grams)\(unit) · ~\(Int(kcal))kcal"
            await reload()
        } catch { err = error.localizedDescription }
    }

    private func commitQuick() async {
        let line = quickLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        do {
            if line.contains("운동") || line.lowercased().contains("workout") {
                let minutes = Int(line.filter(\.isNumber)) ?? 20
                try await core.dietLogWorkout(kind: line, minutes: minutes, intensity: nil)
            } else {
                let digits = line.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
                let kcal = digits.first.flatMap { Double($0) }
                let text = line.contains(selectedSlot) ? line : "\(selectedSlot) \(line)"
                try await core.dietLogMeal(items: [text], kcal: kcal, proteinG: nil, note: line)
            }
            quickLine = ""
            kHapticSuccess()
            flash = "저장"
            await reload()
        } catch { err = error.localizedDescription }
    }

    private func saveMeal() async {
        let items = mealItems.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !items.isEmpty else { return }
        let labeled = items.map { $0.contains(selectedSlot) ? $0 : "\(selectedSlot) \($0)" }
        do {
            try await core.dietLogMeal(items: labeled, kcal: Double(mealKcal), proteinG: Double(mealProtein), note: nil)
            mealItems = ""; mealKcal = ""; mealProtein = ""
            flash = "식사 저장"
            showLog = false
            kHapticSuccess()
            await reload()
        } catch { err = error.localizedDescription }
    }

    private func saveWorkout() async {
        do {
            try await core.dietLogWorkout(kind: workoutKind, minutes: Int(workoutMin) ?? 0, intensity: nil)
            flash = "운동 저장"
            showLog = false
            kHapticSuccess()
            await reload()
        } catch { err = error.localizedDescription }
    }

    private func saveMetric() async {
        do {
            try await core.dietLogMetric(weightKg: Double(weightKg), sleepH: Double(sleepH))
            weightKg = ""; sleepH = ""
            flash = "지표 저장"
            showLog = false
            await reload()
        } catch { err = error.localizedDescription }
    }

    private func loadGoals() {
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
        } catch { err = error.localizedDescription }
    }

    private func intVal(_ any: Any?) -> Int {
        if let i = any as? Int { return i }
        if let d = any as? Double { return Int(d) }
        return 0
    }

    private func doubleVal(_ any: Any?) -> Double {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        return 0
    }
}
