import Foundation
import KnowledgeCore

/// Mode B critic (light, local heuristics). Optional second model later.
/// Does not block review forever: hard fails only for clear cheerleading / empty-when-cued.
public enum SummaryCritic {
    public struct Report: Equatable, Sendable {
        public var ok: Bool
        public var warnings: [String]
        public var hardFail: Bool

        public init(ok: Bool, warnings: [String], hardFail: Bool) {
            self.ok = ok
            self.warnings = warnings
            self.hardFail = hardFail
        }
    }

    public static func evaluate(
        summary: MeetingSummaryV1,
        transcript: TranscriptDocument
    ) -> Report {
        var warnings: [String] = []
        var hard = false
        let body = transcript.segments.map(\.text).joined(separator: " ")
        let lower = body.lowercased()

        // Cheerleading / empty fluff
        let fluff = ["great meeting", "좋은 회의였", "수고 많", "감사합니다 모두"]
        if fluff.contains(where: { summary.oneLineSummary.lowercased().contains($0) || lower.contains($0) && summary.decisions.isEmpty }) {
            warnings.append("cheerlead_risk")
        }

        // Decision cues in transcript but no decisions
        let decisionCues = ["결정", "합의", "확정", "가자", "하기로", "decided", "agreed", "ship"]
        let hasCue = decisionCues.contains { lower.contains($0.lowercased()) }
        if hasCue && summary.decisions.isEmpty {
            warnings.append("empty_decisions_with_cues")
            hard = true
        }

        // Action cues without actions
        let actionCues = ["할 일", "액션", "담당", "기한", "action item", "todo", "due"]
        if actionCues.contains(where: { lower.contains($0.lowercased()) }) && summary.actionItems.isEmpty {
            warnings.append("empty_actions_with_cues")
        }

        // One-liner too long / too short
        if summary.oneLineSummary.count < 4 {
            warnings.append("one_line_too_short")
            hard = true
        }
        if summary.oneLineSummary.count > 200 {
            warnings.append("one_line_too_long")
        }

        // Evidence empty on decisions
        for (i, d) in summary.decisions.enumerated() where d.evidence.isEmpty {
            warnings.append("decision_\(i)_no_evidence")
        }

        let ok = !hard
        return Report(ok: ok, warnings: warnings, hardFail: hard)
    }
}
