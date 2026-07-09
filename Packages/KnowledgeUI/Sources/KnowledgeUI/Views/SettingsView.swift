import SwiftUI
import KnowledgeCore
import KnowledgeWorkers

/// Settings: vault, cloud free-tier keys, local 7B, retention.
public struct SettingsView: View {
    @ObservedObject public var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var abandonedDays: Int = 14
    @State private var audioDays: Int = 0
    @State private var purgeOnLaunch: Bool = true
    @State private var useLocal7B: Bool = true
    @State private var cloudEnabled: Bool = true
    @State private var geminiKey: String = ""
    @State private var groqKey: String = ""
    @State private var openrouterKey: String = ""
    @State private var savedFlash: String?
    @State private var llmDetail: String = ""

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        ZStack {
            TossColor.grey100.ignoresSafeArea()
            VStack(spacing: 0) {
                nav
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: TossSpace.x8) {
                        titleBlock
                        vaultBlock
                        cascadeBlock
                        cloudKeysBlock
                        local7BBlock
                        retentionBlock
                        if let savedFlash {
                            Text(savedFlash)
                                .font(TossFont.caption())
                                .foregroundStyle(TossColor.blue500)
                        }
                        TossPrimaryButton("저장하기") { save() }
                    }
                    .padding(.horizontal, TossSpace.x6)
                    .padding(.bottom, TossSpace.x8)
                }
            }
        }
        .onAppear { load() }
    }

    private var nav: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(TossColor.grey900)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, TossSpace.x2)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: TossSpace.x3) {
            Text("설정")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(TossColor.grey900)
            Text("기본은 로컬 7B예요. 클라우드 키를 넣으면 그때만 클라우드가 1순위예요.")
                .font(.system(size: 17))
                .foregroundStyle(TossColor.grey700)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var vaultBlock: some View {
        VStack(alignment: .leading, spacing: TossSpace.x3) {
            Text("노트 저장 위치")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(TossColor.grey500)
            VStack(alignment: .leading, spacing: TossSpace.x3) {
                Text(model.vaultDisplayPath)
                    .font(.system(size: 14))
                    .foregroundStyle(TossColor.grey900)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Button("폴더 열기") { model.openVaultInFinder() }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(TossColor.blue500)
                    .buttonStyle(.plain)
            }
            .padding(TossSpace.x5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TossColor.white)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private var cascadeBlock: some View {
        VStack(alignment: .leading, spacing: TossSpace.x3) {
            Text("답변 우선순위")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(TossColor.grey500)
            VStack(alignment: .leading, spacing: TossSpace.x3) {
                Text("· 키 있음 → 클라우드 무료 (Gemini → Groq → OpenRouter)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(TossColor.grey900)
                Text("· 키 없음 → 로컬 7B (기본)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(TossColor.grey900)
                Text("· 7B도 없으면 → 근거 모음 (최후)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(TossColor.grey900)
                if !llmDetail.isEmpty {
                    Text(llmDetail)
                        .font(.system(size: 13))
                        .foregroundStyle(TossColor.grey500)
                        .padding(.top, 4)
                }
                Text("모델·엔드포인트는 config/llm_providers.json 에서 갈아탈 수 있어요. (앱 재빌드 불필요)")
                    .font(.system(size: 13))
                    .foregroundStyle(TossColor.grey500)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(TossSpace.x5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TossColor.white)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private var cloudKeysBlock: some View {
        VStack(alignment: .leading, spacing: TossSpace.x3) {
            Text("클라우드 무료 키")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(TossColor.grey500)
            VStack(alignment: .leading, spacing: TossSpace.x5) {
                Toggle(isOn: $cloudEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("클라우드 무료 티어 사용")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(TossColor.grey900)
                        Text("키가 있는 제공자만 순서대로 시도해요")
                            .font(.system(size: 14))
                            .foregroundStyle(TossColor.grey500)
                    }
                }
                .tint(TossColor.blue500)

                keyField(title: "Gemini API 키", text: $geminiKey, hint: "aistudio.google.com/apikey")
                keyField(title: "Groq API 키", text: $groqKey, hint: "console.groq.com/keys")
                keyField(title: "OpenRouter API 키", text: $openrouterKey, hint: "openrouter.ai/keys")

                Text("키는 이 Mac의 config/secrets.json 에만 저장돼요. (권한 600)")
                    .font(.system(size: 13))
                    .foregroundStyle(TossColor.grey500)
            }
            .padding(TossSpace.x5)
            .background(TossColor.white)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func keyField(title: String, text: Binding<String>, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(TossColor.grey900)
            SecureField(hint, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 14, design: .monospaced))
                .padding(12)
                .background(TossColor.grey100)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var local7BBlock: some View {
        VStack(alignment: .leading, spacing: TossSpace.x3) {
            Text("로컬 7B (2순위)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(TossColor.grey500)
            VStack(alignment: .leading, spacing: TossSpace.x3) {
                Toggle(isOn: $useLocal7B) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("로컬 7B 사용 (키 없을 때 기본)")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(TossColor.grey900)
                        Text(
                            model.llmEngine.contains("7b")
                                ? "지금 기본 엔진으로 준비됨"
                                : "설치 필요: scripts/install-llm-field.sh"
                        )
                        .font(.system(size: 14))
                        .foregroundStyle(TossColor.grey500)
                    }
                }
                .tint(TossColor.blue500)
            }
            .padding(TossSpace.x5)
            .background(TossColor.white)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private var retentionBlock: some View {
        VStack(alignment: .leading, spacing: TossSpace.x3) {
            Text("자동 정리")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(TossColor.grey500)

            VStack(alignment: .leading, spacing: TossSpace.x5) {
                Toggle(isOn: $purgeOnLaunch) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("앱 켤 때 정리")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(TossColor.grey900)
                        Text("오래된 중단 녹음을 조용히 지워요")
                            .font(.system(size: 14))
                            .foregroundStyle(TossColor.grey500)
                    }
                }
                .tint(TossColor.blue500)

                stepperRow(
                    title: "중단 녹음 보관",
                    value: $abandonedDays,
                    range: 0...90,
                    unit: "일",
                    zeroLabel: "끄기"
                )

                stepperRow(
                    title: "저장 후 녹음 파일",
                    value: $audioDays,
                    range: 0...180,
                    unit: "일 후 삭제",
                    zeroLabel: "계속 보관"
                )
            }
            .padding(TossSpace.x5)
            .background(TossColor.white)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func stepperRow(
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        unit: String,
        zeroLabel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: TossSpace.x2) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(TossColor.grey900)
            HStack {
                Text(value.wrappedValue == 0 ? zeroLabel : "\(value.wrappedValue)\(unit)")
                    .font(.system(size: 15))
                    .foregroundStyle(TossColor.grey700)
                Spacer()
                Stepper("", value: value, in: range)
                    .labelsHidden()
            }
        }
    }

    private func load() {
        let cfg = AppConfig.load(knowledgeRoot: model.knowledgeRoot)
        abandonedDays = cfg.retentionAbandonedDays
        audioDays = cfg.retentionAudioAfterCommitDays
        purgeOnLaunch = cfg.retentionPurgeOnLaunch
        useLocal7B = cfg.ragUseLlama
        cloudEnabled = cfg.cloudEnabled
        model.refreshVaultConfig()
        LLMProviderCatalog.ensureInstalled(knowledgeRoot: model.knowledgeRoot)
        let secrets = LLMSecrets.load(knowledgeRoot: model.knowledgeRoot)
        // Don't show full keys — only indicate presence; allow overwrite on save
        geminiKey = secrets["gemini_api_key"] != nil ? "••••••••" : ""
        groqKey = secrets["groq_api_key"] != nil ? "••••••••" : ""
        openrouterKey = secrets["openrouter_api_key"] != nil ? "••••••••" : ""
        let st = LLMRouter.status(knowledgeRoot: model.knowledgeRoot)
        llmDetail = st.detail
    }

    private func save() {
        var cfg = AppConfig.load(knowledgeRoot: model.knowledgeRoot)
        cfg.retentionAbandonedDays = abandonedDays
        cfg.retentionAudioAfterCommitDays = audioDays
        cfg.retentionPurgeOnLaunch = purgeOnLaunch
        cfg.ragUseLlama = useLocal7B
        cfg.cloudEnabled = cloudEnabled
        do {
            try cfg.save(knowledgeRoot: model.knowledgeRoot)
            // Merge secrets: keep existing if placeholder bullets
            var secrets = LLMSecrets.load(knowledgeRoot: model.knowledgeRoot)
            func apply(_ key: String, field: String) {
                let t = field.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.isEmpty {
                    secrets.removeValue(forKey: key)
                } else if !t.hasPrefix("••") {
                    secrets[key] = t
                }
            }
            apply("gemini_api_key", field: geminiKey)
            apply("groq_api_key", field: groqKey)
            apply("openrouter_api_key", field: openrouterKey)
            try LLMSecrets.save(secrets, knowledgeRoot: model.knowledgeRoot)
            model.refreshVaultConfig()
            model.refreshLLMStatus()
            let st = LLMRouter.status(knowledgeRoot: model.knowledgeRoot)
            llmDetail = st.detail
            savedFlash = "저장했어요"
            model.appendUILog("settings saved cloud=\(cloudEnabled) local7b=\(useLocal7B) keys=\(secrets.keys.sorted())")
        } catch {
            savedFlash = "저장에 실패했어요"
            model.appendUILog("settings save failed \(error)")
        }
    }
}
