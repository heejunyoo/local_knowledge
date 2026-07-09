import XCTest
import KnowledgeCore
@testable import KnowledgeIndex

final class KnowledgeStoreTests: XCTestCase {
    private var tmpDir: URL!
    private var store: KnowledgeStore!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("KnowledgeIndex-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let dbPath = tmpDir.appendingPathComponent("knowledge.db").path
        store = try KnowledgeStore(path: dbPath)
    }

    override func tearDownWithError() throws {
        store = nil
        if let tmpDir {
            try? FileManager.default.removeItem(at: tmpDir)
        }
    }

    func testMigrateAndSchemaVersion() throws {
        XCTAssertEqual(try store.schemaVersion(), 1)
        try store.assertMeetingHasNoBodySOTColumn()
    }

    func testInsertAndGetMeeting() throws {
        let m = MeetingRecord(id: "m1", title: "주간회의", status: .recording)
        try store.insertMeeting(m)
        let got = try store.getMeeting(id: "m1")
        XCTAssertEqual(got?.title, "주간회의")
        XCTAssertEqual(got?.status, .recording)
    }

    func testLegalTransitionAndEvents() throws {
        try store.insertMeeting(MeetingRecord(id: "m2", status: .recording))
        let ctx = GuardContext(hasAudioArtifact: true, audioDurationMs: 3000)
        let updated = try store.transition(meetingId: "m2", to: .recorded, ctx: ctx) { rec in
            rec.audioPath = "/tmp/a.m4a"
            rec.audioSha256 = "abc"
            rec.audioDurationMs = 3000
        }
        XCTAssertEqual(updated.status, .recorded)

        let events = try store.events(meetingId: "m2")
        XCTAssertEqual(events.first?.fromStatus, .recording)
        XCTAssertEqual(events.first?.toStatus, .recorded)
    }

    func testIllegalTransitionRejected() throws {
        try store.insertMeeting(MeetingRecord(id: "m3", status: .recording))
        let ctx = GuardContext(
            hasAudioArtifact: true,
            audioDurationMs: 1000,
            stage1OK: true,
            stage2: .pass,
            humanAccepted: true,
            vaultFinalExists: true,
            indexCommittedOK: true
        )
        XCTAssertThrowsError(try store.transition(meetingId: "m3", to: .committed, ctx: ctx))
    }

    func testTimeoutToSuccessRejected() throws {
        try store.insertMeeting(MeetingRecord(
            id: "m4",
            status: .transcribing,
            audioPath: "/a",
            audioSha256: "h",
            audioDurationMs: 1000,
            transcriptPath: "/t",
            transcriptSegmentCount: 2
        ))
        let ctx = GuardContext(
            hasAudioArtifact: true,
            audioDurationMs: 1000,
            transcriptSegmentCount: 2,
            hasTranscriptPath: true
        )
        XCTAssertThrowsError(
            try store.transition(meetingId: "m4", to: .transcribed, ctx: ctx, errorCode: "timeout")
        )
        // failure sink OK
        let failed = try store.transition(
            meetingId: "m4",
            to: .transcribeFailed,
            ctx: ctx,
            errorCode: "timeout"
        )
        XCTAssertEqual(failed.status, .transcribeFailed)
        XCTAssertEqual(failed.errorCode, "timeout")
    }

    func testFTSDerivedSearch() throws {
        try store.upsertFTS(
            docId: "m5",
            sourceType: "meeting",
            title: "로드맵",
            body: "Q3 출시 결정 액션아이템 스펙 초안"
        )
        let hits = try store.searchFTS(query: "출시")
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.docId, "m5")
    }

    func testOfflineHappyPathTransitions() throws {
        let id = "m6"
        try store.insertMeeting(MeetingRecord(id: id, status: .recording))

        func go(_ to: PipelineStatus, _ ctx: GuardContext, _ mutate: ((inout MeetingRecord) -> Void)? = nil) throws {
            _ = try store.transition(meetingId: id, to: to, ctx: ctx, mutate: mutate)
        }

        try go(.recorded, .init(hasAudioArtifact: true, audioDurationMs: 5000)) { r in
            r.audioPath = "audio/raw/m6.m4a"
            r.audioSha256 = "h"
            r.audioDurationMs = 5000
        }
        try go(.transcribing, .init(hasAudioArtifact: true, audioDurationMs: 5000, workerSlotFree: true))
        try go(.transcribed, .init(transcriptSegmentCount: 3, hasTranscriptPath: true)) { r in
            r.transcriptPath = "transcripts/m6.json"
            r.transcriptSegmentCount = 3
            r.asrModelId = "whisper"
        }
        try go(.summarizing, .init(transcriptSegmentCount: 3, hasTranscriptPath: true, workerSlotFree: true))
        try go(.summarizedCandidate, .init(stage1OK: true, stage2: .pass)) { r in
            r.stage1OK = true
            r.stage2Outcome = .pass
            r.candidatePath = "summaries/m6.candidate.json"
        }
        try go(.reviewNeeded, .init(criticEnabled: false))
        try go(.commitPending, .init(stage1OK: true, humanAccepted: true)) { r in
            r.acceptedAt = ISO8601DateFormatter().string(from: Date())
        }
        try go(.committed, .init(vaultFinalExists: true, indexCommittedOK: true)) { r in
            r.vaultPath = "Meetings/2026/07/m6.md"
            r.vaultContentHash = "vh"
        }

        let final = try store.getMeeting(id: id)
        XCTAssertEqual(final?.status, .committed)
        XCTAssertNotNil(final?.vaultPath)
        // S06: vault path is pointer; no body column
        try store.assertMeetingHasNoBodySOTColumn()
    }

    func testCountActiveRecordings() throws {
        try store.insertMeeting(MeetingRecord(id: "a", status: .recording))
        try store.insertMeeting(MeetingRecord(id: "b", status: .recorded))
        XCTAssertEqual(try store.countActiveRecordings(), 1)
    }
}
