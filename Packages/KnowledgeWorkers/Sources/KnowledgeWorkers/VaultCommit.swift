import Foundation
import CryptoKit
import KnowledgeCore

public enum VaultCommit {
    public static func meetingMarkdown(
        meetingId: String,
        title: String,
        summary: MeetingSummaryV1,
        transcriptRel: String?
    ) -> String {
        var lines: [String] = []
        lines.append("---")
        lines.append("id: \(meetingId)")
        lines.append("title: \(yamlEscape(title))")
        lines.append("schema_version: \(summary.schemaVersion)")
        lines.append("model_id: \(summary.modelId)")
        lines.append("created_at: \(iso(summary.createdAt))")
        lines.append("type: meeting")
        lines.append("---")
        lines.append("")
        lines.append("# \(title)")
        lines.append("")
        lines.append("> \(summary.oneLineSummary)")
        lines.append("")
        lines.append("## 주요 논의")
        appendBullets(&lines, summary.keyDiscussionPoints)
        lines.append("")
        lines.append("## 결정 사항")
        appendBullets(&lines, summary.decisions)
        lines.append("")
        lines.append("## 액션 아이템")
        if summary.actionItems.isEmpty {
            lines.append("- (없음)")
        } else {
            for a in summary.actionItems {
                var line = "- \(a.text)"
                if let o = a.owner { line += " · \(o)" }
                if let d = a.dueOn { line += " · 기한 \(d)" }
                lines.append(line)
                if let q = a.evidence.first?.quote {
                    lines.append("  - 근거: \"\(q)\"")
                }
            }
        }
        lines.append("")
        lines.append("## 미해결 / 오픈")
        appendBullets(&lines, summary.unresolvedItems)
        if let transcriptRel {
            lines.append("")
            lines.append("## 소스")
            lines.append("- transcript: `\(transcriptRel)`")
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// Two-phase: write .tmp then rename. Returns path relative to vault root.
    public static func commit(
        vaultPath: URL,
        meetingId: String,
        title: String,
        summary: MeetingSummaryV1,
        transcriptRel: String?,
        date: Date = Date()
    ) throws -> (relativePath: String, contentHash: String) {
        let cal = Calendar.current
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        let dir = vaultPath
            .appendingPathComponent("Meetings", isDirectory: true)
            .appendingPathComponent(String(format: "%04d", y), isDirectory: true)
            .appendingPathComponent(String(format: "%02d", m), isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let fileName = "\(meetingId).md"
        let finalURL = dir.appendingPathComponent(fileName)
        let tmpURL = dir.appendingPathComponent("\(fileName).tmp")

        let body = meetingMarkdown(
            meetingId: meetingId,
            title: title,
            summary: summary,
            transcriptRel: transcriptRel
        )
        let data = Data(body.utf8)
        try data.write(to: tmpURL, options: .atomic)
        if FileManager.default.fileExists(atPath: finalURL.path) {
            try FileManager.default.removeItem(at: finalURL)
        }
        try FileManager.default.moveItem(at: tmpURL, to: finalURL)

        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let rel = "Meetings/\(String(format: "%04d", y))/\(String(format: "%02d", m))/\(fileName)"
        return (rel, hash)
    }

    private static func appendBullets(_ lines: inout [String], _ items: [GroundedBullet]) {
        if items.isEmpty {
            lines.append("- (없음)")
            return
        }
        for b in items {
            lines.append("- \(b.text)")
            if let q = b.evidence.first?.quote {
                lines.append("  - 근거: \"\(q)\"")
            }
        }
    }

    private static func yamlEscape(_ s: String) -> String {
        "\"\(s.replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private static func iso(_ d: Date) -> String {
        ISO8601DateFormatter().string(from: d)
    }
}
