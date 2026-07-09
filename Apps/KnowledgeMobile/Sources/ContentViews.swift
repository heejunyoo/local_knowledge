import SwiftUI

// MARK: - Pairing

struct PairingView: View {
    @EnvironmentObject var core: CoreClient
    @State private var code = ""
    @State private var name = UIDevice.current.name
    @State private var busy = false
    @State private var showScanner = false
    @State private var pasteHint: String?

    var body: some View {
        ZStack {
            KPageBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: KSpace.x6) {
                    Text("Knowledge 연결")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(KColor.grey900)
                        .padding(.top, KSpace.x8)

                    Text("Mac 설정 → 모바일 연결에서 QR을 스캔하거나, 주소·코드를 입력하세요.")
                        .font(.system(size: 15))
                        .foregroundStyle(KColor.grey700)
                        .fixedSize(horizontal: false, vertical: true)

                    KPrimaryButton(title: "QR 스캔으로 채우기") {
                        showScanner = true
                    }

                    Button {
                        applyPasteboard()
                    } label: {
                        Text("클립보드에서 연결 정보 붙여넣기")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(KColor.blue500)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(KColor.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    if let pasteHint {
                        Text(pasteHint)
                            .font(.caption)
                            .foregroundStyle(KColor.grey500)
                    }

                    KCard {
                        VStack(alignment: .leading, spacing: KSpace.x4) {
                            fieldLabel("Core URL")
                            TextField("http://100.x.x.x:8741", text: $core.baseURL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                                .padding(12)
                                .background(KColor.grey100)
                                .clipShape(RoundedRectangle(cornerRadius: 12))

                            fieldLabel("페어링 코드")
                            TextField("6자리", text: $code)
                                .keyboardType(.numberPad)
                                .padding(12)
                                .background(KColor.grey100)
                                .clipShape(RoundedRectangle(cornerRadius: 12))

                            fieldLabel("이 기기 이름")
                            TextField("iPhone", text: $name)
                                .padding(12)
                                .background(KColor.grey100)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }

                    if let err = core.lastError {
                        Text(err)
                            .font(.system(size: 14))
                            .foregroundStyle(KColor.red500)
                    }

                    KPrimaryButton(title: busy ? "연결 중…" : "연결하기", enabled: !busy && code.count >= 4 && !core.baseURL.isEmpty) {
                        Task {
                            busy = true
                            await core.completePair(code: code, deviceName: name)
                            busy = false
                            if core.isPaired { kHapticSuccess() }
                        }
                    }
                }
                .padding(.horizontal, KSpace.x6)
                .padding(.bottom, KSpace.x8)
            }
        }
        .fullScreenCover(isPresented: $showScanner) {
            QRScannerView(
                onCode: { value in
                    showScanner = false
                    applyPayload(value)
                },
                onClose: { showScanner = false }
            )
            .ignoresSafeArea()
        }
    }

    private func fieldLabel(_ t: String) -> some View {
        Text(t)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(KColor.grey500)
    }

    private func applyPasteboard() {
        guard let s = UIPasteboard.general.string else {
            pasteHint = "클립보드가 비어 있어요"
            return
        }
        applyPayload(s)
    }

    private func applyPayload(_ s: String) {
        if let p = PairingPayload.parse(s) {
            core.baseURL = p.coreURL
            code = p.code
            pasteHint = "QR/붙여넣기 정보를 채웠어요. 연결하기를 누르세요."
            kHapticLight()
        } else if s.lowercased().hasPrefix("http") {
            core.baseURL = s.trimmingCharacters(in: .whitespacesAndNewlines)
            pasteHint = "주소만 채웠어요. 코드도 입력해 주세요."
        } else {
            pasteHint = "인식할 수 없는 형식이에요. Mac에서 QR을 다시 확인하세요."
        }
    }
}

// MARK: - Home

struct HomeMobileView: View {
    @EnvironmentObject var core: CoreClient
    @State private var goReview = false
    @State private var goDiet = false
    @State private var goAsk = false

    var body: some View {
        NavigationStack {
            ZStack {
                KPageBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: KSpace.x6) {
                        VStack(alignment: .leading, spacing: KSpace.x2) {
                            Text(greetingTitle)
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(KColor.grey900)
                            Text(greetingBody)
                                .font(.system(size: 16))
                                .foregroundStyle(KColor.grey700)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, KSpace.x4)

                        connectionChip

                        KPrimaryButton(title: primaryTitle, enabled: true) {
                            primaryAction()
                        }

                        if !core.dietLine.isEmpty {
                            KCard {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("오늘 식단")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(KColor.grey500)
                                    Text(core.dietLine)
                                        .font(.system(size: 15))
                                        .foregroundStyle(KColor.grey900)
                                }
                            }
                        }

                        KCard(padded: false) {
                            VStack(spacing: 0) {
                                KListRow(
                                    title: "확인함",
                                    subtitle: core.reviewCount > 0 ? "저장 대기 \(core.reviewCount)건" : "비어 있어요",
                                    systemImage: "checkmark.circle.fill",
                                    trailing: core.reviewCount > 0 ? "\(core.reviewCount)" : nil
                                ) { goReview = true }
                                Divider().padding(.leading, 56)
                                KListRow(
                                    title: "물어보기",
                                    subtitle: "지식에 질문",
                                    systemImage: "bubble.left.and.bubble.right.fill"
                                ) { goAsk = true }
                            }
                            .padding(.horizontal, KSpace.x4)
                        }
                    }
                    .padding(.horizontal, KSpace.x6)
                    .padding(.bottom, KSpace.x8)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await core.refreshStatus() }
            .task { await core.refreshStatus() }
            .navigationDestination(isPresented: $goReview) { ReviewMobileView() }
            .navigationDestination(isPresented: $goDiet) { DietMobileView() }
            .navigationDestination(isPresented: $goAsk) { AskMobileView() }
        }
    }

