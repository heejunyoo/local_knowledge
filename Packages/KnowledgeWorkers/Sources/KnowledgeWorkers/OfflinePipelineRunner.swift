import Foundation
import KnowledgeCore
import KnowledgeIndex

/// Drives offline vertical slice: recorded → ASR → transcribed (and optional later stages).
/// Silent-miss forbidden: missing tools → explicit `transcribe_failed` with error_code.
public final class OfflinePipelineRunner: @unchecked Sendable {
    private let store: KnowledgeStore
    private let knowledgeRoot: URL
    private let thresholds: Thresholds
    private let language: String
    private let singleFlight = SingleFlightGate()

    public init(
        store: KnowledgeStore,
        knowledgeRoot: URL,
        thresholds: Thresholds = .default,
        language: String = "ko"
    ) {
        self.store = store
        self.knowledgeRoot = knowledgeRoot
        self.thresholds = thresholds
        self.language = language
    }

    /// Process at most one meeting. Returns true if work was attempted.
    @discardableResult
    public func tick() throws -> Bool {
        try singleFlight.run {
            if let m = try store.meetings(withStatus: .recorded).first {
                try runASR(meeting: m)
                return true
            }
            return false
        }
    }

    private func runASR(meeting: MeetingRecord) throws {
        let id = meeting.id
        let ctx = meeting.toGuardContext(workerSlotFree: true)

        // recorded → transcribing
        guard PipelineGraph.canTransition(from: .recorded, to: .transcribing, ctx: ctx) else {
            return
        }
        _ = try store.transition(meetingId: id, to: .transcribing, ctx: ctx, event: "pipeline.asr.start")

        let boot = ToolBootstrap(knowledgeRoot: knowledgeRoot)
        guard let binary = try boot.whisperBinaryURL(),
              let model = try boot.whisperModelURL() else {
            _ = try store.transition(
                meetingId: id,
                to: .transcribeFailed,
                ctx: GuardContext(hasAudioArtifact: true, audioDurationMs: meeting.audioDurationMs ?? 1),
                errorCode: "asr_tools_missing",
                event: "pipeline.asr.fail"
            )
            return
        }

        guard let audioRel = meeting.audioPath else {
            _ = try store.transition(
                meetingId: id,
                to: .transcribeFailed,
                ctx: GuardContext(),
                errorCode: "audio_missing",
                event: "pipeline.asr.fail"
            )
            return
        }

        let audioURL = knowledgeRoot.appendingPathComponent(audioRel)
        let outJSON = knowledgeRoot
            .appendingPathComponent("transcripts", isDirectory: true)
            .appendingPathComponent("\(id).json")
        let durationS = Double(meeting.audioDurationMs ?? 1000) / 1000.0

        let asr = WhisperASR(
            binaryURL: binary,
            modelURL: model,
            language: language,
            thresholds: thresholds
        )

        do {
            let doc = try asr.transcribe(
                meetingId: id,
                audioURL: audioURL,
                outputJSON: outJSON,
                audioDurationSeconds: max(1, durationS)
            )
            let rel = "transcripts/\(id).json"
            let doneCtx = GuardContext(
                hasAudioArtifact: true,
                audioDurationMs: meeting.audioDurationMs ?? 1,
                transcriptSegmentCount: doc.segments.count,
                hasTranscriptPath: true,
                asrModelId: doc.asrModelId,
                workerSlotFree: true
            )
            _ = try store.transition(
                meetingId: id,
                to: .transcribed,
                ctx: doneCtx,
                event: "pipeline.asr.ok"
            ) { rec in
                rec.transcriptPath = rel
                rec.transcriptSegmentCount = doc.segments.count
                rec.asrModelId = doc.asrModelId
                rec.stageAttempts = 0
            }
        } catch WorkerError.timeout {
            _ = try failASR(id: id, meeting: meeting, code: "timeout")
        } catch {
            let code: String
            if let w = error as? WorkerError {
                switch w {
                case .binaryMissing: code = "asr_binary_missing"
                case .modelMissing: code = "asr_model_missing"
                case .timeout: code = "timeout"
                case .failed: code = "asr_failed"
                }
            } else {
                code = "asr_failed"
            }
            _ = try failASR(id: id, meeting: meeting, code: code)
        }
    }

    private func failASR(id: String, meeting: MeetingRecord, code: String) throws -> MeetingRecord {
        let ctx = GuardContext(
            hasAudioArtifact: meeting.audioPath != nil,
            audioDurationMs: meeting.audioDurationMs ?? 0
        )
        return try store.transition(
            meetingId: id,
            to: .transcribeFailed,
            ctx: ctx,
            errorCode: code,
            event: "pipeline.asr.fail"
        ) { rec in
            rec.stageAttempts += 1
        }
    }
}

/// Ensures only one heavy pipeline job runs at a time (KD-18).
public final class SingleFlightGate: @unchecked Sendable {
    private let lock = NSLock()
    private var busy = false

    public init() {}

    /// If already busy, skip work (return false via optional body pattern used by tick).
    public func run(_ body: () throws -> Bool) throws -> Bool {
        lock.lock()
        if busy {
            lock.unlock()
            return false
        }
        busy = true
        lock.unlock()
        defer {
            lock.lock()
            busy = false
            lock.unlock()
        }
        return try body()
    }
}
