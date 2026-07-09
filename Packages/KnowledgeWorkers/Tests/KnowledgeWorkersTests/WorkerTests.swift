import XCTest
@testable import KnowledgeWorkers

final class WorkerTests: XCTestCase {
    func testParseWhisperTranscriptionFormat() throws {
        let json = """
        {
          "transcription": [
            {"offsets": {"from": 0, "to": 1200}, "text": " 안녕하세요 "},
            {"offsets": {"from": 1200, "to": 2500}, "text": "회의 시작"}
          ]
        }
        """.data(using: .utf8)!
        let segs = try WhisperASR.parseWhisperJSON(json)
        XCTAssertEqual(segs.count, 2)
        XCTAssertEqual(segs[0].text, "안녕하세요")
        XCTAssertEqual(segs[0].tEndMs, 1200)
        XCTAssertEqual(segs[1].tStartMs, 1200)
    }

    func testParseWhisperSegmentsFormat() throws {
        let json = """
        {
          "segments": [
            {"start": 0.0, "end": 1.5, "text": "hello"},
            {"start": 1.5, "end": 3.0, "text": "world"}
          ]
        }
        """.data(using: .utf8)!
        let segs = try WhisperASR.parseWhisperJSON(json)
        XCTAssertEqual(segs.count, 2)
        XCTAssertEqual(segs[0].tEndMs, 1500)
        XCTAssertEqual(segs[1].text, "world")
    }

    func testWorkerMissingBinary() {
        let url = URL(fileURLWithPath: "/tmp/does-not-exist-whisper-cli-\(UUID().uuidString)")
        XCTAssertThrowsError(
            try WorkerProcess.run(executable: url, arguments: [], timeout: 1)
        ) { err in
            guard case WorkerError.binaryMissing = err else {
                return XCTFail("\(err)")
            }
        }
    }

    func testWorkerTimeoutNeverSuccess() throws {
        // Use /bin/sleep to verify timeout path
        let result = try WorkerProcess.run(
            executable: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["5"],
            timeout: 0.2
        )
        XCTAssertTrue(result.timedOut)
        XCTAssertFalse(result.succeeded)
    }

    func testWorkerSuccessEcho() throws {
        let result = try WorkerProcess.run(
            executable: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["ok"],
            timeout: 2
        )
        XCTAssertTrue(result.succeeded)
        XCTAssertTrue(result.stdout.contains("ok"))
        XCTAssertFalse(result.timedOut)
    }
}
