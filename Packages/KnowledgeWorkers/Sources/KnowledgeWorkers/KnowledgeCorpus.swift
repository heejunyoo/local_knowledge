import Foundation
import KnowledgeCore
import KnowledgeIndex

/// Unified knowledge corpus: meetings + connected roots → units/chunks/FTS.
/// RAG Chat consumes this layer — not one-shot “import” buttons.
public final class KnowledgeCorpus: @unchecked Sendable {
    private let store: KnowledgeStore
    private let knowledgeRoot: URL
    private let vaultURL: URL
    private let lock = NSLock()
    private let cancelLock = NSLock()
    private var cancelled = false

    public init(store: KnowledgeStore, knowledgeRoot: URL, vaultURL: URL) {
        self.store = store
        self.knowledgeRoot = knowledgeRoot
        self.vaultURL = vaultURL
    }

    public struct SyncReport: Equatable, Sendable {
        public var meetings: Int
        public var obsidian: Int
        public var notes: Int
        public var files: Int
        public var message: String

        public init(meetings: Int, obsidian: Int, notes: Int, files: Int, message: String) {
            self.meetings = meetings
            self.obsidian = obsidian
            self.notes = notes
            self.files = files
            self.message = message
        }
    }

    /// Progress for large vault/folder indexing (UI progress bar).
    public struct Progress: Equatable, Sendable {
        public var phase: String
        public var completed: Int
        public var total: Int
        public var currentName: String?

        public init(phase: String, completed: Int, total: Int, currentName: String? = nil) {
            self.phase = phase
            self.completed = completed
            self.total = total
            self.currentName = currentName
        }

        public var fraction: Double {
            guard total > 0 else { return 0 }
            return min(1, max(0, Double(completed) / Double(total)))
        }

        public var label: String {
            let name = currentName.map { " · \($0)" } ?? ""
            if total > 0 {
                return "\(phase) \(completed)/\(total)\(name)"
            }
            return "\(phase)\(name)"
        }
    }

    public typealias ProgressHandler = (Progress) -> Void

    public enum CorpusError: Error, LocalizedError {
        case cancelled

        public var errorDescription: String? {
            switch self {
            case .cancelled: return "동기화가 취소되었어요"
            }
        }
    }

    public func requestCancel() {
        cancelLock.lock()
        cancelled = true
        cancelLock.unlock()
    }

    public func resetCancel() {
        cancelLock.lock()
        cancelled = false
        cancelLock.unlock()
    }

    private func throwIfCancelled() throws {
        cancelLock.lock()
        let c = cancelled
        cancelLock.unlock()
        if c { throw CorpusError.cancelled }
    }

    private func report(_ progress: ProgressHandler?, phase: String, completed: Int, total: Int, name: String? = nil) {
        progress?(Progress(phase: phase, completed: completed, total: total, currentName: name))
    }

    // MARK: - Bootstrap connections

    /// Ensure implicit sources exist: meetings pipeline + default Obsidian vault.
    public func ensureDefaultConnections() throws {
        let now = ISO8601DateFormatter().string(from: Date())
        if try store.getConnectedSource(id: "src:meeting") == nil {
            try store.upsertConnectedSource(ConnectedSourceRecord(
                id: "src:meeting",
                sourceType: "meeting",
                rootPath: knowledgeRoot.path,
                label: "미팅 (녹음·전사·요약)",
                enabled: true,
                createdAt: now,
                updatedAt: now
            ))
        }
        if try store.getConnectedSource(id: "src:obsidian-default") == nil {
            try store.upsertConnectedSource(ConnectedSourceRecord(
                id: "src:obsidian-default",
                sourceType: "obsidian",
                rootPath: vaultURL.path,
                label: "Obsidian vault",
                enabled: FileManager.default.fileExists(atPath: vaultURL.path),
                createdAt: now,
                updatedAt: now
            ))
        }
    }

    public func connectFolder(path: String, label: String?, asObsidian: Bool) throws -> ConnectedSourceRecord {
        let id = "src:folder:\(SourceIngest.stableId(path))"
        let now = ISO8601DateFormatter().string(from: Date())
        let rec = ConnectedSourceRecord(
            id: id,
            sourceType: asObsidian ? "obsidian" : "folder",
            rootPath: path,
            label: label ?? URL(fileURLWithPath: path).lastPathComponent,
            enabled: true,
            createdAt: now,
            updatedAt: now
        )
        try store.upsertConnectedSource(rec)
        return rec
    }

