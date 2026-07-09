import Foundation
import KnowledgeCore
import KnowledgeIndex

/// Delete machine-local meeting artifacts (audio/transcript/summary).
/// Vault markdown is **not** deleted (SoT lives in Obsidian).
public enum MeetingCleanup {
    public struct Result: Equatable, Sendable {
        public var deletedMeetings: Int
        public var deletedFiles: Int
        public var freedBytes: Int64
        public var message: String

        public init(deletedMeetings: Int, deletedFiles: Int, freedBytes: Int64, message: String) {
            self.deletedMeetings = deletedMeetings
            self.deletedFiles = deletedFiles
            self.freedBytes = freedBytes
            self.message = message
        }
    }

    /// Remove one meeting from index + local files under knowledge root.
    @discardableResult
    public static func deleteMeeting(
        id: String,
        store: KnowledgeStore,
        knowledgeRoot: URL,
        deleteLocalFiles: Bool = true
    ) throws -> Result {
        guard let m = try store.getMeeting(id: id) else {
            return Result(deletedMeetings: 0, deletedFiles: 0, freedBytes: 0, message: "미팅이 없어요")
        }
        var files = 0
        var bytes: Int64 = 0
        if deleteLocalFiles {
            let paths = [m.audioPath, m.transcriptPath, m.candidatePath].compactMap { $0 }
            for rel in paths {
                let url = knowledgeRoot.appendingPathComponent(rel)
                if let n = try? removeFile(url) {
                    files += 1
                    bytes += n
                }
            }
            // raw stem variants
            let rawDir = knowledgeRoot.appendingPathComponent("audio/raw", isDirectory: true)
            if let items = try? FileManager.default.contentsOfDirectory(at: rawDir, includingPropertiesForKeys: [.fileSizeKey]) {
                for u in items where u.deletingPathExtension().lastPathComponent == id {
                    if let n = try? removeFile(u) {
                        files += 1
                        bytes += n
                    }
                }
            }
        }
        try store.deleteMeeting(id: id)
        return Result(
            deletedMeetings: 1,
            deletedFiles: files,
            freedBytes: bytes,
            message: "미팅을 지웠어요"
        )
    }

    /// Purge abandoned / failed meetings and their local files.
    /// - Parameter olderThanDays: if > 0, only meetings with updated_at older than N days.
    public static func purgeAbandoned(
        store: KnowledgeStore,
        knowledgeRoot: URL,
        olderThanDays: Int = 0
    ) throws -> Result {
        let statuses: [PipelineStatus] = [.abandoned, .recordFailed, .transcribeFailed, .summaryFailed]
        var meetings = 0
        var files = 0
        var bytes: Int64 = 0
        let cutoff = olderThanDays > 0
            ? Calendar.current.date(byAdding: .day, value: -olderThanDays, to: Date())
            : nil
        for st in statuses {
            for m in try store.meetings(withStatus: st) {
                if let cutoff, let updated = parseISO(m.updatedAt), updated > cutoff {
                    continue
                }
                let r = try deleteMeeting(id: m.id, store: store, knowledgeRoot: knowledgeRoot)
                meetings += r.deletedMeetings
                files += r.deletedFiles
                bytes += r.freedBytes
            }
        }
        let mb = Double(bytes) / 1_048_576
        let msg: String
        if meetings == 0 {
            msg = olderThanDays > 0
                ? "\(olderThanDays)일 지난 중단 미팅이 없어요"
                : "지울 중단·실패 미팅이 없어요"
        } else if bytes > 0 {
            msg = "\(meetings)건 정리 · 파일 \(files)개 · \(String(format: "%.1f", mb))MB 확보"
        } else {
            msg = "\(meetings)건 정리했어요"
        }
        return Result(deletedMeetings: meetings, deletedFiles: files, freedBytes: bytes, message: msg)
    }

    /// Delete local audio for committed meetings older than N days (keep meeting + vault note).
    public static func purgeCommittedAudio(
        store: KnowledgeStore,
        knowledgeRoot: URL,
        olderThanDays: Int
    ) throws -> Result {
        guard olderThanDays > 0 else {
            return Result(deletedMeetings: 0, deletedFiles: 0, freedBytes: 0, message: "오디오 자동 삭제 꺼짐")
        }
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -olderThanDays, to: Date()) else {
            return Result(deletedMeetings: 0, deletedFiles: 0, freedBytes: 0, message: "날짜 계산 실패")
        }
        var files = 0
        var bytes: Int64 = 0
        for m in try store.meetings(withStatus: .committed) {
            guard m.audioPath != nil else { continue }
            guard let updated = parseISO(m.updatedAt), updated <= cutoff else { continue }
            let n = try deleteAudioOnly(meeting: m, knowledgeRoot: knowledgeRoot)
            if n > 0 {
                files += 1
                bytes += n
                var copy = m
                copy.audioPath = nil
                copy.audioSha256 = nil
                try store.upsertMeeting(copy)
            }
        }
        let mb = Double(bytes) / 1_048_576
        let msg = files == 0
            ? "지울 오래된 녹음 파일이 없어요"
            : "저장 완료 미팅 녹음 \(files)개 삭제 · \(String(format: "%.1f", mb))MB"
        return Result(deletedMeetings: 0, deletedFiles: files, freedBytes: bytes, message: msg)
    }

    /// Apply retention from AppConfig (quiet).
    public static func runRetentionPolicy(
        store: KnowledgeStore,
        knowledgeRoot: URL,
        config: AppConfig
    ) throws -> Result {
        var meetings = 0, files = 0
        var bytes: Int64 = 0
        var parts: [String] = []
        if config.retentionAbandonedDays > 0 {
            let r = try purgeAbandoned(
                store: store,
                knowledgeRoot: knowledgeRoot,
                olderThanDays: config.retentionAbandonedDays
            )
            meetings += r.deletedMeetings
            files += r.deletedFiles
            bytes += r.freedBytes
            if r.deletedMeetings > 0 { parts.append(r.message) }
        }
        if config.retentionAudioAfterCommitDays > 0 {
            let r = try purgeCommittedAudio(
                store: store,
                knowledgeRoot: knowledgeRoot,
                olderThanDays: config.retentionAudioAfterCommitDays
            )
            files += r.deletedFiles
            bytes += r.freedBytes
            if r.deletedFiles > 0 { parts.append(r.message) }
        }
        let message = parts.isEmpty ? "보관 정책: 정리할 항목 없음" : parts.joined(separator: " · ")
        return Result(deletedMeetings: meetings, deletedFiles: files, freedBytes: bytes, message: message)
    }

    private static func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    /// Delete only the audio file, keep meeting row (optional future use).
    public static func deleteAudioOnly(
        meeting: MeetingRecord,
        knowledgeRoot: URL
    ) throws -> Int64 {
        guard let rel = meeting.audioPath else { return 0 }
        return try removeFile(knowledgeRoot.appendingPathComponent(rel)) ?? 0
    }

    private static func removeFile(_ url: URL) throws -> Int64? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
        try fm.removeItem(at: url)
        return size
    }
}
