import SwiftUI

/// Diet hub — suggest, slots, chips, rings, NL, delete. Aligned with Mac DietView.
struct DietMobileView: View {
    @EnvironmentObject var core: CoreClient
    @EnvironmentObject var feedback: ActionFeedback

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
    @State private var mealAmount = ""
    @State private var mealUnit: DietNutritionCalc.Unit = .g
    @State private var mealAutoNote = ""
    @State private var mealKcalManual = false
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
    @State private var profileBusy = false
    @State private var profileMessage: String?
    @State private var profileError: String?
    @State private var goalsBusy = false
    @State private var goalsMessage: String?
    @State private var goalsError: String?
    @State private var pendingDelete: PendingDelete?
    @State private var deleteBusyId: String?
    @State private var fastingBusy = false
    @State private var morningWeightOnly = true
    @State private var fastingHours: Double = 14

    private struct PendingDelete: Identifiable {
        var id: String
        var kind: Kind
        var title: String
        enum Kind { case meal, workout }
    }

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
            ZStack(alignment: .top) {
                KPageBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: KSpace.x5) {
                        header
                        planCard
                        fastingCard
                        morningWeightCard
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
                        if let err {
                            Text(err).font(.caption).foregroundStyle(KColor.red500)
                        }
                    }
                    .padding(.horizontal, KSpace.x6)
                    .padding(.vertical, KSpace.x4)
                }
                .scrollDismissesKeyboard(.interactively)

                // Always-visible toast (was buried at bottom of scroll before)
                if let flash {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(KColor.green500)
                            .font(.system(size: 20))
                        Text(flash)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(KColor.grey900)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button {
                            self.flash = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(KColor.grey500)
                        }
                    }
                    .padding(14)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                    .padding(.horizontal, KSpace.x6)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: flash)
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await reload() }
            .task { await reload() }
            .sheet(isPresented: $showLog) { logSheet }
            .sheet(isPresented: $showWeek) { weekSheet }
            .sheet(isPresented: $showGoals) { goalsSheet }
            .sheet(isPresented: $showProfile) {
                profileSheet
                    .onAppear { loadProfileFields() }
            }
            .confirmationDialog(
                pendingDelete.map { "「\($0.title)」을(를) 삭제할까요?" } ?? "삭제",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("삭제", role: .destructive) {
                    if let p = pendingDelete {
                        Task { await performDelete(p) }
                    }
                }
                Button("취소", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("삭제하면 오늘 합계에서 바로 빠져요.")
            }
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
            Button("내 정보") {
                loadProfileFields()
                profileMessage = nil
                profileError = nil
                showProfile = true
            }
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
                        Text("규칙 계산 (Mifflin + 적자) · AI API 미사용")
                            .font(.system(size: 11))
                            .foregroundStyle(KColor.grey500)
                        Button("정보 수정") { showProfile = true }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(KColor.blue500)
                    }
                }
            }
        }
    }

    private var fastingDict: [String: Any] {
        dashboard["fasting"] as? [String: Any] ?? [:]
    }

    private var fastingActive: Bool {
        (fastingDict["active"] as? Bool) == true
    }

    private var fastingHourPresets: [Double] {
        if let arr = fastingDict["hour_presets"] as? [Double], !arr.isEmpty { return arr }
        if let arr = fastingDict["hour_presets"] as? [Int] { return arr.map(Double.init) }
        return [12, 14, 16, 18, 20]
    }

    private var fastingEndPreviewLine: String {
        if fastingActive {
            return (fastingDict["preview_line"] as? String)
                ?? (fastingDict["ends_at_label"] as? String).map { "\($0)에 끝나요" }
                ?? ""
        }
        // Local preview when idle so chips update instantly without round-trip
        let end = Date().addingTimeInterval(fastingHours * 3600)
        let labels = localDayTimeLabels(start: Date(), end: end)
        return "\(Int(fastingHours))시간 하면 \(labels.end)에 끝나요"
    }

    private func localDayTimeLabels(start: Date, end: Date) -> (start: String, end: String) {
        let cal = Calendar.current
        let timeFmt = DateFormatter()
        timeFmt.locale = Locale(identifier: "ko_KR")
        timeFmt.dateFormat = "a h:mm"
        let dayFmt = DateFormatter()
        dayFmt.locale = Locale(identifier: "ko_KR")
        dayFmt.dateFormat = "M월 d일"
        func word(_ d: Date) -> String {
            let today = cal.startOfDay(for: Date())
            let d0 = cal.startOfDay(for: d)
            switch cal.dateComponents([.day], from: today, to: d0).day ?? 0 {
            case 0: return "오늘"
            case 1: return "내일"
            case 2: return "모레"
            default: return dayFmt.string(from: d)
            }
        }
        return ("\(word(start)) \(timeFmt.string(from: start))", "\(word(end)) \(timeFmt.string(from: end))")
    }

    private var healthRefLines: [String] {
        let href = fastingDict["health_reference"] as? [String: Any] ?? [:]
        return href["lines"] as? [String] ?? []
    }

    private var fastingCard: some View {
        KCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("간헐적 단식")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(KColor.grey500)
                Text((fastingDict["label"] as? String) ?? "간헐적 단식 대기")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(KColor.grey900)

                if !fastingEndPreviewLine.isEmpty {
                    Text(fastingEndPreviewLine)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(KColor.blue500)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let detail = fastingDict["detail_line"] as? String, fastingActive {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(KColor.grey500)
                }

                if !fastingActive {
                    Text("공복 시간")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(KColor.grey500)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(fastingHourPresets, id: \.self) { h in
                                let selected = Int(fastingHours) == Int(h)
                                Button {
                                    fastingHours = h
                                } label: {
                                    Text("\(Int(h))시간")
                                        .font(.system(size: 13, weight: .semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(selected ? KColor.blue500 : KColor.blue50)
                                        .foregroundStyle(selected ? Color.white : KColor.blue500)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    Text({
                        let L = localDayTimeLabels(
                            start: Date(),
                            end: Date().addingTimeInterval(fastingHours * 3600)
                        )
                        return "시작 \(L.start) → 종료 \(L.end)"
                    }())
                        .font(.caption)
                        .foregroundStyle(KColor.grey500)
                }

                if let hint = fastingDict["hint"] as? String, !hint.isEmpty {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(KColor.grey500)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if fastingActive {
                    let prog = doubleVal(fastingDict["progress"])
                    ProgressView(value: min(1, max(0, prog)))
                        .tint(KColor.blue500)
                    if let rem = fastingDict["remaining_hours"] as? Double {
                        Text(String(format: "남은 시간 약 %.1f시간", rem))
                            .font(.caption)
                            .foregroundStyle(KColor.grey500)
                    }
                }

                // Optional health / diet reference (never required)
                VStack(alignment: .leading, spacing: 4) {
                    Text("참고 정보 (없어도 됨)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(KColor.grey500)
                    if healthRefLines.isEmpty {
                        Text("건강·식사 참고 데이터가 없어요. 직접 기록만으로 단식·목표 예상이 동작해요.")
                            .font(.system(size: 11))
                            .foregroundStyle(KColor.grey500)
                    } else {
                        ForEach(Array(healthRefLines.prefix(8).enumerated()), id: \.offset) { _, line in
                            Text("· \(line)")
                                .font(.system(size: 11))
                                .foregroundStyle(KColor.grey700)
                        }
                        Text("워치/건강 값은 참고만 하며, 목표 계산 우선순위는 공복 직접 체중이에요.")
                            .font(.system(size: 10))
                            .foregroundStyle(KColor.grey500)
                    }
                }
                .padding(.top, 2)

                HStack(spacing: 12) {
                    if fastingActive {
                        Button {
                            Task { await endFasting() }
                        } label: {
                            if fastingBusy { ProgressView() } else { Text("단식 종료") }
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(KColor.blue500)
                        .disabled(fastingBusy)
                    } else {
                        Button {
                            Task { await startFasting() }
                        } label: {
                            if fastingBusy {
                                ProgressView()
                            } else {
                                Text("\(Int(fastingHours))시간 단식 시작")
                            }
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(KColor.blue500)
                        .disabled(fastingBusy || !core.isPaired)
                    }
                }
                Text("첫 식사 기록 시 단식이 자동 종료돼요.")
                    .font(.system(size: 11))
                    .foregroundStyle(KColor.grey500)
            }
        }
    }

    private var morningWeightCard: some View {
        KCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("아침 공복 체중")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(KColor.grey500)
                Text((fastingDict["weight_prompt"] as? String)
                     ?? "매일 아침 공복에 재면 목표 도달 예상이 안정적이에요.")
                    .font(.caption)
                    .foregroundStyle(KColor.grey500)
                    .fixedSize(horizontal: false, vertical: true)
                if let w = fastingDict["preferred_weight_kg"] as? Double
                    ?? dashboard["latest_weight_kg"] as? Double {
                    Text(String(format: "최근 기준 체중 %.1f kg", w))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(KColor.grey900)
                }
                HStack(spacing: 8) {
                    TextField("kg", text: $weightKg)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                    Button("공복 체중 저장") {
                        morningWeightOnly = true
                        Task { await saveMorningWeight() }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(KColor.blue500)
                    .disabled(weightKg.isEmpty || !core.isPaired)
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
                    TextField("예: \(selectedSlot) 닭가슴살 150g · 커피 300ml", text: $quickLine)
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
            Text("빠른 식사 (기본 분량 · g/ml 비례)")
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
                                do {
                                    try await core.dietLogWorkout(kind: item.0, minutes: item.1, intensity: nil)
                                    kHapticSuccess()
                                    showFlash("\(item.0) \(item.1)분 저장됐어요")
                                    await reload()
                                } catch {
                                    showFlash("저장 실패: \(error.localizedDescription)")
                                }
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
            HStack {
                Text("오늘 기록")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(KColor.grey500)
                Spacer()
                if !meals.isEmpty || !workouts.isEmpty {
                    Text("삭제 버튼 · 길게 눌러도 삭제")
                        .font(.system(size: 11))
                        .foregroundStyle(KColor.grey500)
                }
            }
            KCard(padded: false) {
                if meals.isEmpty && workouts.isEmpty {
                    KEmptyState(
                        systemImage: "fork.knife",
                        title: "아직 없어요",
                        message: "끼니 칩이나 한 줄로 시작해 보세요.",
                        actionTitle: "기록하기"
                    ) { showLog = true }
                    .padding(KSpace.x4)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(meals.enumerated()), id: \.offset) { idx, m in
                            let id = stringVal(m["id"])
                            let items = (m["items"] as? [String])?.joined(separator: ", ") ?? "식사"
                            let kcal = intVal(m["kcal"])
                            let protein = intVal(m["protein_g"])
                            let sub: String = {
                                var p: [String] = []
                                if kcal > 0 { p.append("\(kcal) kcal") }
                                if protein > 0 { p.append("P\(protein)g") }
                                return p.joined(separator: " · ")
                            }()
                            dietRow(
                                icon: "fork.knife",
                                title: items,
                                subtitle: sub,
                                rowId: id,
                                isLast: idx == meals.count - 1 && workouts.isEmpty
                            ) {
                                guard !id.isEmpty else {
                                    showFlash("이 기록에 id가 없어 삭제할 수 없어요. 앱을 다시 받아 주세요.")
                                    return
                                }
                                pendingDelete = PendingDelete(id: id, kind: .meal, title: items)
                            }
                        }
                        ForEach(Array(workouts.enumerated()), id: \.offset) { idx, w in
                            let id = stringVal(w["id"])
                            let kind = (w["kind"] as? String) ?? "운동"
                            let minutes = intVal(w["minutes"])
                            let title = "\(kind) · \(minutes)분"
                            dietRow(
                                icon: "figure.walk",
                                title: title,
                                subtitle: "",
                                rowId: id,
                                isLast: idx == workouts.count - 1
                            ) {
                                guard !id.isEmpty else {
                                    showFlash("이 기록에 id가 없어 삭제할 수 없어요.")
                                    return
                                }
                                pendingDelete = PendingDelete(id: id, kind: .workout, title: title)
                            }
                        }
                    }
                }
            }
        }
    }

    private func dietRow(
        icon: String,
        title: String,
        subtitle: String,
        rowId: String,
        isLast: Bool,
        onDelete: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(KColor.blue500)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(KColor.grey900)
                        .multilineTextAlignment(.leading)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(KColor.grey500)
                    }
                }
                Spacer(minLength: 8)
                if deleteBusyId == rowId {
                    ProgressView().scaleEffect(0.85)
                } else {
                    Button(role: .destructive, action: onDelete) {
                        Text("삭제")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(KColor.red500)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("\(title) 삭제")
                }
            }
            .padding(.horizontal, KSpace.x4)
            .padding(.vertical, 12)
            .background(KColor.white)
            .contentShape(Rectangle())
            .contextMenu {
                Button(role: .destructive, action: onDelete) {
                    Label("삭제", systemImage: "trash")
                }
            }
            if !isLast {
                Divider().padding(.leading, 50)
            }
        }
    }

    private func performDelete(_ p: PendingDelete) async {
        deleteBusyId = p.id
        pendingDelete = nil
        defer { deleteBusyId = nil }
        do {
            let removed: Bool
            switch p.kind {
            case .meal:
                removed = try await core.dietDeleteMeal(id: p.id)
            case .workout:
                removed = try await core.dietDeleteWorkout(id: p.id)
            }
            if removed {
                // Optimistic local remove so UI updates even if reload is slow
                optimisticallyRemove(id: p.id, kind: p.kind)
                kHapticSuccess()
                showFlash("삭제됐어요")
                await reload()
            } else {
                showFlash("이미 없거나 찾을 수 없는 기록이에요")
                await reload()
            }
        } catch {
            err = error.localizedDescription
            showFlash("삭제 실패: \(error.localizedDescription)")
            kHapticLight()
        }
    }

    private func optimisticallyRemove(id: String, kind: PendingDelete.Kind) {
        guard var day = dashboard["day"] as? [String: Any] else { return }
        switch kind {
        case .meal:
            var meals = day["meals"] as? [[String: Any]] ?? []
            meals.removeAll { stringVal($0["id"]) == id }
            day["meals"] = meals
        case .workout:
            var workouts = day["workouts"] as? [[String: Any]] ?? []
            workouts.removeAll { stringVal($0["id"]) == id }
            day["workouts"] = workouts
        }
        dashboard["day"] = day
    }

    private func stringVal(_ any: Any?) -> String {
        if let s = any as? String { return s }
        if let n = any as? NSNumber { return n.stringValue }
        return ""
    }

    private var logSheet: some View {
        NavigationStack {
            Form {
                Section("식사") {
                    Picker("끼니", selection: $selectedSlot) {
                        ForEach(slots, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    TextField("음식 (예: 닭가슴살)", text: $mealItems)
                        .onChange(of: mealItems) { _, _ in recomputeMealNutrition() }
                    HStack {
                        TextField("분량", text: $mealAmount)
                            .keyboardType(.decimalPad)
                            .onChange(of: mealAmount) { _, _ in
                                mealKcalManual = false
                                recomputeMealNutrition()
                            }
                        Picker("단위", selection: $mealUnit) {
                            Text("g").tag(DietNutritionCalc.Unit.g)
                            Text("ml").tag(DietNutritionCalc.Unit.ml)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 120)
                        .onChange(of: mealUnit) { _, _ in
                            mealKcalManual = false
                            recomputeMealNutrition()
                        }
                    }
                    if !mealAutoNote.isEmpty {
                        Text(mealAutoNote)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    TextField("kcal (자동·수정 가능)", text: $mealKcal)
                        .keyboardType(.decimalPad)
                        .onChange(of: mealKcal) { _, _ in mealKcalManual = true }
                    TextField("단백질 g (자동·수정 가능)", text: $mealProtein)
                        .keyboardType(.decimalPad)
                    Text("g/ml만 넣어도 kcal·단백질을 대략 계산해요.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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
                    Button("내 정보로 자동 계산") {
                        showGoals = false
                        showProfile = true
                    }
                }
                if let goalsMessage {
                    Section {
                        Label(goalsMessage, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(KColor.green500)
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
                if let goalsError {
                    Section {
                        Text(goalsError)
                            .font(.caption)
                            .foregroundStyle(KColor.red500)
                    }
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
                Section {
                    Button {
                        Task { await saveGoals() }
                    } label: {
                        HStack {
                            Spacer()
                            if goalsBusy {
                                ProgressView()
                            } else {
                                Text("목표 저장").fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(goalsBusy)
                }
            }
            .navigationTitle("목표")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") {
                        showGoals = false
                        goalsMessage = nil
                        goalsError = nil
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("완료") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { goalsMessage = nil; goalsError = nil }
    }

    private var profileSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Text("다이어트 막 시작할 때 쓰는 최소 정보예요. 저장하면 목표 칼로리·단백질을 자동으로 넣고, 도달 시점도 계산해요.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let profileMessage {
                    Section {
                        Label(profileMessage, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(KColor.green500)
                            .font(.system(size: 14, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let profileError {
                    Section {
                        Text(profileError)
                            .font(.caption)
                            .foregroundStyle(KColor.red500)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
                Section {
                    Button {
                        Task { await saveProfile() }
                    } label: {
                        HStack {
                            Spacer()
                            if profileBusy {
                                ProgressView()
                            } else {
                                Text("저장하고 목표 자동 적용").fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(profileBusy)
                } footer: {
                    Text("저장되면 위에 초록 확인 문구가 보인 뒤 닫혀요.")
                        .font(.caption2)
                }
            }
            .navigationTitle("내 정보")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") {
                        showProfile = false
                        profileMessage = nil
                        profileError = nil
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("완료") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
        }
        .presentationDetents([.large])
        .onAppear { profileMessage = nil; profileError = nil }
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
        profileError = nil
        profileMessage = nil
        // Accept "165.0" / whitespace / full-width digits lightly
        let hStr = pHeight.trimmingCharacters(in: .whitespacesAndNewlines)
        let wStr = pWeight.trimmingCharacters(in: .whitespacesAndNewlines)
        let ageStr = pAge.trimmingCharacters(in: .whitespacesAndNewlines)
        let tStr = pTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let h = Double(hStr), let w = Double(wStr),
              let age = Int(ageStr), let t = Double(tStr),
              h > 50, h < 250, w > 20, w < 300, age > 10, age < 120, t > 20, t < 300 else {
            profileError = "키·몸무게·나이·목표 몸무게 숫자를 다시 확인해 주세요."
            kHapticLight()
            return
        }
        profileBusy = true
        defer { profileBusy = false }
        do {
            let result = try await core.dietSetProfile(
                heightCm: h, weightKg: w, age: age, sex: pSex,
                targetWeightKg: t, activity: pActivity, applyGoals: true
            )
            let goals = result["goals"] as? [String: Any] ?? [:]
            let kcal = intVal(goals["target_kcal"])
            let protein = intVal(goals["target_protein_g"])
            let plan = result["plan"] as? [String: Any]
            let eta = plan?["eta_text"] as? String
            var lines = ["저장됐어요. 목표가 적용됐어요."]
            if kcal > 0 || protein > 0 {
                lines.append("하루 \(kcal) kcal · 단백질 \(protein)g")
            }
            if let eta, !eta.isEmpty {
                lines.append(eta)
            }
            let msg = lines.joined(separator: "\n")
            profileMessage = msg
            err = nil
            kHapticSuccess()
            await reload()
            // Let user read confirmation in-sheet before close
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            showProfile = false
            profileMessage = nil
            profileError = nil
            // Main screen toast after sheet dismisses
            showFlash("저장 완료 · 목표 \(kcal)kcal · 단백질 \(protein)g 적용됨")
        } catch {
            profileError = "저장 실패: \(error.localizedDescription)\nMac Core가 켜져 있고 페어링됐는지 확인해 주세요."
            err = error.localizedDescription
            kHapticLight()
        }
    }

    private func showFlash(_ text: String) {
        // Dual surface: local banner + global toast (always visible above tabs)
        flash = text
        let isErr = text.contains("실패") || text.contains("확인") || text.contains("입력")
        if isErr { feedback.error(text) } else { feedback.success(text) }
        Task {
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            if flash == text { flash = nil }
        }
    }

    private func loadProfileFields() {
        let p = dashboard["profile"] as? [String: Any] ?? [:]
        if let h = doubleValOpt(p["height_cm"]) { pHeight = formatNum(h) }
        if let w = doubleValOpt(p["weight_kg"]) { pWeight = formatNum(w) }
        if let a = intValOpt(p["age"]) { pAge = "\(a)" }
        if let s = p["sex"] as? String, !s.isEmpty { pSex = s }
        if let t = doubleValOpt(p["target_weight_kg"]) { pTarget = formatNum(t) }
        if let act = p["activity"] as? String, !act.isEmpty { pActivity = act }
    }

    private func formatNum(_ d: Double) -> String {
        d.rounded() == d ? "\(Int(d))" : String(format: "%.1f", d)
    }

    private func doubleValOpt(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let s = any as? String { return Double(s) }
        return nil
    }

    private func intValOpt(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let d = any as? Double { return Int(d) }
        if let s = any as? String { return Int(s) }
        return nil
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
            showFlash("\(name) \(grams)\(unit) · ~\(Int(kcal))kcal 저장됐어요")
            await reload()
        } catch {
            err = error.localizedDescription
            showFlash("저장 실패: \(error.localizedDescription)")
            kHapticLight()
        }
    }

    private func commitQuick() async {
        let line = quickLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        do {
            if line.contains("운동") || line.lowercased().contains("workout") {
                let minutes = Int(line.filter(\.isNumber)) ?? 20
                try await core.dietLogWorkout(kind: line, minutes: minutes, intensity: nil)
                showFlash("운동 \(minutes)분 저장됐어요")
            } else if let est = DietNutritionCalc.parse(line) {
                let text = line.contains(selectedSlot) ? est.itemLine : "\(selectedSlot) \(est.itemLine)"
                try await core.dietLogMeal(
                    items: [text],
                    kcal: est.kcal,
                    proteinG: est.proteinG,
                    note: est.note
                )
                showFlash("\(est.itemLine) · ~\(Int(est.kcal))kcal · P\(Int(est.proteinG))g")
            } else {
                // "샐러드 350kcal" still works
                let kcal: Double? = {
                    if let r = try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)\s*kcal"#, options: .caseInsensitive),
                       let m = r.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                       let rr = Range(m.range(at: 1), in: line) {
                        return Double(line[rr])
                    }
                    return nil
                }()
                let text = line.contains(selectedSlot) ? line : "\(selectedSlot) \(line)"
                try await core.dietLogMeal(items: [text], kcal: kcal, proteinG: nil, note: line)
                showFlash("식사 저장됐어요")
            }
            quickLine = ""
            kHapticSuccess()
            await reload()
        } catch {
            err = error.localizedDescription
            showFlash("저장 실패: \(error.localizedDescription)")
            kHapticLight()
        }
    }

    private func recomputeMealNutrition() {
        let name = mealItems.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            mealAutoNote = ""
            return
        }
        if let amt = Double(mealAmount.trimmingCharacters(in: .whitespacesAndNewlines)), amt > 0 {
            if let e = DietNutritionCalc.estimate(foodQuery: name, amount: amt, unit: mealUnit) {
                applyEstimate(e, forceKcal: !mealKcalManual)
            }
            return
        }
        if let e = DietNutritionCalc.parse(name, defaultUnit: mealUnit) {
            mealAmount = e.amount == e.amount.rounded() ? "\(Int(e.amount))" : String(format: "%.1f", e.amount)
            mealUnit = e.unit
            applyEstimate(e, forceKcal: !mealKcalManual)
        }
    }

    private func applyEstimate(_ e: DietNutritionCalc.Estimate, forceKcal: Bool) {
        if forceKcal {
            mealKcal = e.kcal == e.kcal.rounded() ? "\(Int(e.kcal))" : String(format: "%.0f", e.kcal)
            mealProtein = String(format: "%.1f", e.proteinG)
        } else if mealProtein.isEmpty {
            mealProtein = String(format: "%.1f", e.proteinG)
        }
        mealAutoNote = e.matchedCatalog
            ? "자동: ~\(Int(e.kcal))kcal · 단백질 \(String(format: "%.1f", e.proteinG))g"
            : e.note
    }

    private func saveMeal() async {
        var items = mealItems.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !items.isEmpty else {
            showFlash("음식 이름을 입력해 주세요")
            return
        }
        var kcal = Double(mealKcal)
        var protein = Double(mealProtein)
        var note: String? = nil
        if (kcal == nil || kcal == 0), let amt = Double(mealAmount), amt > 0 {
            if let e = DietNutritionCalc.estimate(foodQuery: items.joined(separator: " "), amount: amt, unit: mealUnit) {
                kcal = e.kcal
                protein = protein ?? e.proteinG
                note = e.note
                items = [e.itemLine]
            }
        } else if let amt = Double(mealAmount), amt > 0 {
            let aStr = amt == amt.rounded() ? "\(Int(amt))" : String(format: "%.1f", amt)
            if let first = items.first, !first.contains(mealUnit.rawValue) {
                items[0] = "\(first) \(aStr)\(mealUnit.rawValue)"
            }
        }
        let labeled = items.map { $0.contains(selectedSlot) ? $0 : "\(selectedSlot) \($0)" }
        do {
            try await core.dietLogMeal(items: labeled, kcal: kcal, proteinG: protein, note: note)
            mealItems = ""; mealKcal = ""; mealProtein = ""; mealAmount = ""; mealAutoNote = ""; mealKcalManual = false
            showLog = false
            kHapticSuccess()
            showFlash("식사 저장됐어요\(kcal.map { " · \(Int($0))kcal" } ?? "")")
            await reload()
        } catch {
            err = error.localizedDescription
            showFlash("식사 저장 실패: \(error.localizedDescription)")
            kHapticLight()
        }
    }

    private func saveWorkout() async {
        do {
            try await core.dietLogWorkout(kind: workoutKind, minutes: Int(workoutMin) ?? 0, intensity: nil)
            showLog = false
            kHapticSuccess()
            showFlash("운동 저장됐어요")
            await reload()
        } catch {
            err = error.localizedDescription
            showFlash("운동 저장 실패: \(error.localizedDescription)")
            kHapticLight()
        }
    }

    private func saveMetric() async {
        guard Double(weightKg) != nil || Double(sleepH) != nil else {
            showFlash("체중 또는 수면을 입력해 주세요")
            return
        }
        do {
            try await core.dietLogMetric(
                weightKg: Double(weightKg),
                sleepH: Double(sleepH),
                morningFasted: morningWeightOnly && Double(weightKg) != nil
            )
            weightKg = ""; sleepH = ""
            showLog = false
            kHapticSuccess()
            showFlash("지표 저장됐어요")
            await reload()
        } catch {
            err = error.localizedDescription
            showFlash("지표 저장 실패: \(error.localizedDescription)")
            kHapticLight()
        }
    }

    private func saveMorningWeight() async {
        guard let w = Double(weightKg.trimmingCharacters(in: .whitespacesAndNewlines)), w > 30, w < 300 else {
            showFlash("체중(kg)을 확인해 주세요")
            return
        }
        do {
            try await core.dietLogMetric(weightKg: w, sleepH: nil, morningFasted: true)
            weightKg = ""
            kHapticSuccess()
            showFlash(String(format: "공복 체중 %.1fkg 저장 · 목표 도달 예상 갱신", w))
            feedback.success(String(format: "공복 %.1fkg 반영", w))
            await reload()
        } catch {
            err = error.localizedDescription
            showFlash("저장 실패: \(error.localizedDescription)")
            feedback.error(error.localizedDescription)
            kHapticLight()
        }
    }

    private func startFasting() async {
        fastingBusy = true
        defer { fastingBusy = false }
        do {
            let r = try await core.dietFastingStart(targetHours: fastingHours)
            kHapticSuccess()
            let endLabel = r["ends_at_label"] as? String
            let label = endLabel.map { "\(Int(fastingHours))h 단식 시작 · \($0) 종료" }
                ?? (r["label"] as? String)
                ?? "\(Int(fastingHours))시간 단식 시작"
            showFlash(label)
            feedback.success(label)
            if let plan = r["plan"] as? [String: Any], let eta = plan["eta_text"] as? String {
                planEta = eta
            }
            await reload()
        } catch {
            err = error.localizedDescription
            feedback.error(error.localizedDescription)
            kHapticLight()
        }
    }

    private func endFasting() async {
        fastingBusy = true
        defer { fastingBusy = false }
        do {
            _ = try await core.dietFastingEnd(reason: "manual")
            kHapticSuccess()
            showFlash("단식을 종료했어요")
            feedback.info("단식 종료 · 식사 창")
            await reload()
        } catch {
            err = error.localizedDescription
            feedback.error(error.localizedDescription)
            kHapticLight()
        }
    }

    private func loadGoals() {
        let g = dashboard["goals"] as? [String: Any] ?? [:]
        goalKcal = "\(intVal(g["target_kcal"]))"
        goalProtein = "\(intVal(g["target_protein_g"]))"
        goalWeekly = "\(intVal(g["weekly_workouts"]))"
        goalDayMin = "\(intVal(g["target_workout_minutes_per_day"]))"
    }

    private func saveGoals() async {
        goalsError = nil
        goalsMessage = nil
        let kcal = Double(goalKcal.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let protein = Double(goalProtein.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        guard kcal > 500, kcal < 8000, protein > 0, protein < 500 else {
            goalsError = "칼로리·단백질 숫자를 확인해 주세요."
            kHapticLight()
            return
        }
        goalsBusy = true
        defer { goalsBusy = false }
        do {
            try await core.dietSetGoals(
                kcal: kcal,
                protein: protein,
                weeklyWorkouts: Int(goalWeekly.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 4,
                dayMinutes: Int(goalDayMin.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 30
            )
            goalsMessage = "저장됐어요 · 하루 \(Int(kcal)) kcal · 단백질 \(Int(protein))g"
            err = nil
            kHapticSuccess()
            await reload()
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            showGoals = false
            goalsMessage = nil
            goalsError = nil
            showFlash("목표 저장 완료 · \(Int(kcal))kcal · 단백질 \(Int(protein))g")
        } catch {
            goalsError = "저장 실패: \(error.localizedDescription)\nMac Core 연결을 확인해 주세요."
            err = error.localizedDescription
            kHapticLight()
        }
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
