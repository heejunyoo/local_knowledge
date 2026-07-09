import XCTest
import KnowledgeCore
import KnowledgeIndex
@testable import KnowledgeWorkers

final class PipelineRunnerTests: XCTestCase {
    func testMissingToolsMarksTranscribeFailed() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("config"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("audio/raw"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // Minimal unpinned manifest without actual binaries
        let manifest = """
        {"version":1,"tools":[{"name":"whisper.cpp","version":"1","binary_rel":"tools/whisper.cpp/x/whisper-cli","sha256":"PIN_AFTER_DOWNLOAD"}],"models":[{"name":"whisper-x","rel":"tools/models/whisper/m.bin","sha256":"PIN_AFTER_DOWNLOAD"}]}
        """
        try Data(manifest.utf8).write(to: root.appendingPathComponent("config/tools_manifest.json"))

        let db = root.appendingPathComponent("index/knowledge.db").path
        let store = try KnowledgeStore(path: db)
        let audio = root.appendingPathComponent("audio/raw/m1.m4a")
        try Data(repeating: 1, count: 100).write(to: audio)

        try store.insertMeeting(MeetingRecord(
            id: "m1",
            status: .recorded,
            audioPath: "audio/raw/m1.m4a",
            audioSha256: "ab",
            audioDurationMs: 1000
        ))

        let runner = OfflinePipelineRunner(store: store, knowledgeRoot: root)
        XCTAssertTrue(try runner.tick())

        let m = try store.getMeeting(id: "m1")
        XCTAssertEqual(m?.status, .transcribeFailed)
        XCTAssertEqual(m?.errorCode, "asr_tools_missing")

        let events = try store.events(meetingId: "m1")
        XCTAssertTrue(events.contains { $0.toStatus == .transcribeFailed })
        // Never silent success
        XCTAssertFalse(events.contains { $0.toStatus == .transcribed })
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