    public func connectFile(path: String) throws -> ConnectedSourceRecord {
        let id = "src:file:\(SourceIngest.stableId(path))"
        let now = ISO8601DateFormatter().string(from: Date())
        let rec = ConnectedSourceRecord(
            id: id,
            sourceType: "file",
            rootPath: path,
            label: URL(fileURLWithPath: path).lastPathComponent,
            enabled: true,
            createdAt: now,
            updatedAt: now
        )
        try store.upsertConnectedSource(rec)
        return rec
    }

    public func connectAppleNotes(enabled: Bool = true) throws {
        let now = ISO8601DateFormatter().string(from: Date())
        try store.upsertConnectedSource(ConnectedSourceRecord(
            id: "src:notes",
            sourceType: "notes",
            rootPath: nil,
            label: "Apple Notes",
            enabled: enabled,
            createdAt: now,
            updatedAt: now
        ))
    }

    // MARK: - Full sync

    public func syncAll(
        notesProvider: (() throws -> [SourceIngest.AppleNoteDTO])? = nil,
        progress: ProgressHandler? = nil
    ) throws -> SyncReport {
        lock.lock()
        defer { lock.unlock() }
        resetCancel()
        try ensureDefaultConnections()

        var mCount = 0, oCount = 0, nCount = 0, fCount = 0
        report(progress, phase: "미팅 인덱싱", completed: 0, total: 0)
        mCount = try syncMeetings(progress: progress)

        let sources = try store.listConnectedSources().filter(\.enabled)
        var sourceIndex = 0
        for src in sources {
            try throwIfCancelled()
            sourceIndex += 1
            switch src.sourceType {
            case "obsidian":
                if let path = src.rootPath {
                    report(progress, phase: "Obsidian 준비", completed: 0, total: 0, name: src.label)
                    oCount += try syncObsidian(
                        source: src,
                        root: URL(fileURLWithPath: path),
                        progress: progress
                    )
                }
            case "folder":
                if let path = src.rootPath {
                    report(progress, phase: "폴더 준비", completed: 0, total: 0, name: src.label)
                    fCount += try syncFolder(
                        source: src,
                        root: URL(fileURLWithPath: path),
                        progress: progress
                    )
                }
            case "file":
                if let path = src.rootPath {
                    fCount += try syncSingleFile(source: src, file: URL(fileURLWithPath: path))
                }
            case "notes":
                if let notesProvider {
                    report(progress, phase: "Apple Notes", completed: 0, total: 0)
                    nCount += try syncNotes(source: src, notes: try notesProvider(), progress: progress)
                }
            case "meeting":
                break
            default:
                break
            }
            _ = sourceIndex
        }

        let msg = "코퍼스 동기화: 미팅 \(mCount) · Obsidian \(oCount) · Notes \(nCount) · 파일 \(fCount)"
        report(progress, phase: "완료", completed: 1, total: 1)
        return SyncReport(meetings: mCount, obsidian: oCount, notes: nCount, files: fCount, message: msg)
    }

    /// Sync only one connected source (used after folder connect).
    public func syncSource(id: String, progress: ProgressHandler? = nil) throws -> Int {
        lock.lock()
        defer { lock.unlock() }
        resetCancel()
        guard let src = try store.getConnectedSource(id: id), src.enabled else { return 0 }
        switch src.sourceType {
        case "obsidian":
            guard let path = src.rootPath else { return 0 }
            return try syncObsidian(source: src, root: URL(fileURLWithPath: path), progress: progress)
        case "folder":
            guard let path = src.rootPath else { return 0 }
            return try syncFolder(source: src, root: URL(fileURLWithPath: path), progress: progress)
        case "file":
            guard let path = src.rootPath else { return 0 }
            return try syncSingleFile(source: src, file: URL(fileURLWithPath: path))
        case "meeting":
            return try syncMeetings(progress: progress)
        default:
            return 0
        }
    }

    // MARK: - Meeting (core product knowledge)

