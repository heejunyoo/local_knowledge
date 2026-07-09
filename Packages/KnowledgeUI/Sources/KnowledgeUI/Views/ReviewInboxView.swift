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
                        section(
                            title: "확인이 필요해요",
                            empty: "확인할 미팅이 없어요",
                            items: reviewItems,
                            kind: .info
                        )
                        section(
                            title: "문제가 있었어요",
                            empty: "실패한 작업이 없어요",
                            items: failedItems,
                            kind: .danger
                        )
                        Text("요약 수정·vault 저장은 다음 단계에서 이어져요.")
                            .font(TossFont.caption())
                            .foregroundStyle(TossColor.grey500)
                    }
                    .padding(.horizontal, TossSpace.x6)
                    .padding(.bottom, TossSpace.x8)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 480)
        .onAppear { model.refresh() }
    }

    private func section(
        title: String,
        empty: String,
        items: [AppModel.MeetingRow],
        kind: TossBadge.Kind
    ) -> some View {
        VStack(alignment: .leading, spacing: TossSpace.x3) {
            Text(title)
                .font(TossFont.section())
                .foregroundStyle(TossColor.grey900)
            if items.isEmpty {
                TossCard {
                    Text(empty)
                        .font(TossFont.body())
                        .foregroundStyle(TossColor.grey500)
                }
            } else {
                ForEach(items) { row in
                    TossCard {
                        VStack(alignment: .leading, spacing: TossSpace.x2) {
                            HStack {
                                Text(row.title)
                                    .font(TossFont.body())
                                    .fontWeight(.semibold)
                                    .foregroundStyle(TossColor.grey900)
                                Spacer()
                                TossBadge(StatusCopy.label(row.status), kind: kind)
                            }
                            if let code = row.errorCode {
                                Text(code)
                                    .font(TossFont.caption())
                                    .foregroundStyle(TossColor.grey500)
                            }
                        }
                    }
                }
            }
        }
    }
}
