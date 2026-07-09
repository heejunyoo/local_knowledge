import XCTest
import KnowledgeCore
import KnowledgeIndex
@testable import KnowledgeWorkers

final class RAGTests: XCTestCase {
    func testAskReturnsCitationsFromCorpus() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rag-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = try KnowledgeStore(path: dir.appendingPathComponent("r.db").path)
        let unitId = "obsidian:test1"
        try store.upsertKnowledgeUnit(KnowledgeUnitRecord(
            unitId: unitId,
            sourceType: "obsidian",
            title: "선형대수 노트",
            sotKind: "vault_md",
            sotRef: "Basics.md",
            contentHash: "h1",
            ragEligible: true
        ))
        try store.replaceChunks(unitId: unitId, chunks: [
            KnowledgeChunkRecord(
                chunkId: "\(unitId)#0",
                unitId: unitId,
                ordinal: 0,
                text: "고유벡터와 고유값은 선형 변환의 핵심 개념입니다. 유니크RAG토큰XYZ",
                contentHash: "c1"
            ),
        ])
        try store.upsertFTS(
            docId: unitId,
            sourceType: "obsidian",
            title: "선형대수 노트",
            body: "고유벡터와 고유값은 선형 변환의 핵심 개념입니다. 유니크RAG토큰XYZ"
        )

        let ans = try KnowledgeRAG.ask(question: "유니크RAG토큰XYZ 고유값", store: store)
        XCTAssertFalse(ans.citations.isEmpty)
        XCTAssertTrue(ans.answer.contains("유니크RAG토큰XYZ") || ans.citations.contains(where: { $0.snippet.contains("유니크RAG토큰XYZ") }))
        // Product extractive: no engineer dump about missing LLM
        XCTAssertFalse(ans.answer.contains("LLM 없음"))
        XCTAssertFalse(ans.answer.contains("extractive"))
        XCTAssertTrue(ans.answer.contains("출처") || ans.answer.contains("근거"))
    }

    func testSynthesizeIsReadableKorean() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rag-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = try KnowledgeStore(path: dir.appendingPathComponent("r.db").path)
        let unitId = "meeting:m1"
        try store.upsertKnowledgeUnit(KnowledgeUnitRecord(
            unitId: unitId,
            sourceType: "meeting",
            title: "스프린트 계획",
            sotKind: "vault_md",
            sotRef: "Meetings/m1.md",
            contentHash: "h2",
            ragEligible: true
        ))
        try store.replaceChunks(unitId: unitId, chunks: [
            KnowledgeChunkRecord(
                chunkId: "\(unitId)#0",
                unitId: unitId,
                ordinal: 0,
                text: "다음 주 월요일까지 결제 API 스펙을 확정하기로 했습니다. 담당은 김민수입니다.",
                contentHash: "c2"
            ),
        ])

        let ans = try KnowledgeRAG.ask(question: "결제 API 스펙", store: store, useLlama: false)
        XCTAssertTrue(ans.engine.contains("extractive-rag") || ans.engine.contains("retrieve"))
        XCTAssertFalse(ans.citations.isEmpty)
        XCTAssertTrue(ans.answer.contains("결제") || ans.citations.first!.snippet.contains("결제"))
    }
}
