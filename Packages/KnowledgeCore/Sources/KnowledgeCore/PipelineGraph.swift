import Foundation

/// One legal edge in the pipeline graph. Illegal edges are default-deny.
public struct PipelineTransition: Hashable, Sendable {
    public let from: PipelineStatus
    public let to: PipelineStatus
    public let guardId: GuardId

    public init(from: PipelineStatus, to: PipelineStatus, guardId: GuardId) {
        self.from = from
        self.to = to
        self.guardId = guardId
    }
}

/// Data-driven pipeline graph. No wildcard `(_, .committed)` edges.
public enum PipelineGraph {
    /// Exact legal edges from the design transition table (excluding ∅ start handled separately).
    public static let transitions: [PipelineTransition] = [
        // recording
        .init(from: .recording, to: .recorded, guardId: .audioReady),
        .init(from: .recording, to: .recordFailed, guardId: .userOrError),
        .init(from: .recording, to: .abandoned, guardId: .userOnly),
        // recorded
        .init(from: .recorded, to: .transcribing, guardId: .audioAndWorkerFree),
        .init(from: .recorded, to: .abandoned, guardId: .userOnly),
        // transcribing
        .init(from: .transcribing, to: .transcribed, guardId: .transcriptReady),
        .init(from: .transcribing, to: .transcribeFailed, guardId: .workerErrorOrTimeout),
        // transcribed
        .init(from: .transcribed, to: .summarizing, guardId: .transcriptAndWorkerFree),
        .init(from: .transcribed, to: .abandoned, guardId: .userOnly),
        // summarizing
        .init(from: .summarizing, to: .summarizedCandidate, guardId: .summarySchemaAndEvidence),
        .init(from: .summarizing, to: .summaryFailed, guardId: .summaryFail),
        // summarized_candidate
        .init(from: .summarizedCandidate, to: .criticRunning, guardId: .criticEnabled),
        .init(from: .summarizedCandidate, to: .reviewNeeded, guardId: .criticDisabled),
        // critic
        .init(from: .criticRunning, to: .reviewNeeded, guardId: .criticDone),
        .init(from: .criticRunning, to: .criticFailed, guardId: .criticError),
        .init(from: .criticFailed, to: .reviewNeeded, guardId: .always),
        // review
        .init(from: .reviewNeeded, to: .commitPending, guardId: .humanAccept),
        .init(from: .reviewNeeded, to: .summarizing, guardId: .userOnly),
        .init(from: .reviewNeeded, to: .transcribing, guardId: .userOnly),
        .init(from: .reviewNeeded, to: .abandoned, guardId: .userOnly),
        // commit
        .init(from: .commitPending, to: .committed, guardId: .vaultAndIndex),
        .init(from: .commitPending, to: .commitFailed, guardId: .commitFail),
        .init(from: .commitFailed, to: .commitPending, guardId: .retryAlways),
        .init(from: .commitFailed, to: .reviewNeeded, guardId: .userOnly),
        // failure retries
        .init(from: .recordFailed, to: .recording, guardId: .userOnly),
        .init(from: .recordFailed, to: .abandoned, guardId: .userOnly),
        .init(from: .transcribeFailed, to: .transcribing, guardId: .retryWithAudio),
        .init(from: .transcribeFailed, to: .abandoned, guardId: .userOnly),
        .init(from: .summaryFailed, to: .summarizing, guardId: .retryAlways),
        .init(from: .summaryFailed, to: .reviewNeeded, guardId: .openAnyway),
        .init(from: .summaryFailed, to: .abandoned, guardId: .userOnly),
    ]

    public static var transitionSet: Set<PipelineTransition> {
        Set(transitions)
    }

    /// Edges only (ignore guard identity) for default-deny membership.
    public static func hasEdge(from: PipelineStatus, to: PipelineStatus) -> Bool {
        transitions.contains { $0.from == from && $0.to == to }
    }

    public static func transition(from: PipelineStatus, to: PipelineStatus) -> PipelineTransition? {
        transitions.first { $0.from == from && $0.to == to }
    }

    public static func evaluateGuard(_ id: GuardId, ctx: GuardContext) -> Bool {
        switch id {
        case .always:
            return true
        case .startRecording:
            return !ctx.otherRecordingActive && ctx.capturePreflightOK
        case .audioReady:
            return ctx.hasAudioArtifact && ctx.audioDurationMs > 0
        case .userOrError:
            return true
        case .userOnly:
            return true
        case .audioAndWorkerFree:
            return ctx.hasAudioArtifact && ctx.audioDurationMs > 0 && ctx.workerSlotFree
        case .transcriptReady:
            return ctx.hasTranscript
        case .workerErrorOrTimeout:
            return true
        case .transcriptAndWorkerFree:
            return ctx.hasTranscript && ctx.workerSlotFree
        case .summarySchemaAndEvidence:
            return ctx.hasSummaryEvidence
        case .summaryFail:
            return true
        case .criticEnabled:
            return ctx.criticEnabled
        case .criticDisabled:
            return !ctx.criticEnabled
        case .criticDone:
            return ctx.criticDone
        case .criticError:
            return true
        case .humanAccept:
            return ctx.humanAccepted && ctx.stage1OK
        case .vaultAndIndex:
            return ctx.vaultFinalExists && ctx.indexCommittedOK
        case .commitFail:
            return true
        case .openAnyway:
            return ctx.openAnywayAllowed
        case .retryWithAudio:
            return ctx.hasAudioArtifact && ctx.audioDurationMs > 0
        case .retryAlways:
            return true
        }
    }

    /// Default-deny: edge must exist AND guard must pass.
    public static func canTransition(
        from: PipelineStatus,
        to: PipelineStatus,
        ctx: GuardContext
    ) -> Bool {
        guard let edge = transition(from: from, to: to) else {
            return false
        }
        return evaluateGuard(edge.guardId, ctx: ctx)
    }

    /// Whether a brand-new meeting may enter `recording` (∅ → recording).
    public static func canStartRecording(ctx: GuardContext) -> Bool {
        evaluateGuard(.startRecording, ctx: ctx)
    }

    public static func legalTargets(from: PipelineStatus, ctx: GuardContext) -> [PipelineStatus] {
        transitions
            .filter { $0.from == from && evaluateGuard($0.guardId, ctx: ctx) }
            .map(\.to)
    }

    /// S11: no transition into `committed` except from `commit_pending`.
    public static var committedSources: [PipelineStatus] {
        transitions.filter { $0.to == .committed }.map(\.from)
    }

    /// Timeout may only land on failure statuses (S12).
    public static func isTimeoutSuccessViolation(to: PipelineStatus, errorCode: String?) -> Bool {
        guard errorCode == "timeout" else { return false }
        switch to {
        case .transcribeFailed, .summaryFailed, .criticFailed, .recordFailed, .commitFailed:
            return false
        default:
            return true
        }
    }
}
