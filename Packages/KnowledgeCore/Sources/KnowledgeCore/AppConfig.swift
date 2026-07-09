import Foundation

/// Loads/saves `config/app.json` under the knowledge root (user-local L1 config).
public struct AppConfig: Equatable, Sendable {
    public var knowledgeRoot: String?
    public var vaultPath: String
    public var asrLanguage: String
    public var cloudEnabled: Bool
    /// Purge abandoned/failed meetings older than this many days (0 = off).
    public var retentionAbandonedDays: Int
    /// After commit, delete local audio older than this many days (0 = keep forever).
    public var retentionAudioAfterCommitDays: Int
    /// Run retention quietly on app/daemon start.
    public var retentionPurgeOnLaunch: Bool
    /// Prefer llama for RAG when binary+model present.
    public var ragUseLlama: Bool

    public init(
        knowledgeRoot: String? = nil,
        vaultPath: String = "~/Obsidian/Main",
        asrLanguage: String = "ko",
        cloudEnabled: Bool = true,
        retentionAbandonedDays: Int = 14,
        retentionAudioAfterCommitDays: Int = 0,
        retentionPurgeOnLaunch: Bool = true,
        ragUseLlama: Bool = true
    ) {
        self.knowledgeRoot = knowledgeRoot
        self.vaultPath = vaultPath
        self.asrLanguage = asrLanguage
        self.cloudEnabled = cloudEnabled
        self.retentionAbandonedDays = retentionAbandonedDays
        self.retentionAudioAfterCommitDays = retentionAudioAfterCommitDays
        self.retentionPurgeOnLaunch = retentionPurgeOnLaunch
        self.ragUseLlama = ragUseLlama
    }

    public static func load(knowledgeRoot: URL) -> AppConfig {
        let url = knowledgeRoot.appendingPathComponent("config/app.json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return AppConfig()
        }
        let vault = (obj["vault_path"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let lang: String = {
            if let asr = obj["asr"] as? [String: Any], let l = asr["language"] as? String { return l }
            return "ko"
        }()
        let cloud: Bool = {
            if let llm = obj["llm"] as? [String: Any], let c = llm["cloud_enabled"] as? Bool { return c }
            return true // product default 2026-07: free-tier cloud first
        }()
        let ret = obj["retention"] as? [String: Any]
        let abandonedDays = intValue(ret?["abandoned_days"], default: 14)
        let audioDays = intValue(ret?["audio_after_commit_days"], default: 0)
        let purgeOnLaunch = (ret?["purge_on_launch"] as? Bool) ?? true
        let ragLlama: Bool = {
            if let rag = obj["rag"] as? [String: Any], let v = rag["use_llama"] as? Bool { return v }
            return true
        }()
        return AppConfig(
            knowledgeRoot: obj["knowledge_root"] as? String,
            vaultPath: (vault?.isEmpty == false) ? vault! : "~/Obsidian/Main",
            asrLanguage: lang,
            cloudEnabled: cloud,
            retentionAbandonedDays: abandonedDays,
            retentionAudioAfterCommitDays: audioDays,
            retentionPurgeOnLaunch: purgeOnLaunch,
            ragUseLlama: ragLlama
        )
    }

    /// Merge retention/rag/vault into existing app.json (preserves other keys).
    public func save(knowledgeRoot root: URL) throws {
        let url = root.appendingPathComponent("config/app.json")
        var obj: [String: Any] = [:]
        if let data = try? Data(contentsOf: url),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            obj = existing
        }
        obj["vault_path"] = vaultPath
        if let kr = knowledgeRoot { obj["knowledge_root"] = kr }
        var asr = obj["asr"] as? [String: Any] ?? [:]
        asr["language"] = asrLanguage
        obj["asr"] = asr
        var llm = obj["llm"] as? [String: Any] ?? [:]
        llm["cloud_enabled"] = cloudEnabled
        obj["llm"] = llm
        obj["retention"] = [
            "abandoned_days": retentionAbandonedDays,
            "audio_after_commit_days": retentionAudioAfterCommitDays,
            "purge_on_launch": retentionPurgeOnLaunch,
        ]
        obj["rag"] = ["use_llama": ragUseLlama]
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    public var vaultURL: URL {
        let expanded = (vaultPath as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }

    public var vaultDisplayPath: String {
        vaultURL.path
    }

    public func ensureVaultDirectory() -> String? {
        do {
            try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private static func intValue(_ any: Any?, default def: Int) -> Int {
        if let i = any as? Int { return i }
        if let d = any as? Double { return Int(d) }
        if let s = any as? String, let i = Int(s) { return i }
        return def
    }
}
