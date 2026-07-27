import SwiftUI
import KnowledgeWorkers

/// Full human-readable meeting view: summary + transcript (not RAG).
public struct MeetingDetailView: View {
    public var title: String
    public var statusLabel: String
    public var bundle: MeetingArtifactReader.Bundle
    public var onAccept: (() -> Void)?
    public var onOpenVault: (() -> Void)?

    @State private var tab: Tab = .summary

    public enum Tab: String, CaseIterable, Identifiable {
        case summary = "요약"
        case transcript = "전사"
        case note = "노트"
        public var id: String { rawValue }
    }

    public init(
        title: String,
        statusLabel: String = "",
        bundle: MeetingArtifactReader.Bundle,
        onAccept: (() -> Void)? = nil,
        onOpenVault: (() -> Void)? = nil
    ) {
        self.title = title
        self.statusLabel = statusLabel
        self.bundle = bundle
        self.onAccept = onAccept
        self.onOpenVault = onOpenVault
        // Prefer first tab that has content
        if bundle.summary.map({ !$0.isEmpty }) == true {
            _tab = State(initialValue: .summary)
        } else if bundle.transcript.map({ !$0.isEmpty }) == true {
            _tab = State(initialValue: .transcript)
        } else if bundle.vaultMarkdown != nil {
            _tab = State(initialValue: .note)
        } else {
            _tab = State(initialValue: .summary)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: TossSpace.x2) {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(TossColor.grey900)
                    .fixedSize(horizontal: false, vertical: true)
                if !statusLabel.isEmpty {
                    Text(statusLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(TossColor.blue500)
                }
                Text("요약·전사는 직접 읽어 확인하는 화면이에요. 물어보기 검색과는 별개예요.")
                    .font(.system(size: 12))
                    .foregroundStyle(TossColor.grey500)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, TossSpace.x6)
            .padding(.top, TossSpace.x4)
            .padding(.bottom, TossSpace.x3)

            Picker("", selection: $tab) {
                ForEach(availableTabs) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, TossSpace.x6)
            .padding(.bottom, TossSpace.x3)

            ScrollView(showsIndicators: true) {
                VStack(alignment: .leading, spacing: TossSpace.x5) {
                    switch tab {
                    case .summary:
                        summaryBody
                    case .transcript:
                        transcriptBody
                    case .note:
                        noteBody
                    }
                }
                .padding(.horizontal, TossSpace.x6)
                .padding(.bottom, TossSpace.x8)
            }

            if onAccept != nil || onOpenVault != nil {
                VStack(spacing: TossSpace.x3) {
                    if let onAccept {
                        TossPrimaryButton("저장하기") { onAccept() }
                    }
                    if let onOpenVault {
                        Button("노트 폴더에서 열기") { onOpenVault() }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(TossColor.blue500)
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, TossSpace.x6)
                .padding(.vertical, TossSpace.x4)
                .background(TossColor.white.shadow(color: .black.opacity(0.04), radius: 8, y: -2))
            }
        }
        .background(TossColor.grey100.ignoresSafeArea())
    }

    private var availableTabs: [Tab] {
        var t: [Tab] = []
        if bundle.summary.map({ !$0.isEmpty }) != false { t.append(.summary) }
        if bundle.transcript.map({ !$0.isEmpty }) == true { t.append(.transcript) }
        if bundle.vaultMarkdown != nil { t.append(.note) }
        if t.isEmpty { t = [.summary, .transcript] }
        return t
    }

    @ViewBuilder
    private var summaryBody: some View {
        if let s = bundle.summary, !s.isEmpty {
            if !s.oneLine.isEmpty {
                card {
                    Text("한 줄")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(TossColor.grey500)
                    Text(s.oneLine)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(TossColor.grey900)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            sectionCard(title: "이야기한 것", items: s.discussion)
            sectionCard(title: "결정", items: s.decisions)
            sectionCard(title: "할 일", items: s.actions)
            sectionCard(title: "남은 이슈", items: s.open)
            if !s.warnings.isEmpty {
                sectionCard(title: "경고", items: s.warnings)
            }
            if let mid = s.modelId, !mid.isEmpty {
                Text("요약 모델: \(mid)")
                    .font(.system(size: 11))
                    .foregroundStyle(TossColor.grey500)
            }
        } else {
            empty("요약을 불러오지 못했어요. 전사 탭을 확인해 보세요.")
        }
    }

    @ViewBuilder
    private var transcriptBody: some View {
        if let t = bundle.transcript, !t.isEmpty {
            card {
                HStack {
                    Text("전사 전문")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(TossColor.grey500)
                    Spacer()
                    Text("\(t.segmentCount)구간")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(TossColor.blue500)
                }
                if let lang = t.language {
                    Text("언어 \(lang)\(t.asrModelId.map { " · \($0)" } ?? "")")
                        .font(.system(size: 11))
                        .foregroundStyle(TossColor.grey500)
                }
            }
            // Timed segments — primary reading surface
            VStack(alignment: .leading, spacing: TossSpace.x3) {
                ForEach(Array(t.segments.enumerated()), id: \.offset) { _, seg in
                    HStack(alignment: .top, spacing: TossSpace.x3) {
                        Text(seg.timeLabel)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(TossColor.blue500)
                            .frame(width: 48, alignment: .leading)
                        Text(seg.text)
                            .font(.system(size: 16))
                            .foregroundStyle(TossColor.grey900)
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                    if seg.index != t.segments.last?.index {
                        Divider().overlay(TossColor.grey200)
                    }
                }
            }
            .padding(TossSpace.x5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TossColor.white)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            card {
                Text("연속 텍스트 (복사·검색용)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TossColor.grey500)
                Text(t.fullText)
                    .font(.system(size: 15))
                    .foregroundStyle(TossColor.grey700)
                    .lineSpacing(5)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            empty("전사 파일이 없거나 비어 있어요. 녹음·ASR이 끝났는지 확인해 주세요.")
        }
    }

    @ViewBuilder
    private var noteBody: some View {
        if let md = bundle.vaultMarkdown, !md.isEmpty {
            card {
                Text("저장된 노트")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TossColor.grey500)
                Text(md)
                    .font(.system(size: 15))
                    .foregroundStyle(TossColor.grey900)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            empty("아직 vault 노트가 없어요. 저장하기를 누르면 만들어져요.")
        }
    }

    private func sectionCard(title: String, items: [String]) -> some View {
        Group {
            if !items.isEmpty {
                card {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(TossColor.grey500)
                    ForEach(Array(items.enumerated()), id: \.offset) { _, text in
                        HStack(alignment: .top, spacing: TossSpace.x2) {
                            Text("·")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(TossColor.blue500)
                            Text(text)
                                .font(.system(size: 16))
                                .foregroundStyle(TossColor.grey900)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: TossSpace.x3) {
            content()
        }
        .padding(TossSpace.x5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TossColor.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func empty(_ msg: String) -> some View {
        Text(msg)
            .font(.system(size: 15))
            .foregroundStyle(TossColor.grey500)
            .padding(TossSpace.x5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TossColor.white)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