    private var connectionChip: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(core.connected ? KColor.green500 : Color.orange)
                .frame(width: 8, height: 8)
            Text(core.connected ? "Mac 연결됨" : "연결 확인 중…")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(KColor.grey700)
            if !core.coreName.isEmpty {
                Text("· \(core.coreName)")
                    .font(.system(size: 13))
                    .foregroundStyle(KColor.grey500)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(KColor.white)
        .clipShape(Capsule())
    }

    private var greetingTitle: String {
        if core.reviewCount > 0 { return "확인할 게 있어요" }
        if !core.connected { return "연결을 확인해요" }
        if core.dietLine.isEmpty { return "오늘도 남겨 볼까요" }
        return "준비됐어요"
    }

    private var greetingBody: String {
        if core.reviewCount > 0 {
            return "저장 전에 요약 \(core.reviewCount)건을 보면 좋아요."
        }
        if !core.connected {
            return "Mac과 Tailscale이 켜져 있는지 확인해 주세요."
        }
        return "녹음은 Mac에서, 질문·식단은 여기서 이어가요."
    }

    private var primaryTitle: String {
        if core.reviewCount > 0 { return "확인함 열기 (\(core.reviewCount))" }
        if core.dietLine.isEmpty { return "오늘 식단 남기기" }
        return "지식에 물어보기"
    }

    private func primaryAction() {
        if core.reviewCount > 0 { goReview = true }
        else if core.dietLine.isEmpty { goDiet = true }
        else { goAsk = true }
    }
}

// MARK: - Ask

struct AskMobileView: View {
    @EnvironmentObject var core: CoreClient
    @State private var draft = ""
    @State private var messages: [ChatBubble] = []
    @State private var busy = false
    @State private var status = ""
    @FocusState private var composerFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if messages.isEmpty {
                                KEmptyState(
                                    systemImage: "bubble.left.and.bubble.right",
                                    title: "무엇이 궁금한가요?",
                                    message: "지식에서 찾아 답해요. 보내기 후 키보드는 자동으로 닫혀요."
                                )
                            }
                            ForEach(messages) { m in
                                bubble(m).id(m.id)
                            }
                            if busy {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text(status.isEmpty ? "답하는 중…" : status)
                                        .font(.caption)
                                        .foregroundStyle(KColor.grey500)
                                }
                                .padding()
                                .id("busy")
                            }
                        }
                        .padding(.vertical)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture { dismissKeyboard() }
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                    .onChange(of: busy) { _, on in
                        if on { withAnimation { proxy.scrollTo("busy", anchor: .bottom) } }
                    }
                }
                composerBar
            }
            .background(KColor.grey100)
            .navigationTitle("물어보기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("완료") { dismissKeyboard() }
                        .fontWeight(.semibold)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if composerFocused {
                        Button("키보드 닫기") { dismissKeyboard() }
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
            // Tab bar stays usable when keyboard is up
            .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 0) }
        }
    }

    private var composerBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("메시지", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .focused($composerFocused)
                .padding(12)
                .background(KColor.grey100)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .submitLabel(.send)
                .onSubmit { send() }
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(KColor.blue500)
            }
            .disabled(busy || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("보내기")
        }
        .padding()
        .background(KColor.white)
    }

    private func dismissKeyboard() {
        composerFocused = false
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }

    private func bubble(_ m: ChatBubble) -> some View {
        let isUser = m.role == "user"
        return HStack {
            if isUser { Spacer(minLength: 40) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(m.text)
                    .padding(12)
                    .background(isUser ? KColor.blue500 : KColor.white)
                    .foregroundStyle(isUser ? Color.white : KColor.grey900)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                if !m.meta.isEmpty {
                    Text(m.meta).font(.caption2).foregroundStyle(KColor.grey500)
                }
            }
            if !isUser { Spacer(minLength: 40) }
        }
        .padding(.horizontal)
    }

    private func send() {
        let q = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        draft = ""
        dismissKeyboard()
        kHapticLight()
        messages.append(ChatBubble(role: "user", text: q, meta: ""))
        busy = true
        status = "지식 찾는 중…"
        Task {
            do {
                // Single full path (cloud refine first on Mac) — avoid flashing garbage extractive as final.
                status = "답 만드는 중…"
                let full = try await core.ask(q: q)
                var answer = full.answer
                var engine = full.engine
                // If still extractive-only, try chat refine once more (knowledge mode).
                if engine.contains("extractive"), let chat = try? await core.chat(message: q),
                   !chat.answer.isEmpty, chat.answer != answer, !chat.engine.contains("extractive") {
                    answer = chat.answer
                    engine = chat.engine
                }
                let cites = full.citations.prefix(3).compactMap { $0["title"] as? String }.joined(separator: " · ")
                let meta = [engine.isEmpty ? nil : engine, cites.isEmpty ? nil : "출처 \(cites)"]
                    .compactMap { $0 }.joined(separator: " · ")
                messages.append(ChatBubble(role: "assistant", text: answer, meta: meta))
            } catch {
                messages.append(ChatBubble(role: "assistant", text: "오류: \(error.localizedDescription)", meta: ""))
            }
            busy = false
            status = ""
            dismissKeyboard()
        }
    }
}

