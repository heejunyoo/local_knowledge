import Foundation
import KnowledgeCore
import KnowledgeWorkers

/// Load candidate summary JSON for review UI (friendly display).
/// Prefer `MeetingArtifactReader` for full summary + transcript bundles.
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

        public init(from view: MeetingArtifactReader.SummaryView) {
            self.oneLine = view.oneLine
            self.discussion = view.discussion
            self.decisions = view.decisions
            self.actions = view.actions
            self.open = view.open
        }
    }

    public static func load(knowledgeRoot: URL, candidateRel: String?) -> Display? {
        guard let v = MeetingArtifactReader.loadSummary(
            knowledgeRoot: knowledgeRoot,
            candidateRel: candidateRel
        ) else { return nil }
        return Display(from: v)
    }

    public static func loadBundle(
        knowledgeRoot: URL,
        candidateRel: String?,
        transcriptRel: String?,
        vaultRel: String? = nil,
        vaultRoot: URL? = nil
    ) -> MeetingArtifactReader.Bundle {
        MeetingArtifactReader.loadBundle(
            knowledgeRoot: knowledgeRoot,
            candidateRel: candidateRel,
            transcriptRel: transcriptRel,
            vaultRel: vaultRel,
            vaultRoot: vaultRoot
        )
    }
}
