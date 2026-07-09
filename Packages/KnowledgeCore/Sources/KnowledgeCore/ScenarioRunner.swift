import Foundation

/// Declarative eval scenario (JSON-serializable).
public struct EvalScenario: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var kind: Kind
    public var assertions: [Assertion]

    public enum Kind: String, Codable, Sendable {
        case graph
        case thresholds
        case timeout
        case recovery
    }

    public enum Assertion: Codable, Equatable, Sendable {
        case edgeExists(from: String, to: String, expected: Bool)
        case canTransition(from: String, to: String, fixture: String, expected: Bool)
        case noWildcardToCommitted
        /// `expectViolation: true` → status is success-like (timeout must not land here).
        /// `expectViolation: false` → status is a legal failure sink for timeouts.
        case timeoutPolicy(to: String, expectViolation: Bool)
        case thresholdKeysPresent
        case recovery(fromStatus: String, hasAudio: Bool, durationMs: Int, ageS: Int?, heartbeat: Bool, attempts: Int, expectTo: String?, expectRule: String?)

        enum CodingKeys: String, CodingKey {
            case type
            case from, to, expected, fixture
            case fromStatus = "from_status"
            case hasAudio = "has_audio"
            case durationMs = "duration_ms"
            case ageS = "age_s"
            case heartbeat, attempts
            case expectTo = "expect_to"
            case expectRule = "expect_rule"
            case expectViolation = "expect_violation"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let type = try c.decode(String.self, forKey: .type)
            switch type {
            case "edge_exists":
                self = .edgeExists(
                    from: try c.decode(String.self, forKey: .from),
                    to: try c.decode(String.self, forKey: .to),
                    expected: try c.decode(Bool.self, forKey: .expected)
                )
            case "can_transition":
                self = .canTransition(
                    from: try c.decode(String.self, forKey: .from),
                    to: try c.decode(String.self, forKey: .to),
                    fixture: try c.decode(String.self, forKey: .fixture),
                    expected: try c.decode(Bool.self, forKey: .expected)
                )
            case "no_wildcard_to_committed":
                self = .noWildcardToCommitted
            case "timeout_never_success", "timeout_policy":
                // timeout_never_success defaults expect_violation=true for back-compat
                let expectViolation = try c.decodeIfPresent(Bool.self, forKey: .expectViolation) ?? true
                self = .timeoutPolicy(
                    to: try c.decode(String.self, forKey: .to),
                    expectViolation: expectViolation
                )
            case "threshold_keys_present":
                self = .thresholdKeysPresent
            case "recovery":
                self = .recovery(
                    fromStatus: try c.decode(String.self, forKey: .fromStatus),
                    hasAudio: try c.decode(Bool.self, forKey: .hasAudio),
                    durationMs: try c.decode(Int.self, forKey: .durationMs),
                    ageS: try c.decodeIfPresent(Int.self, forKey: .ageS),
                    heartbeat: try c.decode(Bool.self, forKey: .heartbeat),
                    attempts: try c.decodeIfPresent(Int.self, forKey: .attempts) ?? 0,
                    expectTo: try c.decodeIfPresent(String.self, forKey: .expectTo),
                    expectRule: try c.decodeIfPresent(String.self, forKey: .expectRule)
                )
            default:
                throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown assertion type \(type)")
            }
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case let .edgeExists(from, to, expected):
                try c.encode("edge_exists", forKey: .type)
                try c.encode(from, forKey: .from)
                try c.encode(to, forKey: .to)
                try c.encode(expected, forKey: .expected)
            case let .canTransition(from, to, fixture, expected):
                try c.encode("can_transition", forKey: .type)
                try c.encode(from, forKey: .from)
                try c.encode(to, forKey: .to)
                try c.encode(fixture, forKey: .fixture)
                try c.encode(expected, forKey: .expected)
            case .noWildcardToCommitted:
                try c.encode("no_wildcard_to_committed", forKey: .type)
            case let .timeoutPolicy(to, expectViolation):
                try c.encode("timeout_policy", forKey: .type)
                try c.encode(to, forKey: .to)
                try c.encode(expectViolation, forKey: .expectViolation)
            case .thresholdKeysPresent:
                try c.encode("threshold_keys_present", forKey: .type)
            case let .recovery(fromStatus, hasAudio, durationMs, ageS, heartbeat, attempts, expectTo, expectRule):
                try c.encode("recovery", forKey: .type)
                try c.encode(fromStatus, forKey: .fromStatus)
                try c.encode(hasAudio, forKey: .hasAudio)
                try c.encode(durationMs, forKey: .durationMs)
                try c.encodeIfPresent(ageS, forKey: .ageS)
                try c.encode(heartbeat, forKey: .heartbeat)
                try c.encode(attempts, forKey: .attempts)
                try c.encodeIfPresent(expectTo, forKey: .expectTo)
                try c.encodeIfPresent(expectRule, forKey: .expectRule)
            }
        }
    }
}

public struct ScenarioResult: Equatable, Sendable {
    public var scenarioId: String
    public var passed: Bool
    public var failures: [String]

    public init(scenarioId: String, passed: Bool, failures: [String]) {
        self.scenarioId = scenarioId
        self.passed = passed
        self.failures = failures
    }
}

public enum ScenarioRunner {
    public static func run(_ scenario: EvalScenario) -> ScenarioResult {
        var failures: [String] = []
        for (idx, assertion) in scenario.assertions.enumerated() {
            if let msg = evaluate(assertion) {
                failures.append("[\(idx)] \(msg)")
            }
        }
        return ScenarioResult(
            scenarioId: scenario.id,
            passed: failures.isEmpty,
            failures: failures
        )
    }

    public static func runAll(_ scenarios: [EvalScenario]) -> [ScenarioResult] {
        scenarios.map(run)
    }

