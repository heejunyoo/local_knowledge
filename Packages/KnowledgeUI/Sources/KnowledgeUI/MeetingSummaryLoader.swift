import Foundation
import KnowledgeCore

/// Load candidate summary JSON for review UI (friendly display).
public enum MeetingSummaryLoader {
    public struct Display: Equatable, Sendable {
        public var oneLine: String
        public var discussion: [String]
        public var decisions: [String]
        public var actions: [String]
        public var open: [String]

        public init(
            oneLine: String = "",
            discussion: [String] = [],
            decisions: [String] = [],
            actions: [String] = [],
            open: [String] = []
        ) {
            self.oneLine = oneLine
            self.discussion = discussion
            self.decisions = decisions
            self.actions = actions
            self.open = open
        }

        public var isEmpty: Bool {
            oneLine.isEmpty && discussion.isEmpty && decisions.isEmpty && actions.isEmpty && open.isEmpty
        }
    }

    public static func load(knowledgeRoot: URL, candidateRel: String?) -> Display? {
        guard let rel = candidateRel else { return nil }
        let url = knowledgeRoot.appendingPathComponent(rel)
        guard let data = try? Data(contentsOf: url) else { return nil }
        // Prefer typed decode
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        if let s = try? dec.decode(MeetingSummaryV1.self, from: data) {
            return Display(
                oneLine: s.oneLineSummary,
                discussion: s.keyDiscussionPoints.map(\.text),
                decisions: s.decisions.map(\.text),
                actions: s.actionItems.map(\.text),
                open: s.unresolvedItems.map(\.text)
            )
        }
        // Loose parse
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func texts(_ key: String) -> [String] {
            ((obj[key] as? [[String: Any]]) ?? []).compactMap { $0["text"] as? String }
        }
        return Display(
            oneLine: (obj["one_line_summary"] as? String) ?? "",
            discussion: texts("key_discussion_points"),
            decisions: texts("decisions"),
            actions: texts("action_items"),
            open: texts("unresolved_items")
        )
    }
}
