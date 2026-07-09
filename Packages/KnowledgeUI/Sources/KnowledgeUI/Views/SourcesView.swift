import SwiftUI

/// Connect knowledge quietly. One primary: sync. Rest as simple rows.
public struct SourcesView: View {
    @ObservedObject public var model: AppModel
    @Environment(\.dismiss) private var dismiss

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        ZStack {
            TossColor.grey100.ignoresSafeArea()
            VStack(spacing: 0) {
                nav
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: TossSpace.x8) {
                        titleBlock
                        syncBlock
                        if model.isIngesting {
                            progressBlock
                        }
                        connectBlock
                        if model.abandonedMeetingCount > 0 {
                            cleanupBlock
                        }
                    }
                    .padding(.horizontal, TossSpace.x6)
                    .padding(.bottom, TossSpace.x8)
                }
            }
        }
        .onAppear { model.refreshSourceStats() }
    }

    private var cleanupBlock: some View {
        VStack(alignment: .leading, spacing: TossSpace.x3) {
            Text("정리")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(TossColor.grey500)
            VStack(alignment: .leading, spacing: TossSpace.x3) {
                Text("안 쓰는 녹음 \(model.abandonedMeetingCount)건")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(TossColor.grey900)
                Text("중단·실패한 녹음 파일과 목록을 지워요. 이미 저장한 노트는 그대로 둡니다. (자동: 14일 지난 중단 건은 앱 켤 때 정리)")
                    .font(.system(size: 14))
                    .foregroundStyle(TossColor.grey500)
                    .fixedSize(horizontal: false, vertical: true)
                Button("지금 정리하기") {
                    model.purgeAbandonedMeetings()
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(TossColor.blue500)
                .buttonStyle(.plain)
            }
            .padding(TossSpace.x5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TossColor.white)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
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

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: TossSpace.x3) {
            Text("지식 연결")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(TossColor.grey900)
            Text(model.corpusTotalUnits == 0
                 ? "미팅은 저장하면 자동으로 들어와요.\n메모나 폴더는 아래에서 연결해요."
                 : "지금 \(model.corpusTotalUnits)개가 연결되어 있어요.")
                .font(.system(size: 17))
                .foregroundStyle(TossColor.grey700)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var syncBlock: some View {
        TossPrimaryButton(
            model.isIngesting ? "가져오는 중…" : "최신으로 맞추기",
            enabled: !model.isIngesting
        ) {
            model.syncKnowledgeCorpus(includeNotes: true)
        }
    }

    private var progressBlock: some View {
        VStack(alignment: .leading, spacing: TossSpace.x3) {
            HStack {
                Text(model.ingestProgressLabel.isEmpty ? "가져오는 중" : model.ingestProgressLabel)
                    .font(.system(size: 14))
                    .foregroundStyle(TossColor.grey700)
                    .lineLimit(2)
                Spacer()
                Button("취소") { model.cancelCorpusSync() }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(TossColor.blue500)
                    .buttonStyle(.plain)
            }
            ProgressView(value: max(model.ingestProgress, 0.03))
                .tint(TossColor.blue500)
        }
        .padding(TossSpace.x4)
        .background(TossColor.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var connectBlock: some View {
        VStack(alignment: .leading, spacing: TossSpace.x3) {
            Text("연결 추가")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(TossColor.grey500)

            VStack(spacing: 0) {
                simpleRow("메모 앱", "Apple Notes") {
                    model.connectAndSyncAppleNotes()
                }
                Divider().padding(.leading, 16)
                simpleRow("노트 폴더", "지금 쓰는 Obsidian") {
                    model.syncKnowledgeCorpus(includeNotes: false)
                }
                Divider().padding(.leading, 16)
                simpleRow("다른 폴더", "Finder에서 고르기") {
                    model.connectFolder(asObsidian: false)
                }
                Divider().padding(.leading, 16)
                simpleRow("파일", "문서 몇 개만") {
                    model.connectFiles()
                }
            }
            .background(TossColor.white)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            if let err = model.ingestError {
                Text(friendly(err))
                    .font(TossFont.caption())
                    .foregroundStyle(TossColor.red500)
            } else if let msg = model.ingestStatusMessage, !model.isIngesting, !msg.isEmpty {
                Text(msg)
                    .font(TossFont.caption())
                    .foregroundStyle(TossColor.grey500)
            }
        }
    }

    private func simpleRow(_ title: String, _ sub: String, action: @escaping () -> Void) -> some View {
        Button {
            guard !model.isIngesting else { return }
            action()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(TossColor.grey900)
                    Text(sub)
                        .font(.system(size: 14))
                        .foregroundStyle(TossColor.grey500)
                }
                Spacer()
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(TossColor.blue500)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.isIngesting)
        .opacity(model.isIngesting ? 0.5 : 1)
    }

    private func friendly(_ err: String) -> String {
        if err.contains("취소") { return "가져오기를 멈췄어요" }
        if err.contains("자동화") || err.contains("Notes") {
            return "메모 앱 권한을 허용해 주세요"
        }
        return err.count > 120 ? String(err.prefix(120)) + "…" : err
    }
}
