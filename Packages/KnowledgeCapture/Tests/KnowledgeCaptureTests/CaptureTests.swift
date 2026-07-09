import XCTest
@testable import KnowledgeCapture

final class CaptureTests: XCTestCase {
    func testHeartbeatFreshness() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hb-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let hb = CaptureHeartbeat(meetingId: "m1")
        try hb.write(to: root)
        let loaded = try CaptureHeartbeat.load(from: root)
        XCTAssertEqual(loaded?.meetingId, "m1")
        XCTAssertTrue(loaded!.isFresh(maxAge: 10))

        try CaptureHeartbeat.clear(knowledgeRoot: root)
        XCTAssertNil(try CaptureHeartbeat.load(from: root))
    }

    func testAudioArtifactBuilder() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("aud-\(UUID().uuidString)", isDirectory: true)
        let rawDir = root.appendingPathComponent("audio/raw", isDirectory: true)
        try FileManager.default.createDirectory(at: rawDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = rawDir.appendingPathComponent("m9.m4a")
        try Data(repeating: 0xAB, count: 2048).write(to: file)

        let art = try AudioArtifactBuilder.build(
            knowledgeRoot: root,
            meetingId: "m9",
            fileURL: file,
            durationMs: 1500
        )
        XCTAssertEqual(art.path, "audio/raw/m9.m4a")
        XCTAssertEqual(art.durationMs, 1500)
        XCTAssertEqual(art.byteCount, 2048)
        XCTAssertEqual(art.sha256.count, 64)

        XCTAssertThrowsError(
            try AudioArtifactBuilder.build(
                knowledgeRoot: root,
                meetingId: "empty",
                fileURL: rawDir.appendingPathComponent("nope"),
                durationMs: 1
            )
        )
    }

    func testEmptyAudioRejected() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("empty-\(UUID().uuidString)", isDirectory: true)
        let file = root.appendingPathComponent("z.m4a")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: file)
        XCTAssertThrowsError(
            try AudioArtifactBuilder.build(
                knowledgeRoot: root,
                meetingId: "z",
                fileURL: file,
                durationMs: 10
            )
        ) { err in
            XCTAssertEqual(err as? CaptureError, .emptyAudio)
        }
    }
}
