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
    @State private var pairCode: String?
    @State private var pairExpires: Int = 0
    @State private var pairError: String?
    @State private var pairBusy = false
    @State private var coreURL: String = ""
    @State private var coreURLNote: String = ""
    @State private var lanURL: String = ""
    @State private var gatewayLive: Bool = false
    @State private var copiedFlash: String?
    @State private var gatewayPort: UInt16 = 8741

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
                        mobilePairBlock
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

    private var mobilePairBlock: some View {
        VStack(alignment: .leading, spacing: TossSpace.x3) {
            Text("모바일 연결")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(TossColor.grey500)
            VStack(alignment: .leading, spacing: TossSpace.x5) {
                Text("아이폰 Knowledge 앱에 아래를 그대로 입력하세요.")
                    .font(.system(size: 14))
                    .foregroundStyle(TossColor.grey700)
                    .fixedSize(horizontal: false, vertical: true)

                // 1) Core URL — primary value for the phone
                VStack(alignment: .leading, spacing: TossSpace.x2) {
                    HStack(spacing: 8) {
                        Text("① Core URL (아이폰에 붙여넣기)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(TossColor.grey500)
                        Spacer()
                        HStack(spacing: 4) {
                            Circle()
                                .fill(gatewayLive ? TossColor.green500 : Color.orange.opacity(0.85))
                                .frame(width: 8, height: 8)
                            Text(gatewayLive ? "게이트웨이 ON" : "게이트웨이 확인 중…")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(TossColor.grey500)
                        }
                    }

                    Text(coreURL.isEmpty ? "불러오는 중…" : coreURL)
                        .font(.system(size: 17, weight: .semibold, design: .monospaced))
                        .foregroundStyle(TossColor.grey900)
                        .textSelection(.enabled)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(TossColor.blue50)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    if !coreURLNote.isEmpty {
                        Text(coreURLNote)
                            .font(.system(size: 12))
                            .foregroundStyle(TossColor.grey500)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !lanURL.isEmpty, lanURL != coreURL {
                        Text("같은 Wi‑Fi만 쓸 때: \(lanURL)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(TossColor.grey500)
                            .textSelection(.enabled)
                    }

                    HStack(spacing: TossSpace.x4) {
                        Button {
                            copyToPasteboard(coreURL)
                            copiedFlash = "Core URL 복사됨"
                        } label: {
                            Text("Core URL 복사")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(TossColor.blue500)
                        }
                        .buttonStyle(.plain)
                        .disabled(coreURL.isEmpty || coreURL.contains("<"))

                        Button {
                            refreshCoreConnectionInfo()
                        } label: {
                            Text("주소 새로고침")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(TossColor.grey700)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider().overlay(TossColor.grey200)

                // 2) Pair code
                VStack(alignment: .leading, spacing: TossSpace.x2) {
                    Text("② 페어링 코드 (6자리)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(TossColor.grey500)

                    if let pairCode {
                        HStack(alignment: .firstTextBaseline, spacing: TossSpace.x4) {
                            Text(pairCode)
                                .font(.system(size: 40, weight: .bold, design: .monospaced))
                                .foregroundStyle(TossColor.blue500)
                                .textSelection(.enabled)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(pairExpires)초 유효 · 1회용")
                                    .font(.system(size: 13))
                                    .foregroundStyle(TossColor.grey500)
                                Button {
                                    copyToPasteboard(pairCode)
                                    copiedFlash = "코드 복사됨"
                                } label: {
                                    Text("코드 복사")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(TossColor.blue500)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } else {
                        Text("아래 버튼으로 코드를 만드세요.")
                            .font(.system(size: 14))
                            .foregroundStyle(TossColor.grey500)
                    }
                }

                if let copiedFlash {
                    Text(copiedFlash)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(TossColor.green500)
                }

                if let pairError {
                    Text(pairError)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.red.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    Task { await requestPairCode() }
                } label: {
                    HStack {
                        if pairBusy { ProgressView().controlSize(.small) }
                        Text(pairCode == nil ? "페어링 코드 만들기" : "새 코드 만들기")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(TossColor.blue500)
                }
                .buttonStyle(.plain)
                .disabled(pairBusy)

                Text("아이폰: Core URL 붙여넣기 → 코드 입력 → 연결. 집 밖에서는 Tailscale이 켜져 있어야 해요.")
                    .font(.system(size: 12))
                    .foregroundStyle(TossColor.grey500)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(TossSpace.x5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TossColor.white)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .onAppear { refreshCoreConnectionInfo() }
    }

    private func copyToPasteboard(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    private func refreshCoreConnectionInfo() {
        let port = gatewayPort
        let tsIP = Self.resolveTailscaleIPv4()
        let lanIP = Self.resolveLANIPv4()

        if let tsIP, !tsIP.isEmpty {
            coreURL = "http://\(tsIP):\(port)"
            coreURLNote = "Tailscale 주소예요. 집 안·밖 모두 이 값을 쓰면 됩니다. (Mac·iPhone 둘 다 Tailscale 로그인)"
        } else if let lanIP, !lanIP.isEmpty {
            coreURL = "http://\(lanIP):\(port)"
            coreURLNote = "Tailscale IP를 못 찾아서 집 Wi‑Fi 주소를 넣었어요. 집 밖에서는 Tailscale을 켠 뒤 「주소 새로고침」을 누르세요."
        } else {
            coreURL = "http://<Mac-IP>:\(port)"
            coreURLNote = "IP를 자동으로 못 찾았어요. Tailscale 앱에서 Mac IP(100.x.x.x)를 확인한 뒤 http://그IP:\(port) 형식으로 입력하세요."
        }

        if let lanIP, !lanIP.isEmpty {
            lanURL = "http://\(lanIP):\(port)"
        } else {
            lanURL = ""
        }

        gatewayLive = DaemonSupervisor(knowledgeRoot: model.knowledgeRoot).probeHTTP(port: port)
    }

    /// Prefer Tailscale CLI / app binary.
    private static func resolveTailscaleIPv4() -> String? {
        let candidates: [[String]] = [
            ["tailscale", "ip", "-4"],
            ["/Applications/Tailscale.app/Contents/MacOS/Tailscale", "ip", "-4"],
            ["/usr/local/bin/tailscale", "ip", "-4"],
            ["\(NSHomeDirectory())/Applications/Tailscale.app/Contents/MacOS/Tailscale", "ip", "-4"],
        ]
        for args in candidates {
            guard let bin = args.first else { continue }
            let executable: String
            let arguments: [String]
            if bin.hasPrefix("/") {
                guard FileManager.default.isExecutableFile(atPath: bin) else { continue }
                executable = bin
                arguments = Array(args.dropFirst())
            } else {
                executable = "/usr/bin/env"
                arguments = args
            }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: executable)
            p.arguments = arguments
            let out = Pipe()
            p.standardOutput = out
            p.standardError = Pipe()
            do {
                try p.run()
                p.waitUntilExit()
                let data = out.fileHandleForReading.readDataToEndOfFile()
                if let ip = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .split(separator: "\n").first.map(String.init),
                   !ip.isEmpty,
                   ip.contains(".") {
                    return ip
                }
            } catch {
                continue
            }
        }
        return nil
    }

    private static func resolveLANIPv4() -> String? {
        for iface in ["en0", "en1", "en2"] {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/ipconfig")
            p.arguments = ["getifaddr", iface]
            let out = Pipe()
            p.standardOutput = out
            p.standardError = Pipe()
            do {
                try p.run()
                p.waitUntilExit()
                let data = out.fileHandleForReading.readDataToEndOfFile()
                if let ip = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !ip.isEmpty {
                    return ip
                }
            } catch {
                continue
            }
        }
        return nil
    }

    private func requestPairCode() async {
        pairBusy = true
        pairError = nil
        copiedFlash = nil
        defer { pairBusy = false }

        // Old daemons often run without --http-port; bring gateway up first.
        let root = model.knowledgeRoot
        let port = gatewayPort
        let gatewayOK = await Task.detached(priority: .userInitiated) {
            DaemonSupervisor(knowledgeRoot: root).ensureMobileGateway(port: port, timeout: 12)
        }.value

        refreshCoreConnectionInfo()

        if !gatewayOK {
            pairError = "모바일 게이트웨이를 켜지 못했어요. 앱을 완전히 종료한 뒤 다시 열어 주세요."
            pairCode = nil
            gatewayLive = false
            return
        }
        gatewayLive = true

        let url = URL(string: "http://127.0.0.1:\(gatewayPort)/v1/pair/start")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("{}".utf8)
        req.timeoutInterval = 5
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            if code == 200, let c = obj["code"] as? String {
                pairCode = c
                pairExpires = obj["expires_in"] as? Int ?? 300
                pairError = nil
                refreshCoreConnectionInfo()
            } else {
                pairError = (obj["error"] as? String)
                    ?? "게이트웨이에 연결할 수 없어요. (HTTP \(code))"
                pairCode = nil
            }
        } catch {
            pairError = "게이트웨이 응답 없음 — 잠시 후 다시 시도해 주세요. (\(error.localizedDescription))"
            pairCode = nil
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
                                ? "빠른 근거 답 먼저 → 이어서 7B로 다듬기 (첫 실행 느릴 수 있음)"
                                : "설치 필요: scripts/install-llm-field.sh · 없어도 빠른 근거 답은 가능"
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