    /// Index one meeting into corpus. Call on commit and reindex.
    @discardableResult
    public func indexMeeting(_ meeting: MeetingRecord) throws -> Bool {
        let unitId = "meeting:\(meeting.id)"
        let title = meeting.title ?? "미팅"
        var parts: [String] = [title]
        var chunks: [(String, Int?, Int?)] = []

        // Summary candidate — labeled for structure-aware retrieval boost
        if let rel = meeting.candidatePath {
            let url = knowledgeRoot.appendingPathComponent(rel)
            if let data = try? Data(contentsOf: url),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                func texts(_ key: String) -> [String] {
                    ((obj[key] as? [[String: Any]]) ?? []).compactMap { $0["text"] as? String }.filter { !$0.isEmpty }
                }
                let one = obj["one_line_summary"] as? String
                if let one, !one.isEmpty { parts.append(one) }
                let labeled = TextChunker.labeledMeetingPieces(
                    oneLine: one,
                    discussion: texts("key_discussion_points"),
                    decisions: texts("decisions"),
                    actions: texts("action_items"),
                    open: texts("unresolved_items")
                )
                for t in labeled {
                    parts.append(t)
                    chunks.append((t, nil, nil))
                }
            }
        }

        // Transcript — full meeting knowledge, not optional
        if let tRel = meeting.transcriptPath {
            let tURL = knowledgeRoot.appendingPathComponent(tRel)
            if let data = try? Data(contentsOf: tURL),
               let doc = try? JSONDecoder().decode(TranscriptDocument.self, from: data) {
                let coalesced = TranscriptCoalesce.coalesce(doc.segments)
                for seg in coalesced {
                    let t = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !t.isEmpty else { continue }
                    parts.append(t)
                    chunks.append((t, seg.tStartMs, seg.tEndMs))
                }
            }
        }

        // Vault body if present (committed meetings) — structure-aware chunker
        if let vRel = meeting.vaultPath {
            let vURL = vaultURL.appendingPathComponent(vRel)
            if let text = try? String(contentsOf: vURL, encoding: .utf8), !text.isEmpty {
                parts.append(text)
                for piece in TextChunker.chunk(text) {
                    chunks.append((piece, nil, nil))
                }
            }
        }

        let body = SourceIngest.truncate(parts.joined(separator: "\n\n"))
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

        let hash = SourceIngest.sha256Hex(body)
        if let existing = try store.getKnowledgeUnit(id: unitId), existing.contentHash == hash {
            return false
        }

        let ragOK = meeting.status == .committed || meeting.status == .reviewNeeded
        let unit = KnowledgeUnitRecord(
            unitId: unitId,
            sourceType: "meeting",
            title: title,
            scope: meeting.scope,
            sotKind: "meeting_artifacts",
            sotRef: meeting.vaultPath ?? meeting.id,
            contentHash: hash,
            meetingStatus: meeting.status.rawValue,
            inCorpus: true,
            ragEligible: meeting.status == .committed
        )
        try store.upsertKnowledgeUnit(unit)

        let chunkRecords = makeChunks(unitId: unitId, pieces: chunks)
        try store.replaceChunks(unitId: unitId, chunks: chunkRecords)
        try? LocalHashEmbedder.indexUnit(store: store, unitId: unitId)

