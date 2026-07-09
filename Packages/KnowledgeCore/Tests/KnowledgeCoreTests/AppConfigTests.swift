import XCTest
@testable import KnowledgeCore

final class AppConfigTests: XCTestCase {
    func testLoadDefaultsWhenMissing() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("appcfg-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let cfg = AppConfig.load(knowledgeRoot: tmp)
        XCTAssertTrue(cfg.vaultPath.contains("Obsidian") || cfg.vaultPath.contains("~"))
        XCTAssertEqual(cfg.asrLanguage, "ko")
        XCTAssertTrue(cfg.cloudEnabled) // free-tier cloud first (2026-07)
    }

    func testLoadVaultPathAndEnsureDir() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("appcfg-\(UUID().uuidString)", isDirectory: true)
        let vault = tmp.appendingPathComponent("vault-out", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tmp.appendingPathComponent("config"),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tmp) }

        let json = """
        {"vault_path":"\(vault.path)","asr":{"language":"en"},"llm":{"cloud_enabled":false}}
        """
        try json.write(
            to: tmp.appendingPathComponent("config/app.json"),
            atomically: true,
            encoding: .utf8
        )

        let cfg = AppConfig.load(knowledgeRoot: tmp)
        XCTAssertEqual(cfg.vaultPath, vault.path)
        XCTAssertEqual(cfg.asrLanguage, "en")
        XCTAssertNil(cfg.ensureVaultDirectory())
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.path))
    }

    func testExpandTilde() {
        let cfg = AppConfig(vaultPath: "~/Obsidian/Main")
        XCTAssertFalse(cfg.vaultDisplayPath.contains("~"))
        XCTAssertTrue(cfg.vaultDisplayPath.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path))
    }

    func testSaveAndLoadRetentionAndRag() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("appcfg-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let cfg = AppConfig(
            vaultPath: "~/Obsidian/Main",
            asrLanguage: "ko",
            cloudEnabled: false,
            retentionAbandonedDays: 21,
            retentionAudioAfterCommitDays: 30,
            retentionPurgeOnLaunch: false,
            ragUseLlama: false
        )
        try cfg.save(knowledgeRoot: tmp)

        let loaded = AppConfig.load(knowledgeRoot: tmp)
        XCTAssertEqual(loaded.retentionAbandonedDays, 21)
        XCTAssertEqual(loaded.retentionAudioAfterCommitDays, 30)
        XCTAssertFalse(loaded.retentionPurgeOnLaunch)
        XCTAssertFalse(loaded.ragUseLlama)
        XCTAssertEqual(loaded.asrLanguage, "ko")
    }

    func testSavePreservesUnknownKeys() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("appcfg-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tmp.appendingPathComponent("config"),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tmp) }

        let json = """
        {"vault_path":"~/x","custom_flag":true,"asr":{"language":"ko","engine":"keep-me"}}
        """
        try json.write(
            to: tmp.appendingPathComponent("config/app.json"),
            atomically: true,
            encoding: .utf8
        )
        var cfg = AppConfig.load(knowledgeRoot: tmp)
        cfg.retentionAbandonedDays = 7
        try cfg.save(knowledgeRoot: tmp)

        let data = try Data(contentsOf: tmp.appendingPathComponent("config/app.json"))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(obj["custom_flag"] as? Bool, true)
        let asr = try XCTUnwrap(obj["asr"] as? [String: Any])
        XCTAssertEqual(asr["engine"] as? String, "keep-me")
        let ret = try XCTUnwrap(obj["retention"] as? [String: Any])
        XCTAssertEqual(ret["abandoned_days"] as? Int, 7)
    }
}
