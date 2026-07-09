import Foundation
import CryptoKit
import KnowledgeCore
import KnowledgeIndex

/// Import external knowledge into index FTS + pointers.
/// - Apple Notes: FTS mirror (`note_mirror`), SoT = Notes.app
/// - Obsidian / files: FTS derived text + `source_pointer` (body SoT stays on disk)
public enum SourceIngest {
    public static let maxBodyChars = 200_000
    public static let textExtensions: Set<String> = [
        "md", "markdown", "txt", "text", "csv", "json", "yaml", "yml", "swift", "py", "rs", "go", "ts", "tsx", "js",
    ]

    public struct Result: Equatable, Sendable {
        public var imported: Int
        public var skipped: Int
        public var failed: Int
        public var sourceType: String
        public var message: String

        public init(imported: Int, skipped: Int, failed: Int, sourceType: String, message: String) {
            self.imported = imported
            self.skipped = skipped
            self.failed = failed
            self.sourceType = sourceType
            self.message = message
        }
    }

    // MARK: - Apple Notes (payload from JXA)

    public struct AppleNoteDTO: Codable, Equatable, Sendable {
        public var id: String
        public var name: String?
        public var body: String?
        public var folder: String?

        public init(id: String, name: String? = nil, body: String? = nil, folder: String? = nil) {
            self.id = id
            self.name = name
            self.body = body
            self.folder = folder
        }
    }

