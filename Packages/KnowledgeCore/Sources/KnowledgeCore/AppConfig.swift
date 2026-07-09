import Foundation

/// Runtime paths and worker config — **no** feature flags (those live in FeatureFlags).
public struct AppConfig: Codable, Equatable, Sendable {
    public var knowledgeRoot: String
    public var vaultPath: String
    public var asr: AsrConfig
    public var llm: LlmConfig
    public var notes: NotesConfig
    public var ipc: IpcConfig

    public init(
        knowledgeRoot: String,
        vaultPath: String,
        asr: AsrConfig = .default,
        llm: LlmConfig = .default,
        notes: NotesConfig = .default,
        ipc: IpcConfig = .default
    ) {
        self.knowledgeRoot = knowledgeRoot
        self.vaultPath = vaultPath
        self.asr = asr
        self.llm = llm
        self.notes = notes
        self.ipc = ipc
    }

    enum CodingKeys: String, CodingKey {
        case knowledgeRoot = "knowledge_root"
        case vaultPath = "vault_path"
        case asr
        case llm
        case notes
        case ipc
    }

    public struct AsrConfig: Codable, Equatable, Sendable {
        public var engine: String
        public var binaryRel: String
        public var modelRel: String
        public var language: String

        public static let `default` = AsrConfig(
            engine: "whisper.cpp",
            binaryRel: "tools/whisper.cpp/1.7.5/whisper-cli",
            modelRel: "tools/models/whisper/ggml-large-v3-turbo.bin",
            language: "ko"
        )

        enum CodingKeys: String, CodingKey {
            case engine
            case binaryRel = "binary_rel"
            case modelRel = "model_rel"
            case language
        }

        public init(engine: String, binaryRel: String, modelRel: String, language: String) {
            self.engine = engine
            self.binaryRel = binaryRel
            self.modelRel = modelRel
            self.language = language
        }
    }

    public struct LlmConfig: Codable, Equatable, Sendable {
        public var engine: String
        public var binaryRel: String
        public var modelRel: String
        public var cloudEnabled: Bool

        public static let `default` = LlmConfig(
            engine: "llama.cpp",
            binaryRel: "tools/llama.cpp/b0/llama-cli",
            modelRel: "tools/models/llm/Qwen2.5-7B-Instruct-Q4_K_M.gguf",
            cloudEnabled: false
        )

        enum CodingKeys: String, CodingKey {
            case engine
            case binaryRel = "binary_rel"
            case modelRel = "model_rel"
            case cloudEnabled = "cloud_enabled"
        }

        public init(engine: String, binaryRel: String, modelRel: String, cloudEnabled: Bool) {
            self.engine = engine
            self.binaryRel = binaryRel
            self.modelRel = modelRel
            self.cloudEnabled = cloudEnabled
        }
    }

    public struct NotesConfig: Codable, Equatable, Sendable {
        public var folderAllowlist: [String]
        public var pageSize: Int

        public static let `default` = NotesConfig(folderAllowlist: [], pageSize: 50)

        enum CodingKeys: String, CodingKey {
            case folderAllowlist = "folder_allowlist"
            case pageSize = "page_size"
        }

        public init(folderAllowlist: [String], pageSize: Int) {
            self.folderAllowlist = folderAllowlist
            self.pageSize = pageSize
        }
    }

    public struct IpcConfig: Codable, Equatable, Sendable {
        public var socketRel: String

        public static let `default` = IpcConfig(socketRel: "cache/daemon.sock")

        enum CodingKeys: String, CodingKey {
            case socketRel = "socket_rel"
        }

        public init(socketRel: String) {
            self.socketRel = socketRel
        }
    }
}

public enum KnowledgePaths {
    public static var defaultKnowledgeRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Knowledge", isDirectory: true)
    }

    public static func ensureLayout(at root: URL) throws {
        let fm = FileManager.default
        let dirs = [
            "config",
            "docs",
            "schemas",
            "tools",
            "audio/raw",
            "audio/derived",
            "audio/orphan",
            "transcripts",
            "summaries",
            "index",
            "logs",
            "cache",
            "evals",
        ]
        for rel in dirs {
            let url = root.appendingPathComponent(rel, isDirectory: true)
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
