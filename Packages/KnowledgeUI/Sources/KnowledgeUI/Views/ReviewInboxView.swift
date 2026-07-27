import SwiftUI
import KnowledgeCore
import KnowledgeWorkers

/// Review inbox — read full summary + transcript, then save.
/// Viewing content is the primary job; accept is secondary.
public struct ReviewInboxView: View {
    @ObservedObject public var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedId: String?
    @State private var showDetail = false

    public init(model: AppModel) {
        self.model = model
    }

    private var pending: [AppModel.MeetingRow] {
        model.meetings.filter { $0.status == "review_needed" }
    }

    private var failed: [AppModel.MeetingRow] {
        model.meetings.filter { $0.status.contains("fail") }
    }

    private var recentReadable: [AppModel.MeetingRow] {
        model.meetings.filter {
            $0.status == "committed"
                || $0.status == "review_needed"
                || ($0.transcriptPath != nil && !$0.status.contains("fail"))
        }
        .filter { row in
            // Avoid double-list: pending shown above; here prefer committed + others with artifacts
            row.status != "review_needed"
        }
        .prefix(12)
        .map { $0 }
    }

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                TossColor.grey100.ignoresSafeArea()
                VStack(spacing: 0) {
                    nav
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: TossSpace.x6) {
                            title
                            if pending.isEmpty && failed.isEmpty && recentReadable.isEmpty {
                                TossEmptyState(
                                    systemImage: "checkmark.circle",
                                    title: "확인할 일이 없어요",
                                    message: "녹음이 끝나면 전사·요약이 여기로 와요. 홈에서 녹음을 시작해 보세요."
                                )
                                .padding(.top, TossSpace.x4)
                            }
                            if !pending.isEmpty {
                                sectionHeader("저장 전 확인")
                                ForEach(pending) { row in
                                    pendingCard(row)
                                }
                            }
                            ForEach(failed) { row in
                                failedCard(row)
                            }
                            if !recentReadable.isEmpty {
                                sectionHeader("최근 기록 (읽기)")
                                Text("저장된 노트·전사도 여기서 다시 볼 수 있어요. 물어보기와는 별개예요.")
                                    .font(.system(size: 13))
                                    .foregroundStyle(TossColor.grey500)
                                ForEach(recentReadable) { row in
                                    historyCard(row)
                                }
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
            .navigationDestination(isPresented: $showDetail) {
                if let id = selectedId, let row = model.meetings.first(where: { $0.id == id }) {
                    detail(for: row)
                } else {
                    Text("항목을 찾을 수 없어요.")
                        .foregroundStyle(TossColor.grey500)
                        .padding()
                }
            }
        }
        .onAppear { model.refresh() }
    }

