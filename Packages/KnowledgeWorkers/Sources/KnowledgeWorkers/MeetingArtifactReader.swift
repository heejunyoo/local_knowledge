import Foundation
import KnowledgeCore

/// Load meeting summary + transcript for human reading (review UI / mobile RPC).
/// Separate from RAG — primary purpose is **owner can read what was said and summarized**.
public enum MeetingArtifactReader {
    public struct SummaryView: Equatable, Sendable {
        public var oneLine: String
        public var discussion: [String]
        public var decisions: [String]
        public var actions: [String]
        public var open: [String]
        public var warnings: [String]
        public var modelId: String?
        public var candidateRel: String?

        public var isEmpty: Bool {
            oneLine.isEmpty && discussion.isEmpty && decisions.isEmpty
                && actions.isEmpty && open.isEmpty
        }

        public func asDict() -> [String: Any] {
            var d: [String: Any] = [
                "one_line": oneLine,
                "discussion": discussion,
                "decisions": decisions,
                "actions": actions,
                "open": open,
                "warnings": warnings,
            ]
            if let modelId { d["model_id"] = modelId }
            if let candidateRel { d["candidate_path"] = candidateRel }
            return d
        }
    }

    public struct TranscriptView: Equatable, Sendable {
        public struct Segment: Equatable, Sendable {
            public var index: Int
            public var tStartMs: Int
            public var tEndMs: Int
            public var text: String
            public var timeLabel: String
        }

        public var segments: [Segment]
        public var fullText: String
        public var language: String?
        public var asrModelId: String?
        public var transcriptRel: String?
        public var segmentCount: Int { segments.count }

        public var isEmpty: Bool { fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        public func asDict() -> [String: Any] {
            var d: [String: Any] = [
                "full_text": fullText,
                "segment_count": segmentCount,
                "segments": segments.map { s -> [String: Any] in
                    [
                        "index": s.index,
                        "t_start_ms": s.tStartMs,
                        "t_end_ms": s.tEndMs,
                        "text": s.text,
                        "time_label": s.timeLabel,
                    ]
                },
            ]
            if let language { d["language"] = language }
            if let asrModelId { d["asr_model_id"] = asrModelId }
            if let transcriptRel { d["transcript_path"] = transcriptRel }
            return d
        }
    }

    public struct Bundle: Equatable, Sendable {
        public var summary: SummaryView?
        public var transcript: TranscriptView?
        public var vaultMarkdown: String?
        public var vaultRel: String?

        public var hasReadableContent: Bool {
            !(summary?.isEmpty ?? true) || !(transcript?.isEmpty ?? true)
                || !(vaultMarkdown?.isEmpty ?? true)
        }

        public func asDict() -> [String: Any] {
            var d: [String: Any] = [:]
            if let summary { d["summary"] = summary.asDict() }
            if let transcript { d["transcript"] = transcript.asDict() }
            if let vaultMarkdown { d["vault_markdown"] = vaultMarkdown }
            if let vaultRel { d["vault_path"] = vaultRel }
            d["has_summary"] = summary.map { !$0.isEmpty } ?? false
            d["has_transcript"] = transcript.map { !$0.isEmpty } ?? false
            return d
        }
    }

    // MARK: - Load

