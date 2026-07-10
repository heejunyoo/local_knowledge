import SwiftUI

struct InboxMobileView: View {
    @EnvironmentObject var core: CoreClient
    @State private var items: [[String: Any]] = []
    @State private var draft = ""
    @State private var busy = false
    @State private var error: String?
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
                                            Button("vault로 보내기") {
                                                Task {
                                                    busy = true
                                                    try? await core.inboxPromote(id: id)
                                                    await reload()
                                                    busy = false
                                                }
                                            }
                                            .font(.system(size: 13, weight: .semibold))
                                            Spacer()
                                            Button("삭제", role: .destructive) {
                                                Task {
                                                    try? await core.inboxDelete(id: id)
                                                    await reload()
                                                }
                                            }
                                            .font(.system(size: 13))
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
                            .foregroundStyle(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? KColor.grey200 : KColor.blue500)
                    }
                    .disabled(busy || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, KSpace.x6)
                .padding(.vertical, KSpace.x4)
                .background(KColor.grey100)
            }
        }
        .navigationTitle("인박스")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload(); LocalNotify.requestAuth() }
        .refreshable { await reload() }
    }

    private func reload() async {
        do {
            items = try await core.inboxList()
            error = nil
        } catch {
            self.error = error.localizedDescription
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
            await reload()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct WeekReviewMobileView: View {
    @EnvironmentObject var core: CoreClient
    @State private var narrative = ""
    @State private var days: [[String: Any]] = []
    @State private var error: String?

    var body: some View {
        ZStack {
            KPageBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: KSpace.x6) {
                    Text("주간 리뷰")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(KColor.grey900)
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
                                    let wo = d["workout_minutes"] as? Int ?? Int(d["workout_minutes"] as? Double ?? 0)
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
                    if let error {
                        Text(error).foregroundStyle(KColor.red500).font(.caption)
                    }
                }
                .padding(KSpace.x6)
            }
        }
        .navigationTitle("주간 리뷰")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                let r = try await core.fetchWeekReview()
                narrative = r["narrative"] as? String ?? ""
                days = r["days"] as? [[String: Any]] ?? []
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
