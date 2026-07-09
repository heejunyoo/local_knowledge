import Foundation

/// Pipeline status wire values (snake_case). Default-deny graph lands in PR-02.
public enum PipelineStatus: String, Codable, CaseIterable, Sendable {
    case recording
    case recorded
    case transcribing
    case transcribed
    case summarizing
    case summarizedCandidate = "summarized_candidate"
    case criticRunning = "critic_running"
    case criticFailed = "critic_failed"
    case reviewNeeded = "review_needed"
    case commitPending = "commit_pending"
    case committed
    case recordFailed = "record_failed"
    case transcribeFailed = "transcribe_failed"
    case summaryFailed = "summary_failed"
    case commitFailed = "commit_failed"
    case abandoned

    public var isTerminal: Bool {
        switch self {
        case .committed, .abandoned:
            return true
        default:
            return false
        }
    }

    public var isFailure: Bool {
        switch self {
        case .recordFailed, .transcribeFailed, .summaryFailed, .criticFailed, .commitFailed:
            return true
        default:
            return false
        }
    }
}

/// Stage2 evidence gate outcomes (KD-22).
public enum Stage2Outcome: String, Codable, Sendable {
    case pass
    case passWithWarnings = "pass_with_warnings"
    case fail
}

/// Quiet-by-default notification kinds (KD-11).
public enum NotificationKind: String, Codable, Sendable {
    case failure
    case reviewNeeded = "review_needed"
    case actionDue = "action_due"
}

/// Index / search source types.
public enum SourceType: String, Codable, Sendable {
    case meeting
    case obsidian
    case notes
}
