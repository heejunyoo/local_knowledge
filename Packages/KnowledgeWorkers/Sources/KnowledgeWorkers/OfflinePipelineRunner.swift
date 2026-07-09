import Foundation
import KnowledgeCore
import KnowledgeIndex

/// Offline vertical slice:
/// recorded → ASR → transcribed → summarizing → summarized_candidate → review_needed
/// Silent-miss forbidden.
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

    @discardableResult
    public func tick() throws -> Bool {
        try singleFlight.run {
            if let m = try store.meetings(withStatus: .recorded).first {
                try runASR(meeting: m)
                return true
            }
            // Allow retry of failed ASR (e.g. tools installed later / speech now allowed)
            if let m = try store.meetings(withStatus: .transcribeFailed).first,
               (m.stageAttempts < thresholds.maxStageAttempts) {
                try retryFailedASR(meeting: m)
                return true
            }
            if let m = try store.meetings(withStatus: .transcribed).first {
                try runSummarize(meeting: m)
                return true
            }
            return false
        }
    }

    // MARK: - ASR

    private func retryFailedASR(meeting: MeetingRecord) throws {
        // recorded-like retry: transcribe_failed → transcribing
        let ctx = GuardContext(
            hasAudioArtifact: meeting.audioPath != nil,
            audioDurationMs: meeting.audioDurationMs ?? 1
        )
        guard PipelineGraph.canTransition(from: .transcribeFailed, to: .transcribing, ctx: ctx) else {
            return
        }
        var m = meeting
        m = try store.transition(
            meetingId: meeting.id,
            to: .transcribing,
            ctx: ctx,
            event: "pipeline.asr.retry"
        ) { rec in
            rec.stageAttempts += 1
            rec.errorCode = nil
        }
        try performASR(meeting: m)
    }

    private func runASR(meeting: MeetingRecord) throws {
        let ctx = meeting.toGuardContext(workerSlotFree: true)
        guard PipelineGraph.canTransition(from: .recorded, to: .transcribing, ctx: ctx) else {
            return
        }
        let m = try store.transition(
            meetingId: meeting.id,
            to: .transcribing,
            ctx: ctx,
            event: "pipeline.asr.start"
        )
        try performASR(meeting: m)
    }

    private func performASR(meeting: MeetingRecord) throws {
        let id = meeting.id
        guard let audioRel = meeting.audioPath else {
            _ = try failASR(id: id, meeting: meeting, code: "audio_missing")
            return
        }
        let audioURL = knowledgeRoot.appendingPathComponent(audioRel)
        let outJSON = knowledgeRoot
            .appendingPathComponent("transcripts", isDirectory: true)
            .appendingPathComponent("\(id).json")
        let durationS = Double(meeting.audioDurationMs ?? 1000) / 1000.0
        let timeout = TimeInterval(thresholds.asrTimeoutSeconds(audioDurationSeconds: max(1, durationS)))

        do {
            let doc: TranscriptDocument
            let boot = ToolBootstrap(knowledgeRoot: knowledgeRoot)
            if let binary = try boot.whisperBinaryURL(),
               let model = try boot.whisperModelURL() {
                let asr = WhisperASR(
                    binaryURL: binary,
                    modelURL: model,
                    language: language,
                    thresholds: thresholds
                )
                doc = try asr.transcribe(
                    meetingId: id,
                    audioURL: audioURL,
                    outputJSON: outJSON,
                    audioDurationSeconds: max(1, durationS)
                )
            } else {
                // Apple Speech fallback — no CLI tools required
                doc = try AppleSpeechASRBridge.transcribeSync(
                    meetingId: id,
                    audioURL: audioURL,
                    outputJSON: outJSON,
                    language: language,
                    timeout: timeout
                )
            }

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
                rec.errorCode = nil
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
                case .failed(let r):
                    code = r.stderr.contains("speech_auth") ? "speech_permission" : "asr_failed"
                }
            } else {
                let msg = String(describing: error)
                code = msg.contains("authorization") || msg.contains("not authorized")
                    ? "speech_permission"
                    : "asr_failed"
            }
            _ = try failASR(id: id, meeting: meeting, code: code)
        }
    }

    private func failASR(id: String, meeting: MeetingRecord, code: String) throws -> MeetingRecord {
        let ctx = GuardContext(
            hasAudioArtifact: meeting.audioPath != nil,
            audioDurationMs: meeting.audioDurationMs ?? 0
        )
        // From transcribing only
        let from = (try? store.getMeeting(id: id))?.status ?? .transcribing
        if from == .transcribing {
            return try store.transition(
                meetingId: id,
                to: .transcribeFailed,
                ctx: ctx,
                errorCode: code,
                event: "pipeline.asr.fail"
            )
        }
        return meeting
    }

    // MARK: - Summarize

    private func runSummarize(meeting: MeetingRecord) throws {
        let id = meeting.id
        let ctx = meeting.toGuardContext(workerSlotFree: true)
        guard PipelineGraph.canTransition(from: .transcribed, to: .summarizing, ctx: ctx) else {
            return
        }
        _ = try store.transition(
            meetingId: id,
            to: .summarizing,
            ctx: ctx,
            event: "pipeline.summary.start"
        )

        guard let tRel = meeting.transcriptPath else {
            _ = try failSummary(id: id, code: "transcript_missing")
            return
        }
        let tURL = knowledgeRoot.appendingPathComponent(tRel)
        guard let data = try? Data(contentsOf: tURL),
              let transcript = try? JSONDecoder().decode(TranscriptDocument.self, from: data) else {
            _ = try failSummary(id: id, code: "transcript_unreadable")
            return
        }

        var summary = ExtractiveSummarizer.summarize(
            meetingId: id,
            transcript: transcript,
            titleHint: meeting.title
        )

        // Stage1
        let issues = MeetingSummaryValidator.validate(summary, thresholds: thresholds)
        if !issues.isEmpty {
            _ = try failSummary(id: id, code: "stage1_fail")
            return
        }

        // Stage2
        let report = Stage2Evidence.evaluate(
            summary: summary,
            transcript: transcript,
            thresholds: thresholds
        )
        summary.stage2Warnings = report.warnings.isEmpty ? nil : report.warnings

        if report.outcome == .fail {
            // Still write candidate for debugging
            try writeCandidate(id: id, summary: summary)
            _ = try failSummary(id: id, code: "stage2_fail")
            return
        }

        let candRel = try writeCandidate(id: id, summary: summary)
        let okCtx = GuardContext(
            transcriptSegmentCount: meeting.transcriptSegmentCount,
            hasTranscriptPath: true,
            stage1OK: true,
            stage2: report.outcome,
            criticEnabled: false,
            workerSlotFree: true
        )
        _ = try store.transition(
            meetingId: id,
            to: .summarizedCandidate,
            ctx: okCtx,
            event: "pipeline.summary.ok"
        ) { rec in
            rec.candidatePath = candRel
            rec.stage1OK = true
            rec.stage2Outcome = report.outcome
            rec.errorCode = nil
        }

        // critic off → review_needed
        let reviewCtx = GuardContext(stage1OK: true, stage2: report.outcome, criticEnabled: false)
        _ = try store.transition(
            meetingId: id,
            to: .reviewNeeded,
            ctx: reviewCtx,
            event: "pipeline.review_needed"
        )
    }

    private func writeCandidate(id: String, summary: MeetingSummaryV1) throws -> String {
        let dir = knowledgeRoot.appendingPathComponent("summaries", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let rel = "summaries/\(id).candidate.json"
        let url = knowledgeRoot.appendingPathComponent(rel)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        try enc.encode(summary).write(to: url, options: .atomic)
        return rel
    }

    private func failSummary(id: String, code: String) throws -> MeetingRecord {
        let ctx = GuardContext()
        return try store.transition(
            meetingId: id,
            to: .summaryFailed,
            ctx: ctx,
            errorCode: code,
            event: "pipeline.summary.fail"
        )
    }
}

public final class SingleFlightGate: @unchecked Sendable {
    private let lock = NSLock()
    private var busy = false

    public init() {}

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
