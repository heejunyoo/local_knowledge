import SwiftUI

// MARK: - Pairing

struct PairingView: View {
    @EnvironmentObject var core: CoreClient
    @State private var code = ""
    @State private var name = UIDevice.current.name
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Mac에서 게이트웨이를 켠 뒤 6자리 코드를 입력하세요.\n설정 → 모바일 연결, 또는 knowledged --pair")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Section("Core (Tailscale IP)") {
                    TextField("http://100.x.y.z:8741", text: $core.baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
                Section("페어링") {
                    TextField("6자리 코드", text: $code)
                        .keyboardType(.numberPad)
                    TextField("기기 이름", text: $name)
                    Button {
                        Task {
                            busy = true
                            await core.completePair(code: code, deviceName: name)
                            busy = false
                        }
                    } label: {
                        if busy { ProgressView() } else { Text("연결") }
                    }
                    .disabled(code.count < 4 || core.baseURL.isEmpty || busy)
                }
                if let err = core.lastError {
                    Section {
                        Text(err).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Knowledge 연결")
        }
    }
}

// MARK: - Home

struct HomeMobileView: View {
    @EnvironmentObject var core: CoreClient

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Circle()
                            .fill(core.connected ? Color.green : Color.orange)
                            .frame(width: 10, height: 10)
                        Text(core.connected ? "연결됨 · \(core.coreName.isEmpty ? "Core" : core.coreName)" : "연결 확인 중…")
                    }
                }
                Section("확인함") {
                    HStack {
                        Text("저장 대기")
                        Spacer()
                        Text("\(core.reviewCount)")
                            .foregroundStyle(core.reviewCount > 0 ? Color(red: 0.19, green: 0.51, blue: 0.96) : .secondary)
                            .fontWeight(.semibold)
                    }
                }
                if !core.dietLine.isEmpty {
                    Section("오늘 (식단)") {
                        Text(core.dietLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("안내") {
                    Text("물어보기에서 지식·식단을 물어보세요. 답은 Mac Core가 만듭니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("홈")
            .refreshable { await core.refreshStatus() }
            .task { await core.refreshStatus() }
        }
    }
}

// MARK: - Ask

private struct ChatBubble: Identifiable {
    let id = UUID()
    var role: String
    var text: String
    var meta: String
}

struct AskMobileView: View {
    @EnvironmentObject var core: CoreClient
    @State private var draft = ""
    @State private var messages: [ChatBubble] = []
    @State private var busy = false
    @State private var status = ""

    private let accent = Color(red: 0.19, green: 0.51, blue: 0.96)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                messageList
                composer
            }
            .navigationTitle("물어보기")
        }
    }

    private var messageList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if messages.isEmpty {
                    Text("근거를 먼저 보여 주고, 가능하면 AI가 문장을 다듬어요.")
                        .foregroundStyle(.secondary)
                        .padding()
                }
                ForEach(messages) { m in
                    bubbleRow(m)
                }
                if busy {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(status.isEmpty ? "찾는 중…" : status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
            }
            .padding(.vertical)
        }
    }

    private func bubbleRow(_ m: ChatBubble) -> some View {
        let isUser = m.role == "user"
        return HStack {
            if isUser { Spacer(minLength: 40) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(m.text)
                    .padding(12)
                    .background(isUser ? accent : Color(.secondarySystemBackground))
                    .foregroundStyle(isUser ? Color.white : Color.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                if !m.meta.isEmpty {
                    Text(m.meta)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            if !isUser { Spacer(minLength: 40) }
        }
        .padding(.horizontal)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("메시지", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 34))
            }
            .disabled(busy || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
    }

    private func send() {
        let q = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        draft = ""
        messages.append(ChatBubble(role: "user", text: q, meta: ""))
        busy = true
        status = "지식 찾는 중…"
        Task {
            do {
                let fast = try await core.askFast(q: q)
                let meta = fast.engine.isEmpty ? "빠른 답" : fast.engine
                messages.append(ChatBubble(role: "assistant", text: fast.answer, meta: meta))
                status = "AI로 다듬는 중…"
                if let chat = try? await core.chat(message: q),
                   !chat.answer.isEmpty,
                   chat.answer != fast.answer,
                   let last = messages.indices.last,
                   messages[last].role == "assistant" {
                    messages[last].text = chat.answer
                    messages[last].meta = chat.engine.isEmpty ? "다듬음" : chat.engine
                }
            } catch {
                messages.append(ChatBubble(role: "assistant", text: "오류: \(error.localizedDescription)", meta: ""))
            }
            busy = false
            status = ""
        }
    }
}

// MARK: - Search

struct SearchMobileView: View {
    @EnvironmentObject var core: CoreClient
    @State private var q = ""
    @State private var hits: [[String: Any]] = []
    @State private var busy = false
    @State private var err: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("검색", text: $q)
                            .textInputAutocapitalization(.never)
                            .onSubmit { Task { await run() } }
                        if busy { ProgressView() }
                        else {
                            Button("찾기") { Task { await run() } }
                                .disabled(q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                if let err {
                    Section { Text(err).foregroundStyle(.red).font(.caption) }
                }
                ForEach(Array(hits.enumerated()), id: \.offset) { _, h in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(titleOf(h))
                            .font(.headline)
                        Text(snippetOf(h))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
            }
            .navigationTitle("검색")
        }
    }

    private func titleOf(_ h: [String: Any]) -> String {
        h["title"] as? String
            ?? h["doc_title"] as? String
            ?? "(제목 없음)"
    }

    private func snippetOf(_ h: [String: Any]) -> String {
        h["snippet"] as? String
            ?? h["body"] as? String
            ?? h["text"] as? String
            ?? ""
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

// MARK: - Review

struct ReviewMobileView: View {
    @EnvironmentObject var core: CoreClient
    @State private var items: [[String: Any]] = []
    @State private var busy = false
    @State private var err: String?
    @State private var acceptingId: String?

    var body: some View {
        NavigationStack {
            List {
                if let err {
                    Section { Text(err).foregroundStyle(.red).font(.caption) }
                }
                if items.isEmpty && !busy {
                    Section {
                        Text("확인할 요약이 없어요. Mac에서 회의를 처리하면 여기에 나타나요.")
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
                        if let one = m["one_line"] as? String, !one.isEmpty {
                            Text(one).font(.subheadline)
                        }
                        Button {
                            Task { await accept(id: id) }
                        } label: {
                            if acceptingId == id {
                                ProgressView()
                            } else {
                                Text("노트에 저장")
                                    .fontWeight(.semibold)
                            }
                        }
                        .disabled(id.isEmpty || acceptingId != nil)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("확인함")
            .refreshable { await load() }
            .overlay {
                if busy && items.isEmpty { ProgressView() }
            }
            .task { await load() }
        }
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

// MARK: - Settings

struct SettingsMobileView: View {
    @EnvironmentObject var core: CoreClient
    @State private var revoking = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Core") {
                    TextField("Base URL", text: $core.baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    LabeledContent("기기", value: core.deviceId.isEmpty ? "—" : String(core.deviceId.prefix(8)) + "…")
                    LabeledContent("상태", value: core.connected ? "연결됨" : "끊김")
                    LabeledContent("Core 이름", value: core.coreName.isEmpty ? "—" : core.coreName)
                }
                Section {
                    Button("연결 상태 새로고침") {
                        Task { await core.refreshStatus() }
                    }
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
                Section("안내") {
                    Text("Free Apple ID는 약 7일마다 재설치가 필요할 수 있어요. 데이터는 Mac에 있습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let err = core.lastError {
                    Section { Text(err).foregroundStyle(.red) }
                }
            }
            .navigationTitle("설정")
        }
    }
}
