import SwiftUI

public struct ReviewInboxView: View {
    @ObservedObject public var model: AppModel
    @Environment(\.dismiss) private var dismiss

    public init(model: AppModel) {
        self.model = model
    }

    private var reviewItems: [AppModel.MeetingRow] {
        model.meetings.filter { $0.status == "review_needed" }
    }

    private var failedItems: [AppModel.MeetingRow] {
        model.meetings.filter { $0.status.contains("fail") }
    }

    private var committedItems: [AppModel.MeetingRow] {
        model.meetings.filter { $0.status == "committed" }.prefix(5).map { $0 }
    }

    public var body: some View {
        ZStack {
            TossColor.grey50.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text("확인함")
                        .font(TossFont.title())
                        .foregroundStyle(TossColor.grey900)
                    Spacer()
                    Button("닫기") { dismiss() }
                        .font(TossFont.body())
                        .foregroundStyle(TossColor.blue500)
                        .buttonStyle(.plain)
                }
                .padding(TossSpace.x6)

                ScrollView {
                    VStack(alignment: .leading, spacing: TossSpace.x6) {
                        sectionReview
                        sectionFailed
                        if !committedItems.isEmpty {
                            sectionCommitted
                        }
                        Text("확인을 누르면 Obsidian vault에 미팅 노트가 저장돼요.")
                            .font(TossFont.caption())
                            .foregroundStyle(TossColor.grey500)
                    }
                    .padding(.horizontal, TossSpace.x6)
                    .padding(.bottom, TossSpace.x8)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 520)
        .onAppear { model.refresh() }
    }

    private var sectionReview: some View {
        VStack(alignment: .leading, spacing: TossSpace.x3) {
            Text("확인이 필요해요")
                .font(TossFont.section())
                .foregroundStyle(TossColor.grey900)
            if reviewItems.isEmpty {
                TossCard {
                    Text("확인할 미팅이 없어요")
                        .font(TossFont.body())
                        .foregroundStyle(TossColor.grey500)
                }
            } else {
                ForEach(reviewItems) { row in
                    TossCard {
                        VStack(alignment: .leading, spacing: TossSpace.x3) {
                            HStack {
                                Text(row.title)
                                    .font(TossFont.body())
                                    .fontWeight(.semibold)
                                    .foregroundStyle(TossColor.grey900)
                                Spacer()
                                TossBadge("확인 필요", kind: .info)
                            }
                            TossPrimaryButton("확인 후 저장") {
                                model.acceptReview(meetingId: row.id)
                            }
                        }
                    }
                }
            }
        }
    }

    private var sectionFailed: some View {
        VStack(alignment: .leading, spacing: TossSpace.x3) {
            Text("문제가 있었어요")
                .font(TossFont.section())
                .foregroundStyle(TossColor.grey900)
            if failedItems.isEmpty {
                TossCard {
                    Text("실패한 작업이 없어요")
                        .font(TossFont.body())
                        .foregroundStyle(TossColor.grey500)
                }
            } else {
                ForEach(failedItems) { row in
                    TossCard {
                        VStack(alignment: .leading, spacing: TossSpace.x3) {
                            HStack {
                                Text(row.title)
                                    .font(TossFont.body())
                                    .fontWeight(.semibold)
                                    .foregroundStyle(TossColor.grey900)
                                Spacer()
                                TossBadge(StatusCopy.label(row.status), kind: .danger)
                            }
                            if let code = row.errorCode {
                                Text(friendlyError(code))
                                    .font(TossFont.caption())
                                    .foregroundStyle(TossColor.grey500)
                            }
                            TossSecondaryButton("다시 시도") {
                                model.retryMeeting(meetingId: row.id)
                            }
                        }
                    }
                }
            }
        }
    }

    private var sectionCommitted: some View {
        VStack(alignment: .leading, spacing: TossSpace.x3) {
            Text("저장됨")
                .font(TossFont.section())
                .foregroundStyle(TossColor.grey900)
            ForEach(committedItems) { row in
                TossCard {
                    HStack {
                        Text(row.title)
                            .font(TossFont.body())
                            .foregroundStyle(TossColor.grey900)
                        Spacer()
                        TossBadge("저장됨", kind: .neutral)
                    }
                }
            }
        }
    }

    private func friendlyError(_ code: String) -> String {
        switch code {
        case "asr_tools_missing", "asr_binary_missing", "asr_model_missing":
            return "받아쓰기를 시스템 음성 인식으로 다시 시도할 수 있어요"
        case "speech_permission":
            return "시스템 설정에서 음성 인식 권한을 허용해 주세요"
        case "timeout":
            return "시간이 초과됐어요. 다시 시도해 주세요"
        case "stage2_fail", "stage1_fail":
            return "요약 검증에 실패했어요"
        default:
            return code
        }
    }
}
