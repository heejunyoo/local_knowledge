import XCTest
import KnowledgeCore
import KnowledgeIndex
@testable import KnowledgeWorkers

final class SourceIngestTests: XCTestCase {
    func testIngestMarkdownFileAndSearch() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ingest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let md = dir.appendingPathComponent("hello.md")
        try "# 제목\n\n지식베이스 테스트 본문 유니크토큰XYZ\n".write(to: md, atomically: true, encoding: .utf8)

        let db = dir.appendingPathComponent("t.db")
        let store = try KnowledgeStore(path: db.path)
        let r = try SourceIngest.ingestURLs(urls: [md], store: store)
        XCTAssertEqual(r.imported, 1)

        let hits = try store.searchFTS(query: "유니크토큰XYZ")
        XCTAssertFalse(hits.isEmpty)
        XCTAssertEqual(hits.first?.sourceType, "file")
        XCTAssertEqual(try store.countSourcePointers(sourceType: "file"), 1)
    }

    func testIngestObsidianFolder() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }
        try FileManager.default.createDirectory(
            at: vault.appendingPathComponent(".obsidian"),
            withIntermediateDirectories: true
        )
        try "# Note A\nobsidian_unique_abc\n".write(
            to: vault.appendingPathComponent("a.md"),
            atomically: true,
            encoding: .utf8
        )

        let db = vault.appendingPathComponent("idx.db")
        let store = try KnowledgeStore(path: db.path)
        let r = try SourceIngest.ingestObsidianVault(vaultURL: vault, store: store)
        XCTAssertEqual(r.imported, 1)
        let hits = try store.searchFTS(query: "obsidian_unique_abc")
        XCTAssertEqual(hits.first?.sourceType, "obsidian")
    }

    func testMeetingEntersCorpus() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("corpus-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = try KnowledgeStore(path: dir.appendingPathComponent("c.db").path)
        let mid = "meet-1"
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("transcripts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("summaries"), withIntermediateDirectories: true)
        let tdoc = TranscriptDocument(
            meetingId: mid,
            asrModelId: "t",
            language: "ko",
            segments: [
                TranscriptSegment(index: 0, tStartMs: 0, tEndMs: 1000, text: "회의에서 로드맵을 논의했습니다"),
                TranscriptSegment(index: 1, tStartMs: 1000, tEndMs: 2000, text: "다음 주까지 스펙을 확정하기로 했습니다"),
            ]
        )
        let tURL = dir.appendingPathComponent("transcripts/\(mid).json")
        try JSONEncoder().encode(tdoc).write(to: tURL)
        let summary = MeetingSummaryV1(
            oneLineSummary: "로드맵 논의 및 스펙 확정",
            keyDiscussionPoints: [
                GroundedBullet(
                    text: "로드맵 논의",
                    evidence: [EvidenceSpan(tStartMs: 0, tEndMs: 1, quote: "로드맵")]
                ),
            ],
            modelId: "t"
        )
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        try enc.encode(summary).write(to: dir.appendingPathComponent("summaries/\(mid).candidate.json"))

        try store.insertMeeting(MeetingRecord(
            id: mid,
            title: "테스트 미팅",
            status: .committed,
            transcriptPath: "transcripts/\(mid).json",
            candidatePath: "summaries/\(mid).candidate.json",
            vaultPath: nil
        ))
        guard let m = try store.getMeeting(id: mid) else {
            XCTFail("meeting missing")
            return
        }
        let corpus = KnowledgeCorpus(store: store, knowledgeRoot: dir, vaultURL: dir)
        XCTAssertTrue(try corpus.indexMeeting(m))
        XCTAssertEqual(try store.countKnowledgeUnits(sourceType: "meeting"), 1)
        let hits = try store.searchFTS(query: "로드맵")
        XCTAssertFalse(hits.isEmpty)
        let chunks = try store.searchChunks(query: "스펙", limit: 5)
        XCTAssertFalse(chunks.isEmpty)
    }

    func testAppleNotesIngest() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("notes-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try KnowledgeStore(path: dir.appendingPathComponent("n.db").path)
        let notes = [
            SourceIngest.AppleNoteDTO(id: "x1", name: "메모1", body: "apple_notes_token_qwe", folder: "Notes"),
        ]
        let r = try SourceIngest.ingestAppleNotes(notes: notes, store: store)
        XCTAssertEqual(r.imported, 1)
        XCTAssertEqual(try store.countNoteMirrors(), 1)
        let hits = try store.searchFTS(query: "apple_notes_token_qwe")
        XCTAssertEqual(hits.first?.sourceType, "notes")
    }
}
