import SwiftUI

/// One job: capture meeting audio.
public struct RecordView: View {
    @ObservedObject public var model: AppModel
    @Environment(\.dismiss) private var dismiss

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        ZStack {
            TossColor.grey100.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: TossSpace.x6)
                center
                Spacer()
                bottomActions
                    .padding(.horizontal, TossSpace.x6)
                    .padding(.bottom, TossSpace.x8)
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(TossColor.grey900)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, TossSpace.x3)
        .padding(.top, TossSpace.x2)
    }

    private var center: some View {
        VStack(spacing: TossSpace.x5) {
            ZStack {
                Circle()
                    .fill(model.isRecording ? TossColor.red50 : TossColor.blue50)
                    .frame(width: 120, height: 120)
                Image(systemName: model.isRecording ? "waveform" : "mic.fill")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(model.isRecording ? TossColor.red500 : TossColor.blue500)
            }

            Text(centerTitle)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(TossColor.grey900)
                .multilineTextAlignment(.center)

            Text(centerBody)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(TossColor.grey700)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, TossSpace.x8)
                .fixedSize(horizontal: false, vertical: true)

            if let err = model.lastError, model.isRecording == false {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(TossColor.red500)
                    Text(shortError(err))
                        .font(TossFont.caption())
                        .foregroundStyle(TossColor.grey900)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(TossSpace.x4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(TossColor.red50)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, TossSpace.x6)

                if shortError(err).contains("화면 기록") {
                    Button("시스템 설정 열기") {
                        AppModel.openScreenRecordingSettings()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(TossColor.blue500)
                    .buttonStyle(.plain)
                }
            } else if !model.healthOK {
                Text("백그라운드 준비 중이에요. 잠시 후 다시 눌러 주세요.")
                    .font(TossFont.caption())
                    .foregroundStyle(TossColor.grey500)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, TossSpace.x6)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var centerTitle: String {
        if model.isRecording { return "듣고 있어요" }
        if model.isProcessing { return "정리하는 중" }
        return "회의 녹음"
    }

    private var centerBody: String {
        if model.isRecording {
            return "Zoom, 브라우저, 동영상 소리가\n여기에 저장되고 있어요."
        }
        if model.isProcessing {
            return "받아쓰고 요약하는 중이에요.\n끝나면 확인함에서 볼 수 있어요."
        }
        return "회의 탭을 켠 뒤 시작해 주세요.\n화면 기록이 필요할 수 있어요."
    }

    private var bottomActions: some View {
        VStack(spacing: TossSpace.x3) {
            if model.isRecording {
                TossPrimaryButton("녹음 끝내기") {
                    model.stopRecording()
                }
            } else if model.isProcessing {
                TossPrimaryButton("정리하는 중…", enabled: false) {}
            } else {
                TossPrimaryButton(
                    model.isStartingBackend ? "준비 중…" : "녹음 시작하기",
                    enabled: !model.isStartingBackend && model.vaultReady
                ) {
                    model.startRecording()
                }
                if model.lastError?.contains("화면 기록") == true
                    || model.lastError?.contains("TCC") == true
                    || model.lastError?.contains("3801") == true {
                    Button("화면 기록 허용하기") {
                        AppModel.openScreenRecordingSettings()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(TossColor.blue500)
                    .buttonStyle(.plain)
                    .padding(.top, TossSpace.x2)
                }
            }
        }
    }

    private func shortError(_ err: String) -> String {
        if err.contains("화면 기록") || err.contains("TCC") || err.contains("3801") {
            return "화면 기록을 허용해야 소리를 담을 수 있어요."
        }
        if err.count > 100 { return String(err.prefix(100)) + "…" }
        return err
    }
}
