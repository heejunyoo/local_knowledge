import SwiftUI

// MARK: - Pairing

struct PairingView: View {
    @EnvironmentObject var core: CoreClient
    @State private var code = ""
    @State private var name = UIDevice.current.name
    @State private var busy = false
    @State private var probeBusy = false
    @State private var showScanner = false
    @State private var pasteHint: String?
    @State private var probeLine: String?

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

                    KCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("연결 전 체크")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(KColor.grey500)
                            recoveryStep("1", "Mac에서 Knowledge.app 실행")
                            recoveryStep("2", "Tailscale 켜기 (같은 tailnet)")
                            recoveryStep("3", "Mac 설정 → 모바일 연결 → 코드/QR")
                            recoveryStep("4", "아래 URL이 http://100.x.x.x:8741 형태인지 확인")
                        }
                    }

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

                            Button {
                                Task {
                                    probeBusy = true
                                    let r = await core.probeCoreHealth()
                                    probeLine = r.message
                                    if !r.ok { core.lastError = r.message }
                                    probeBusy = false
                                }
                            } label: {
                                HStack {
                                    if probeBusy { ProgressView() }
                                    Text(probeBusy ? "확인 중…" : "이 주소로 Core 응답 확인")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .foregroundStyle(KColor.blue500)
                            }
                            .disabled(probeBusy || core.baseURL.trimmingCharacters(in: .whitespaces).isEmpty)

                            if let probeLine {
                                Text(probeLine)
                                    .font(.caption)
                                    .foregroundStyle(probeLine.contains("OK") ? KColor.green500 : KColor.grey700)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

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
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    KPrimaryButton(title: busy ? "연결 중…" : "연결하기", enabled: !busy && code.count >= 4 && !core.baseURL.isEmpty) {
                        Task {
                            busy = true
                            await core.completePair(code: code, deviceName: name)
                            busy = false
                            if core.isPaired { kHapticSuccess() }
                            else { kHapticLight() }
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

    private func recoveryStep(_ n: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(n)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(KColor.blue500)
                .frame(width: 18)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(KColor.grey900)
                .fixedSize(horizontal: false, vertical: true)
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

                        if !core.connected && core.isPaired {
                            KCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Mac에 연결되지 않았어요")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(KColor.grey900)
                                    Text("Knowledge.app이 켜져 있는지, Tailscale·Core URL을 확인해 주세요.")
                                        .font(.system(size: 13))
                                        .foregroundStyle(KColor.grey500)
                                        .fixedSize(horizontal: false, vertical: true)
                                    HStack(spacing: 12) {
                                        Button("다시 연결") {
                                            Task { await core.refreshStatus() }
                                        }
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(KColor.blue500)
                                        NavigationLink {
                                            SettingsMobileView()
                                        } label: {
                                            Text("설정 열기")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(KColor.blue500)
                                        }
                                    }
                                }
                            }
                        }

                        // W0 Assistant Hub — body / knowledge / next (one screen)
                        KCard {
                            VStack(alignment: .leading, spacing: 12) {
                                briefingRow(
                                    label: "몸",
                                    text: core.bodyLine.isEmpty ? (core.dietLine.isEmpty ? "아직 오늘 기록이 없어요" : core.dietLine) : core.bodyLine
                                )
                                if core.streakDays > 0 {
                                    Text("연속 \(core.streakDays)일")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(KColor.blue500)
                                        .padding(.leading, 48)
                                }
                                if !core.sleepHint.isEmpty {
                                    Text(core.sleepHint)
                                        .font(.system(size: 12))
                                        .foregroundStyle(KColor.grey500)
                                        .padding(.leading, 48)
                                }
                                Divider()
                                briefingRow(
                                    label: "지식",
                                    text: core.knowledgeLine.isEmpty
                                        ? (core.reviewCount > 0 ? "저장 전 요약 \(core.reviewCount)건" : "확인할 요약 없음")
                                        : core.knowledgeLine
                                )
                                Divider()
                                briefingRow(
                                    label: "다음",
                                    text: core.nextActionLabel.isEmpty
                                        ? (core.dietSuggestTitle.isEmpty ? "기록하거나 물어보세요" : core.dietSuggestTitle)
                                        : core.nextActionLabel
                                )
                            }
                        }

                        if !core.gaps.isEmpty {
                            KCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("빠진 기록")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(KColor.grey500)
                                    ForEach(Array(core.gaps.prefix(4).enumerated()), id: \.offset) { _, g in
                                        let label = g["label"] as? String ?? ""
                                        Button { goDiet = true } label: {
                                            HStack {
                                                Image(systemName: "exclamationmark.circle")
                                                    .foregroundStyle(KColor.blue500)
                                                Text(label)
                                                    .font(.system(size: 14, weight: .medium))
                                                    .foregroundStyle(KColor.grey900)
                                                Spacer()
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }

                        KPrimaryButton(title: primaryTitle, enabled: true) {
                            primaryAction()
                        }

                        if !core.timelinePreview.isEmpty {
                            KCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("오늘")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(KColor.grey500)
                                    ForEach(Array(core.timelinePreview.enumerated()), id: \.offset) { _, ev in
                                        let title = ev["title"] as? String ?? ""
                                        let type = ev["type"] as? String ?? ""
                                        let source = ev["source"] as? String
                                        HStack(spacing: 8) {
                                            Text(timelineGlyph(type))
                                                .font(.system(size: 12))
                                                .foregroundStyle(KColor.grey500)
                                                .frame(width: 36, alignment: .leading)
                                            Text(title)
                                                .font(.system(size: 14))
                                                .foregroundStyle(KColor.grey900)
                                                .lineLimit(1)
                                            if !timelineSourceBadge(source).isEmpty {
                                                Text(timelineSourceBadge(source))
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .foregroundStyle(KColor.blue500)
                                            }
                                        }
                                    }
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
                                    title: "식단",
                                    subtitle: core.dietSuggestSubtitle.isEmpty ? "식사·운동 기록" : core.dietSuggestSubtitle,
                                    systemImage: "fork.knife"
                                ) { goDiet = true }
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

    private func briefingRow(label: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(KColor.blue500)
                .frame(width: 36, alignment: .leading)
            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(KColor.grey900)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func timelineGlyph(_ type: String) -> String {
        switch type {
        case "meal": return "식사"
        case "workout": return "운동"
        case "metric": return "지표"
        case "review": return "확인"
        default: return "·"
        }
    }

    private func timelineSourceBadge(_ source: String?) -> String {
        source == "healthkit" ? "건강" : ""
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
        if core.bodyLine.isEmpty && core.dietLine.isEmpty { return "오늘을 열어 볼까요" }
        return "오늘의 나"
    }

    private var greetingBody: String {
        if core.reviewCount > 0 {
            return "저장 전에 요약 \(core.reviewCount)건을 보면 좋아요."
        }
        if !core.connected {
            return "Mac과 Tailscale이 켜져 있는지 확인해 주세요."
        }
        return "몸·지식·다음 할 일을 한곳에서 이어가요."
    }

    private var primaryTitle: String {
        if core.reviewCount > 0 { return "확인함 열기 (\(core.reviewCount))" }
        if !core.dietSuggestTitle.isEmpty, core.dietLine.contains("없어요") || core.dietLine.isEmpty {
            return core.dietSuggestTitle
        }
        if core.dietLine.isEmpty || core.dietLine.contains("없어요") { return "오늘 식단 남기기" }
        return "지식에 물어보기"
    }

    private func primaryAction() {
        if core.reviewCount > 0 { goReview = true }
        else if core.dietLine.isEmpty || core.dietLine.contains("없어요") || !core.dietSuggestTitle.isEmpty && core.dietSuggestTitle.contains("?") {
            goDiet = true
        } else { goAsk = true }
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
                                    message: "지식·식단을 섞어 물어도 돼요. 예: 「이번 주 단백질이랑 회의 목표」"
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
                status = "답 만드는 중…"
                // Prefer /v1/chat for intent routing (knowledge / diet / mixed) + sources transparency.
                if !core.connected {
                    messages.append(ChatBubble(
                        role: "assistant",
                        text: "Mac에 연결되지 않았어요. 더보기 → 설정에서 Core URL·페어링을 확인해 주세요.",
                        meta: "연결 필요"
                    ))
                } else if let chat = try? await core.chat(message: q), !chat.answer.isEmpty {
                    let src = chat.sources.prefix(4).compactMap { s -> String? in
                        let svc = s["service"] as? String ?? ""
                        let title = s["title"] as? String ?? ""
                        if title.isEmpty { return nil }
                        return svc.isEmpty ? title : "\(svc):\(title)"
                    }.joined(separator: " · ")
                    let meta = [chat.engine.isEmpty ? nil : chat.engine, src.isEmpty ? nil : "출처 \(src)"]
                        .compactMap { $0 }.joined(separator: " · ")
                    messages.append(ChatBubble(role: "assistant", text: chat.answer, meta: meta))
                } else {
                    let full = try await core.ask(q: q)
                    if full.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        messages.append(ChatBubble(
                            role: "assistant",
                            text: "답을 만들지 못했어요. Mac Core와 클라우드 키(설정)를 확인해 주세요.",
                            meta: "빈 응답"
                        ))
                    } else {
                        let cites = full.citations.prefix(3).compactMap { $0["title"] as? String }.joined(separator: " · ")
                        let meta = [full.engine.isEmpty ? nil : full.engine, cites.isEmpty ? nil : "출처 \(cites)"]
                            .compactMap { $0 }.joined(separator: " · ")
                        messages.append(ChatBubble(role: "assistant", text: full.answer, meta: meta))
                    }
                }
            } catch {
                messages.append(ChatBubble(
                    role: "assistant",
                    text: "질문을 처리하지 못했어요.\n\(error.localizedDescription)\nMac 앱이 켜져 있는지 확인해 주세요.",
                    meta: "오류"
                ))
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
    @State private var healthBusy = false
    @State private var probeBusy = false
    @State private var probeLine: String?
    @ObservedObject private var hk = HealthKitBridge.shared

    var body: some View {
        Form {
            Section("Core") {
                TextField("Base URL", text: $core.baseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                LabeledContent("기기", value: core.deviceId.isEmpty ? "—" : String(core.deviceId.prefix(8)) + "…")
                LabeledContent("상태", value: core.connected ? "연결됨 · \(core.coreName.isEmpty ? "Core" : core.coreName)" : "끊김")
                if let err = core.lastError, !core.connected {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(KColor.red500)
                }
            }
            Section("연결 문제 해결") {
                Text("안 될 때 순서대로 확인해 주세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("1. Mac Knowledge.app 실행")
                Text("2. Tailscale 연결")
                Text("3. Mac 설정 → 모바일 연결에서 새 코드")
                Text("4. 아래 「Core 응답 확인」")
                    .font(.subheadline)
                Button {
                    Task {
                        probeBusy = true
                        let r = await core.probeCoreHealth()
                        probeLine = r.message
                        if r.ok {
                            await core.refreshStatus()
                        } else {
                            core.lastError = r.message
                        }
                        probeBusy = false
                    }
                } label: {
                    if probeBusy { ProgressView() } else { Text("Core 응답 확인") }
                }
                .disabled(probeBusy)
                if let probeLine {
                    Text(probeLine)
                        .font(.caption)
                        .foregroundStyle(probeLine.contains("OK") ? KColor.green500 : .secondary)
                }
                Button("연결 새로고침") {
                    Task { await core.refreshStatus() }
                }
            }
            Section("Apple 건강 (W1)") {
                if !hk.isAvailable {
                    Text("이 기기에서 건강 데이터를 쓸 수 없어요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("워치·아이폰 운동·수면·체중을 앱을 열 때 Mac으로 가져와요. 쓰기는 하지 않아요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        Task {
                            healthBusy = true
                            await core.syncHealthKitIfPossible(forceAuth: true)
                            healthBusy = false
                        }
                    } label: {
                        if healthBusy {
                            ProgressView()
                        } else {
                            Text(hk.authorizationRequested ? "건강 다시 동기화" : "건강 연결 · 동기화")
                        }
                    }
                    .disabled(!core.isPaired || healthBusy)
                    if !core.healthSyncLine.isEmpty {
                        Text(core.healthSyncLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let e = hk.lastError, !e.isEmpty {
                        Text(e).font(.caption).foregroundStyle(KColor.red500)
                    }
                }
            }
            Section {
                Button(role: .destructive) {
                    Task {
                        revoking = true
                        await core.revokeRemote()
                        revoking = false
                    }
                } label: {
                    if revoking { ProgressView() } else { Text("페어링 해제 · 다시 연결") }
                }
            } footer: {
                Text("페어링을 해제하면 처음부터 QR/코드로 다시 연결해요.")
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
