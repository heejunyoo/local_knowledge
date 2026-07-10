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
        preferLocal7B: Bool = true,
        localTimeout: TimeInterval = 45
    ) -> Answer? {
        LLMProviderCatalog.ensureInstalled(knowledgeRoot: knowledgeRoot)
        let catalog = LLMProviderCatalog.load(knowledgeRoot: knowledgeRoot)
        let cfg = AppConfig.load(knowledgeRoot: knowledgeRoot)
        let hasCloudKey = LLMSecrets.hasAnyCloudKey(knowledgeRoot: knowledgeRoot, catalog: catalog)

        // 0) Disk cache — same prompt must not re-hit free-tier RPD/TPM
        if let hit = LLMAnswerCache.get(knowledgeRoot: knowledgeRoot, prompt: prompt, maxTokens: maxTokens) {
            return Answer(text: hit.text, engine: hit.engine)
        }

        // 1) Cloud free tiers — only when keys exist; redaction + soft rate gate
        if preferCloud && cfg.cloudEnabled && hasCloudKey {
            let redaction = RedactionPreflight.scan(prompt, knowledgeRoot: knowledgeRoot)
            if redaction.allowed {
                if let block = LLMAnswerCache.cloudCallBlockReason(knowledgeRoot: knowledgeRoot) {
                    // Skip cloud this turn; try local 7B / extractive instead of burning RPD
                    _ = block
                } else if let cloud = tryCloud(prompt: prompt, knowledgeRoot: knowledgeRoot, catalog: catalog, maxTokens: maxTokens) {
                    LLMAnswerCache.recordCloudCall(knowledgeRoot: knowledgeRoot)
                    LLMAnswerCache.put(
                        knowledgeRoot: knowledgeRoot,
                        prompt: prompt,
                        maxTokens: maxTokens,
                        text: cloud.text,
                        engine: cloud.engine
                    )
                    return cloud
                }
            }
            // blocked or failed → fall through to local 7B
        }

        // 2) Local 7B — short timeout so UI never hangs forever
        if preferLocal7B, LocalLLM.isAvailable(knowledgeRoot: knowledgeRoot) {
            if let text = try? LocalLLM.complete(
                prompt: prompt,
                knowledgeRoot: knowledgeRoot,
                maxTokens: maxTokens,
                timeout: localTimeout
            ), !text.isEmpty {
                let ans = Answer(text: text, engine: "local-7b/llama")
                LLMAnswerCache.put(
                    knowledgeRoot: knowledgeRoot,
                    prompt: prompt,
                    maxTokens: maxTokens,
                    text: ans.text,
                    engine: ans.engine
                )
                return ans
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
        var modelHints: [String] = []
        for id in catalog.order {
            guard let p = catalog.providers[id] else { continue }
            if LLMSecrets.resolve(secretKey: p.apiKeySecret, envFallback: p.envFallback, knowledgeRoot: knowledgeRoot) != nil {
                cloudIds.append(id)
                modelHints.append("\(id):\(p.model)")
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
            parts.append("지금: 클라우드 free (\(cloudIds.joined(separator: "→")))")
            if !modelHints.isEmpty {
                parts.append("모델 \(modelHints.joined(separator: ", "))")
            }
            parts.append(LLMAnswerCache.usageSummary(knowledgeRoot: knowledgeRoot))
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
        // Only providers with keys, preserve catalog order among those that have keys.
        let keyed = catalog.order.filter { id in
            guard let def = catalog.providers[id] else { return false }
            return LLMSecrets.resolve(
                secretKey: def.apiKeySecret,
                envFallback: def.envFallback,
                knowledgeRoot: knowledgeRoot
            ) != nil
        }
        for id in keyed {
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
                // try next free tier / model fallbacks inside client
                continue
            }
        }
        return nil
    }
}
