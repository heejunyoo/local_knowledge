import XCTest
import KnowledgeCore
import KnowledgeIndex
@testable import KnowledgeWorkers

final class PhaseCompleteTests: XCTestCase {
    func testHashEmbedCosineSelf() {
        let a = LocalHashEmbedder.embed("결제 API 스펙 확정")
        let b = LocalHashEmbedder.embed("결제 API 스펙 확정")
        XCTAssertEqual(a.count, LocalHashEmbedder.dimension)
        XCTAssertGreaterThan(LocalHashEmbedder.cosine(a, b), 0.99)
    }

    func testHybridRetrievalUsesVectors() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hyb-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try KnowledgeStore(path: dir.appendingPathComponent("h.db").path)
        let id = "obsidian:vec1"
        try store.upsertKnowledgeUnit(KnowledgeUnitRecord(
            unitId: id, sourceType: "obsidian", title: "벡터노트",
            sotKind: "vault_md", sotRef: "v.md", contentHash: "h", ragEligible: true
        ))
        let text = "하이브리드 검색을 위한 고유벡터 청크 유니크XYZ"
        try store.replaceChunks(unitId: id, chunks: [
            KnowledgeChunkRecord(chunkId: "\(id)#0", unitId: id, ordinal: 0, text: text)
        ])
        try LocalHashEmbedder.indexUnit(store: store, unitId: id)
        let hits = try LocalRetrieve.retrieve(query: "유니크XYZ 하이브리드", store: store, topK: 3)
        XCTAssertFalse(hits.isEmpty)
        XCTAssertEqual(hits.first?.unitId, id)
    }

    func testRedactionBlocksAWSKey() {
        let r = RedactionPreflight.scan("key=AKIAIOSFODNN7EXAMPLE rest")
        XCTAssertFalse(r.allowed)
        XCTAssertTrue(r.hits.contains(where: { $0.id == "aws_access_key" }))
    }

    func testRedactionAllowsClean() {
        let r = RedactionPreflight.scan("미팅에서 API 스펙을 논의했습니다.")
        XCTAssertTrue(r.allowed)
    }

    func testCriticEmptyDecisionsWithCues() {
        let segs = [
            TranscriptSegment(index: 0, tStartMs: 0, tEndMs: 1000, text: "그럼 월요일까지 스펙 확정하기로 결정하자"),
        ]
        let doc = TranscriptDocument(meetingId: "m", asrModelId: "t", language: "ko", segments: segs)
        let summary = MeetingSummaryV1(
            oneLineSummary: "회의함",
            decisions: [],
            modelId: "test"
        )
        let rep = SummaryCritic.evaluate(summary: summary, transcript: doc)
        XCTAssertTrue(rep.hardFail)
        XCTAssertTrue(rep.warnings.contains(where: { $0.contains("empty_decisions") }))
    }

    func testActionDueSoon() {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        let today = f.string(from: Date())
        let items = [
            ActionDueNotifier.Item(id: "1", meetingId: "m", text: "할일", dueOn: today),
            ActionDueNotifier.Item(id: "2", meetingId: "m", text: "나중", dueOn: "2099-01-01"),
        ]
        let due = ActionDueNotifier.dueSoon(items: items, withinDays: 3)
        XCTAssertEqual(due.count, 1)
        XCTAssertEqual(due.first?.id, "1")
    }

    func testFeatureFlagsLoadSave() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ff-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var f = FeatureFlags.mvpDefaults
        f.critic = true
        f.vectorSearch = true
        try f.save(knowledgeRoot: dir)
        let loaded = FeatureFlags.load(knowledgeRoot: dir)
        XCTAssertTrue(loaded.critic)
        XCTAssertTrue(loaded.vectorSearch)
    }
}
