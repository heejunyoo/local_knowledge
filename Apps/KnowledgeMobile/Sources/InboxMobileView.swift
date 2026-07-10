import SwiftUI

struct InboxMobileView: View {
    @EnvironmentObject var core: CoreClient
    @EnvironmentObject var feedback: ActionFeedback
    @State private var items: [[String: Any]] = []
    @State private var draft = ""
    @State private var busy = false
    @State private var actionId: String?
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            KPageBackground()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: KSpace.x4) {
                        Text("빠른 메모를 남기면 Mac vault/inbox 로 보낼 수 있어요.")
                            .font(.system(size: 14))
                            .foregroundStyle(KColor.grey500)

                        if !core.connected {
                            Text("Mac에 연결되지 않았어요. 설정에서 Core를 확인해 주세요.")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(KColor.red500)
                        }

                        if items.isEmpty {
                            KEmptyState(
                                systemImage: "tray",
                                title: "인박스가 비어 있어요",
                                message: "이동 중 생각·할 일을 한 줄로 남겨 보세요"
                            )
                            .padding(.top, 40)
                        } else {
                            ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                                let id = it["id"] as? String ?? ""
                                let text = it["text"] as? String ?? ""
                                KCard {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(text)
                                            .font(.system(size: 15))
                                            .foregroundStyle(KColor.grey900)
                                        HStack {
                                            Button {
                                                Task { await promote(id: id) }
                                            } label: {
                                                if actionId == id {
                                                    ProgressView()
                                                } else {
                                                    Text("vault로 보내기")
                                                        .font(.system(size: 13, weight: .semibold))
                                                }
                                            }
                                            .disabled(id.isEmpty || actionId != nil || !core.connected)
                                            Spacer()
                                            Button("삭제", role: .destructive) {
                                                Task { await deleteItem(id: id) }
                                            }
                                            .font(.system(size: 13))
                                            .disabled(id.isEmpty || actionId != nil)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(KSpace.x6)
                }

                HStack(spacing: 8) {
                    TextField("한 줄 메모", text: $draft, axis: .vertical)
                        .lineLimit(1...3)
                        .focused($focused)
                        .padding(12)
                        .background(KColor.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    Button {
                        Task { await send() }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(
                                (busy || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !core.connected)
                                ? KColor.grey200 : KColor.blue500
                            )
                    }
                    .disabled(busy || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !core.connected)
                    .accessibilityLabel("메모 저장")
                }
                .padding(.horizontal, KSpace.x6)
                .padding(.vertical, KSpace.x4)
                .background(KColor.grey100)
            }
        }
        .navigationTitle("인박스")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func reload() async {
        do {
            items = try await core.inboxList()
        } catch {
            feedback.error("인박스를 불러오지 못했어요: \(error.localizedDescription)")
        }
    }

    private func send() async {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        busy = true
        defer { busy = false }
        do {
            try await core.inboxCreate(text: t)
            draft = ""
            focused = false
            feedback.success("메모를 남겼어요")
            await reload()
        } catch {
            feedback.error("메모 저장 실패: \(error.localizedDescription)")
        }
    }

    private func promote(id: String) async {
        actionId = id
        defer { actionId = nil }
        do {
            try await core.inboxPromote(id: id)
            feedback.success("vault/inbox 로 보냈어요")
            await reload()
        } catch {
            feedback.error("보내기 실패: \(error.localizedDescription)")
        }
    }

    private func deleteItem(id: String) async {
        actionId = id
        defer { actionId = nil }
        do {
            try await core.inboxDelete(id: id)
            feedback.success("삭제했어요")
            await reload()
        } catch {
            feedback.error("삭제 실패: \(error.localizedDescription)")
        }
    }
}

struct WeekReviewMobileView: View {
    @EnvironmentObject var core: CoreClient
    @EnvironmentObject var feedback: ActionFeedback
    @State private var narrative = ""
    @State private var days: [[String: Any]] = []
    @State private var loading = true

    var body: some View {
        ZStack {
            KPageBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: KSpace.x6) {
                    Text("주간 리뷰")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(KColor.grey900)

                    if loading {
                        ProgressView("불러오는 중…")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else if narrative.isEmpty && days.isEmpty {
                        KEmptyState(
                            systemImage: "chart.bar",
                            title: "주간 데이터가 없어요",
                            message: "식단·운동을 기록하면 여기에 요약돼요"
                        )
                        .padding(.top, 24)
                    } else {
                        if !narrative.isEmpty {
                            KCard {
                                Text(narrative)
                                    .font(.system(size: 15))
                                    .foregroundStyle(KColor.grey900)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        if !days.isEmpty {
                            KCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("7일 버킷")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(KColor.grey500)
                                    ForEach(Array(days.enumerated()), id: \.offset) { _, d in
                                        let date = d["date"] as? String ?? ""
                                        let kcal = d["kcal"] as? Double ?? 0
                                        let wo = d["workout_minutes"] as? Int
                                            ?? Int(d["workout_minutes"] as? Double ?? 0)
                                        HStack {
                                            Text(date).font(.system(size: 13)).foregroundStyle(KColor.grey700)
                                            Spacer()
                                            Text("\(Int(kcal)) kcal · \(wo)분")
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundStyle(KColor.grey900)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(KSpace.x6)
            }
        }
        .navigationTitle("주간 리뷰")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let r = try await core.fetchWeekReview()
            narrative = r["narrative"] as? String ?? ""
            days = r["days"] as? [[String: Any]] ?? []
        } catch {
            feedback.error("주간 리뷰를 불러오지 못했어요: \(error.localizedDescription)")
        }
    }
}
