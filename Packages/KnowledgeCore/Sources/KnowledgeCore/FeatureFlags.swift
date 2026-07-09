import Foundation

/// Feature flags — single home: `~/Knowledge/config/features.json` (AP-10).
public struct FeatureFlags: Codable, Equatable, Sendable {
    public var cloudLlm: Bool
    public var cloudStt: Bool
    public var critic: Bool
    public var criticSecondModel: Bool
    public var vectorSearch: Bool
    public var blackholeFallback: Bool
    public var notesIngest: Bool
    public var writeActionIndexMd: Bool
    public var embedTranscriptInVault: Bool
    public var audioDirPassphrase: Bool

    public static let mvpDefaults = FeatureFlags(
        cloudLlm: true,
        cloudStt: false,
        critic: true,
        criticSecondModel: false,
        vectorSearch: true,
        blackholeFallback: false,
        notesIngest: true,
        writeActionIndexMd: false,
        embedTranscriptInVault: false,
        audioDirPassphrase: false
    )

    /// Load `config/features.json` (missing → field defaults).
    public static func load(knowledgeRoot: URL) -> FeatureFlags {
        let url = knowledgeRoot.appendingPathComponent("config/features.json")
        guard let data = try? Data(contentsOf: url) else { return .mvpDefaults }
        return (try? JSONDecoder().decode(FeatureFlags.self, from: data)) ?? .mvpDefaults
    }

    public func save(knowledgeRoot: URL) throws {
        let url = knowledgeRoot.appendingPathComponent("config/features.json")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: url, options: .atomic)
    }

    public init(
        cloudLlm: Bool,
        cloudStt: Bool,
        critic: Bool,
        criticSecondModel: Bool,
        vectorSearch: Bool,
        blackholeFallback: Bool,
        notesIngest: Bool,
        writeActionIndexMd: Bool,
        embedTranscriptInVault: Bool,
        audioDirPassphrase: Bool
    ) {
        self.cloudLlm = cloudLlm
        self.cloudStt = cloudStt
        self.critic = critic
        self.criticSecondModel = criticSecondModel
        self.vectorSearch = vectorSearch
        self.blackholeFallback = blackholeFallback
        self.notesIngest = notesIngest
        self.writeActionIndexMd = writeActionIndexMd
        self.embedTranscriptInVault = embedTranscriptInVault
        self.audioDirPassphrase = audioDirPassphrase
    }

    enum CodingKeys: String, CodingKey {
        case cloudLlm = "cloud_llm"
        case cloudStt = "cloud_stt"
        case critic
        case criticSecondModel = "critic_second_model"
        case vectorSearch = "vector_search"
        case blackholeFallback = "blackhole_fallback"
        case notesIngest = "notes_ingest"
        case writeActionIndexMd = "write_action_index_md"
        case embedTranscriptInVault = "embed_transcript_in_vault"
        case audioDirPassphrase = "audio_dir_passphrase"
    }
}
