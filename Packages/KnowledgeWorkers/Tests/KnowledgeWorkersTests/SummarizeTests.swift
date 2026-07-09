import XCTest
import KnowledgeCore
@testable import KnowledgeWorkers

final class SummarizeTests: XCTestCase {
    func testExtractiveAndStage2Pass() throws {
        let transcript = TranscriptDocument(
            meetingId: "m1",
            asrModelId: "test",
            language: "ko",
            segments: [
                TranscriptSegment(index: 0, tStartMs: 0, tEndMs: 2000, text: "오늘 로드맵을 결정했습니다"),
                TranscriptSegment(index: 1, tStartMs: 2000, tEndMs: 4000, text: "스펙 초안을 작성해야 합니다"),
                TranscriptSegment(index: 2, tStartMs: 4000, tEndMs: 6000, text: "일정은 추후 확인 필요"),
            ]
        )
        var summary = ExtractiveSummarizer.summarize(meetingId: "m1", transcript: transcript)
        XCTAssertFalse(summary.oneLineSummary.isEmpty)
        XCTAssertFalse(summary.keyDiscussionPoints.isEmpty)
        XCTAssertFalse(summary.decisions.isEmpty)
        XCTAssertFalse(summary.actionItems.isEmpty)
        XCTAssertFalse(summary.unresolvedItems.isEmpty)

        let issues = MeetingSummaryValidator.validate(summary)
        XCTAssertTrue(issues.isEmpty, "\(issues)")

        let report = Stage2Evidence.evaluate(summary: summary, transcript: transcript)
        XCTAssertNotEqual(report.outcome, .fail)
    }

    func testVaultMarkdownContainsSections() {
        let summary = MeetingSummaryV1(
            oneLineSummary: "한 줄",
            keyDiscussionPoints: [
                GroundedBullet(
                    text: "논의",
                    evidence: [EvidenceSpan(tStartMs: 0, tEndMs: 1, quote: "논의")]
                ),
            ],
            modelId: "t"
        )
        let md = VaultCommit.meetingMarkdown(
            meetingId: "x",
            title: "테스트",
            summary: summary,
            transcriptRel: "transcripts/x.json"
        )
        XCTAssertTrue(md.contains("## 주요 논의"))
        XCTAssertTrue(md.contains("## 결정 사항"))
        XCTAssertTrue(md.contains("## 액션 아이템"))
    }

    func testCoalesceWordSegments() {
        let crumbs = (0..<20).map { i in
            TranscriptSegment(index: i, tStartMs: i * 200, tEndMs: i * 200 + 180, text: "가")
        }
        let merged = TranscriptCoalesce.coalesce(crumbs)
        XCTAssertLessThan(merged.count, crumbs.count)
        XCTAssertFalse(merged.isEmpty)
        XCTAssertTrue(merged[0].text.count > 1)
    }

    func testVaultCommitWritesFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let summary = MeetingSummaryV1(
            oneLineSummary: "요약",
            modelId: "t"
        )
        let (rel, hash) = try VaultCommit.commit(
            vaultPath: dir,
            meetingId: "mid1",
            title: "미팅",
            summary: summary,
            transcriptRel: nil
        )
        XCTAssertTrue(rel.hasSuffix("mid1.md"))
        XCTAssertEqual(hash.count, 64)
        let url = dir.appendingPathComponent(rel)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}
