import XCTest
@testable import KnowledgeCore

final class KnowledgeCoreTests: XCTestCase {
    func testThresholdDocumentationKeysMatchDefaultStruct() {
        // S05 precursor: documentation key count is stable and non-empty.
        XCTAssertEqual(Thresholds.documentationKeys.count, 25)
        XCTAssertTrue(Thresholds.documentationKeys.contains("evidence_fuzzy_min"))
        XCTAssertEqual(Thresholds.default.evidenceFuzzyMin, 0.82, accuracy: 0.0001)
        XCTAssertEqual(Thresholds.default.singleFlightHeavyWorkers, 1)
    }

    func testAsrTimeoutUsesFloorAndMultiplier() {
        let t = Thresholds.default
        XCTAssertEqual(t.asrTimeoutSeconds(audioDurationSeconds: 10), 120)
        XCTAssertEqual(t.asrTimeoutSeconds(audioDurationSeconds: 100), 400)
    }

    func testFeatureFlagsFieldDefaultsOn() throws {
        let flags = FeatureFlags.mvpDefaults
        // Field complete defaults (2026-07): critic + vector hybrid + cloud opt-in path
        XCTAssertTrue(flags.critic)
        XCTAssertTrue(flags.vectorSearch)
        XCTAssertTrue(flags.cloudLlm)
        XCTAssertTrue(flags.notesIngest)

        let data = try JSONEncoder().encode(flags)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(obj["cloud_llm"] as? Bool, true)
        XCTAssertEqual(obj["vector_search"] as? Bool, true)
        XCTAssertEqual(obj["critic"] as? Bool, true)
    }

    func testMeetingSummaryStage1ValidMinimal() {
        let summary = MeetingSummaryV1(
            oneLineSummary: "팀 주간 싱크",
            modelId: "test-model"
        )
        let issues = MeetingSummaryValidator.validate(summary)
        XCTAssertTrue(issues.isEmpty, "\(issues)")
    }

    func testMeetingSummaryRejectsEmptyOneLinerAndEmptyEvidence() {
        let summary = MeetingSummaryV1(
            oneLineSummary: "   ",
            keyDiscussionPoints: [
                GroundedBullet(text: "point", evidence: [])
            ],
            modelId: "m"
        )
        let issues = MeetingSummaryValidator.validate(summary)
        XCTAssertTrue(issues.contains { $0.path == "one_line_summary" })
        XCTAssertTrue(issues.contains { $0.path == "key_discussion_points[0].evidence" })
    }

    func testMeetingSummaryRoundTripJSON() throws {
        let evidence = EvidenceSpan(tStartMs: 0, tEndMs: 1500, quote: "결정했습니다", segmentIndex: 0)
        let summary = MeetingSummaryV1(
            oneLineSummary: "로드맵 확정",
            decisions: [GroundedBullet(text: "Q3 출시", evidence: [evidence])],
            actionItems: [
                ActionItem(text: "스펙 초안", owner: nil, dueOn: "2026-07-15", evidence: [evidence])
            ],
            modelId: "qwen2.5-7b",
            createdAt: Date(timeIntervalSince1970: 1_720_000_000)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]

        let data = try encoder.encode(summary)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(object["schema_version"] as? Int, 1)
        XCTAssertEqual(object["one_line_summary"] as? String, "로드맵 확정")
        XCTAssertNotNil(object["key_discussion_points"])
        XCTAssertNotNil(object["unresolved_items"])

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(MeetingSummaryV1.self, from: data)
        XCTAssertEqual(decoded.decisions.count, 1)
        XCTAssertEqual(decoded.actionItems.first?.dueOn, "2026-07-15")
    }

    func testPipelineStatusWireValues() throws {
        XCTAssertEqual(PipelineStatus.reviewNeeded.rawValue, "review_needed")
        XCTAssertEqual(PipelineStatus.commitPending.rawValue, "commit_pending")
        XCTAssertTrue(PipelineStatus.committed.isTerminal)
        XCTAssertTrue(PipelineStatus.transcribeFailed.isFailure)

        let data = try JSONEncoder().encode(PipelineStatus.summarizedCandidate)
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"summarized_candidate\"")
    }

    func testKnowledgeRootLayoutCreate() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("KnowledgeCoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        try KnowledgePaths.ensureLayout(at: tmp)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("audio/raw").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("index").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("cache").path))
    }
}
