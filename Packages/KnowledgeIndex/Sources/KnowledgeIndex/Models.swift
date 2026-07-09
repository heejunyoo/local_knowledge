import Foundation
import KnowledgeCore

public struct MeetingRecord: Equatable, Sendable, Codable {
    public var id: String
    public var title: String?
    public var mode: String
    public var status: PipelineStatus
    public var scope: String
    public var audioPath: String?
    public var audioSha256: String?
    public var audioDurationMs: Int?
    public var transcriptPath: String?
    public var transcriptSegmentCount: Int
    public var asrModelId: String?
    public var candidatePath: String?
    public var stage1OK: Bool
    public var stage2Outcome: Stage2Outcome?
    public var vaultPath: String?
    public var vaultContentHash: String?
    public var acceptedAt: String?
    public var stageAttempts: Int
    public var errorCode: String?
    public var createdAt: String
    public var updatedAt: String

    public init(
        id: String,
        title: String? = nil,
        mode: String = "offline_mic",
        status: PipelineStatus,
        scope: String = "personal",
        audioPath: String? = nil,
        audioSha256: String? = nil,
        audioDurationMs: Int? = nil,
        transcriptPath: String? = nil,
        transcriptSegmentCount: Int = 0,
        asrModelId: String? = nil,
        candidatePath: String? = nil,
        stage1OK: Bool = false,
        stage2Outcome: Stage2Outcome? = nil,
        vaultPath: String? = nil,
        vaultContentHash: String? = nil,
        acceptedAt: String? = nil,
        stageAttempts: Int = 0,
        errorCode: String? = nil,
        createdAt: String = ISO8601DateFormatter().string(from: Date()),
        updatedAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.title = title
        self.mode = mode
        self.status = status
        self.scope = scope
        self.audioPath = audioPath
        self.audioSha256 = audioSha256
        self.audioDurationMs = audioDurationMs
        self.transcriptPath = transcriptPath
        self.transcriptSegmentCount = transcriptSegmentCount
        self.asrModelId = asrModelId
        self.candidatePath = candidatePath
        self.stage1OK = stage1OK
        self.stage2Outcome = stage2Outcome
        self.vaultPath = vaultPath
        self.vaultContentHash = vaultContentHash
        self.acceptedAt = acceptedAt
        self.stageAttempts = stageAttempts
        self.errorCode = errorCode
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func toGuardContext(workerSlotFree: Bool = true, criticEnabled: Bool = false) -> GuardContext {
        GuardContext(
            hasAudioArtifact: audioPath != nil && (audioDurationMs ?? 0) > 0 && audioSha256 != nil,
            audioDurationMs: audioDurationMs ?? 0,
            hasDerivedAudio: false,
            transcriptSegmentCount: transcriptSegmentCount,
            hasTranscriptPath: transcriptPath != nil,
            asrModelId: asrModelId,
            stage1OK: stage1OK,
            stage2: stage2Outcome,
            criticEnabled: criticEnabled,
            criticDone: false,
            humanAccepted: acceptedAt != nil,
            vaultFinalExists: vaultPath != nil,
            vaultTmpExists: false,
            indexCommittedOK: status == .committed && vaultPath != nil,
            workerSlotFree: workerSlotFree,
            stageAttempts: stageAttempts,
            errorCode: errorCode
        )
    }
}

public struct PipelineEvent: Equatable, Sendable {
    public var id: Int64?
    public var meetingId: String?
    public var ts: String
    public var fromStatus: PipelineStatus?
    public var toStatus: PipelineStatus?
    public var event: String
    public var errorCode: String?
    public var detailJSON: String?

    public init(
        id: Int64? = nil,
        meetingId: String? = nil,
        ts: String = ISO8601DateFormatter().string(from: Date()),
        fromStatus: PipelineStatus? = nil,
        toStatus: PipelineStatus? = nil,
        event: String,
        errorCode: String? = nil,
        detailJSON: String? = nil
    ) {
        self.id = id
        self.meetingId = meetingId
        self.ts = ts
        self.fromStatus = fromStatus
        self.toStatus = toStatus
        self.event = event
        self.errorCode = errorCode
        self.detailJSON = detailJSON
    }
}

public struct FTSHit: Equatable, Sendable {
    public var docId: String
    public var sourceType: String
    public var title: String?
    public var snippet: String?
}
