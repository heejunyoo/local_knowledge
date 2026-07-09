import Foundation

/// Meeting summary candidate — field names locked to MeetingSummaryV1 schema.
public struct MeetingSummaryV1: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var oneLineSummary: String
    public var keyDiscussionPoints: [GroundedBullet]
    public var decisions: [GroundedBullet]
    public var actionItems: [ActionItem]
    public var unresolvedItems: [GroundedBullet]
    public var modelId: String
    public var createdAt: Date
    public var warnings: [String]?
    public var stage2Warnings: [String]?

    public init(
        schemaVersion: Int = 1,
        oneLineSummary: String,
        keyDiscussionPoints: [GroundedBullet] = [],
        decisions: [GroundedBullet] = [],
        actionItems: [ActionItem] = [],
        unresolvedItems: [GroundedBullet] = [],
        modelId: String,
        createdAt: Date = Date(),
        warnings: [String]? = nil,
        stage2Warnings: [String]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.oneLineSummary = oneLineSummary
        self.keyDiscussionPoints = keyDiscussionPoints
        self.decisions = decisions
        self.actionItems = actionItems
        self.unresolvedItems = unresolvedItems
        self.modelId = modelId
        self.createdAt = createdAt
        self.warnings = warnings
        self.stage2Warnings = stage2Warnings
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case oneLineSummary = "one_line_summary"
        case keyDiscussionPoints = "key_discussion_points"
        case decisions
        case actionItems = "action_items"
        case unresolvedItems = "unresolved_items"
        case modelId = "model_id"
        case createdAt = "created_at"
        case warnings
        case stage2Warnings = "stage2_warnings"
    }
}

public struct EvidenceSpan: Codable, Equatable, Sendable {
    public var tStartMs: Int
    public var tEndMs: Int
    public var quote: String
    public var segmentIndex: Int?

    public init(tStartMs: Int, tEndMs: Int, quote: String, segmentIndex: Int? = nil) {
        self.tStartMs = tStartMs
        self.tEndMs = tEndMs
        self.quote = quote
        self.segmentIndex = segmentIndex
    }

    enum CodingKeys: String, CodingKey {
        case tStartMs = "t_start_ms"
        case tEndMs = "t_end_ms"
        case quote
        case segmentIndex = "segment_index"
    }
}

public struct GroundedBullet: Codable, Equatable, Sendable {
    public var text: String
    public var evidence: [EvidenceSpan]

    public init(text: String, evidence: [EvidenceSpan]) {
        self.text = text
        self.evidence = evidence
    }
}

public struct ActionItem: Codable, Equatable, Sendable {
    public var text: String
    public var owner: String?
    public var dueOn: String?
    public var evidence: [EvidenceSpan]

    public init(text: String, owner: String? = nil, dueOn: String? = nil, evidence: [EvidenceSpan]) {
        self.text = text
        self.owner = owner
        self.dueOn = dueOn
        self.evidence = evidence
    }

    enum CodingKeys: String, CodingKey {
        case text
        case owner
        case dueOn = "due_on"
        case evidence
    }
}

/// Stage1 structural validation (JSON Schema subset enforced in code for MVP).
public enum MeetingSummaryValidator {
    public struct Issue: Equatable, Sendable {
        public let path: String
        public let message: String

        public init(path: String, message: String) {
            self.path = path
            self.message = message
        }
    }

    public static func validate(
        _ summary: MeetingSummaryV1,
        thresholds: Thresholds = .default
    ) -> [Issue] {
        var issues: [Issue] = []

        if summary.schemaVersion != 1 {
            issues.append(.init(path: "schema_version", message: "must be 1"))
        }

        let line = summary.oneLineSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty {
            issues.append(.init(path: "one_line_summary", message: "must not be empty"))
        } else if line.count > thresholds.maxOneLineSummaryChars {
            issues.append(.init(
                path: "one_line_summary",
                message: "exceeds \(thresholds.maxOneLineSummaryChars) characters"
            ))
        }

        if summary.modelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(path: "model_id", message: "must not be empty"))
        }

        issues += validateBullets(summary.keyDiscussionPoints, path: "key_discussion_points")
        issues += validateBullets(summary.decisions, path: "decisions")
        issues += validateBullets(summary.unresolvedItems, path: "unresolved_items")
        issues += validateActions(summary.actionItems, path: "action_items")

        return issues
    }

    private static func validateBullets(_ items: [GroundedBullet], path: String) -> [Issue] {
        var issues: [Issue] = []
        for (i, item) in items.enumerated() {
            if item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(.init(path: "\(path)[\(i)].text", message: "must not be empty"))
            }
            if item.evidence.isEmpty {
                issues.append(.init(path: "\(path)[\(i)].evidence", message: "minItems 1"))
            }
            issues += validateEvidence(item.evidence, path: "\(path)[\(i)].evidence")
        }
        return issues
    }

    private static func validateActions(_ items: [ActionItem], path: String) -> [Issue] {
        var issues: [Issue] = []
        for (i, item) in items.enumerated() {
            if item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(.init(path: "\(path)[\(i)].text", message: "must not be empty"))
            }
            if item.evidence.isEmpty {
                issues.append(.init(path: "\(path)[\(i)].evidence", message: "minItems 1"))
            }
            issues += validateEvidence(item.evidence, path: "\(path)[\(i)].evidence")
        }
        return issues
    }

    private static func validateEvidence(_ spans: [EvidenceSpan], path: String) -> [Issue] {
        var issues: [Issue] = []
        for (i, span) in spans.enumerated() {
            if span.quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(.init(path: "\(path)[\(i)].quote", message: "must not be empty"))
            }
            if span.quote.count > 500 {
                issues.append(.init(path: "\(path)[\(i)].quote", message: "maxLength 500"))
            }
            if span.tStartMs < 0 || span.tEndMs < 0 {
                issues.append(.init(path: "\(path)[\(i)]", message: "timestamps must be >= 0"))
            }
            if span.tEndMs < span.tStartMs {
                issues.append(.init(path: "\(path)[\(i)]", message: "t_end_ms must be >= t_start_ms"))
            }
        }
        return issues
    }
}
