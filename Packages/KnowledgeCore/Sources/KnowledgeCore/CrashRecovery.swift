import Foundation

public enum RecoveryRule: String, Codable, Sendable {
    case r1OrphanEmpty = "R1"
    case r2StaleRecording = "R2"
    case r3ReenterOrFail = "R3"
    case r4CommitReconcile = "R4"
    case r5OrphanAudio = "R5"
    case r6Heartbeat = "R6"
}

public enum RecoveryAction: Equatable, Sendable {
    case transition(to: PipelineStatus, reason: String)
    case reenterWork(status: PipelineStatus)
    case reconcileCommit
    case quarantineOrphanAudio(path: String)
    case none
}

public struct MeetingRecoverySnapshot: Equatable, Sendable {
    public var status: PipelineStatus
    public var hasAudioArtifact: Bool
    public var audioDurationMs: Int
    public var audioMtimeAgeSeconds: Int?
    public var heartbeatFresh: Bool
    public var stageAttempts: Int
    public var maxStageAttempts: Int
    public var orphanAudioPath: String?

    public init(
        status: PipelineStatus,
        hasAudioArtifact: Bool = false,
        audioDurationMs: Int = 0,
        audioMtimeAgeSeconds: Int? = nil,
        heartbeatFresh: Bool = false,
        stageAttempts: Int = 0,
        maxStageAttempts: Int = Thresholds.default.maxStageAttempts,
        orphanAudioPath: String? = nil
    ) {
        self.status = status
        self.hasAudioArtifact = hasAudioArtifact
        self.audioDurationMs = audioDurationMs
        self.audioMtimeAgeSeconds = audioMtimeAgeSeconds
        self.heartbeatFresh = heartbeatFresh
        self.stageAttempts = stageAttempts
        self.maxStageAttempts = maxStageAttempts
        self.orphanAudioPath = orphanAudioPath
    }
}

/// Crash recovery rules R1–R6 from the design doc.
public enum CrashRecovery {
    public static func evaluate(
        _ snap: MeetingRecoverySnapshot,
        orphanGraceSeconds: Int = Thresholds.default.captureOrphanGraceS
    ) -> (rule: RecoveryRule?, action: RecoveryAction) {
        // R5: orphan audio file without meeting row (caller passes status placeholder abandoned + path)
        if let path = snap.orphanAudioPath {
            return (.r5OrphanAudio, .quarantineOrphanAudio(path: path))
        }

        switch snap.status {
        case .recording:
            if !snap.hasAudioArtifact || snap.audioDurationMs <= 0 {
                return (.r1OrphanEmpty, .transition(to: .recordFailed, reason: "orphan_empty"))
            }
            let age = snap.audioMtimeAgeSeconds ?? 0
            if age >= orphanGraceSeconds && !snap.heartbeatFresh {
                // R2 + R6 (heartbeat absence drives R2)
                return (.r2StaleRecording, .transition(to: .recorded, reason: "stale_recording_no_heartbeat"))
            }
            return (nil, .none)

        case .transcribing, .summarizing, .criticRunning:
            if snap.stageAttempts >= snap.maxStageAttempts {
                let failed: PipelineStatus
                switch snap.status {
                case .transcribing: failed = .transcribeFailed
                case .summarizing: failed = .summaryFailed
                case .criticRunning: failed = .criticFailed
                default: failed = .abandoned
                }
                return (.r3ReenterOrFail, .transition(to: failed, reason: "max_stage_attempts"))
            }
            return (.r3ReenterOrFail, .reenterWork(status: snap.status))

        case .commitPending:
            return (.r4CommitReconcile, .reconcileCommit)

        default:
            return (nil, .none)
        }
    }

    /// Apply recovery action through the pipeline graph when it is a status transition.
    public static func applyTransitionIfLegal(
        from: PipelineStatus,
        action: RecoveryAction,
        ctx: GuardContext
    ) -> PipelineStatus? {
        guard case let .transition(to, _) = action else { return nil }
        // Recovery edges must still be legal graph edges.
        guard PipelineGraph.canTransition(from: from, to: to, ctx: ctx) else {
            return nil
        }
        return to
    }
}
