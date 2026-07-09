import Foundation

/// UI capture heartbeat (design R6). Written every N seconds while recording.
public struct CaptureHeartbeat: Codable, Equatable, Sendable {
    public var meetingId: String
    public var updatedAt: String
    public var pid: Int32
    public var mode: String

    public init(meetingId: String, updatedAt: Date = Date(), pid: Int32 = ProcessInfo.processInfo.processIdentifier, mode: String = "offline_mic") {
        self.meetingId = meetingId
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        self.updatedAt = f.string(from: updatedAt)
        self.pid = pid
        self.mode = mode
    }

    public static func fileURL(knowledgeRoot: URL) -> URL {
        knowledgeRoot.appendingPathComponent("cache/capture_heartbeat.json")
    }

    public func write(to knowledgeRoot: URL) throws {
        let url = Self.fileURL(knowledgeRoot: knowledgeRoot)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
    }

    public static func load(from knowledgeRoot: URL) throws -> CaptureHeartbeat? {
        let url = fileURL(knowledgeRoot: knowledgeRoot)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(CaptureHeartbeat.self, from: data)
    }

    public static func clear(knowledgeRoot: URL) throws {
        let url = fileURL(knowledgeRoot: knowledgeRoot)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// True if updated within `maxAge` seconds.
    public func isFresh(maxAge: TimeInterval, now: Date = Date()) -> Bool {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        guard let t = f.date(from: updatedAt) else { return false }
        return now.timeIntervalSince(t) <= maxAge
    }
}