    private func sectionHeader(_ t: String) -> some View {
        Text(t)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(TossColor.grey500)
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
                 ? "전사·요약을 다시 읽어볼 수 있어요."
                 : "전사와 요약을 읽은 뒤 저장하면 노트에 남고, 물어보기에도 쓰여요.")
                .font(.system(size: 17))
                .foregroundStyle(TossColor.grey700)
                .lineSpacing(3)
        }
    }

    private func bundle(for row: AppModel.MeetingRow) -> MeetingArtifactReader.Bundle {
        let vaultRoot = AppConfig.load(knowledgeRoot: model.knowledgeRoot).vaultURL
        return MeetingSummaryLoader.loadBundle(
            knowledgeRoot: model.knowledgeRoot,
            candidateRel: row.candidatePath,
            transcriptRel: row.transcriptPath,
            vaultRel: row.vaultPath,
            vaultRoot: vaultRoot
        )
    }

    private func detail(for row: AppModel.MeetingRow) -> some View {
        let b = bundle(for: row)
        let needsAccept = row.status == "review_needed"
        return MeetingDetailView(
            title: row.title,
            statusLabel: statusKO(row.status),
            bundle: b,
            onAccept: needsAccept ? {
                model.acceptReview(meetingId: row.id)
                showDetail = false
                selectedId = nil
            } : nil,
            onOpenVault: row.vaultPath != nil ? {
                if let rel = row.vaultPath {
                    model.openMeetingInFinder(vaultRel: rel)
                }
            } : nil
        )
    }

    private func statusKO(_ raw: String) -> String {
        switch raw {
        case "review_needed": return "저장 전 · 요약·전사 확인"
        case "committed": return "노트에 저장됨"
        default: return StatusCopy.label(raw)
        }
    }

    private func pendingCard(_ row: AppModel.MeetingRow) -> some View {
        let b = bundle(for: row)
        let display = b.summary
        let hasTx = b.transcript.map { !$0.isEmpty } ?? false
        return VStack(alignment: .leading, spacing: TossSpace.x4) {
            Text(row.title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(TossColor.grey900)

            if let one = display?.oneLine, !one.isEmpty {
                Text(one)
                    .font(.system(size: 16))
                    .foregroundStyle(TossColor.grey700)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let one = row.oneLine, !one.isEmpty {
                Text(one)
                    .font(.system(size: 16))
                    .foregroundStyle(TossColor.grey700)
            } else {
                Text("요약을 불러오지 못했어요. 전사를 열어 확인할 수 있어요.")
                    .font(.system(size: 15))
                    .foregroundStyle(TossColor.grey500)
            }

            HStack(spacing: TossSpace.x3) {
                badge(
                    hasTx
                        ? "전사 \(b.transcript?.segmentCount ?? 0)구간"
                        : "전사 없음"
                )
                badge(
                    (display.map { !$0.isEmpty } ?? false) ? "요약 있음" : "요약 없음"
                )
            }

            // Preview first discussion points (full list in detail)
            if let d = display?.discussion.prefix(3), !d.isEmpty {
                VStack(alignment: .leading, spacing: TossSpace.x2) {
                    Text("이야기한 것 (미리보기)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(TossColor.grey500)
                    ForEach(Array(d.enumerated()), id: \.offset) { _, text in
                        Text("· \(text)")
                            .font(.system(size: 15))
                            .foregroundStyle(TossColor.grey900)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Button {
                selectedId = row.id
                showDetail = true
            } label: {
                Text("전사·요약 전체 보기")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(TossColor.blue50)
                    .foregroundStyle(TossColor.blue500)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            TossPrimaryButton("저장하기") {
                model.acceptReview(meetingId: row.id)
            }
        }
        .padding(TossSpace.x5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TossColor.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func historyCard(_ row: AppModel.MeetingRow) -> some View {
        Button {
            selectedId = row.id
            showDetail = true
        } label: {
            HStack(spacing: TossSpace.x3) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TossColor.grey900)
                        .multilineTextAlignment(.leading)
                    Text(statusKO(row.status))
                        .font(.system(size: 12))
                        .foregroundStyle(TossColor.grey500)
                    if let one = row.oneLine, !one.isEmpty {
                        Text(one)
                            .font(.system(size: 13))
                            .foregroundStyle(TossColor.grey700)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(TossColor.grey200)
            }
            .padding(TossSpace.x5)
            .background(TossColor.white)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(TossColor.blue500)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(TossColor.blue50)
            .clipShape(Capsule())
    }

    private func failedCard(_ row: AppModel.MeetingRow) -> some View {
        VStack(alignment: .leading, spacing: TossSpace.x4) {
            Text(row.title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(TossColor.grey900)
            Text("처리 중 문제가 생겼어요.")
                .font(.system(size: 15))
                .foregroundStyle(TossColor.grey500)
            if row.transcriptPath != nil {
                Button("전사라도 열어보기") {
                    selectedId = row.id
                    showDetail = true
                }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(TossColor.blue500)
                    .buttonStyle(.plain)
            }
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
