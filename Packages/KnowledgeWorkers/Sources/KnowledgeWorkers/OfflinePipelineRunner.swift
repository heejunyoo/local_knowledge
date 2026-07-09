import Foundation
import KnowledgeCore
import KnowledgeIndex

/// Offline pipeline:
/// - ASR (whisper only, in daemon): recorded → transcribed
/// - UI owns Apple Speech ASR (TCC); daemon must not loop-fail those
/// - Summarize: transcribed → review_needed
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

    private var hasWhisper: Bool {
        let boot = ToolBootstrap(knowledgeRoot: knowledgeRoot)
        return (try? boot.whisperBinaryURL()) != nil && (try? boot.whisperModelURL()) != nil
    }

    @discardableResult
    public func tick() throws -> Bool {
        try singleFlight.run {
            // Prefer summarize so UI-transcribed meetings progress quickly
            if let m = try store.meetings(withStatus: .transcribed).first {
                try runSummarize(meeting: m)
                return true
            }
            // Whisper-only ASR in daemon
            if hasWhisper {
                if let m = try store.meetings(withStatus: .recorded).first {
                    try runASR(meeting: m)
                    return true
                }
                if let m = try store.meetings(withStatus: .transcribeFailed).first,
                   m.errorCode != "needs_ui_asr",
                   m.stageAttempts < thresholds.maxStageAttempts {
                    try retryFailedASR(meeting: m)
                    return true
                }
            }
            // Without whisper: leave recorded / needs_ui_asr for UI — no status thrash
            return false
        }
    }

    // MARK: - ASR (whisper)

    private func retryFailedASR(meeting: MeetingRecord) throws {
        let ctx = GuardContext(
            hasAudioArtifact: meeting.audioPath != nil,
            audioDurationMs: meeting.audioDurationMs ?? 1
        )
        guard PipelineGraph.canTransition(from: .transcribeFailed, to: .transcribing, ctx: ctx) else {
            return
        }
        let m = try store.transition(
            meetingId: meeting.id,
            to: .transcribing,
            ctx: ctx,
            event: "pipeline.asr.retry"
        ) { rec in
            rec.stageAttempts += 1
            rec.errorCode = nil
        }
        try performWhisperASR(meeting: m)
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
        try performWhisperASR(meeting: m)
    }

    private func performWhisperASR(meeting: MeetingRecord) throws {
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

        let boot = ToolBootstrap(knowledgeRoot: knowledgeRoot)
        guard let binary = try boot.whisperBinaryURL(),
              let model = try boot.whisperModelURL() else {
            // Should not reach when hasWhisper is true; leave for UI without looping
            _ = try failASR(id: id, meeting: meeting, code: "needs_ui_asr")
            return
        }

        do {
            let asr = WhisperASR(
                binaryURL: binary,
                modelURL: model,
                language: language,
                thresholds: thresholds
            )
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
                rec.errorCode = nil
            }
        } catch WorkerError.timeout {
            _ = try failASR(id: id, meeting: meeting, code: "timeout")
        } catch {
            _ = try failASR(id: id, meeting: meeting, code: "asr_failed")
        }
    }

    private func failASR(id: String, meeting: MeetingRecord, code: String) throws -> MeetingRecord {
        let ctx = GuardContext(
            hasAudioArtifact: meeting.audioPath != nil,
            audioDurationMs: meeting.audioDurationMs ?? 0
        )
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
              var transcript = try? JSONDecoder().decode(TranscriptDocument.self, from: data) else {
            _ = try failSummary(id: id, code: "transcript_unreadable")
            return
        }

        // Persist coalesced segments so Stage2 quotes match corpus (word-level ASR).
        let before = transcript.segments.count
        transcript = TranscriptCoalesce.apply(to: transcript)
        if transcript.segments.count != before {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try? enc.encode(transcript).write(to: tURL, options: .atomic)
        }

        var summary = ExtractiveSummarizer.summarize(
            meetingId: id,
            transcript: transcript,
            titleHint: meeting.title
        )

        // Optional one-line polish: cloud free only (skip local 7B — cold load blocks pipeline for minutes).
        // Local 7B remains for RAG ask. Set KNOWLEDGE_SKIP_LLM_POLISH=1 to skip entirely.
        if ProcessInfo.processInfo.environment["KNOWLEDGE_SKIP_LLM_POLISH"] != "1" {
            let polishPrompt = """
            다음 회의 한 줄 요약을 한국어로 더 자연스럽게 다듬으세요.
            사실 추가 금지. 40자 이내. 설명 없이 결과만.

            원문: \(summary.oneLineSummary)

            한 줄:
            """
            if let polished = LLMRouter.complete(
                prompt: polishPrompt,
                knowledgeRoot: knowledgeRoot,
                maxTokens: 64,
                preferCloud: true,
                preferLocal7B: false
            ) {
                let line = polished.text
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .first { !$0.isEmpty } ?? polished.text
                if line.count >= 4 && line.count <= 120 {
                    summary.oneLineSummary = line
                    summary.modelId = polished.engine
                }
            }
        }

        let issues = MeetingSummaryValidator.validate(summary, thresholds: thresholds)
        if !issues.isEmpty {
            _ = try failSummary(id: id, code: "stage1_fail")
            return
        }

        let report = Stage2Evidence.evaluate(
            summary: summary,
            transcript: transcript,
            thresholds: thresholds
        )
        summary.stage2Warnings = report.warnings.isEmpty ? nil : report.warnings

        if report.outcome == .fail {
            _ = try writeCandidate(id: id, summary: summary)
            _ = try failSummary(id: id, code: "stage2_fail")
            return
        }

        var finalSummary = summary
        let flags = FeatureFlags.load(knowledgeRoot: knowledgeRoot)
        let criticOn = flags.critic

        // Optional Mode B critic
        if criticOn {
            let critic = SummaryCritic.evaluate(summary: finalSummary, transcript: transcript)
            var warns = finalSummary.stage2Warnings ?? []
            warns.append(contentsOf: critic.warnings.map { "critic:\($0)" })
            finalSummary.stage2Warnings = warns.isEmpty ? nil : warns
            if critic.hardFail {
                // Still write candidate for human review, but mark via warning
                _ = try writeCandidate(id: id, summary: finalSummary)
            }
        }

        let candRel = try writeCandidate(id: id, summary: finalSummary)
        let okCtx = GuardContext(
            transcriptSegmentCount: meeting.transcriptSegmentCount,
            hasTranscriptPath: true,
            stage1OK: true,
            stage2: report.outcome,
            criticEnabled: criticOn,
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

        if criticOn {
            let runCtx = GuardContext(
                stage1OK: true,
                stage2: report.outcome,
                criticEnabled: true,
                criticDone: false
            )
            _ = try store.transition(
                meetingId: id,
                to: .criticRunning,
                ctx: runCtx,
                event: "pipeline.critic.start"
            )
            let critic = SummaryCritic.evaluate(summary: finalSummary, transcript: transcript)
            let doneCtx = GuardContext(
                stage1OK: true,
                stage2: report.outcome,
                criticEnabled: true,
                criticDone: true
            )
            if critic.hardFail {
                // critic_error path then always → review so human can still accept
                _ = try store.transition(
                    meetingId: id,
                    to: .criticFailed,
                    ctx: GuardContext(criticEnabled: true, errorCode: "critic_hard_fail"),
                    errorCode: critic.warnings.first ?? "critic_hard_fail",
                    event: "pipeline.critic.fail"
                )
                _ = try store.transition(
                    meetingId: id,
                    to: .reviewNeeded,
                    ctx: GuardContext(),
                    event: "pipeline.critic.to_review"
                )
            } else {
                _ = try store.transition(
                    meetingId: id,
                    to: .reviewNeeded,
                    ctx: doneCtx,
                    event: "pipeline.critic.ok"
                )
            }
        } else {
            let reviewCtx = GuardContext(stage1OK: true, stage2: report.outcome, criticEnabled: false)
            _ = try store.transition(
                meetingId: id,
                to: .reviewNeeded,
                ctx: reviewCtx,
                event: "pipeline.review_needed"
            )
        }

        let reviewed = try store.getMeeting(id: id) ?? meeting
        // Draft knowledge unit (transcript+summary in corpus; RAG eligible only after commit)
        let vault = AppConfig.load(knowledgeRoot: knowledgeRoot).vaultURL
        try? KnowledgeCorpus(store: store, knowledgeRoot: knowledgeRoot, vaultURL: vault)
            .indexMeeting(reviewed)
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
        try store.transition(
            meetingId: id,
            to: .summaryFailed,
            ctx: GuardContext(),
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
