import Foundation
import KnowledgeCore

public struct Stage2Report: Equatable, Sendable {
    public var outcome: Stage2Outcome
    public var warnings: [String]

    public init(outcome: Stage2Outcome, warnings: [String] = []) {
        self.outcome = outcome
        self.warnings = warnings
    }
}

/// Stage2: form already passed Stage1; check evidence quotes against transcript.
public enum Stage2Evidence {
    public static func evaluate(
        summary: MeetingSummaryV1,
        transcript: TranscriptDocument,
        thresholds: Thresholds = .default
    ) -> Stage2Report {
        var warnings: [String] = []
        let corpus = transcript.segments.map(\.text).joined(separator: "\n").lowercased()
        let durationMax = transcript.segments.map(\.tEndMs).max() ?? Int.max

        func checkBullet(_ path: String, text: String, evidence: [EvidenceSpan]) {
            if evidence.isEmpty {
                warnings.append("\(path):empty_evidence")
                return
            }
            for (i, e) in evidence.enumerated() {
                if e.quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    warnings.append("\(path)[\(i)]:empty_quote")
                    continue
                }
                if e.tEndMs < e.tStartMs {
                    warnings.append("\(path)[\(i)]:bad_range")
                }
                if e.tStartMs > durationMax + 5_000 {
                    warnings.append("\(path)[\(i)]:ts_oob")
                }
                let q = e.quote.lowercased()
                // Fuzzy-lite: substring or high overlap
                if !corpus.contains(q) && !fuzzyContains(corpus: corpus, quote: q, min: thresholds.evidenceFuzzyMin) {
                    // Try segment index
                    if let idx = e.segmentIndex,
                       transcript.segments.indices.contains(idx),
                       transcript.segments[idx].text.lowercased().contains(q)
                        || q.contains(transcript.segments[idx].text.lowercased().prefix(20)) {
                        warnings.append("\(path)[\(i)]:timestamp_repaired")
                    } else {
                        warnings.append("\(path)[\(i)]:quote_not_found")
                    }
                }
            }
        }

        for (i, b) in summary.keyDiscussionPoints.enumerated() {
            checkBullet("key_discussion_points[\(i)]", text: b.text, evidence: b.evidence)
        }
        for (i, b) in summary.decisions.enumerated() {
            checkBullet("decisions[\(i)]", text: b.text, evidence: b.evidence)
        }
        for (i, a) in summary.actionItems.enumerated() {
            checkBullet("action_items[\(i)]", text: a.text, evidence: a.evidence)
        }
        for (i, b) in summary.unresolvedItems.enumerated() {
            checkBullet("unresolved_items[\(i)]", text: b.text, evidence: b.evidence)
        }

        if summary.oneLineSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Stage2Report(outcome: .fail, warnings: warnings + ["one_line_empty"])
        }

        let hard = warnings.filter { $0.contains("empty_evidence") || $0.contains("quote_not_found") }
        if hard.count > thresholds.evidenceMaxWarnings {
            return Stage2Report(outcome: .fail, warnings: warnings)
        }
        if warnings.isEmpty {
            return Stage2Report(outcome: .pass, warnings: [])
        }
        return Stage2Report(outcome: .passWithWarnings, warnings: warnings)
    }

    private static func fuzzyContains(corpus: String, quote: String, min: Double) -> Bool {
        guard quote.count >= 4 else { return corpus.contains(quote) }
        // sliding window ratio
        let q = Array(quote)
        let window = Swift.min(q.count, 40)
        if window < 4 { return false }
        let needle = String(q.prefix(window))
        if corpus.contains(needle) { return true }
        // token overlap
        let qt = Set(quote.split(separator: " ").map(String.init))
        let ct = Set(corpus.split(separator: " ").map(String.init))
        guard !qt.isEmpty else { return false }
        let inter = qt.intersection(ct).count
        return Double(inter) / Double(qt.count) >= min
    }
}
