import XCTest
@testable import KnowledgeCore

final class ToolsManifestTests: XCTestCase {
    func testInstallAndVerifyUnpinned() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tools-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("config"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manifest = ToolsManifest(
            tools: [
                .init(
                    name: "whisper.cpp",
                    version: "1.7.5",
                    binaryRel: "tools/whisper.cpp/1.7.5/whisper-cli",
                    sha256: "PIN_AFTER_DOWNLOAD"
                ),
            ],
            models: [
                .init(
                    name: "whisper-large-v3-turbo",
                    rel: "tools/models/whisper/ggml-large-v3-turbo.bin",
                    sha256: "PIN_AFTER_DOWNLOAD",
                    tier: "T16"
                ),
            ]
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(manifest).write(to: root.appendingPathComponent("config/tools_manifest.json"))

        let boot = ToolBootstrap(knowledgeRoot: root)
        let src = root.appendingPathComponent("scratch-bin")
        try Data("#!/bin/sh\necho hi\n".utf8).write(to: src)

        let sha = try boot.installFile(from: src, rel: "tools/whisper.cpp/1.7.5/whisper-cli")
        XCTAssertFalse(sha.isEmpty)

        let reports = try boot.verifyAll()
        XCTAssertEqual(reports.count, 2)
        let whisper = reports.first { $0.name == "whisper.cpp" }
        XCTAssertEqual(whisper?.status, .presentUnpinned)
        let model = reports.first { $0.name.contains("whisper-large") }
        XCTAssertEqual(model?.status, .missing)
    }

    func testHashMismatch() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tools2-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("config"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let rel = "tools/x/bin"
        let src = root.appendingPathComponent("a.txt")
        try Data("hello".utf8).write(to: src)
        let boot = ToolBootstrap(knowledgeRoot: root)
        let actual = try boot.installFile(from: src, rel: rel)

        let manifest = ToolsManifest(tools: [
            .init(name: "x", version: "1", binaryRel: rel, sha256: "deadbeef"),
        ])
        try JSONEncoder().encode(manifest).write(to: root.appendingPathComponent("config/tools_manifest.json"))

        let status = try boot.verify(rel: rel, expectedSHA256: "deadbeef")
        guard case let .hashMismatch(expected, got) = status else {
            return XCTFail("expected mismatch, got \(status)")
        }
        XCTAssertEqual(expected, "deadbeef")
        XCTAssertEqual(got, actual)
    }
}
