import SwiftUI

/// Product home (Toss philosophy):
/// 1) One calm greeting  2) One primary action  3) Short list  4) Quiet recent
public struct HomeView: View {
    @ObservedObject public var model: AppModel
    @State private var path = NavigationPath()

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                TossColor.grey100.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        Spacer().frame(height: TossSpace.x8)
                        greetingBlock
                        if showOnboarding {
                            Spacer().frame(height: TossSpace.x6)
                            onboardingBlock
                        }
                        if let err = surfaceError {
                            Spacer().frame(height: TossSpace.x4)
                            errorBanner(err)
                        }
                        Spacer().frame(height: TossSpace.x8)
                        primaryBlock
                        Spacer().frame(height: TossSpace.x8)
                        menuBlock
                        if showRecent {
                            Spacer().frame(height: TossSpace.x8)
                            recentBlock
                        }
                        Spacer().frame(height: TossSpace.x8)
                    }
                    .padding(.horizontal, TossSpace.x6)
                }
            }
            .navigationDestination(for: AppRoute.self) { route in
                destination(route)
                    .navigationBarBackButtonHidden(true)
            }
        }
        .frame(minWidth: 400, idealWidth: 440, minHeight: 600)
        .task {
            model.refreshVaultConfig()
            model.startPolling()
            model.kickPendingASR()
            model.refreshSourceStats()
            model.refreshLLMStatus()
            model.refreshActionDue()
        }
    }

    /// First-run / setup tips — quiet, dismissible by progress (no meetings + vault ok).
    private var showOnboarding: Bool {
        !model.isRecording && !model.isProcessing
            && model.healthOK && model.vaultReady
            && model.reviewCount == 0
            && model.meetings.filter { $0.status != "abandoned" }.isEmpty
    }

    private var onboardingBlock: some View {
        VStack(alignment: .leading, spacing: TossSpace.x4) {
            Text("시작 안내")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(TossColor.grey500)
            VStack(alignment: .leading, spacing: TossSpace.x3) {
                onboardingRow(
                    icon: "waveform",
                    title: "녹음",
                    body: "회의 소리를 남기면 받아쓰고 요약해요. 시스템 설정에서 화면 기록이 필요할 수 있어요."
                )
                Divider().overlay(TossColor.grey200)
                onboardingRow(
                    icon: "checkmark.circle",
                    title: "확인 후 저장",
                    body: "요약은 확인함에서 보고, 저장하면 노트 폴더에 남아요."
                )
                Divider().overlay(TossColor.grey200)
                onboardingRow(
                    icon: "bubble.left.and.bubble.right",
                    title: "물어보기",
                    body: model.llmEngine.contains("7b") || model.llmEngine.contains("local")
                        ? "지금은 로컬 7B로 답해요. 설정에 클라우드 키를 넣으면 free 티어가 먼저예요."
                        : "지식 연결을 동기화한 뒤, 모은 내용에 질문해 보세요."
                )
                if model.corpusTotalUnits == 0 {
                    Divider().overlay(TossColor.grey200)
                    Button {
                        path.append(AppRoute.library)
                    } label: {
                        Text("지식 연결하러 가기")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(TossColor.blue500)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(TossSpace.x5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TossColor.white)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func onboardingRow(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: TossSpace.x3) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(TossColor.blue500)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(TossColor.grey900)
                Text(body)
                    .font(.system(size: 14))
                    .foregroundStyle(TossColor.grey500)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(TossColor.red500)
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(TossColor.grey900)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(TossSpace.x4)
        .background(TossColor.red50)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func destination(_ route: AppRoute) -> some View {
        switch route {
        case .record: RecordView(model: model)
        case .chat: ChatView(model: model)
        case .library: SourcesView(model: model)
        case .review: ReviewInboxView(model: model)
        case .search: SearchView(model: model)
        case .diet: DietView(knowledgeRoot: model.knowledgeRoot)
        case .settings: SettingsView(model: model)
        }
    }

    // MARK: Greeting — human, not product dump

    private var greetingBlock: some View {
        VStack(alignment: .leading, spacing: TossSpace.x3) {
            Text(greetingTitle)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(TossColor.grey900)
                .fixedSize(horizontal: false, vertical: true)
            Text(greetingBody)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(TossColor.grey700)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var greetingTitle: String {
        if model.isRecording { return "듣고 있어요" }
        if model.isProcessing { return "정리하고 있어요" }
        if model.reviewCount > 0 { return "확인할 게 있어요" }
        if model.isStartingBackend || !model.healthOK { return "잠깐만요" }
        return "오늘도 남겨 둘까요"
    }

    private var greetingBody: String {
        if model.isRecording {
            return "회의가 끝나면 아래 버튼으로 마쳐 주세요."
        }
        if model.isProcessing {
            return "곧 확인함으로 옮겨 드릴게요."
        }
        if model.reviewCount == 1 {
            return "요약 1건을 저장하기 전에 보면 좋아요."
        }
        if model.reviewCount > 1 {
            return "요약 \(model.reviewCount)건이 기다리고 있어요."
        }
        if !model.vaultReady {
            return "저장 폴더를 아직 쓸 수 없어요."
        }
        if !model.healthOK {
            return "준비만 끝내면 바로 시작할 수 있어요."
        }
        return "중요한 대화는 녹음해 두고, 필요할 때 물어보세요."
    }

    // MARK: Primary — do the thing, don't open a menu

    private var primaryBlock: some View {
        VStack(spacing: TossSpace.x3) {
            TossPrimaryButton(primaryTitle, enabled: primaryEnabled) {
                primaryAction()
            }
            if let sub = secondaryTitle {
                Button(sub) { secondaryAction() }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(TossColor.blue500)
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .padding(.top, TossSpace.x1)
            }
        }
    }

    private var primaryTitle: String {
        if model.isRecording { return "녹음 끝내기" }
        if model.isProcessing { return "정리하는 중…" }
        if model.reviewCount > 0 { return "확인하러 가기" }
        if model.isStartingBackend { return "준비 중…" }
        return "녹음 시작하기"
    }

    private var primaryEnabled: Bool {
        if model.isProcessing || model.isStartingBackend { return false }
        if model.isRecording { return true }
        if model.reviewCount > 0 { return true }
        return model.vaultReady && model.healthOK
    }

    private var secondaryTitle: String? {
        if model.isRecording { return "녹음 화면 자세히" }
        if model.reviewCount > 0 { return "녹음하기" }
        if model.corpusTotalUnits > 0 { return "지식에게 물어보기" }
        return nil
    }

    private func primaryAction() {
        if model.isRecording {
            model.stopRecording()
            return
        }
        if model.reviewCount > 0 {
            path.append(AppRoute.review)
            return
        }
        // Start capture immediately — instinctive, not "open record page first"
        path.append(AppRoute.record)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if !model.isRecording && !model.isProcessing {
                model.startRecording()
            }
        }
    }

    private func secondaryAction() {
        if model.isRecording {
            path.append(AppRoute.record)
        } else if model.reviewCount > 0 {
            path.append(AppRoute.record)
        } else {
            path.append(AppRoute.chat)
        }
    }

    private var surfaceError: String? {
        guard let e = model.lastError, !model.isRecording else { return nil }
        if e.contains("화면 기록") || e.contains("TCC") || e.contains("3801") {
            return "화면 기록을 허용해 주세요"
        }
        return nil
    }

    // MARK: Menu — short list, not a dashboard

    private var menuBlock: some View {
        VStack(alignment: .leading, spacing: TossSpace.x3) {
            Text("바로가기")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(TossColor.grey500)
                .padding(.leading, TossSpace.x1)

            VStack(spacing: 0) {
                menuRow(
                    title: "물어보기",
                    subtitle: "모아 둔 지식에 질문",
                    icon: "bubble.left.and.bubble.right.fill",
                    trailing: nil
                ) { path.append(AppRoute.chat) }

                rowDivider

                menuRow(
                    title: "식단 · 운동",
                    subtitle: "기록 · 분석 · 진행률",
                    icon: "fork.knife.circle.fill",
                    trailing: nil
                ) { path.append(AppRoute.diet) }

                rowDivider

                menuRow(
                    title: "확인함",
                    subtitle: model.reviewCount > 0 ? "저장 전 살펴보기" : "비어 있어요",
                    icon: "checkmark.circle.fill",
                    trailing: model.reviewCount > 0 ? "\(model.reviewCount)" : nil
                ) { path.append(AppRoute.review) }

                rowDivider

                menuRow(
                    title: "찾아보기",
                    subtitle: "키워드로 검색",
                    icon: "magnifyingglass",
                    trailing: nil
                ) { path.append(AppRoute.search) }

                rowDivider

                menuRow(
                    title: "지식 연결",
                    subtitle: "메모·폴더 가져오기",
                    icon: "folder.fill",
                    trailing: model.corpusTotalUnits > 0 ? "\(model.corpusTotalUnits)" : nil
                ) { path.append(AppRoute.library) }

                rowDivider

                menuRow(
                    title: "설정",
                    subtitle: "보관·저장 위치",
                    icon: "gearshape.fill",
                    trailing: nil
                ) { path.append(AppRoute.settings) }
            }
            .padding(.horizontal, TossSpace.x4)
            .background(TossColor.white)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func menuRow(
        title: String,
        subtitle: String,
        icon: String,
        trailing: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: TossSpace.x3) {
                ZStack {
                    Circle()
                        .fill(TossColor.blue50)
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(TossColor.blue500)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(TossColor.grey900)
                    Text(subtitle)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(TossColor.grey500)
                }
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(TossColor.blue500)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(TossColor.blue50)
                        .clipShape(Capsule())
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xD1D6DB))
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var rowDivider: some View {
        Divider()
            .overlay(TossColor.grey200)
            .padding(.leading, 56)
    }

    // MARK: Recent — only if useful

    private var showRecent: Bool {
        !model.meetings.filter { $0.status != "abandoned" }.isEmpty
    }

    private var recentBlock: some View {
        VStack(alignment: .leading, spacing: TossSpace.x3) {
            Text("최근 미팅")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(TossColor.grey500)
                .padding(.leading, TossSpace.x1)

            VStack(spacing: 0) {
                ForEach(model.meetings.filter { $0.status != "abandoned" }.prefix(3)) { row in
                    Button {
                        if row.status == "review_needed" {
                            path.append(AppRoute.review)
                        } else {
                            path.append(AppRoute.record)
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.title)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(TossColor.grey900)
                                    .lineLimit(1)
                                Text(StatusCopy.label(row.status))
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundStyle(TossColor.grey500)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color(hex: 0xD1D6DB))
                        }
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if row.status != "recording" {
                            Button("삭제", role: .destructive) {
                                model.deleteMeeting(id: row.id)
                            }
                        }
                    }

                    if row.id != model.meetings.filter({ $0.status != "abandoned" }).prefix(3).last?.id {
                        Divider().overlay(TossColor.grey200)
                    }
                }
            }
            .padding(.horizontal, TossSpace.x4)
            .background(TossColor.white)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}
