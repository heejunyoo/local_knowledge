import XCTest
import KnowledgeCore
import KnowledgeIndex
@testable import KnowledgeWorkers

final class PipelineRunnerTests: XCTestCase {
    func testSummarizePathToReviewNeeded() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipe-sum-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("transcripts"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try KnowledgeStore(path: root.appendingPathComponent("k.db").path)
        let transcript = TranscriptDocument(
            meetingId: "m2",
            asrModelId: "test",
            language: "ko",
            segments: [
                TranscriptSegment(index: 0, tStartMs: 0, tEndMs: 1000, text: "결정을 내렸습니다 출시"),
                TranscriptSegment(index: 1, tStartMs: 1000, tEndMs: 2000, text: "문서를 작성해야 합니다"),
            ]
        )
        let tURL = root.appendingPathComponent("transcripts/m2.json")
        try JSONEncoder().encode(transcript).write(to: tURL)

        try store.insertMeeting(MeetingRecord(
            id: "m2",
            title: "테스트",
            status: .transcribed,
            audioPath: "audio/raw/m2.m4a",
            audioSha256: "x",
            audioDurationMs: 2000,
            transcriptPath: "transcripts/m2.json",
            transcriptSegmentCount: 2,
            asrModelId: "test"
        ))

        let runner = OfflinePipelineRunner(store: store, knowledgeRoot: root)
        XCTAssertTrue(try runner.tick())

        let m = try store.getMeeting(id: "m2")
        XCTAssertEqual(m?.status, .reviewNeeded)
        XCTAssertEqual(m?.stage1OK, true)
        XCTAssertNotNil(m?.candidatePath)
    }

    func testNoWorkWhenEmpty() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipe2-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try KnowledgeStore(path: root.appendingPathComponent("k.db").path)
        let runner = OfflinePipelineRunner(store: store, knowledgeRoot: root)
        XCTAssertFalse(try runner.tick())
    }
}
