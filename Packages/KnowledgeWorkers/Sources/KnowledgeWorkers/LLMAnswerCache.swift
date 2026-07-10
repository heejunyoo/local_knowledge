import Foundation
import CryptoKit

/// Disk cache for cloud/local LLM completions under Core knowledge root.
/// Policy (2026-07 free tier): **never re-call** for the same prompt within TTL;
/// reuse answers aggressively to stay under Groq RPD/TPM (e.g. 70B ~1K RPD).
public enum LLMAnswerCache {
    private static let fileName = "cache/llm_answer_cache.json"
    private static let usageFile = "cache/llm_cloud_usage.json"
    /// Identical refine/complete prompts reuse this long (question+context hash).
    public static let ttlSeconds: TimeInterval = 7 * 24 * 3600
    public static let maxEntries = 300
    /// Soft gap between cloud calls (seconds) — avoids burst RPM spikes.
    public static let minCloudInterval: TimeInterval = 1.2
    /// Soft daily cap across all cloud models (personal free tier safety).
    public static let softDailyCap = 400

    private struct Entry: Codable {
        var key: String
        var text: String
        var engine: String
        var ts: TimeInterval
    }

    private struct FileModel: Codable {
        var entries: [Entry]
    }

    private struct Usage: Codable {
        var day: String
        var count: Int
        var lastUnix: TimeInterval
    }

    public static func cacheKey(prompt: String, maxTokens: Int) -> String {
        let norm = prompt
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let material = "v1|\(maxTokens)|\(norm)"
        let digest = SHA256.hash(data: Data(material.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func get(knowledgeRoot: URL, prompt: String, maxTokens: Int) -> (text: String, engine: String)? {
        let key = cacheKey(prompt: prompt, maxTokens: maxTokens)
        let url = knowledgeRoot.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url),
              let model = try? JSONDecoder().decode(FileModel.self, from: data) else { return nil }
        let now = Date().timeIntervalSince1970
        guard let hit = model.entries.first(where: { $0.key == key }),
              now - hit.ts <= ttlSeconds,
              !hit.text.isEmpty else { return nil }
        return (hit.text, hit.engine + "+cache")
    }

    public static func put(knowledgeRoot: URL, prompt: String, maxTokens: Int, text: String, engine: String) {
        guard !text.isEmpty else { return }
        // Don't cache already-cached engines forever-nested
        let eng = engine.replacingOccurrences(of: "+cache", with: "")
        let key = cacheKey(prompt: prompt, maxTokens: maxTokens)
        let url = knowledgeRoot.appendingPathComponent(fileName)
        var model = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(FileModel.self, from: $0) }
            ?? FileModel(entries: [])
        model.entries.removeAll { $0.key == key }
        model.entries.insert(Entry(key: key, text: text, engine: eng, ts: Date().timeIntervalSince1970), at: 0)
        if model.entries.count > maxEntries {
            model.entries = Array(model.entries.prefix(maxEntries))
        }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(model) {
            try? data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    /// Returns nil if cloud call is allowed; otherwise a short reason to skip cloud.
    public static func cloudCallBlockReason(knowledgeRoot: URL) -> String? {
        let url = knowledgeRoot.appendingPathComponent(usageFile)
        let day = dayKey()
        let now = Date().timeIntervalSince1970
        var usage = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Usage.self, from: $0) }
            ?? Usage(day: day, count: 0, lastUnix: 0)
        if usage.day != day {
            usage = Usage(day: day, count: 0, lastUnix: 0)
        }
        if now - usage.lastUnix < minCloudInterval {
            return "cloud-throttle-interval"
        }
        if usage.count >= softDailyCap {
            return "cloud-soft-daily-cap"
        }
        return nil
    }

    public static func recordCloudCall(knowledgeRoot: URL) {
        let url = knowledgeRoot.appendingPathComponent(usageFile)
        let day = dayKey()
        let now = Date().timeIntervalSince1970
        var usage = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Usage.self, from: $0) }
            ?? Usage(day: day, count: 0, lastUnix: 0)
        if usage.day != day {
            usage = Usage(day: day, count: 0, lastUnix: 0)
        }
        usage.count += 1
        usage.lastUnix = now
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(usage) {
            try? data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    public static func usageSummary(knowledgeRoot: URL) -> String {
        let url = knowledgeRoot.appendingPathComponent(usageFile)
        guard let data = try? Data(contentsOf: url),
              let usage = try? JSONDecoder().decode(Usage.self, from: data) else {
            return "cloud today: 0/\(softDailyCap)"
        }
        let day = dayKey()
        let count = usage.day == day ? usage.count : 0
        return "cloud today: \(count)/\(softDailyCap)"
    }

    private static func dayKey() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
