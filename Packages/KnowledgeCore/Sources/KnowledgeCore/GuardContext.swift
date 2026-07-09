import Foundation

/// Snapshot of artifacts and flags used to evaluate transition guards.
public struct GuardContext: Sendable, Equatable {
    public var hasAudioArtifact: Bool
    public var audioDurationMs: Int
    public var hasDerivedAudio: Bool
    public var transcriptSegmentCount: Int
    public var hasTranscriptPath: Bool
    public var asrModelId: String?
    public var stage1OK: Bool
    public var stage2: Stage2Outcome?
    public var criticEnabled: Bool
    public var criticDone: Bool
    public var humanAccepted: Bool
    public var vaultFinalExists: Bool
    public var vaultTmpExists: Bool
    public var indexCommittedOK: Bool
    public var workerSlotFree: Bool
    public var otherRecordingActive: Bool
    public var capturePreflightOK: Bool
    /// Candidate exists with Stage1 pass and Stage2 != fail (summary_failed → review_needed).
    public var openAnywayAllowed: Bool
    public var stageAttempts: Int
    public var maxStageAttempts: Int
    public var errorCode: String?

    public init(
        hasAudioArtifact: Bool = false,
        audioDurationMs: Int = 0,
        hasDerivedAudio: Bool = false,
        transcriptSegmentCount: Int = 0,
        hasTranscriptPath: Bool = false,
        asrModelId: String? = nil,
        stage1OK: Bool = false,
        stage2: Stage2Outcome? = nil,
        criticEnabled: Bool = false,
        criticDone: Bool = false,
        humanAccepted: Bool = false,
        vaultFinalExists: Bool = false,
        vaultTmpExists: Bool = false,
        indexCommittedOK: Bool = false,
        workerSlotFree: Bool = true,
        otherRecordingActive: Bool = false,
        capturePreflightOK: Bool = true,
        openAnywayAllowed: Bool = false,
        stageAttempts: Int = 0,
        maxStageAttempts: Int = Thresholds.default.maxStageAttempts,
        errorCode: String? = nil
    ) {
        self.hasAudioArtifact = hasAudioArtifact
        self.audioDurationMs = audioDurationMs
        self.hasDerivedAudio = hasDerivedAudio
        self.transcriptSegmentCount = transcriptSegmentCount
        self.hasTranscriptPath = hasTranscriptPath
        self.asrModelId = asrModelId
        self.stage1OK = stage1OK
        self.stage2 = stage2
        self.criticEnabled = criticEnabled
        self.criticDone = criticDone
        self.humanAccepted = humanAccepted
        self.vaultFinalExists = vaultFinalExists
        self.vaultTmpExists = vaultTmpExists
        self.indexCommittedOK = indexCommittedOK
        self.workerSlotFree = workerSlotFree
        self.otherRecordingActive = otherRecordingActive
        self.capturePreflightOK = capturePreflightOK
        self.openAnywayAllowed = openAnywayAllowed
        self.stageAttempts = stageAttempts
        self.maxStageAttempts = maxStageAttempts
        self.errorCode = errorCode
    }

    public var hasTranscript: Bool {
        hasTranscriptPath && transcriptSegmentCount >= 1
    }

    public var hasSummaryEvidence: Bool {
        guard stage1OK, let stage2 else { return false }
        return stage2 == .pass || stage2 == .passWithWarnings
    }

    /// Happy-path fixture for offline MVP (critic off).
    public static func offlineHappyPath(at status: PipelineStatus) -> GuardContext {
        var ctx = GuardContext(
            hasAudioArtifact: true,
            audioDurationMs: 60_000,
            hasDerivedAudio: true,
            transcriptSegmentCount: 10,
            hasTranscriptPath: true,
            asrModelId: "whisper-large-v3-turbo",
            stage1OK: true,
            stage2: .pass,
            criticEnabled: false,
            criticDone: false,
            humanAccepted: true,
            vaultFinalExists: true,
            vaultTmpExists: false,
            indexCommittedOK: true,
            workerSlotFree: true,
            otherRecordingActive: false,
            capturePreflightOK: true
        )
        switch status {
        case .recording:
            ctx.hasAudioArtifact = false
            ctx.audioDurationMs = 0
            ctx.hasDerivedAudio = false
            ctx.transcriptSegmentCount = 0
            ctx.hasTranscriptPath = false
            ctx.stage1OK = false
            ctx.stage2 = nil
            ctx.humanAccepted = false
            ctx.vaultFinalExists = false
            ctx.indexCommittedOK = false
        case .recorded:
            ctx.hasDerivedAudio = false
            ctx.transcriptSegmentCount = 0
            ctx.hasTranscriptPath = false
            ctx.stage1OK = false
            ctx.stage2 = nil
            ctx.humanAccepted = false
            ctx.vaultFinalExists = false
            ctx.indexCommittedOK = false
        case .transcribing:
            ctx.transcriptSegmentCount = 0
            ctx.hasTranscriptPath = false
            ctx.stage1OK = false
            ctx.stage2 = nil
            ctx.humanAccepted = false
            ctx.vaultFinalExists = false
            ctx.indexCommittedOK = false
        case .transcribed:
            ctx.stage1OK = false
            ctx.stage2 = nil
            ctx.humanAccepted = false
            ctx.vaultFinalExists = false
            ctx.indexCommittedOK = false
        case .summarizing:
            ctx.stage1OK = false
            ctx.stage2 = nil
            ctx.humanAccepted = false
            ctx.vaultFinalExists = false
            ctx.indexCommittedOK = false
        case .summarizedCandidate, .criticRunning, .criticFailed, .reviewNeeded:
            ctx.humanAccepted = false
            ctx.vaultFinalExists = false
            ctx.indexCommittedOK = false
        case .commitPending:
            ctx.vaultFinalExists = false
            ctx.indexCommittedOK = false
        case .committed:
            break
        case .recordFailed, .transcribeFailed, .summaryFailed, .commitFailed, .abandoned:
            ctx.humanAccepted = false
            ctx.vaultFinalExists = false
            ctx.indexCommittedOK = false
        }
        return ctx
    }
}

public enum GuardId: String, Codable, CaseIterable, Sendable {
    case always
    case startRecording
    case audioReady
    case userOrError
    case userOnly
    case audioAndWorkerFree
    case transcriptReady
    case workerErrorOrTimeout
    case transcriptAndWorkerFree
    case summarySchemaAndEvidence
    case summaryFail
    case criticEnabled
    case criticDisabled
    case criticDone
    case criticError
    case humanAccept
    case vaultAndIndex
    case commitFail
    case openAnyway
    case retryWithAudio
    case retryAlways
}
