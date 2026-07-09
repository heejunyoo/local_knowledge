import Foundation

/// Same format as KnowledgeCore.PairingPayload (iOS app is not SPM-linked to Core).
enum PairingPayload {
    static let prefix = "knowledge-pair:1|"

    static func encode(coreURL: String, code: String) -> String {
        "\(prefix)\(coreURL.trimmingCharacters(in: .whitespacesAndNewlines))|\(code.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    static func parse(_ raw: String) -> (coreURL: String, code: String)? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix(prefix) {
            let rest = String(s.dropFirst(prefix.count))
            if let lastBar = rest.lastIndex(of: "|") {
                let url = String(rest[..<lastBar])
                let code = String(rest[rest.index(after: lastBar)...])
                if !url.isEmpty, !code.isEmpty { return (url, code) }
            }
        }
        if let data = s.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let url = (obj["url"] as? String) ?? (obj["core_url"] as? String),
           let code = obj["code"] as? String {
            return (url, code)
        }
        return nil
    }
}
