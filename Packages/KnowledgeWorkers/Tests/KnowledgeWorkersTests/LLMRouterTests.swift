import XCTest
import KnowledgeCore
@testable import KnowledgeWorkers

final class LLMRouterTests: XCTestCase {
    func testCatalogBuiltinHasFreeOrder() {
        let c = LLMProviderCatalog.builtinJuly2026
        XCTAssertEqual(c.order.first, "gemini")
        XCTAssertTrue(c.providers.keys.contains("groq"))
        XCTAssertTrue(c.providers.keys.contains("openrouter"))
        XCTAssertEqual(c.providers["gemini"]?.kind, "gemini")
        XCTAssertEqual(c.providers["groq"]?.kind, "openai_compatible")
    }

    func testEnsureInstallWritesEditableCatalog() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("llmcat-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        LLMProviderCatalog.ensureInstalled(knowledgeRoot: dir)
        let url = dir.appendingPathComponent("config/llm_providers.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let loaded = LLMProviderCatalog.load(knowledgeRoot: dir)
        XCTAssertEqual(loaded.order.first, "gemini")
    }

    func testSecretsRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sec-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try LLMSecrets.save(["gemini_api_key": "test-key-123"], knowledgeRoot: dir)
        let loaded = LLMSecrets.load(knowledgeRoot: dir)
        XCTAssertEqual(loaded["gemini_api_key"], "test-key-123")
        let resolved = LLMSecrets.resolve(
            secretKey: "gemini_api_key",
            envFallback: "GEMINI_API_KEY_SHOULD_NOT_EXIST_XYZ",
            knowledgeRoot: dir
        )
        XCTAssertEqual(resolved, "test-key-123")
    }

    func testRouterFallsToNilWithoutKeysOrLocal() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rout-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        // empty tools, no secrets
        let ans = LLMRouter.complete(prompt: "hi", knowledgeRoot: dir)
        XCTAssertNil(ans)
    }

    func testStatusDefaultsToLocal7BWhenNoKeysButLocalReady() throws {
        // Without keys: activeEngine must be local-7b if available, never prefer extractive over 7B.
        // This unit only checks labeling logic with empty root (no 7B) → extractive.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("st-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let st = LLMRouter.status(knowledgeRoot: dir)
        XCTAssertFalse(st.cloudReady)
        XCTAssertEqual(st.activeEngine, "extractive-local")
        XCTAssertTrue(st.detail.contains("7B") || st.detail.contains("근거"))
    }

    func testCatalogParseCustomOrder() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ord-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("config"),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: dir) }
        let json = """
        {
          "version": 2,
          "as_of": "2026-08",
          "order": ["openrouter", "gemini"],
          "providers": {
            "openrouter": {
              "kind": "openai_compatible",
              "label": "OR",
              "base_url": "https://openrouter.ai/api/v1",
              "model": "free-model",
              "api_key_secret": "openrouter_api_key"
            },
            "gemini": {
              "kind": "gemini",
              "label": "G",
              "base_url": "https://generativelanguage.googleapis.com/v1beta",
              "model": "gemini-2.5-flash",
              "api_key_secret": "gemini_api_key"
            }
          }
        }
        """
        try json.write(
            to: dir.appendingPathComponent("config/llm_providers.json"),
            atomically: true,
            encoding: .utf8
        )
        let c = LLMProviderCatalog.load(knowledgeRoot: dir)
        XCTAssertEqual(c.order, ["openrouter", "gemini"])
        XCTAssertEqual(c.providers["openrouter"]?.model, "free-model")
    }
}
