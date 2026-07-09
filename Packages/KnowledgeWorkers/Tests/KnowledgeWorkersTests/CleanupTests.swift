import XCTest
import KnowledgeCore
import KnowledgeIndex
@testable import KnowledgeWorkers

final class CleanupTests: XCTestCase {
    func testDeleteMeetingRemovesFilesAndRow() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("clean-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("audio/raw"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let mid = "del-me"
        let audio = dir.appendingPathComponent("audio/raw/\(mid).wav")
        try Data(repeating: 1, count: 2048).write(to: audio)

        let store = try KnowledgeStore(path: dir.appendingPathComponent("k.db").path)
        try store.insertMeeting(MeetingRecord(
            id: mid,
            title: "지울 미팅",
            status: .abandoned,
            audioPath: "audio/raw/\(mid).wav"
        ))
        XCTAssertNotNil(try store.getMeeting(id: mid))

        let r = try MeetingCleanup.deleteMeeting(id: mid, store: store, knowledgeRoot: dir)
        XCTAssertEqual(r.deletedMeetings, 1)
        XCTAssertGreaterThanOrEqual(r.deletedFiles, 1)
        XCTAssertNil(try store.getMeeting(id: mid))
        XCTAssertFalse(FileManager.default.fileExists(atPath: audio.path))
    }

    func testPurgeAbandoned() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("purge-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try KnowledgeStore(path: dir.appendingPathComponent("k.db").path)
        try store.insertMeeting(MeetingRecord(id: "a1", status: .abandoned))
        try store.insertMeeting(MeetingRecord(id: "c1", status: .committed))
        let r = try MeetingCleanup.purgeAbandoned(store: store, knowledgeRoot: dir)
        XCTAssertEqual(r.deletedMeetings, 1)
        XCTAssertNil(try store.getMeeting(id: "a1"))
        XCTAssertNotNil(try store.getMeeting(id: "c1"))
    }

    func testRetentionPolicyKeepsRecentAbandoned() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ret-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try KnowledgeStore(path: dir.appendingPathComponent("k.db").path)
        let recent = ISO8601DateFormatter().string(from: Date())
        try store.insertMeeting(MeetingRecord(id: "new", status: .abandoned, updatedAt: recent))
        let cfg = AppConfig(
            retentionAbandonedDays: 14,
            retentionAudioAfterCommitDays: 0,
            retentionPurgeOnLaunch: true
        )
        let r = try MeetingCleanup.runRetentionPolicy(store: store, knowledgeRoot: dir, config: cfg)
        XCTAssertEqual(r.deletedMeetings, 0)
        XCTAssertNotNil(try store.getMeeting(id: "new"))
    }
}