private struct ChatBubble: Identifiable {
    let id = UUID()
    var role: String
    var text: String
    var meta: String
}

// MARK: - Search / Review / Settings (More)

struct SearchMobileView: View {
    @EnvironmentObject var core: CoreClient
    @State private var q = ""
    @State private var hits: [[String: Any]] = []
    @State private var busy = false
    @State private var err: String?

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("검색", text: $q)
                        .textInputAutocapitalization(.never)
                        .onSubmit { Task { await run() } }
                    if busy { ProgressView() }
                    else {
                        Button("찾기") { Task { await run() } }
                            .disabled(q.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            if let err {
                Section { Text(err).foregroundStyle(KColor.red500).font(.caption) }
            }
            ForEach(Array(hits.enumerated()), id: \.offset) { _, h in
                VStack(alignment: .leading, spacing: 4) {
                    Text(h["title"] as? String ?? h["doc_title"] as? String ?? "(제목 없음)")
                        .font(.headline)
                    Text(h["snippet"] as? String ?? h["body"] as? String ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
        }
        .navigationTitle("검색")
    }

    private func run() async {
        busy = true
        err = nil
        defer { busy = false }
        do {
            hits = try await core.search(q: q)
            if hits.isEmpty { err = "결과 없음" }
        } catch {
            hits = []
            err = error.localizedDescription
        }
    }
}

struct ReviewMobileView: View {
    @EnvironmentObject var core: CoreClient
    @State private var items: [[String: Any]] = []
    @State private var busy = false
    @State private var err: String?
    @State private var acceptingId: String?

    var body: some View {
        List {
            if let err {
                Section { Text(err).foregroundStyle(KColor.red500).font(.caption) }
            }
            if items.isEmpty && !busy {
                Section {
                    Text("확인할 요약이 없어요.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(Array(items.enumerated()), id: \.offset) { _, m in
                let id = (m["id"] as? String) ?? ""
                VStack(alignment: .leading, spacing: 8) {
                    Text((m["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "제목 없음")
                        .font(.headline)
                    Text(m["status"] as? String ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        Task { await accept(id: id) }
                    } label: {
                        if acceptingId == id { ProgressView() }
                        else { Text("노트에 저장").fontWeight(.semibold) }
                    }
                    .disabled(id.isEmpty || acceptingId != nil)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("확인함")
        .refreshable { await load() }
        .overlay { if busy && items.isEmpty { ProgressView() } }
        .task { await load() }
    }

    private func load() async {
        busy = true
        err = nil
        defer { busy = false }
        do {
            items = try await core.reviewList()
            core.reviewCount = items.count
        } catch {
            err = error.localizedDescription
        }
    }

    private func accept(id: String) async {
        acceptingId = id
        defer { acceptingId = nil }
        do {
            try await core.reviewAccept(id: id)
            await load()
        } catch {
            err = error.localizedDescription
        }
    }
}

struct SettingsMobileView: View {
    @EnvironmentObject var core: CoreClient
    @State private var revoking = false

    var body: some View {
        Form {
            Section("Core") {
                TextField("Base URL", text: $core.baseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                LabeledContent("기기", value: core.deviceId.isEmpty ? "—" : String(core.deviceId.prefix(8)) + "…")
                LabeledContent("상태", value: core.connected ? "연결됨" : "끊김")
            }
            Section {
                Button("연결 새로고침") { Task { await core.refreshStatus() } }
                Button(role: .destructive) {
                    Task {
                        revoking = true
                        await core.revokeRemote()
                        revoking = false
                    }
                } label: {
                    if revoking { ProgressView() } else { Text("페어링 해제") }
                }
            }
            Section {
                Text("데이터는 Mac에 있어요. Free 계정은 약 7일마다 재설치가 필요할 수 있어요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let err = core.lastError {
                Section { Text(err).foregroundStyle(KColor.red500) }
            }
        }
        .navigationTitle("설정")
    }
}
