import Foundation
import KnowledgeCore

/// Generation cascade (product policy, 2026-07):
/// 1) Cloud free-tier **only when a key is present**
/// 2) Local **7B is the default** without keys (must be installed)
/// 3) nil → caller uses extractive (last resort only)
public enum LLMRouter {
    public struct Answer: Equatable, Sendable {
        public var text: String
        public var engine: String

        public init(text: String, engine: String) {
            self.text = text
            self.engine = engine
        }
    }

    public static func complete(
        prompt: String,
        knowledgeRoot: URL,
        maxTokens: Int = 512,
        preferCloud: Bool = true,
        preferLocal7B: Bool = true
    ) -> Answer? {
        LLMProviderCatalog.ensureInstalled(knowledgeRoot: knowledgeRoot)
        let catalog = LLMProviderCatalog.load(knowledgeRoot: knowledgeRoot)
        let cfg = AppConfig.load(knowledgeRoot: knowledgeRoot)
        let hasCloudKey = LLMSecrets.hasAnyCloudKey(knowledgeRoot: knowledgeRoot, catalog: catalog)

        // 1) Cloud free tiers — only when keys exist; redaction preflight first
        if preferCloud && cfg.cloudEnabled && hasCloudKey {
            let redaction = RedactionPreflight.scan(prompt, knowledgeRoot: knowledgeRoot)
            if redaction.allowed {
                if let cloud = tryCloud(prompt: prompt, knowledgeRoot: knowledgeRoot, catalog: catalog, maxTokens: maxTokens) {
                    return cloud
                }
            }
            // blocked or failed → fall through to local 7B
        }

        // 2) Local 7B — default path without keys
        if preferLocal7B, LocalLLM.isAvailable(knowledgeRoot: knowledgeRoot) {
            if let text = try? LocalLLM.complete(
                prompt: prompt,
                knowledgeRoot: knowledgeRoot,
                maxTokens: maxTokens,
                timeout: 180
            ), !text.isEmpty {
                return Answer(text: text, engine: "local-7b/llama")
            }
        }

        return nil
    }

    /// Status for settings / health.
    /// `activeEngine`: what will run **now** (keys → cloud, else 7B, else extractive).
    public static func status(knowledgeRoot: URL) -> (
        cloudReady: Bool,
        local7BReady: Bool,
        activeEngine: String,
        detail: String
    ) {
        LLMProviderCatalog.ensureInstalled(knowledgeRoot: knowledgeRoot)
        let catalog = LLMProviderCatalog.load(knowledgeRoot: knowledgeRoot)
        let cfg = AppConfig.load(knowledgeRoot: knowledgeRoot)
        var cloudIds: [String] = []
        for id in catalog.order {
            guard let p = catalog.providers[id] else { continue }
            if LLMSecrets.resolve(secretKey: p.apiKeySecret, envFallback: p.envFallback, knowledgeRoot: knowledgeRoot) != nil {
                cloudIds.append(id)
            }
        }
        let local = LocalLLM.isAvailable(knowledgeRoot: knowledgeRoot)
        let cloudReady = cfg.cloudEnabled && !cloudIds.isEmpty
        let active: String
        if cloudReady {
            active = "cloud-free"
        } else if local {
            active = "local-7b"
        } else {
            active = "extractive-local"
        }
        var parts: [String] = []
        if cloudReady {
            parts.append("지금: 클라우드 (\(cloudIds.joined(separator: "→")))")
        } else if local {
            parts.append("지금: 로컬 7B (기본)")
            if cfg.cloudEnabled {
                parts.append("클라우드 키 없음 → 7B 사용")
            }
        } else {
            parts.append("지금: 근거 모음")
            parts.append("7B 미설치 — scripts/install-llm-field.sh")
        }
        return (cloudReady, local, active, parts.joined(separator: " · "))
    }

    private static func tryCloud(
        prompt: String,
        knowledgeRoot: URL,
        catalog: LLMProviderCatalog,
        maxTokens: Int
    ) -> Answer? {
        for id in catalog.order {
            guard let def = catalog.providers[id] else { continue }
            guard let key = LLMSecrets.resolve(
                secretKey: def.apiKeySecret,
                envFallback: def.envFallback,
                knowledgeRoot: knowledgeRoot
            ) else { continue }
            do {
                let r = try CloudLLMClient.complete(
                    providerId: id,
                    def: def,
                    apiKey: key,
                    prompt: prompt,
                    maxTokens: maxTokens
                )
                return Answer(text: r.text, engine: r.engine)
            } catch {
                // try next free tier
                continue
            }
        }
        return nil
    }
}
