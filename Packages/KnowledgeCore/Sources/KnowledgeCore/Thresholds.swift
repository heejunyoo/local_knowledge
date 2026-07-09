import Foundation

/// Numeric policy mirrored from `docs/thresholds.md` (AP-12 / S05 parity).
///
/// When adding a key: update `docs/thresholds.md` in the same change.
public struct Thresholds: Codable, Equatable, Sendable {
    public var maxMeetingAudioMinutes: Int
    public var asrTimeoutMultiplierRt: Double
    public var asrTimeoutFloorS: Int
    public var asrRtfTargetP50: Double
    public var llmTimeoutS: Int
    public var llmJsonRepairMaxAttempts: Int
    public var evidenceFuzzyMin: Double
    public var evidenceMaxWarnings: Int
    public var maxStageAttempts: Int
    public var captureHeartbeatIntervalS: Int
    public var captureOrphanGraceS: Int
    public var fseventsDebounceMs: Int
    public var pipelineEventsMaxBytes: Int
    public var rawAudioRetentionDays: Int
    public var derivedAudioRetentionDays: Int
    public var uncommittedCandidateRetentionDays: Int
    public var committedCandidateRetentionDays: Int
    public var criticJsonRetentionDays: Int
    public var maxOneLineSummaryChars: Int
    public var decisionCuePatternsVersion: Int
    public var singleFlightHeavyWorkers: Int
    public var maxConcurrentRecordings: Int
    public var commitRetryMax: Int
    public var notesPageSize: Int
    public var supportBundleEventTail: Int

    public static let `default` = Thresholds(
        maxMeetingAudioMinutes: 180,
        asrTimeoutMultiplierRt: 4.0,
        asrTimeoutFloorS: 120,
        asrRtfTargetP50: 0.4,
        llmTimeoutS: 600,
        llmJsonRepairMaxAttempts: 2,
        evidenceFuzzyMin: 0.82,
        evidenceMaxWarnings: 5,
        maxStageAttempts: 2,
        captureHeartbeatIntervalS: 5,
        captureOrphanGraceS: 120,
        fseventsDebounceMs: 1500,
        pipelineEventsMaxBytes: 52_428_800,
        rawAudioRetentionDays: 90,
        derivedAudioRetentionDays: 90,
        uncommittedCandidateRetentionDays: 14,
        committedCandidateRetentionDays: 30,
        criticJsonRetentionDays: 30,
        maxOneLineSummaryChars: 280,
        decisionCuePatternsVersion: 1,
        singleFlightHeavyWorkers: 1,
        maxConcurrentRecordings: 1,
        commitRetryMax: 3,
        notesPageSize: 50,
        supportBundleEventTail: 500
    )

    public init(
        maxMeetingAudioMinutes: Int,
        asrTimeoutMultiplierRt: Double,
        asrTimeoutFloorS: Int,
        asrRtfTargetP50: Double,
        llmTimeoutS: Int,
        llmJsonRepairMaxAttempts: Int,
        evidenceFuzzyMin: Double,
        evidenceMaxWarnings: Int,
        maxStageAttempts: Int,
        captureHeartbeatIntervalS: Int,
        captureOrphanGraceS: Int,
        fseventsDebounceMs: Int,
        pipelineEventsMaxBytes: Int,
        rawAudioRetentionDays: Int,
        derivedAudioRetentionDays: Int,
        uncommittedCandidateRetentionDays: Int,
        committedCandidateRetentionDays: Int,
        criticJsonRetentionDays: Int,
        maxOneLineSummaryChars: Int,
        decisionCuePatternsVersion: Int,
        singleFlightHeavyWorkers: Int,
        maxConcurrentRecordings: Int,
        commitRetryMax: Int,
        notesPageSize: Int,
        supportBundleEventTail: Int
    ) {
        self.maxMeetingAudioMinutes = maxMeetingAudioMinutes
        self.asrTimeoutMultiplierRt = asrTimeoutMultiplierRt
        self.asrTimeoutFloorS = asrTimeoutFloorS
        self.asrRtfTargetP50 = asrRtfTargetP50
        self.llmTimeoutS = llmTimeoutS
        self.llmJsonRepairMaxAttempts = llmJsonRepairMaxAttempts
        self.evidenceFuzzyMin = evidenceFuzzyMin
        self.evidenceMaxWarnings = evidenceMaxWarnings
        self.maxStageAttempts = maxStageAttempts
        self.captureHeartbeatIntervalS = captureHeartbeatIntervalS
        self.captureOrphanGraceS = captureOrphanGraceS
        self.fseventsDebounceMs = fseventsDebounceMs
        self.pipelineEventsMaxBytes = pipelineEventsMaxBytes
        self.rawAudioRetentionDays = rawAudioRetentionDays
        self.derivedAudioRetentionDays = derivedAudioRetentionDays
        self.uncommittedCandidateRetentionDays = uncommittedCandidateRetentionDays
        self.committedCandidateRetentionDays = committedCandidateRetentionDays
        self.criticJsonRetentionDays = criticJsonRetentionDays
        self.maxOneLineSummaryChars = maxOneLineSummaryChars
        self.decisionCuePatternsVersion = decisionCuePatternsVersion
        self.singleFlightHeavyWorkers = singleFlightHeavyWorkers
        self.maxConcurrentRecordings = maxConcurrentRecordings
        self.commitRetryMax = commitRetryMax
        self.notesPageSize = notesPageSize
        self.supportBundleEventTail = supportBundleEventTail
    }

    /// SoT key names as documented in `docs/thresholds.md`.
    public static let documentationKeys: [String] = [
        "max_meeting_audio_minutes",
        "asr_timeout_multiplier_rt",
        "asr_timeout_floor_s",
        "asr_rtf_target_p50",
        "llm_timeout_s",
        "llm_json_repair_max_attempts",
        "evidence_fuzzy_min",
        "evidence_max_warnings",
        "max_stage_attempts",
        "capture_heartbeat_interval_s",
        "capture_orphan_grace_s",
        "fsevents_debounce_ms",
        "pipeline_events_max_bytes",
        "raw_audio_retention_days",
        "derived_audio_retention_days",
        "uncommitted_candidate_retention_days",
        "committed_candidate_retention_days",
        "critic_json_retention_days",
        "max_one_line_summary_chars",
        "decision_cue_patterns_version",
        "single_flight_heavy_workers",
        "max_concurrent_recordings",
        "commit_retry_max",
        "notes_page_size",
        "support_bundle_event_tail",
    ]

    public func asrTimeoutSeconds(audioDurationSeconds: Double) -> Int {
        let scaled = Int(ceil(audioDurationSeconds * asrTimeoutMultiplierRt))
        return max(asrTimeoutFloorS, scaled)
    }
}
