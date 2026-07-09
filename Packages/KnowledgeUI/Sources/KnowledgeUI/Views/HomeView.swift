import SwiftUI

public struct HomeView: View {
    @ObservedObject public var model: AppModel
    @State private var showReview = false

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        ZStack {
            TossColor.grey50.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: TossSpace.x6) {
                    header
                    statusCard
                    recordCard
                    listCard
                    footerHint
                }
                .padding(TossSpace.x6)
            }
        }
        .frame(minWidth: 380, idealWidth: 400, minHeight: 520)
        .onAppear { model.startPolling() }
        .onDisappear { model.stopPolling() }
        .sheet(isPresented: $showReview) {
            ReviewInboxView(model: model)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: TossSpace.x2) {
            Text("Knowledge")
                .font(TossFont.title())
                .foregroundStyle(TossColor.grey900)
            Text("미팅을 듣고, 정리하고, 남겨 둬요")
                .font(TossFont.body())
                .foregroundStyle(TossColor.grey700)
        }
    }

    private var statusCard: some View {
        TossCard {
            HStack(spacing: TossSpace.x3) {
                Circle()
                    .fill(model.healthOK ? TossColor.green500 : TossColor.red500)
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.statusMessage)
                        .font(TossFont.section())
                        .foregroundStyle(TossColor.grey900)
                    Text(model.healthOK ? "파이프라인 연결됨" : "knowledged 실행이 필요해요")
                        .font(TossFont.caption())
                        .foregroundStyle(TossColor.grey500)
                }
                Spacer()
                if model.reviewCount > 0 {
                    TossBadge("확인 \(model.reviewCount)", kind: .info)
                }
            }
        }
    }

    private var recordCard: some View {
        TossCard {
            VStack(alignment: .leading, spacing: TossSpace.x4) {
                Text(model.isRecording ? "녹음 중" : "오프라인 미팅")
                    .font(TossFont.section())
                    .foregroundStyle(TossColor.grey900)
                Text(model.isRecording
                     ? "마이크가 켜져 있어요. 끝나면 아래 버튼을 눌러 주세요."
                     : "마이크만 사용해요. 온라인 회의 시스템 오디오는 다음 단계예요.")
                    .font(TossFont.body())
                    .foregroundStyle(TossColor.grey700)
                    .fixedSize(horizontal: false, vertical: true)

                if model.isRecording {
                    TossPrimaryButton("녹음 끝내기") {
                        model.stopRecording()
                    }
                    TossSecondaryButton("취소") {
                        // soft cancel via fail path if needed later
                        model.stopRecording()
                    }
                } else {
                    TossPrimaryButton("녹음 시작", enabled: model.healthOK) {
                        model.startRecording()
                    }
                }

                if let err = model.lastError {
                    Text(err)
                        .font(TossFont.caption())
                        .foregroundStyle(TossColor.red500)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var listCard: some View {
        TossCard {
            VStack(alignment: .leading, spacing: TossSpace.x4) {
                HStack {
                    Text("최근 미팅")
                        .font(TossFont.section())
                        .foregroundStyle(TossColor.grey900)
                    Spacer()
                    Button("확인함") { showReview = true }
                        .font(TossFont.caption())
                        .foregroundStyle(TossColor.blue500)
                        .buttonStyle(.plain)
                }

                if model.meetings.isEmpty {
                    Text("아직 미팅이 없어요")
                        .font(TossFont.body())
                        .foregroundStyle(TossColor.grey500)
                        .padding(.vertical, TossSpace.x4)
                } else {
                    ForEach(model.meetings.prefix(8)) { row in
                        HStack(alignment: .top, spacing: TossSpace.x3) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.title)
                                    .font(TossFont.body())
                                    .fontWeight(.medium)
                                    .foregroundStyle(TossColor.grey900)
                                    .lineLimit(1)
                                if let code = row.errorCode {
                                    Text(code)
                                        .font(TossFont.caption())
                                        .foregroundStyle(TossColor.red500)
                                }
                            }
                            Spacer()
                            TossBadge(
                                StatusCopy.label(row.status),
                                kind: StatusCopy.badgeKind(row.status)
                            )
                        }
                        if row.id != model.meetings.prefix(8).last?.id {
                            Divider().overlay(TossColor.grey200)
                        }
                    }
                }
            }
        }
    }

    private var footerHint: some View {
        Text("성공 알림은 보내지 않아요. 확인이 필요할 때만 알려 드릴게요.")
            .font(TossFont.caption())
            .foregroundStyle(TossColor.grey500)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
