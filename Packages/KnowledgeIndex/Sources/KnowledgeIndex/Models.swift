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

    public init(docId: String, sourceType: String, title: String?, snippet: String?) {
        self.docId = docId
        self.sourceType = sourceType
        self.title = title
        self.snippet = snippet
    }
}

/// Derived search mirror for Apple Notes (SoT remains Notes.app).
public struct NoteMirrorRecord: Equatable, Sendable {
    public var notesId: String
    public var folder: String?
    public var title: String?
    public var bodyText: String?
    public var contentHash: String?
    public var bodyStatus: String
    public var mirrorNotSot: Bool
    public var updatedAt: String

    public init(
        notesId: String,
        folder: String? = nil,
        title: String? = nil,
        bodyText: String? = nil,
        contentHash: String? = nil,
        bodyStatus: String = "ok",
        mirrorNotSot: Bool = true,
        updatedAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.notesId = notesId
        self.folder = folder
        self.title = title
        self.bodyText = bodyText
        self.contentHash = contentHash
        self.bodyStatus = bodyStatus
        self.mirrorNotSot = mirrorNotSot
        self.updatedAt = updatedAt
    }
}

/// Pointer to an external knowledge unit (notes / obsidian / file).
public struct SourcePointerRecord: Equatable, Sendable {
    public var id: String
    public var sourceType: String
    public var externalId: String
    public var title: String?
    public var scope: String
    public var meetingId: String?
    public var notesId: String?
    public var vaultRelPath: String?
    public var updatedAt: String

    public init(
        id: String,
        sourceType: String,
        externalId: String,
        title: String? = nil,
        scope: String = "personal",
        meetingId: String? = nil,
        notesId: String? = nil,
        vaultRelPath: String? = nil,
        updatedAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.sourceType = sourceType
        self.externalId = externalId
        self.title = title
        self.scope = scope
        self.meetingId = meetingId
        self.notesId = notesId
        self.vaultRelPath = vaultRelPath
        self.updatedAt = updatedAt
    }
}

public struct ConnectedSourceRecord: Equatable, Sendable {
    public var id: String
    public var sourceType: String
    public var rootPath: String?
    public var label: String?
    public var enabled: Bool
    public var lastSyncAt: String?
    public var lastError: String?
    public var unitCount: Int
    public var createdAt: String
    public var updatedAt: String

    public init(
        id: String,
        sourceType: String,
        rootPath: String? = nil,
        label: String? = nil,
        enabled: Bool = true,
        lastSyncAt: String? = nil,
        lastError: String? = nil,
        unitCount: Int = 0,
        createdAt: String = ISO8601DateFormatter().string(from: Date()),
        updatedAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.sourceType = sourceType
        self.rootPath = rootPath
        self.label = label
        self.enabled = enabled
        self.lastSyncAt = lastSyncAt
        self.lastError = lastError
        self.unitCount = unitCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct KnowledgeUnitRecord: Equatable, Sendable {
    public var unitId: String
    public var sourceType: String
    public var title: String?
    public var scope: String
    public var sotKind: String
    public var sotRef: String
    public var contentHash: String?
    public var meetingStatus: String?
    public var inCorpus: Bool
    public var ragEligible: Bool
    public var updatedAt: String

    public init(
        unitId: String,
        sourceType: String,
        title: String? = nil,
        scope: String = "personal",
        sotKind: String,
        sotRef: String,
        contentHash: String? = nil,
        meetingStatus: String? = nil,
        inCorpus: Bool = true,
        ragEligible: Bool = true,
        updatedAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.unitId = unitId
        self.sourceType = sourceType
        self.title = title
        self.scope = scope
        self.sotKind = sotKind
        self.sotRef = sotRef
        self.contentHash = contentHash
        self.meetingStatus = meetingStatus
        self.inCorpus = inCorpus
        self.ragEligible = ragEligible
        self.updatedAt = updatedAt
    }
}

public struct KnowledgeChunkRecord: Equatable, Sendable {
    public var chunkId: String
    public var unitId: String
    public var ordinal: Int
    public var text: String
    public var tStartMs: Int?
    public var tEndMs: Int?
    public var contentHash: String?

    public init(
        chunkId: String,
        unitId: String,
        ordinal: Int,
        text: String,
        tStartMs: Int? = nil,
        tEndMs: Int? = nil,
        contentHash: String? = nil
    ) {
        self.chunkId = chunkId
        self.unitId = unitId
        self.ordinal = ordinal
        self.text = text
        self.tStartMs = tStartMs
        self.tEndMs = tEndMs
        self.contentHash = contentHash
    }
}
