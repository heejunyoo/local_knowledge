import Foundation
import CryptoKit

/// Pinned third-party tools/models (KD-20). SoT also lives in config/examples/tools_manifest.json.
public struct ToolsManifest: Codable, Equatable, Sendable {
    public var version: Int
    public var tools: [ToolPin]
    public var models: [ModelPin]

    public init(version: Int = 1, tools: [ToolPin] = [], models: [ModelPin] = []) {
        self.version = version
        self.tools = tools
        self.models = models
    }

    public struct ToolPin: Codable, Equatable, Sendable {
        public var name: String
        public var version: String
        public var binaryRel: String
        public var sha256: String
        public var notes: String?

        enum CodingKeys: String, CodingKey {
            case name, version, notes
            case binaryRel = "binary_rel"
            case sha256
        }

        public init(name: String, version: String, binaryRel: String, sha256: String, notes: String? = nil) {
            self.name = name
            self.version = version
            self.binaryRel = binaryRel
            self.sha256 = sha256
            self.notes = notes
        }
    }

    public struct ModelPin: Codable, Equatable, Sendable {
        public var name: String
        public var rel: String
        public var sha256: String
        public var tier: String?
        public var notes: String?

        public init(name: String, rel: String, sha256: String, tier: String? = nil, notes: String? = nil) {
            self.name = name
            self.rel = rel
            self.sha256 = sha256
            self.tier = tier
            self.notes = notes
        }
    }

    public static func load(from url: URL) throws -> ToolsManifest {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ToolsManifest.self, from: data)
    }

    public static func sha256Hex(ofFile url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let chunk = handle.readData(ofLength: 1024 * 1024)
            if chunk.isEmpty { return false }
            hasher.update(data: chunk)
            return true
        }) {}
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

public enum ToolVerifyStatus: Equatable, Sendable {
    case missing
    case presentUnpinned
    case hashMismatch(expected: String, actual: String)
    case ok
}

public struct ToolBootstrap: Sendable {
    public var knowledgeRoot: URL

    public init(knowledgeRoot: URL) {
        self.knowledgeRoot = knowledgeRoot
    }

    public var manifestURL: URL {
        knowledgeRoot.appendingPathComponent("config/tools_manifest.json")
    }

    public var toolsRoot: URL {
        knowledgeRoot.appendingPathComponent("tools", isDirectory: true)
    }

    public func loadManifest() throws -> ToolsManifest {
        try ToolsManifest.load(from: manifestURL)
    }

    public func absoluteURL(rel: String) -> URL {
        knowledgeRoot.appendingPathComponent(rel)
    }

    public func verify(rel: String, expectedSHA256: String) throws -> ToolVerifyStatus {
        let url = absoluteURL(rel: rel)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .missing
        }
        let pin = expectedSHA256.lowercased()
        if pin == "pin_after_download" || pin.isEmpty {
            return .presentUnpinned
        }
        let actual = try ToolsManifest.sha256Hex(ofFile: url)
        if actual != pin {
            return .hashMismatch(expected: pin, actual: actual)
        }
        return .ok
    }

    public struct Report: Equatable, Sendable {
        public var name: String
        public var rel: String
        public var status: ToolVerifyStatus
    }

    public func verifyAll() throws -> [Report] {
        let manifest = try loadManifest()
        var reports: [Report] = []
        for t in manifest.tools {
            reports.append(Report(
                name: t.name,
                rel: t.binaryRel,
                status: try verify(rel: t.binaryRel, expectedSHA256: t.sha256)
            ))
        }
        for m in manifest.models {
            reports.append(Report(
                name: m.name,
                rel: m.rel,
                status: try verify(rel: m.rel, expectedSHA256: m.sha256)
            ))
        }
        return reports
    }

    /// Offline install: copy file into pinned relative path and optionally update manifest sha.
    public func installFile(from source: URL, rel: String) throws -> String {
        let dest = absoluteURL(rel: rel)
        try FileManager.default.createDirectory(
            at: dest.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: source, to: dest)
        // Ensure executable bit for binaries under tools/*/
        if rel.contains("whisper") || rel.contains("llama") || rel.hasSuffix("-cli") {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: dest.path
            )
        }
        return try ToolsManifest.sha256Hex(ofFile: dest)
    }

    public func whisperBinaryURL(manifest: ToolsManifest? = nil) throws -> URL? {
        let m = try manifest ?? loadManifest()
        guard let tool = m.tools.first(where: { $0.name.contains("whisper") }) else {
            return nil
        }
        let url = absoluteURL(rel: tool.binaryRel)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    public func whisperModelURL(manifest: ToolsManifest? = nil) throws -> URL? {
        let m = try manifest ?? loadManifest()
        guard let model = m.models.first(where: { $0.name.contains("whisper") }) else {
            return nil
        }
        let url = absoluteURL(rel: model.rel)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    public func llamaBinaryURL(manifest: ToolsManifest? = nil) throws -> URL? {
        let m = try manifest ?? loadManifest()
        guard let tool = m.tools.first(where: { $0.name.contains("llama") }) else {
            return nil
        }
        let url = absoluteURL(rel: tool.binaryRel)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
