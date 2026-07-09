import XCTest
import KnowledgeCore
import KnowledgeIndex
@testable import KnowledgeWorkers

/// Self-scoring retrieval eval — local model only helps if retrieve hits.
final class RetrievalEvalTests: XCTestCase {
    /// Build a mini PKM corpus and score hit@k for Korean queries.
    func testRetrievalScorecardHitAtK() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("reval-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = try KnowledgeStore(path: dir.appendingPathComponent("e.db").path)

        // Fixture units (personal knowledge style)
        try index(
            store: store,
            id: "obsidian:linear",
            type: "obsidian",
            title: "선형대수 노트",
            body: """
            # 고유값
            고유벡터와 고유값은 선형 변환의 핵심 개념입니다.
            ## 응용
            PCA에서 공분산 행렬의 고유분해를 사용합니다.
            """
        )
        try index(
            store: store,
            id: "meeting:sprint",
            type: "meeting",
            title: "스프린트 계획",
            body: """
            [한줄] 결제 API 스펙을 월요일까지 확정
            [결정] 다음 주 월요일까지 결제 API 스펙 확정
            [할일] 김민수가 OpenAPI 초안 작성
            [논의] 타임아웃은 3초로 맞춤
            """
        )
        try index(
            store: store,
            id: "notes:todo",
            type: "notes",
            title: "개인 할 일",
            body: """
            ## 할 일
            - 치과 예약
            - 세금 신고 서류 준비
            """
        )
        try index(
            store: store,
            id: "obsidian:noise",
            type: "obsidian",
            title: "요리 레시피",
            body: """
            # 파스타
            물을 끓이고 소금을 넣습니다. 면은 8분 삶습니다.
            """
        )

        // (query, must-hit unitId substring)
        let cases: [(String, String)] = [
            ("고유값 PCA", "obsidian:linear"),
            ("결제 API 스펙", "meeting:sprint"),
            ("김민수 할 일", "meeting:sprint"),
            ("세금 신고", "notes:todo"),
            ("고유벡터", "obsidian:linear"),
        ]

        var hits = 0
        for (q, must) in cases {
            let ret = try LocalRetrieve.retrieve(query: q, store: store, topK: 3)
            let ok = ret.contains { $0.unitId.contains(must) || $0.unitId == must }
            if ok { hits += 1 }
            XCTAssertTrue(ok, "query=\(q) expected unit~\(must) got=\(ret.map(\.unitId))")
        }
        let score = Double(hits) / Double(cases.count)
        // Self-score: retrieval quality 0–100
        let retrievalScore = Int((score * 100).rounded())
        XCTAssertGreaterThanOrEqual(retrievalScore, 80, "retrieval self-score \(retrievalScore) < 80")
        print("SCORE retrieval_hit@3=\(retrievalScore)")
    }

    func testStructureBoostPrefersDecisions() {
        let plain = "타임아웃은 3초로 맞춤"
        let labeled = "[결정] 다음 주 월요일까지 결제 API 스펙 확정"
        XCTAssertGreaterThan(
            LocalRetrieve.structureBoost(labeled),
            LocalRetrieve.structureBoost(plain)
        )
    }

    func testChunkerKeepsHeadersAndOverlap() {
        let md = """
        # 제목
        첫 단락입니다. 내용이 조금 있습니다.

        ## 결정
        API 스펙을 확정한다.

        ## 할 일
        문서를 작성한다.
        """
        let chunks = TextChunker.chunk(md, options: .init(targetChars: 80, overlapChars: 20, minChars: 10))
        XCTAssertFalse(chunks.isEmpty)
        // Decision section should appear in some chunk
        XCTAssertTrue(chunks.contains(where: { $0.contains("결정") || $0.contains("API") }))
    }

    func testQueryTermsExpandsHangul() {
        let t = QueryTerms.expand("결제API스펙")
        XCTAssertTrue(t.contains(where: { $0.count >= 2 }))
        XCTAssertTrue(t.contains("결제") || t.contains(where: { $0.contains("결제") || $0.count == 2 }))
    }

    private func index(
        store: KnowledgeStore,
        id: String,
        type: String,
        title: String,
        body: String
    ) throws {
        try store.upsertKnowledgeUnit(KnowledgeUnitRecord(
            unitId: id,
            sourceType: type,
            title: title,
            sotKind: "vault_md",
            sotRef: id,
            contentHash: SourceIngest.sha256Hex(body),
            ragEligible: true
        ))
        let pieces = TextChunker.chunk(body)
        let chunks = pieces.enumerated().map { i, t in
            KnowledgeChunkRecord(
                chunkId: "\(id)#\(i)",
                unitId: id,
                ordinal: i,
                text: t,
                contentHash: SourceIngest.sha256Hex(t)
            )
        }
        // Also keep labeled meeting body as single chunks if short
        let finalChunks = chunks.isEmpty
            ? [KnowledgeChunkRecord(chunkId: "\(id)#0", unitId: id, ordinal: 0, text: body)]
            : chunks
        try store.replaceChunks(unitId: id, chunks: finalChunks)
        try store.upsertFTS(docId: id, sourceType: type, title: title, body: body)
    }
}