    public static func loadSummary(knowledgeRoot: URL, candidateRel: String?) -> SummaryView? {
        guard let rel = candidateRel?.trimmingCharacters(in: .whitespacesAndNewlines), !rel.isEmpty else {
            return nil
        }
        let url = resolve(knowledgeRoot: knowledgeRoot, rel: rel)
        guard let data = try? Data(contentsOf: url) else { return nil }

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        if let s = try? dec.decode(MeetingSummaryV1.self, from: data) {
            return SummaryView(
                oneLine: s.oneLineSummary,
                discussion: s.keyDiscussionPoints.map(\.text).filter { !$0.isEmpty },
                decisions: s.decisions.map(\.text).filter { !$0.isEmpty },
                actions: s.actionItems.map(\.text).filter { !$0.isEmpty },
                open: s.unresolvedItems.map(\.text).filter { !$0.isEmpty },
                warnings: (s.warnings ?? []) + (s.stage2Warnings ?? []),
                modelId: s.modelId,
                candidateRel: rel
            )
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func texts(_ key: String) -> [String] {
            ((obj[key] as? [[String: Any]]) ?? []).compactMap { $0["text"] as? String }.filter { !$0.isEmpty }
        }
        return SummaryView(
            oneLine: (obj["one_line_summary"] as? String) ?? "",
            discussion: texts("key_discussion_points"),
            decisions: texts("decisions"),
            actions: texts("action_items"),
            open: texts("unresolved_items"),
            warnings: (obj["warnings"] as? [String]) ?? [],
            modelId: obj["model_id"] as? String,
            candidateRel: rel
        )
    }

    public static func loadTranscript(knowledgeRoot: URL, transcriptRel: String?) -> TranscriptView? {
        guard let rel = transcriptRel?.trimmingCharacters(in: .whitespacesAndNewlines), !rel.isEmpty else {
            return nil
        }
        let url = resolve(knowledgeRoot: knowledgeRoot, rel: rel)
        guard let data = try? Data(contentsOf: url) else { return nil }

        if let doc = try? JSONDecoder().decode(TranscriptDocument.self, from: data) {
            let segs = doc.segments.sorted { $0.index < $1.index }.map { s in
                TranscriptView.Segment(
                    index: s.index,
                    tStartMs: s.tStartMs,
                    tEndMs: s.tEndMs,
                    text: s.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    timeLabel: formatMs(s.tStartMs)
                )
            }.filter { !$0.text.isEmpty }
            let full = segs.map(\.text).joined(separator: "\n")
            return TranscriptView(
                segments: segs,
                fullText: full,
                language: doc.language,
                asrModelId: doc.asrModelId,
                transcriptRel: rel
            )
        }

        // Loose / alternate shapes
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let segsRaw = obj["segments"] as? [[String: Any]] {
            var segs: [TranscriptView.Segment] = []
            for (i, s) in segsRaw.enumerated() {
                let text = (s["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !text.isEmpty else { continue }
                let start = intAny(s["t_start_ms"] ?? s["tStartMs"] ?? s["start_ms"]) ?? 0
                let end = intAny(s["t_end_ms"] ?? s["tEndMs"] ?? s["end_ms"]) ?? start
                let idx = intAny(s["index"]) ?? i
                segs.append(.init(index: idx, tStartMs: start, tEndMs: end, text: text, timeLabel: formatMs(start)))
            }
            let full = segs.map(\.text).joined(separator: "\n")
            return TranscriptView(
                segments: segs,
                fullText: full,
                language: obj["language"] as? String,
                asrModelId: (obj["asr_model_id"] as? String) ?? (obj["asrModelId"] as? String),
                transcriptRel: rel
            )
        }
        if let text = obj["text"] as? String, !text.isEmpty {
            return TranscriptView(
                segments: [.init(index: 0, tStartMs: 0, tEndMs: 0, text: text, timeLabel: "0:00")],
                fullText: text,
                language: obj["language"] as? String,
                asrModelId: nil,
                transcriptRel: rel
            )
        }
        return nil
    }

    public static func loadVaultMarkdown(vaultRoot: URL?, vaultRel: String?) -> String? {
        guard let vaultRoot, let rel = vaultRel?.trimmingCharacters(in: .whitespacesAndNewlines), !rel.isEmpty else {
            return nil
        }
        // vault_path may be absolute or vault-relative
        let url: URL
        if rel.hasPrefix("/") {
            url = URL(fileURLWithPath: rel)
        } else {
            url = vaultRoot.appendingPathComponent(rel)
        }
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }

    public static func loadBundle(
        knowledgeRoot: URL,
        candidateRel: String?,
        transcriptRel: String?,
        vaultRel: String? = nil,
        vaultRoot: URL? = nil
    ) -> Bundle {
        Bundle(
            summary: loadSummary(knowledgeRoot: knowledgeRoot, candidateRel: candidateRel),
            transcript: loadTranscript(knowledgeRoot: knowledgeRoot, transcriptRel: transcriptRel),
            vaultMarkdown: loadVaultMarkdown(vaultRoot: vaultRoot, vaultRel: vaultRel),
            vaultRel: vaultRel
        )
    }

    // MARK: - helpers

    private static func resolve(knowledgeRoot: URL, rel: String) -> URL {
        if rel.hasPrefix("/") { return URL(fileURLWithPath: rel) }
        return knowledgeRoot.appendingPathComponent(rel)
    }

    public static func formatMs(_ ms: Int) -> String {
        let total = max(0, ms / 1000)
        let m = total / 60
        let s = total % 60
        if m >= 60 {
            let h = m / 60
            let mm = m % 60
            return String(format: "%d:%02d:%02d", h, mm, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    private static func intAny(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let d = any as? Double { return Int(d) }
        if let n = any as? NSNumber { return n.intValue }
        if let s = any as? String { return Int(s) }
        return nil
    }
}
