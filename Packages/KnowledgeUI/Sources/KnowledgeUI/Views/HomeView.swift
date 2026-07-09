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
        .task {
            model.startPolling()
            model.kickPendingASR()
        }
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
                    .fill(statusDotColor)
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.statusMessage)
                        .font(TossFont.section())
                        .foregroundStyle(TossColor.grey900)
                    Text(model.connectionCaption)
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

    private var statusDotColor: Color {
        if model.healthOK { return TossColor.green500 }
        if model.isStartingBackend { return TossColor.blue500 }
        return TossColor.grey500
    }

    private var recordCard: some View {
        TossCard {
            VStack(alignment: .leading, spacing: TossSpace.x4) {
                Text(model.isRecording ? "시스템 오디오 녹음 중" : "시스템 오디오 녹음")
                    .font(TossFont.section())
                    .foregroundStyle(TossColor.grey900)
                Text(model.isRecording
                     ? "Mac에서 나는 회의 소리(Zoom/Meet 등)를 듣고 있어요. 끝나면 아래를 눌러 주세요."
                     : "Mac mini처럼 내장 마이크가 없어도 됩니다. 디스플레이 시스템 오디오를 녹음해요. 첫 실행 시 화면 기록 권한을 허용해 주세요.")
                    .font(TossFont.body())
                    .foregroundStyle(TossColor.grey700)
                    .fixedSize(horizontal: false, vertical: true)

                if model.isRecording {
                    TossPrimaryButton("녹음 끝내기") {
                        model.stopRecording()
                    }
                } else if model.isProcessing {
                    TossPrimaryButton("정리하는 중…", enabled: false) {}
                } else {
                    TossPrimaryButton(
                        model.isStartingBackend ? "준비 중…" : "녹음 시작",
                        enabled: !model.isStartingBackend
                    ) {
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
                        VStack(alignment: .leading, spacing: TossSpace.x2) {
                            HStack(alignment: .top, spacing: TossSpace.x3) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(row.title)
                                        .font(TossFont.body())
                                        .fontWeight(.medium)
                                        .foregroundStyle(TossColor.grey900)
                                        .lineLimit(1)
                                    if let code = row.errorCode {
                                        Text(friendlyCode(code))
                                            .font(TossFont.caption())
                                            .foregroundStyle(TossColor.grey500)
                                    }
                                }
                                Spacer()
                                TossBadge(
                                    StatusCopy.label(row.status),
                                    kind: StatusCopy.badgeKind(row.status)
                                )
                            }
                            if row.status.contains("fail") || row.errorCode == "needs_ui_asr" {
                                Button("다시 처리") {
                                    model.retryMeeting(meetingId: row.id)
                                }
                                .font(TossFont.caption())
                                .fontWeight(.semibold)
                                .foregroundStyle(TossColor.blue500)
                                .buttonStyle(.plain)
                            }
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
        Text("회의 탭을 켠 뒤 녹음하세요. 끝나면 받아쓰기·요약이 이어지고, 확인이 필요할 때만 알려 드릴게요.")
            .font(TossFont.caption())
            .foregroundStyle(TossColor.grey500)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func friendlyCode(_ code: String) -> String {
        switch code {
        case "needs_ui_asr", "asr_tools_missing":
            return "받아쓰기 대기 — 다시 처리를 눌러 주세요"
        case "speech_permission":
            return "설정에서 음성 인식을 허용해 주세요"
        default:
            return code
        }
    }
}
