import Foundation

/// API keys for free-tier cloud LLMs. File: `config/secrets.json` (mode 600).
/// Never log values. Env vars override file when set.
public enum LLMSecrets {
    public static func load(knowledgeRoot: URL) -> [String: String] {
        var map: [String: String] = [:]
        let url = knowledgeRoot.appendingPathComponent("config/secrets.json")
        if let data = try? Data(contentsOf: url),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (k, v) in obj {
                if let s = v as? String {
                    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { map[k] = t }
                }
            }
        }
        return map
    }

    public static func save(_ secrets: [String: String], knowledgeRoot: URL) throws {
        let url = knowledgeRoot.appendingPathComponent("config/secrets.json")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Drop empty
        var clean: [String: String] = [:]
        for (k, v) in secrets {
            let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { clean[k] = t }
        }
        let data = try JSONSerialization.data(withJSONObject: clean, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    public static func resolve(
        secretKey: String,
        envFallback: String?,
        knowledgeRoot: URL
    ) -> String? {
        if let envName = envFallback,
           let env = ProcessInfo.processInfo.environment[envName],
           !env.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return env.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let file = load(knowledgeRoot: knowledgeRoot)
        if let v = file[secretKey], !v.isEmpty { return v }
        return nil
    }

    public static func hasAnyCloudKey(knowledgeRoot: URL, catalog: LLMProviderCatalog) -> Bool {
        for id in catalog.order {
            guard let p = catalog.providers[id] else { continue }
            if resolve(secretKey: p.apiKeySecret, envFallback: p.envFallback, knowledgeRoot: knowledgeRoot) != nil {
                return true
            }
        }
        return false
    }
}
