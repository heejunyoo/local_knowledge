import XCTest
import KnowledgeCore
@testable import KnowledgeWorkers

final class MeetingArtifactReaderTests: XCTestCase {
    func testLoadSummaryAndTranscriptForReading() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("art-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let sumDir = root.appendingPathComponent("summaries", isDirectory: true)
        let txDir = root.appendingPathComponent("transcripts", isDirectory: true)
        try FileManager.default.createDirectory(at: sumDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: txDir, withIntermediateDirectories: true)

        let summary: [String: Any] = [
            "schema_version": 1,
            "one_line_summary": "프로젝트 일정 합의",
            "key_discussion_points": [
                ["text": "1분기 범위", "evidence": []],
                ["text": "인력 배정", "evidence": []],
            ],
            "decisions": [["text": "금요일 마감", "evidence": []]],
            "action_items": [["text": "초안 작성", "evidence": []]],
            "unresolved_items": [["text": "예산 미정", "evidence": []]],
            "model_id": "test",
            "created_at": "2026-07-10T00:00:00Z",
        ]
        let sumData = try JSONSerialization.data(withJSONObject: summary)
        try sumData.write(to: sumDir.appendingPathComponent("m1.candidate.json"))

        let doc = TranscriptDocument(
            meetingId: "m1",
            asrModelId: "test-asr",
            language: "ko",
            segments: [
                TranscriptSegment(index: 0, tStartMs: 0, tEndMs: 2000, text: "안녕하세요"),
                TranscriptSegment(index: 1, tStartMs: 2500, tEndMs: 5000, text: "일정 이야기합시다"),
            ]
        )
        try JSONEncoder().encode(doc).write(to: txDir.appendingPathComponent("m1.json"))

        let bundle = MeetingArtifactReader.loadBundle(
            knowledgeRoot: root,
            candidateRel: "summaries/m1.candidate.json",
            transcriptRel: "transcripts/m1.json"
        )
        XCTAssertTrue(bundle.hasReadableContent)
        XCTAssertEqual(bundle.summary?.oneLine, "프로젝트 일정 합의")
        XCTAssertEqual(bundle.summary?.discussion.count, 2)
        XCTAssertEqual(bundle.summary?.decisions.count, 1)
        XCTAssertEqual(bundle.transcript?.segmentCount, 2)
        XCTAssertTrue(bundle.transcript?.fullText.contains("안녕하세요") == true)
        XCTAssertEqual(bundle.transcript?.segments.first?.timeLabel, "0:00")
        let dict = bundle.asDict()
        XCTAssertEqual(dict["has_transcript"] as? Bool, true)
        XCTAssertEqual(dict["has_summary"] as? Bool, true)
    }
}
