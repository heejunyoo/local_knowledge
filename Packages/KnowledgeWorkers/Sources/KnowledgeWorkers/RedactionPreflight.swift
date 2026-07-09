import Foundation
import KnowledgeCore

/// Cloud LLM preflight: block high-risk secrets in prompts (privacy_rules).
public enum RedactionPreflight {
    public struct Hit: Equatable, Sendable {
        public var id: String
        public var label: String
        public init(id: String, label: String) {
            self.id = id
            self.label = label
        }
    }

    public struct Result: Equatable, Sendable {
        public var allowed: Bool
        public var hits: [Hit]
        public var message: String

        public init(allowed: Bool, hits: [Hit], message: String) {
            self.allowed = allowed
            self.hits = hits
            self.message = message
        }
    }

    public static func scan(_ text: String, knowledgeRoot: URL? = nil) -> Result {
        let patterns = loadPatterns(knowledgeRoot: knowledgeRoot)
        let allow = loadAllowlist(knowledgeRoot: knowledgeRoot)
        var hits: [Hit] = []
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p.regex, options: []) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            re.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                guard let match, let r = Range(match.range, in: text) else { return }
                let frag = String(text[r])
                if allow.contains(where: { frag.contains($0) }) { return }
                hits.append(Hit(id: p.id, label: p.label))
            }
        }
        // unique by id
        var seen = Set<String>()
        hits = hits.filter { seen.insert($0.id).inserted }
        if hits.isEmpty {
            return Result(allowed: true, hits: [], message: "ok")
        }
        let labels = hits.map(\.label).joined(separator: ", ")
        return Result(
            allowed: false,
            hits: hits,
            message: "클라우드 전송 차단: 민감 패턴 (\(labels)). 로컬 7B/extractive로 폴백합니다."
        )
    }

    private struct Pat { var id: String; var regex: String; var label: String }

    private static func loadPatterns(knowledgeRoot: URL?) -> [Pat] {
        let bundled = defaultPatterns()
        guard let root = knowledgeRoot else { return bundled }
        // Prefer user copy under knowledge root, else repo-relative via Knowledge/docs if present
        let candidates = [
            root.appendingPathComponent("config/redaction_patterns.json"),
            root.appendingPathComponent("docs/redaction_patterns.json"),
        ]
        for url in candidates {
            if let data = try? Data(contentsOf: url),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let arr = obj["patterns"] as? [[String: Any]] {
                let parsed: [Pat] = arr.compactMap { d in
                    guard let id = d["id"] as? String,
                          let regex = d["regex"] as? String,
                          let label = d["label"] as? String else { return nil }
                    return Pat(id: id, regex: regex, label: label)
                }
                if !parsed.isEmpty { return parsed }
            }
        }
        return bundled
    }

    private static func loadAllowlist(knowledgeRoot: URL?) -> [String] {
        guard let root = knowledgeRoot else { return [] }
        let url = root.appendingPathComponent("config/redaction_allowlist.json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = obj["allow"] as? [String] else { return [] }
        return arr
    }

    private static func defaultPatterns() -> [Pat] {
        [
            Pat(id: "aws_access_key", regex: #"\bAKIA[0-9A-Z]{16}\b"#, label: "AWS access key"),
            Pat(id: "private_key_pem", regex: #"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"#, label: "PEM private key"),
            Pat(id: "bearer_token", regex: #"(?i)bearer\s+[A-Za-z0-9\-._~+/]+=*"#, label: "Bearer token"),
            Pat(id: "pan_like", regex: #"\b(?:\d[ -]*?){13,19}\b"#, label: "Possible card number"),
        ]
    }
}