    public static func ingestAppleNotes(
        notes: [AppleNoteDTO],
        store: KnowledgeStore,
        folderAllowlist: [String] = []
    ) throws -> Result {
        var imported = 0, skipped = 0, failed = 0
        let allow = Set(folderAllowlist.map { $0.lowercased() })
        for n in notes {
            if !allow.isEmpty {
                let f = (n.folder ?? "").lowercased()
                if !allow.contains(f) {
                    skipped += 1
                    continue
                }
            }
            let title = (n.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let body = truncate(n.body ?? "")
            if title.isEmpty && body.isEmpty {
                skipped += 1
                continue
            }
            do {
                let hash = sha256Hex(body)
                try store.upsertNoteMirror(NoteMirrorRecord(
                    notesId: n.id,
                    folder: n.folder,
                    title: title.isEmpty ? nil : title,
                    bodyText: body,
                    contentHash: hash
                ))
                let docId = "notes:\(n.id)"
                try store.upsertFTS(
                    docId: docId,
                    sourceType: "notes",
                    title: title.isEmpty ? "(제목 없음)" : title,
                    body: body
                )
                try store.upsertSourcePointer(SourcePointerRecord(
                    id: docId,
                    sourceType: "notes",
                    externalId: n.id,
                    title: title.isEmpty ? nil : title,
                    notesId: n.id
                ))
                imported += 1
            } catch {
                failed += 1
            }
        }
        return Result(
            imported: imported,
            skipped: skipped,
            failed: failed,
            sourceType: "notes",
            message: "Apple Notes \(imported)개 반영 (skip \(skipped), fail \(failed))"
        )
    }

    // MARK: - Obsidian vault

    public static func isLikelyObsidianVault(_ url: URL) -> Bool {
        let fm = FileManager.default
        let marker = url.appendingPathComponent(".obsidian", isDirectory: true)
        if fm.fileExists(atPath: marker.path) { return true }
        // Any markdown in root/subdirs
        return true
    }

    public static func ingestObsidianVault(
        vaultURL: URL,
        store: KnowledgeStore,
        maxFiles: Int = 2_000
    ) throws -> Result {
        guard FileManager.default.fileExists(atPath: vaultURL.path) else {
            return Result(imported: 0, skipped: 0, failed: 0, sourceType: "obsidian",
                          message: "Obsidian vault 경로가 없어요: \(vaultURL.path)")
        }
        let files = try listTextFiles(root: vaultURL, maxFiles: maxFiles, skipDirNames: [
            ".obsidian", ".trash", ".git", "node_modules", ".smart-env",
        ])
        var imported = 0, skipped = 0, failed = 0
        for file in files {
            do {
                let rel = relativePath(file, root: vaultURL)
                let r = try ingestFile(
                    fileURL: file,
                    store: store,
                    sourceType: "obsidian",
                    externalId: rel,
                    vaultRelPath: rel,
                    titleHint: file.deletingPathExtension().lastPathComponent
                )
                imported += r.imported
                skipped += r.skipped
                failed += r.failed
            } catch {
                failed += 1
            }
        }
        return Result(
            imported: imported,
            skipped: skipped,
            failed: failed,
            sourceType: "obsidian",
            message: "Obsidian \(imported)개 노트 인덱싱 (skip \(skipped), fail \(failed))"
        )
    }

    // MARK: - Arbitrary files / folders

    public static func ingestURLs(
        urls: [URL],
        store: KnowledgeStore,
        recursive: Bool = true,
        maxFiles: Int = 2_000
    ) throws -> Result {
        var allFiles: [URL] = []
        let fm = FileManager.default
        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                let listed = try listTextFiles(
                    root: url,
                    maxFiles: max(0, maxFiles - allFiles.count),
                    recursive: recursive,
                    skipDirNames: [".git", "node_modules", ".build", "DerivedData"]
                )
                allFiles.append(contentsOf: listed)
            } else if isTextFile(url) {
                allFiles.append(url)
            }
            if allFiles.count >= maxFiles { break }
        }
        var imported = 0, skipped = 0, failed = 0
        for file in allFiles {
            do {
                let r = try ingestFile(
                    fileURL: file,
                    store: store,
                    sourceType: "file",
                    externalId: file.path,
                    vaultRelPath: nil,
                    titleHint: file.lastPathComponent
                )
                imported += r.imported
                skipped += r.skipped
                failed += r.failed
            } catch {
                failed += 1
            }
        }
        return Result(
            imported: imported,
            skipped: skipped,
            failed: failed,
            sourceType: "file",
            message: "파일 \(imported)개 인덱싱 (skip \(skipped), fail \(failed))"
        )
    }

    public static func ingestFile(
        fileURL: URL,
        store: KnowledgeStore,
        sourceType: String,
        externalId: String,
        vaultRelPath: String?,
        titleHint: String?
    ) throws -> Result {
        guard isTextFile(fileURL) else {
            return Result(imported: 0, skipped: 1, failed: 0, sourceType: sourceType, message: "skip")
        }
        let data = try Data(contentsOf: fileURL)
        // Skip obvious binaries
        if data.contains(0) {
            return Result(imported: 0, skipped: 1, failed: 0, sourceType: sourceType, message: "binary")
        }
        let raw = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        let body = truncate(raw)
        if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Result(imported: 0, skipped: 1, failed: 0, sourceType: sourceType, message: "empty")
        }
        let title = titleHint ?? fileURL.deletingPathExtension().lastPathComponent
        let docId = "\(sourceType):\(stableId(externalId))"
        try store.upsertFTS(docId: docId, sourceType: sourceType, title: title, body: body)
        try store.upsertSourcePointer(SourcePointerRecord(
            id: docId,
            sourceType: sourceType,
            externalId: externalId,
            title: title,
            vaultRelPath: vaultRelPath
        ))
        return Result(imported: 1, skipped: 0, failed: 0, sourceType: sourceType, message: "ok")
    }

    // MARK: - helpers

    public static func isTextFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext.isEmpty { return false }
        return textExtensions.contains(ext)
    }

    public static func listTextFiles(
        root: URL,
        maxFiles: Int,
        recursive: Bool = true,
        skipDirNames: Set<String>
    ) throws -> [URL] {
        let fm = FileManager.default
        var out: [URL] = []
        guard let en = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        while let item = en.nextObject() as? URL {
            let name = item.lastPathComponent
            if skipDirNames.contains(name) {
                en.skipDescendants()
                continue
            }
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                if !recursive { en.skipDescendants() }
                continue
            }
            if isTextFile(item) {
                out.append(item)
                if out.count >= maxFiles { break }
            }
        }
        return out
    }

    public static func relativePath(_ file: URL, root: URL) -> String {
        let fp = file.standardizedFileURL.path
        let rp = root.standardizedFileURL.path
        if fp.hasPrefix(rp) {
            let rest = String(fp.dropFirst(rp.count))
            return rest.hasPrefix("/") ? String(rest.dropFirst()) : rest
        }
        return file.lastPathComponent
    }

    public static func truncate(_ s: String) -> String {
        if s.count <= maxBodyChars { return s }
        return String(s.prefix(maxBodyChars))
    }

    public static func sha256Hex(_ s: String) -> String {
        let digest = SHA256.hash(data: Data(s.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func stableId(_ externalId: String) -> String {
        String(sha256Hex(externalId).prefix(24))
    }
}
