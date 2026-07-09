import Foundation
import KnowledgeCore

/// Local extractive summarizer — works without llama.cpp.
/// Coalesces word-level ASR crumbs first, then pulls grounded bullets.
public enum ExtractiveSummarizer {
    public static func summarize(
        meetingId: String,
        transcript: TranscriptDocument,
        titleHint: String? = nil
    ) -> MeetingSummaryV1 {
        let coalesced = TranscriptCoalesce.coalesce(transcript.segments)
        let segs = coalesced.filter {
            !$0.text.isEmpty
                && !$0.text.hasPrefix("(인식된")
                && !$0.text.hasPrefix("(음성에서")
        }
        let full = TranscriptCoalesce.fullText(segs)

        let oneLine: String = {
            if !full.isEmpty {
                return String(full.prefix(120))
            }
            if let titleHint, !titleHint.isEmpty { return titleHint }
            return "미팅 요약"
        }()

        // Key points: up to 5 longer chunks; if still too short, pack windows of 3
        var keySource = segs.filter { $0.text.count >= 8 }
        if keySource.count < 3 {
            keySource = packWindows(segs, window: 3)
        }
        var keyPoints: [GroundedBullet] = []
        for seg in keySource.prefix(5) {
            keyPoints.append(GroundedBullet(
                text: String(seg.text.prefix(200)),
                evidence: [evidence(from: seg)]
            ))
        }
        if keyPoints.isEmpty, let first = segs.first {
            keyPoints = [GroundedBullet(text: String(first.text.prefix(200)), evidence: [evidence(from: first)])]
        }

        let decisionCues = ["결정", "합의", "확정", "가기로", "하겠습니다", "하자", "승인", "채택", "하기로"]
        var decisions: [GroundedBullet] = []
        for seg in segs where decisionCues.contains(where: { seg.text.contains($0) }) {
            decisions.append(GroundedBullet(
                text: String(seg.text.prefix(200)),
                evidence: [evidence(from: seg)]
            ))
            if decisions.count >= 5 { break }
        }

        let actionCues = ["할 것", "액션", "TODO", "해야", "부탁", "담당", "까지", "주세요", "하겠습니다", "하겠습니다", "진행", "후속"]
        var actions: [ActionItem] = []
        for seg in segs where actionCues.contains(where: { seg.text.contains($0) }) {
            actions.append(ActionItem(
                text: String(seg.text.prefix(200)),
                owner: nil,
                dueOn: nil,
                evidence: [evidence(from: seg)]
            ))
            if actions.count >= 8 { break }
        }

        let openCues = ["미정", "보류", "추후", "오픈", "미해결", "확인 필요", "모르겠", "나중에"]
        var unresolved: [GroundedBullet] = []
        for seg in segs where openCues.contains(where: { seg.text.contains($0) }) {
            unresolved.append(GroundedBullet(
                text: String(seg.text.prefix(200)),
                evidence: [evidence(from: seg)]
            ))
            if unresolved.count >= 5 { break }
        }

        var warnings: [String] = []
        if segs.isEmpty {
            warnings.append("transcript_empty_or_silence")
        }
        if decisions.isEmpty {
            warnings.append("no_decision_cues")
        }
        if transcript.segments.count > segs.count * 2 {
            warnings.append("asr_coalesced_from_word_segments")
        }

        return MeetingSummaryV1(
            oneLineSummary: oneLine.isEmpty ? "미팅 요약" : oneLine,
            keyDiscussionPoints: keyPoints,
            decisions: decisions,
            actionItems: actions,
            unresolvedItems: unresolved,
            modelId: "extractive-local/v2",
            createdAt: Date(),
            warnings: warnings.isEmpty ? nil : warnings
        )
    }

    private static func packWindows(_ segs: [TranscriptSegment], window: Int) -> [TranscriptSegment] {
        guard !segs.isEmpty else { return [] }
        var out: [TranscriptSegment] = []
        var i = 0
        while i < segs.count {
            let slice = Array(segs[i..<min(i + window, segs.count)])
            let text = TranscriptCoalesce.fullText(slice)
            out.append(TranscriptSegment(
                index: out.count,
                tStartMs: slice.first!.tStartMs,
                tEndMs: slice.last!.tEndMs,
                text: text
            ))
            i += window
        }
        return out
    }

    private static func evidence(from seg: TranscriptSegment) -> EvidenceSpan {
        let quote = String(seg.text.prefix(200))
        return EvidenceSpan(
            tStartMs: seg.tStartMs,
            tEndMs: max(seg.tEndMs, seg.tStartMs + 1),
            quote: quote.isEmpty ? seg.text : quote,
            segmentIndex: seg.index
        )
    }
}
