import Foundation
import KnowledgeCore

/// Local extractive summarizer — works without llama.cpp.
/// Produces grounded MeetingSummaryV1 with evidence quotes from transcript segments.
public enum ExtractiveSummarizer {
    public static func summarize(
        meetingId: String,
        transcript: TranscriptDocument,
        titleHint: String? = nil
    ) -> MeetingSummaryV1 {
        let segs = transcript.segments.filter {
            !$0.text.isEmpty && !$0.text.hasPrefix("(음성에서")
        }
        let oneLine: String
        if let first = segs.first?.text, !first.isEmpty {
            oneLine = String(first.prefix(120))
        } else if let titleHint, !titleHint.isEmpty {
            oneLine = titleHint
        } else {
            oneLine = "미팅 요약"
        }

        var keyPoints: [GroundedBullet] = []
        for seg in segs.prefix(5) {
            keyPoints.append(GroundedBullet(
                text: String(seg.text.prefix(200)),
                evidence: [evidence(from: seg)]
            ))
        }

        let decisionCues = ["결정", "합의", "확정", "가기로", "하겠습니다", "하자", "승인"]
        var decisions: [GroundedBullet] = []
        for seg in segs where decisionCues.contains(where: { seg.text.contains($0) }) {
            decisions.append(GroundedBullet(
                text: String(seg.text.prefix(200)),
                evidence: [evidence(from: seg)]
            ))
        }

        let actionCues = ["할 것", "액션", "TODO", "해야", "부탁", "담당", "까지", "주세요", "하겠습니다"]
        var actions: [ActionItem] = []
        for seg in segs where actionCues.contains(where: { seg.text.contains($0) }) {
            actions.append(ActionItem(
                text: String(seg.text.prefix(200)),
                owner: nil,
                dueOn: nil,
                evidence: [evidence(from: seg)]
            ))
        }

        let openCues = ["미정", "보류", "추후", "오픈", "미해결", "확인 필요", "모르겠"]
        var unresolved: [GroundedBullet] = []
        for seg in segs where openCues.contains(where: { seg.text.contains($0) }) {
            unresolved.append(GroundedBullet(
                text: String(seg.text.prefix(200)),
                evidence: [evidence(from: seg)]
            ))
        }

        // Empty sections are valid (Stage2 / critic must allow)
        var warnings: [String] = []
        if segs.isEmpty {
            warnings.append("transcript_empty_or_silence")
        }
        if decisions.isEmpty {
            warnings.append("no_decision_cues")
        }

        return MeetingSummaryV1(
            oneLineSummary: oneLine.isEmpty ? "미팅 요약" : oneLine,
            keyDiscussionPoints: keyPoints,
            decisions: decisions,
            actionItems: actions,
            unresolvedItems: unresolved,
            modelId: "extractive-local/v1",
            createdAt: Date(),
            warnings: warnings.isEmpty ? nil : warnings
        )
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

    // silence unused warning for future LLM path
    public static func _allTextPreview(_ t: TranscriptDocument) -> String {
        t.segments.map(\.text).joined(separator: " ")
    }
}
