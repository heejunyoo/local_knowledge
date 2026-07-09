import Foundation

/// User-local runtime tree under `~/Knowledge` (L0/L2 data plane).
public enum KnowledgePaths {
    public static var defaultKnowledgeRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Knowledge", isDirectory: true)
    }

    /// Create standard directories. Idempotent.
    public static func ensureLayout(at root: URL) throws {
        let dirs = [
            "audio/raw",
            "audio/derived",
            "audio/orphan",
            "cache",
            "config",
            "docs",
            "evals",
            "index",
            "logs",
            "schemas",
            "summaries",
            "tools",
            "transcripts",
        ]
        let fm = FileManager.default
        for rel in dirs {
            let url = root.appendingPathComponent(rel, isDirectory: true)
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
