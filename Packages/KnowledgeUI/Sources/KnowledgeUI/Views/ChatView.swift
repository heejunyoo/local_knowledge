import SwiftUI

/// Ask the corpus — conversation first, chrome minimal.
public struct ChatView: View {
    @ObservedObject public var model: AppModel
    @Environment(\.dismiss) private var dismiss
    public var showsBackButton: Bool
    @State private var draft: String = ""
    @FocusState private var focused: Bool

    public init(model: AppModel, showsBackButton: Bool = true) {
        self.model = model
        self.showsBackButton = showsBackButton
    }

    private var suggestions: [String] {
        var out: [String] = []
        if model.corpusMeetingUnits > 0 {
            out.append("최근 미팅에서 결정된 일")
            out.append("할 일로 남은 것")
        }
        if model.corpusNotesUnits > 0 || model.corpusObsidianUnits > 0 {
            out.append("내가 메모해 둔 핵심")
        }
        if out.isEmpty && model.corpusTotalUnits > 0 {
            out = ["핵심 개념 정리", "아직 안 끝낸 일"]
        }
        return Array(out.prefix(3))
    }

    public var body: some View {
        ZStack {
            TossColor.grey100.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                messages
                composer
            }
        }
        .onAppear {
            model.refreshSourceStats()
            focused = model.chatMessages.isEmpty
        }
    }

    private var topBar: some View {
        HStack {
            if showsBackButton {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(TossColor.grey900)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("뒤로")
            } else {
                Color.clear.frame(width: 12, height: 44)
            }
            Text("물어보기")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(TossColor.grey900)
            Spacer()
            Text(engineBadge)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(TossColor.grey500)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(TossColor.white)
                .clipShape(Capsule())
                .padding(.trailing, TossSpace.x3)
                .accessibilityLabel("답변 엔진 \(engineBadge)")
        }
        .padding(.horizontal, TossSpace.x2)
    }

    private var engineBadge: String {
        if model.llmEngine.contains("cloud") { return "클라우드 free" }
        if model.llmEngine.contains("7b") || model.llmEngine.contains("llama") { return "로컬 7B" }
        return "근거 모음"
    }

    // empty body copy clarifies progressive UX

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: TossSpace.x4) {
                    if model.chatMessages.isEmpty {
                        empty
                            .padding(.top, TossSpace.x8)
                    }
                    ForEach(model.chatMessages) { msg in
                        bubble(msg).id(msg.id)
                    }
                    if model.isChatBusy {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(model.chatBusyLabel.isEmpty ? "지식 찾는 중…" : model.chatBusyLabel)
                                .font(.system(size: 14))
                                .foregroundStyle(TossColor.grey500)
                        }
                        .padding(.leading, 4)
                        .id("busy")
                    }
                }
                .padding(.horizontal, TossSpace.x6)
                .padding(.bottom, TossSpace.x4)
            }
            .onChange(of: model.chatMessages.count) { _, _ in
                if let last = model.chatMessages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: model.isChatBusy) { _, busy in
                if busy {
                    withAnimation { proxy.scrollTo("busy", anchor: .bottom) }
                }
            }
            .onChange(of: model.chatMessages.last?.isRefining) { _, _ in
                if let last = model.chatMessages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: TossSpace.x5) {
            TossEmptyState(
                systemImage: model.corpusTotalUnits == 0 ? "tray" : "bubble.left.and.bubble.right",
                title: model.corpusTotalUnits == 0 ? "아직 물어볼 지식이 없어요" : "무엇이 궁금한가요?",
                message: model.corpusTotalUnits == 0
                    ? "회의를 녹음하거나 더보기에서 지식을 연결해 주세요."
                    : "먼저 근거를 보여 주고, 가능하면 문장을 다듬어요."
            )

            if model.corpusTotalUnits > 0, !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: TossSpace.x2) {
                    ForEach(suggestions, id: \.self) { s in
                        Button {
                            draft = s
                            send()
                        } label: {
                            Text(s)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(TossColor.blue500)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(TossColor.white)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, TossSpace.x2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bubble(_ msg: AppModel.ChatMessage) -> some View {
        VStack(alignment: msg.role == .user ? .trailing : .leading, spacing: TossSpace.x2) {
            VStack(alignment: .leading, spacing: 8) {
                Text(msg.text)
                    .font(.system(size: 16))
                    .foregroundStyle(msg.role == .user ? TossColor.white : TossColor.grey900)
                    .textSelection(.enabled)
                if msg.role == .assistant, msg.isRefining {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("다듬는 중… (캐시에 있으면 재호출 없음)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(TossColor.grey500)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(msg.role == .user ? TossColor.blue500 : TossColor.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            if msg.role == .assistant, !msg.engine.isEmpty {
                Text(engineLine(msg.engine))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(TossColor.grey500)
            }

            if !msg.citations.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("출처")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(TossColor.grey500)
                    ForEach(msg.citations.prefix(4)) { c in
                        Button {
                            model.openRAGCitation(c)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(kindLabel(c.sourceType))
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(TossColor.blue500)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(TossColor.blue50)
                                        .clipShape(Capsule())
                                    Text(c.title)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(TossColor.grey900)
                                        .lineLimit(1)
                                }
                                Text(c.snippet)
                                    .font(.system(size: 13))
                                    .foregroundStyle(TossColor.grey500)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(TossColor.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: msg.role == .user ? .trailing : .leading)
    }

    private func kindLabel(_ t: String) -> String {
        switch t {
        case "meeting": return "미팅"
        case "notes": return "Notes"
        case "obsidian": return "노트"
        case "file": return "파일"
        default: return t
        }
    }

    private func engineLine(_ engine: String) -> String {
        var parts: [String] = []
        if engine.contains("cache") { parts.append("캐시 재사용 · 클라우드 재호출 없음") }
        if engine.contains("groq") { parts.append("Groq") }
        if engine.contains("70b") { parts.append("70B") }
        else if engine.contains("8b") { parts.append("8B") }
        else if engine.contains("scout") { parts.append("Scout") }
        if engine.contains("extractive") { parts.append("근거 모음") }
        if engine.contains("local-7b") { parts.append("로컬 7B") }
        if parts.isEmpty { parts.append(engine) }
        return parts.joined(separator: " · ")
    }

    private var composer: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField("메시지 입력", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .font(.system(size: 16))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(TossColor.white)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .focused($focused)
                    .onSubmit { send() }

                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(canSend ? TossColor.blue500 : TossColor.grey200)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .padding(.bottom, 2)
            }
            .padding(.horizontal, TossSpace.x5)
            .padding(.vertical, TossSpace.x3)
            .background(TossColor.grey100)
        }
    }

    private var canSend: Bool {
        !model.isChatBusy && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        let q = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }
        draft = ""
        model.askKnowledge(question: q)
    }
}