    public static func load(from url: URL) throws -> EvalScenario {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(EvalScenario.self, from: data)
    }

    public static func loadDirectory(_ dir: URL) throws -> [EvalScenario] {
        let fm = FileManager.default
        let files = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try files.map { try load(from: $0) }
    }

    private static func evaluate(_ assertion: EvalScenario.Assertion) -> String? {
        switch assertion {
        case let .edgeExists(fromRaw, toRaw, expected):
            guard let from = PipelineStatus(rawValue: fromRaw),
                  let to = PipelineStatus(rawValue: toRaw) else {
                return "unknown status \(fromRaw)->\(toRaw)"
            }
            let actual = PipelineGraph.hasEdge(from: from, to: to)
            if actual != expected {
                return "edge \(fromRaw)->\(toRaw) expected \(expected) got \(actual)"
            }
            return nil

        case let .canTransition(fromRaw, toRaw, fixture, expected):
            guard let from = PipelineStatus(rawValue: fromRaw),
                  let to = PipelineStatus(rawValue: toRaw) else {
                return "unknown status \(fromRaw)->\(toRaw)"
            }
            let ctx = fixtureContext(fixture, for: from)
            let actual = PipelineGraph.canTransition(from: from, to: to, ctx: ctx)
            if actual != expected {
                return "canTransition \(fromRaw)->\(toRaw) fixture=\(fixture) expected \(expected) got \(actual)"
            }
            return nil

        case .noWildcardToCommitted:
            let sources = PipelineGraph.committedSources
            if sources != [.commitPending] {
                return "committed sources must be only commit_pending, got \(sources.map(\.rawValue))"
            }
            // Brute: every other status must not have edge to committed
            for from in PipelineStatus.allCases where from != .commitPending {
                if PipelineGraph.hasEdge(from: from, to: .committed) {
                    return "illegal edge \(from.rawValue)->committed"
                }
            }
            return nil

        case let .timeoutPolicy(toRaw, expectViolation):
            guard let to = PipelineStatus(rawValue: toRaw) else {
                return "unknown status \(toRaw)"
            }
            let actual = PipelineGraph.isTimeoutSuccessViolation(to: to, errorCode: "timeout")
            if actual != expectViolation {
                return "timeout policy for \(toRaw): expect_violation=\(expectViolation) got \(actual)"
            }
            return nil

        case .thresholdKeysPresent:
            if Thresholds.documentationKeys.count < 20 {
                return "threshold keys too few: \(Thresholds.documentationKeys.count)"
            }
            let required = [
                "evidence_fuzzy_min",
                "asr_timeout_multiplier_rt",
                "max_stage_attempts",
                "llm_timeout_s",
            ]
            for key in required where !Thresholds.documentationKeys.contains(key) {
                return "missing threshold key \(key)"
            }
            return nil

        case let .recovery(fromStatus, hasAudio, durationMs, ageS, heartbeat, attempts, expectTo, expectRule):
            guard let status = PipelineStatus(rawValue: fromStatus) else {
                return "unknown status \(fromStatus)"
            }
            let snap = MeetingRecoverySnapshot(
                status: status,
                hasAudioArtifact: hasAudio,
                audioDurationMs: durationMs,
                audioMtimeAgeSeconds: ageS,
                heartbeatFresh: heartbeat,
                stageAttempts: attempts
            )
            let (rule, action) = CrashRecovery.evaluate(snap)
            if let expectRule {
                if rule?.rawValue != expectRule {
                    return "recovery rule expected \(expectRule) got \(rule?.rawValue ?? "nil")"
                }
            }
            if let expectTo {
                guard case let .transition(to, _) = action else {
                    return "recovery expected transition to \(expectTo), got \(action)"
                }
                if to.rawValue != expectTo {
                    return "recovery expected to \(expectTo) got \(to.rawValue)"
                }
            }
            return nil
        }
    }

    private static func fixtureContext(_ name: String, for status: PipelineStatus) -> GuardContext {
        switch name {
        case "happy":
            return .offlineHappyPath(at: status)
        case "empty":
            return GuardContext()
        case "audio_only":
            return GuardContext(hasAudioArtifact: true, audioDurationMs: 1000, workerSlotFree: true)
        case "audio_busy":
            return GuardContext(hasAudioArtifact: true, audioDurationMs: 1000, workerSlotFree: false)
        case "transcript_ready":
            return GuardContext(
                hasAudioArtifact: true,
                audioDurationMs: 1000,
                transcriptSegmentCount: 3,
                hasTranscriptPath: true,
                workerSlotFree: true
            )
        case "summary_pass":
            return GuardContext(
                hasAudioArtifact: true,
                audioDurationMs: 1000,
                transcriptSegmentCount: 3,
                hasTranscriptPath: true,
                stage1OK: true,
                stage2: .pass,
                criticEnabled: false
            )
        case "summary_fail_stage2":
            return GuardContext(
                transcriptSegmentCount: 3,
                hasTranscriptPath: true,
                stage1OK: true,
                stage2: .fail
            )
        case "critic_on":
            var c = GuardContext.offlineHappyPath(at: .summarizedCandidate)
            c.criticEnabled = true
            return c
        case "human_accept":
            var c = GuardContext.offlineHappyPath(at: .reviewNeeded)
            c.humanAccepted = true
            c.stage1OK = true
            return c
        case "commit_ready":
            return GuardContext(
                stage1OK: true,
                humanAccepted: true,
                vaultFinalExists: true,
                indexCommittedOK: true
            )
        case "open_anyway":
            return GuardContext(stage1OK: true, stage2: .passWithWarnings, openAnywayAllowed: true)
        default:
            return GuardContext()
        }
    }
}
