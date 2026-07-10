import Foundation

/// Lightweight capture inbox (W2) — text only; promote writes a vault note file.
public final class InboxStore: @unchecked Sendable {
    public struct Item: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var ts: String
        public var text: String
        public var status: String // open | promoted
        public var promotedPath: String?
    }

    private struct FileModel: Codable {
        var items: [Item]
    }

    private let url: URL
    private let vaultDir: URL
    private let lock = NSLock()
    private var model: FileModel

    public init(knowledgeRoot: URL) {
        let dir = knowledgeRoot.appendingPathComponent("services/inbox", isDirectory: true)
        self.url = dir.appendingPathComponent("inbox.json")
        self.vaultDir = knowledgeRoot.appendingPathComponent("vault/inbox", isDirectory: true)
        if let data = try? Data(contentsOf: url),
           let m = try? JSONDecoder().decode(FileModel.self, from: data) {
            self.model = m
        } else {
            self.model = FileModel(items: [])
        }
    }

    public func list(includePromoted: Bool = false) -> [Item] {
        lock.lock(); defer { lock.unlock() }
        if includePromoted { return model.items.sorted { $0.ts > $1.ts } }
        return model.items.filter { $0.status == "open" }.sorted { $0.ts > $1.ts }
    }

    public func create(text: String) throws -> Item {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw NSError(domain: "inbox", code: 1, userInfo: [NSLocalizedDescriptionKey: "empty"]) }
        lock.lock(); defer { lock.unlock() }
        let item = Item(
            id: UUID().uuidString,
            ts: ISO8601DateFormatter().string(from: Date()),
            text: t,
            status: "open",
            promotedPath: nil
        )
        model.items.insert(item, at: 0)
        try persist()
        return item
    }

    public func promote(id: String) throws -> Item {
        lock.lock(); defer { lock.unlock() }
        guard let idx = model.items.firstIndex(where: { $0.id == id }) else {
            throw NSError(domain: "inbox", code: 404, userInfo: [NSLocalizedDescriptionKey: "not found"])
        }
        var item = model.items[idx]
        if item.status == "promoted", let p = item.promotedPath {
            return item
        }
        try FileManager.default.createDirectory(at: vaultDir, withIntermediateDirectories: true)
        let stamp = item.ts.replacingOccurrences(of: ":", with: "-")
        let name = "inbox-\(stamp.prefix(19))-\(item.id.prefix(8)).md"
        let path = vaultDir.appendingPathComponent(String(name))
        let body = """
        ---
        source: inbox
        id: \(item.id)
        captured: \(item.ts)
        ---

        \(item.text)

        """
        try body.write(to: path, atomically: true, encoding: .utf8)
        item.status = "promoted"
        item.promotedPath = path.path
        model.items[idx] = item
        try persist()
        return item
    }

    public func delete(id: String) throws {
        lock.lock(); defer { lock.unlock() }
        model.items.removeAll { $0.id == id }
        try persist()
    }

    public func openCount() -> Int {
        lock.lock(); defer { lock.unlock() }
        return model.items.filter { $0.status == "open" }.count
    }

    public func asDict(_ item: Item) -> [String: Any] {
        var d: [String: Any] = [
            "id": item.id,
            "ts": item.ts,
            "text": item.text,
            "status": item.status,
        ]
        if let p = item.promotedPath { d["promoted_path"] = p }
        return d
    }

    private func persist() throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(model).write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
