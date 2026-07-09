import Foundation

/// Swappable free-tier provider catalog (`config/llm_providers.json`).
/// Change models / order / endpoints without rebuilding — free tiers rotate often.
public struct LLMProviderCatalog: Equatable, Sendable {
    public var version: Int
    public var asOf: String
    public var notes: String
    public var order: [String]
    public var providers: [String: ProviderDef]

    public struct ProviderDef: Equatable, Sendable {
        public var kind: String // gemini | openai_compatible
        public var label: String
        public var baseURL: String
        public var model: String
        public var fallbackModels: [String]
        public var apiKeySecret: String
        public var envFallback: String?
        public var docsURL: String?
        public var timeoutSec: TimeInterval
        public var extraHeaders: [String: String]

        public init(
            kind: String,
            label: String,
            baseURL: String,
            model: String,
            fallbackModels: [String] = [],
            apiKeySecret: String,
            envFallback: String? = nil,
            docsURL: String? = nil,
            timeoutSec: TimeInterval = 45,
            extraHeaders: [String: String] = [:]
        ) {
            self.kind = kind
            self.label = label
            self.baseURL = baseURL
            self.model = model
            self.fallbackModels = fallbackModels
            self.apiKeySecret = apiKeySecret
            self.envFallback = envFallback
            self.docsURL = docsURL
            self.timeoutSec = timeoutSec
            self.extraHeaders = extraHeaders
        }

        public var modelsToTry: [String] {
            [model] + fallbackModels.filter { $0 != model }
        }
    }

    public static let builtinJuly2026 = LLMProviderCatalog(
        version: 1,
        asOf: "2026-07",
        notes: "Built-in free-tier defaults (Jul 2026). Override via config/llm_providers.json.",
        order: ["gemini", "groq", "openrouter"],
        providers: [
            "gemini": ProviderDef(
                kind: "gemini",
                label: "Google Gemini free",
                baseURL: "https://generativelanguage.googleapis.com/v1beta",
                model: "gemini-2.5-flash",
                fallbackModels: ["gemini-3.5-flash", "gemini-2.0-flash"],
                apiKeySecret: "gemini_api_key",
                envFallback: "GEMINI_API_KEY",
                docsURL: "https://aistudio.google.com/apikey"
            ),
            "groq": ProviderDef(
                kind: "openai_compatible",
                label: "Groq free",
                baseURL: "https://api.groq.com/openai/v1",
                model: "llama-3.3-70b-versatile",
                fallbackModels: ["llama-3.1-8b-instant"],
                apiKeySecret: "groq_api_key",
                envFallback: "GROQ_API_KEY",
                docsURL: "https://console.groq.com/keys"
            ),
            "openrouter": ProviderDef(
                kind: "openai_compatible",
                label: "OpenRouter free",
                baseURL: "https://openrouter.ai/api/v1",
                model: "google/gemini-2.0-flash-exp:free",
                fallbackModels: ["meta-llama/llama-3.3-70b-instruct:free"],
                apiKeySecret: "openrouter_api_key",
                envFallback: "OPENROUTER_API_KEY",
                docsURL: "https://openrouter.ai/keys",
                timeoutSec: 60,
                extraHeaders: [
                    "HTTP-Referer": "https://local.knowledge.app",
                    "X-Title": "Knowledge",
                ]
            ),
        ]
    )

    public static func load(knowledgeRoot: URL) -> LLMProviderCatalog {
        let url = knowledgeRoot.appendingPathComponent("config/llm_providers.json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .builtinJuly2026
        }
        return parse(obj) ?? .builtinJuly2026
    }

    /// Ensure user config exists so they can edit without hunting examples.
    public static func ensureInstalled(knowledgeRoot: URL) {
        let dest = knowledgeRoot.appendingPathComponent("config/llm_providers.json")
        guard !FileManager.default.fileExists(atPath: dest.path) else { return }
        try? FileManager.default.createDirectory(
            at: dest.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Write builtin as editable JSON
        let cat = builtinJuly2026
        var providers: [String: Any] = [:]
        for (id, p) in cat.providers {
            var d: [String: Any] = [
                "kind": p.kind,
                "label": p.label,
                "base_url": p.baseURL,
                "model": p.model,
                "fallback_models": p.fallbackModels,
                "api_key_secret": p.apiKeySecret,
                "timeout_sec": Int(p.timeoutSec),
            ]
            if let e = p.envFallback { d["env_fallback"] = e }
            if let docs = p.docsURL { d["docs_url"] = docs }
            if !p.extraHeaders.isEmpty { d["extra_headers"] = p.extraHeaders }
            providers[id] = d
        }
        let root: [String: Any] = [
            "version": cat.version,
            "as_of": cat.asOf,
            "notes": cat.notes,
            "order": cat.order,
            "providers": providers,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: dest, options: .atomic)
        }
    }

    private static func parse(_ obj: [String: Any]) -> LLMProviderCatalog? {
        let order = (obj["order"] as? [String]) ?? builtinJuly2026.order
        let raw = obj["providers"] as? [String: Any] ?? [:]
        var providers: [String: ProviderDef] = [:]
        for (id, any) in raw {
            guard let d = any as? [String: Any] else { continue }
            guard let kind = d["kind"] as? String,
                  let label = d["label"] as? String,
                  let base = d["base_url"] as? String,
                  let model = d["model"] as? String,
                  let secret = d["api_key_secret"] as? String else { continue }
            let fallbacks = d["fallback_models"] as? [String] ?? []
            let env = d["env_fallback"] as? String
            let docs = d["docs_url"] as? String
            let timeout = (d["timeout_sec"] as? Double)
                ?? Double(d["timeout_sec"] as? Int ?? 45)
            let headers = d["extra_headers"] as? [String: String] ?? [:]
            providers[id] = ProviderDef(
                kind: kind,
                label: label,
                baseURL: base,
                model: model,
                fallbackModels: fallbacks,
                apiKeySecret: secret,
                envFallback: env,
                docsURL: docs,
                timeoutSec: timeout,
                extraHeaders: headers
            )
        }
        guard !providers.isEmpty else { return nil }
        return LLMProviderCatalog(
            version: obj["version"] as? Int ?? 1,
            asOf: obj["as_of"] as? String ?? "",
            notes: obj["notes"] as? String ?? "",
            order: order,
            providers: providers
        )
    }
}
