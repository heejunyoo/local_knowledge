import Foundation

/// Cross-platform mobile pairing payload (QR + paste).
/// Format: `knowledge-pair:1|<coreURL>|<6digitCode>`
public enum PairingPayload {
    public static let prefix = "knowledge-pair:1|"

    public static func encode(coreURL: String, code: String) -> String {
        let url = coreURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let c = code.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(prefix)\(url)|\(c)"
    }

    public static func parse(_ raw: String) -> (coreURL: String, code: String)? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Preferred format
        if s.hasPrefix(prefix) {
            let rest = String(s.dropFirst(prefix.count))
            // URL may contain | rarely — split from the right for code
            if let lastBar = rest.lastIndex(of: "|") {
                let url = String(rest[..<lastBar])
                let code = String(rest[rest.index(after: lastBar)...])
                if !url.isEmpty, !code.isEmpty { return (url, code) }
            }
        }
        // Fallback: JSON {"url":"...","code":"..."}
        if let data = s.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let url = obj["url"] as? String ?? obj["core_url"] as? String,
           let code = obj["code"] as? String {
            return (url, code)
        }
        return nil
    }
}