        try store.upsertFTS(docId: unitId, sourceType: "meeting", title: title, body: body)
        try store.upsertSourcePointer(SourcePointerRecord(
            id: unitId,
            sourceType: "meeting",
            externalId: meeting.id,
            title: title,
            meetingId: meeting.id,
            vaultRelPath: meeting.vaultPath
        ))
        _ = ragOK
        return true
    }

    public func syncMeetings(progress: ProgressHandler? = nil) throws -> Int {
        var all: [MeetingRecord] = []
        let statuses: [PipelineStatus] = [.committed, .reviewNeeded, .summarizedCandidate, .transcribed]
        for st in statuses {
            all.append(contentsOf: try store.meetings(withStatus: st))
        }
        var n = 0
        let total = all.count
        for (i, m) in all.enumerated() {
            try throwIfCancelled()
            report(progress, phase: "미팅 인덱싱", completed: i, total: max(total, 1), name: m.title)
            if try indexMeeting(m) { n += 1 }
            report(progress, phase: "미팅 인덱싱", completed: i + 1, total: max(total, 1), name: m.title)
        }
        let now = ISO8601DateFormatter().string(from: Date())
        if var src = try store.getConnectedSource(id: "src:meeting") {
            src.lastSyncAt = now
            src.lastError = nil
            src.unitCount = try store.countKnowledgeUnits(sourceType: "meeting")
            src.updatedAt = now
            try store.upsertConnectedSource(src)
        }
        return n
    }

    // MARK: - Obsidian / folder / file

    private func syncObsidian(
        source: ConnectedSourceRecord,
        root: URL,
        progress: ProgressHandler? = nil
    ) throws -> Int {
        // Single pass only (was double-scanning → 2× slow on large vaults)
        report(progress, phase: "파일 목록", completed: 0, total: 0, name: root.lastPathComponent)
        let files = try SourceIngest.listTextFiles(
            root: root,
            maxFiles: 5_000,
            skipDirNames: [".obsidian", ".trash", ".git", "node_modules", ".smart-env", "copilot"]
        )
        return try indexFileList(
            files,
            sourceType: "obsidian",
            root: root,
            useRelativeId: true,
            sotKind: "vault_md",
            source: source,
            progress: progress,
            phase: "Obsidian 인덱싱"
        )
    }

    private func syncFolder(
        source: ConnectedSourceRecord,
        root: URL,
        progress: ProgressHandler? = nil
    ) throws -> Int {
        report(progress, phase: "파일 목록", completed: 0, total: 0, name: root.lastPathComponent)
        let files = try SourceIngest.listTextFiles(
            root: root,
            maxFiles: 5_000,
            skipDirNames: [".git", "node_modules", ".build", ".obsidian"]
        )
        return try indexFileList(
            files,
            sourceType: "file",
            root: root,
            useRelativeId: false,
            sotKind: "local_file",
            source: source,
            progress: progress,
            phase: "폴더 인덱싱"
        )
    }

    private func indexFileList(
        _ files: [URL],
        sourceType: String,
        root: URL,
        useRelativeId: Bool,
        sotKind: String,
        source: ConnectedSourceRecord,
        progress: ProgressHandler?,
        phase: String
    ) throws -> Int {
        var n = 0
        let total = files.count
        report(progress, phase: phase, completed: 0, total: max(total, 1))
        for (i, file) in files.enumerated() {
            try throwIfCancelled()
            let name = file.lastPathComponent
            report(progress, phase: phase, completed: i, total: max(total, 1), name: name)
            let externalId = useRelativeId
                ? SourceIngest.relativePath(file, root: root)
                : file.path
            if try indexLocalFile(
                fileURL: file,
                sourceType: sourceType,
                externalId: externalId,
                sotKind: sotKind,
                scope: "personal"
            ) { n += 1 }
            report(progress, phase: phase, completed: i + 1, total: max(total, 1), name: name)
        }
        try touchSource(source, count: try store.countKnowledgeUnits(sourceType: sourceType), error: nil)
        return n
    }

    private func syncSingleFile(source: ConnectedSourceRecord, file: URL) throws -> Int {
        let ok = try indexLocalFile(
            fileURL: file,
            sourceType: "file",
            externalId: file.path,
            sotKind: "local_file",
            scope: "personal"
        )
        try touchSource(source, count: ok ? 1 : 0, error: nil)
        return ok ? 1 : 0
    }

    private func syncNotes(
        source: ConnectedSourceRecord,
        notes: [SourceIngest.AppleNoteDTO],
        progress: ProgressHandler? = nil
    ) throws -> Int {
        _ = try SourceIngest.ingestAppleNotes(notes: notes, store: store)
        var n = 0
        let total = notes.count
        for (i, note) in notes.enumerated() {
            try throwIfCancelled()
            let title = note.name ?? "(제목 없음)"
            report(progress, phase: "Notes 인덱싱", completed: i, total: max(total, 1), name: title)
            let body = SourceIngest.truncate(note.body ?? "")
            guard !body.isEmpty else { continue }
            let unitId = "notes:\(note.id)"
            let hash = SourceIngest.sha256Hex(body)
            if let existing = try store.getKnowledgeUnit(id: unitId), existing.contentHash == hash {
                report(progress, phase: "Notes 인덱싱", completed: i + 1, total: max(total, 1), name: title)
                continue
            }
            try store.upsertKnowledgeUnit(KnowledgeUnitRecord(
                unitId: unitId,
                sourceType: "notes",
                title: title,
                sotKind: "notes_app",
                sotRef: note.id,
                contentHash: hash,
                ragEligible: true
            ))
            let pieces = TextChunker.chunk(body)
            let ch = pieces.enumerated().map { i, t in
                KnowledgeChunkRecord(
                    chunkId: "\(unitId)#\(i)",
                    unitId: unitId,
                    ordinal: i,
                    text: t,
                    contentHash: SourceIngest.sha256Hex(t)
                )
            }
            try store.replaceChunks(unitId: unitId, chunks: ch)
            try? LocalHashEmbedder.indexUnit(store: store, unitId: unitId)
            try store.upsertFTS(docId: unitId, sourceType: "notes", title: title, body: body)
            n += 1
            report(progress, phase: "Notes 인덱싱", completed: i + 1, total: max(total, 1), name: title)
        }
        try touchSource(source, count: try store.countKnowledgeUnits(sourceType: "notes"), error: nil)
        return n
    }

    @discardableResult
    private func indexLocalFile(
        fileURL: URL,
        sourceType: String,
        externalId: String,
        sotKind: String,
        scope: String
    ) throws -> Bool {
        guard SourceIngest.isTextFile(fileURL) else { return false }
        let data = try Data(contentsOf: fileURL)
        if data.contains(0) { return false }
        let raw = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        let body = SourceIngest.truncate(raw)
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let unitId = "\(sourceType):\(SourceIngest.stableId(externalId))"
        let hash = SourceIngest.sha256Hex(body)
        if let existing = try store.getKnowledgeUnit(id: unitId), existing.contentHash == hash {
            return false
        }
        let title = fileURL.deletingPathExtension().lastPathComponent
        try store.upsertKnowledgeUnit(KnowledgeUnitRecord(
            unitId: unitId,
            sourceType: sourceType,
            title: title,
            scope: scope,
            sotKind: sotKind,
            sotRef: externalId,
            contentHash: hash,
            ragEligible: true
        ))
        let pieces = TextChunker.chunk(body)
        let ch = pieces.enumerated().map { i, t in
            KnowledgeChunkRecord(
                chunkId: "\(unitId)#\(i)",
                unitId: unitId,
                ordinal: i,
                text: t,
                contentHash: SourceIngest.sha256Hex(t)
            )
        }
        try store.replaceChunks(unitId: unitId, chunks: ch)
        try? LocalHashEmbedder.indexUnit(store: store, unitId: unitId)
        try store.upsertFTS(docId: unitId, sourceType: sourceType, title: title, body: body)
        try store.upsertSourcePointer(SourcePointerRecord(
            id: unitId,
            sourceType: sourceType,
            externalId: externalId,
            title: title,
            vaultRelPath: sourceType == "obsidian" ? externalId : nil
        ))
        return true
    }

    private func touchSource(_ source: ConnectedSourceRecord, count: Int, error: String?) throws {
        var s = source
        let now = ISO8601DateFormatter().string(from: Date())
        s.lastSyncAt = now
        s.lastError = error
        s.unitCount = count
        s.updatedAt = now
        try store.upsertConnectedSource(s)
    }

    // MARK: - Chunking

    private func makeChunks(unitId: String, pieces: [(String, Int?, Int?)]) -> [KnowledgeChunkRecord] {
        var out: [KnowledgeChunkRecord] = []
        var buf = ""
        var bufStart: Int?
        var bufEnd: Int?
        var ord = 0

        func flush() {
            let t = buf.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return }
            out.append(KnowledgeChunkRecord(
                chunkId: "\(unitId)#\(ord)",
                unitId: unitId,
                ordinal: ord,
                text: t,
                tStartMs: bufStart,
                tEndMs: bufEnd,
                contentHash: SourceIngest.sha256Hex(t)
            ))
            ord += 1
            buf = ""
            bufStart = nil
            bufEnd = nil
        }

        for (text, t0, t1) in pieces {
            if buf.isEmpty {
                buf = text
                bufStart = t0
                bufEnd = t1
            } else if buf.count + text.count < 1000 {
                buf += "\n" + text
                if let t1 { bufEnd = t1 }
            } else {
                flush()
                buf = text
                bufStart = t0
                bufEnd = t1
            }
        }
        flush()
        return out
    }

}

