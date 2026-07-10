import SwiftUI

/// Review inbox — focus on what needs a decision, with structured summary cards.
public struct ReviewInboxView: View {
    @ObservedObject public var model: AppModel
    @Environment(\.dismiss) private var dismiss

    public init(model: AppModel) {
        self.model = model
    }

    private var pending: [AppModel.MeetingRow] {
        model.meetings.filter { $0.status == "review_needed" }
    }

    private var failed: [AppModel.MeetingRow] {
        model.meetings.filter { $0.status.contains("fail") }
    }

    public var body: some View {
        ZStack(alignment: .top) {
            TossColor.grey100.ignoresSafeArea()
            VStack(spacing: 0) {
                nav
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: TossSpace.x6) {
                        title
                        if pending.isEmpty && failed.isEmpty {
                            TossEmptyState(
                                systemImage: "checkmark.circle",
                                title: "확인할 일이 없어요",
                                message: "녹음이 끝나면 요약이 여기로 와요. 홈에서 녹음을 시작해 보세요."
                            )
                            .padding(.top, TossSpace.x4)
                        }
                        ForEach(pending) { row in
                            pendingCard(row)
                        }
                        ForEach(failed) { row in
                            failedCard(row)
                        }
                        if let rel = model.lastVaultRel {
                            Button("방금 저장한 노트 보기") {
                                model.openMeetingInFinder(vaultRel: rel)
                            }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(TossColor.blue500)
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, TossSpace.x6)
                    .padding(.bottom, TossSpace.x8)
                }
            }
            if !model.statusMessage.isEmpty {
                TossToastBanner(
                    message: model.statusMessage,
                    isError: model.statusMessage.contains("못")
                        || model.statusMessage.contains("실패")
                        || model.lastError != nil,
                    onDismiss: { model.statusMessage = "" }
                )
                .padding(.horizontal, TossSpace.x6)
                .padding(.top, TossSpace.x2)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(20)
            }
        }
        .animation(TossMotion.soft, value: model.statusMessage)
        .onAppear { model.refresh() }
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

    private var title: some View {
        VStack(alignment: .leading, spacing: TossSpace.x3) {
            Text(pending.isEmpty ? "확인함" : "확인이 필요해요")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(TossColor.grey900)
            Text(pending.isEmpty
                 ? "지금은 볼 일이 없어요."
                 : "저장하면 노트에 남고, 물어보기에도 쓰여요.")
                .font(.system(size: 17))
                .foregroundStyle(TossColor.grey700)
                .lineSpacing(3)
        }
    }

    private func pendingCard(_ row: AppModel.MeetingRow) -> some View {
        let display = MeetingSummaryLoader.load(
            knowledgeRoot: model.knowledgeRoot,
            candidateRel: row.candidatePath
        )
        return VStack(alignment: .leading, spacing: TossSpace.x5) {
            Text(row.title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(TossColor.grey900)

            if let display, !display.isEmpty {
                if !display.oneLine.isEmpty {
                    Text(display.oneLine)
                        .font(.system(size: 16))
                        .foregroundStyle(TossColor.grey700)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                sectionBlock(title: "이야기한 것", items: display.discussion)
                sectionBlock(title: "결정", items: display.decisions)
                sectionBlock(title: "할 일", items: display.actions)
                sectionBlock(title: "남은 이슈", items: display.open)
            } else if let one = row.oneLine, !one.isEmpty {
                Text(one)
                    .font(.system(size: 16))
                    .foregroundStyle(TossColor.grey700)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("요약을 불러오지 못했어요. 그래도 저장할 수 있어요.")
                    .font(.system(size: 15))
                    .foregroundStyle(TossColor.grey500)
            }

            TossPrimaryButton("저장하기") {
                model.acceptReview(meetingId: row.id)
            }
        }
        .padding(TossSpace.x5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TossColor.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private func sectionBlock(title: String, items: [String]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: TossSpace.x2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TossColor.grey500)
                ForEach(Array(items.prefix(6).enumerated()), id: \.offset) { _, text in
                    HStack(alignment: .top, spacing: TossSpace.x2) {
                        Text("·")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(TossColor.blue500)
                        Text(text)
                            .font(.system(size: 15))
                            .foregroundStyle(TossColor.grey900)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if items.count > 6 {
                    Text("외 \(items.count - 6)개")
                        .font(.system(size: 13))
                        .foregroundStyle(TossColor.grey500)
                }
            }
            .padding(.top, TossSpace.x1)
        }
    }

    private func failedCard(_ row: AppModel.MeetingRow) -> some View {
        VStack(alignment: .leading, spacing: TossSpace.x4) {
            Text(row.title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(TossColor.grey900)
            Text("처리 중 문제가 생겼어요.")
                .font(.system(size: 15))
                .foregroundStyle(TossColor.grey500)
            TossSecondaryButton("다시 시도") {
                model.retryMeeting(meetingId: row.id)
            }
            Button("삭제하기") {
                model.deleteMeeting(id: row.id)
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(TossColor.grey500)
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        }
        .padding(TossSpace.x5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TossColor.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
