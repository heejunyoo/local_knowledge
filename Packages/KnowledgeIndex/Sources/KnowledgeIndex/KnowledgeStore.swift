import Foundation
import KnowledgeCore
import SQLite3

/// SQLite index: meetings, events, FTS. Does **not** store vault body as SoT (S06).
public final class KnowledgeStore: @unchecked Sendable {
    private let db: SQLiteDatabase
    public let path: String

    public init(path: String) throws {
        self.path = path
        let dir = URL(fileURLWithPath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.db = try SQLiteDatabase(path: path)
        try migrate()
    }

    public static func openDefault(knowledgeRoot: URL = KnowledgePaths.defaultKnowledgeRoot) throws -> KnowledgeStore {
        let dbPath = knowledgeRoot.appendingPathComponent("index/knowledge.db").path
        return try KnowledgeStore(path: dbPath)
    }

    private func migrate() throws {
        try db.exec(IndexSchema.migrationV1)
        let count = try db.scalarInt("SELECT COUNT(*) FROM schema_version;")
        if count == 0 {
            try db.exec("INSERT INTO schema_version(version) VALUES (1);")
        }
        var ver = try db.scalarInt("SELECT version FROM schema_version LIMIT 1")
        if ver < 2 {
            try db.exec(IndexSchema.migrationV2)
            try db.exec("UPDATE schema_version SET version = 2;")
            ver = 2
        }
        if ver < 3 {
            try db.exec(IndexSchema.migrationV3)
            try db.exec("UPDATE schema_version SET version = 3;")
            ver = 3
        }
        if ver < IndexSchema.currentVersion {
            try db.exec("UPDATE schema_version SET version = \(IndexSchema.currentVersion);")
        }
    }

    // MARK: - Meetings

    public func insertMeeting(_ m: MeetingRecord) throws {
        try db.withStatement(
            """
            INSERT INTO meeting (
              id, title, mode, status, scope, audio_path, audio_sha256, audio_duration_ms,
              transcript_path, transcript_segment_count, asr_model_id, candidate_path,
              stage1_ok, stage2_outcome, vault_path, vault_content_hash, accepted_at,
              stage_attempts, error_code, created_at, updated_at
            ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """
        ) { stmt in
            bindMeeting(stmt, m)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw SQLiteError.step(db.errorMessage)
            }
        }
    }

    public func upsertMeeting(_ m: MeetingRecord) throws {
        try db.withStatement(
            """
            INSERT INTO meeting (
              id, title, mode, status, scope, audio_path, audio_sha256, audio_duration_ms,
              transcript_path, transcript_segment_count, asr_model_id, candidate_path,
              stage1_ok, stage2_outcome, vault_path, vault_content_hash, accepted_at,
              stage_attempts, error_code, created_at, updated_at
            ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            ON CONFLICT(id) DO UPDATE SET
              title=excluded.title,
              mode=excluded.mode,
              status=excluded.status,
              scope=excluded.scope,
              audio_path=excluded.audio_path,
              audio_sha256=excluded.audio_sha256,
              audio_duration_ms=excluded.audio_duration_ms,
              transcript_path=excluded.transcript_path,
              transcript_segment_count=excluded.transcript_segment_count,
              asr_model_id=excluded.asr_model_id,
              candidate_path=excluded.candidate_path,
              stage1_ok=excluded.stage1_ok,
              stage2_outcome=excluded.stage2_outcome,
              vault_path=excluded.vault_path,
              vault_content_hash=excluded.vault_content_hash,
              accepted_at=excluded.accepted_at,
              stage_attempts=excluded.stage_attempts,
              error_code=excluded.error_code,
              updated_at=excluded.updated_at
            """
        ) { stmt in
            bindMeeting(stmt, m)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw SQLiteError.step(db.errorMessage)
            }
        }
    }

    public func getMeeting(id: String) throws -> MeetingRecord? {
        var result: MeetingRecord?
        try db.withStatement("SELECT * FROM meeting WHERE id = ? LIMIT 1") { stmt in
            SQLiteBind.text(stmt, 1, id)
            if sqlite3_step(stmt) == SQLITE_ROW {
                result = try readMeeting(stmt)
            }
        }
        return result
    }

    public func meetings(withStatus status: PipelineStatus) throws -> [MeetingRecord] {
        var rows: [MeetingRecord] = []
        try db.withStatement("SELECT * FROM meeting WHERE status = ? ORDER BY updated_at DESC") { stmt in
            SQLiteBind.text(stmt, 1, status.rawValue)
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(try readMeeting(stmt))
            }
        }
        return rows
    }

    public func countActiveRecordings() throws -> Int {
        try db.scalarInt("SELECT COUNT(*) FROM meeting WHERE status = 'recording'")
    }

    /// Remove meeting row and derived index entries. Does not touch vault markdown files.
    public func deleteMeeting(id: String) throws {
        let unitId = "meeting:\(id)"
        try db.withStatement("DELETE FROM action_item WHERE meeting_id = ?") { stmt in
            SQLiteBind.text(stmt, 1, id)
            _ = sqlite3_step(stmt)
        }
        try db.withStatement("DELETE FROM pipeline_events WHERE meeting_id = ?") { stmt in
            SQLiteBind.text(stmt, 1, id)
            _ = sqlite3_step(stmt)
        }
        try db.withStatement("DELETE FROM knowledge_chunk WHERE unit_id = ?") { stmt in
            SQLiteBind.text(stmt, 1, unitId)
            _ = sqlite3_step(stmt)
        }
        try db.withStatement("DELETE FROM knowledge_unit WHERE unit_id = ?") { stmt in
            SQLiteBind.text(stmt, 1, unitId)
            _ = sqlite3_step(stmt)
        }
        try db.withStatement("DELETE FROM fts_docs WHERE doc_id = ? OR doc_id = ?") { stmt in
            SQLiteBind.text(stmt, 1, unitId)
            SQLiteBind.text(stmt, 2, id)
            _ = sqlite3_step(stmt)
        }
        try db.withStatement("DELETE FROM source_pointer WHERE meeting_id = ? OR id = ? OR external_id = ?") { stmt in
            SQLiteBind.text(stmt, 1, id)
            SQLiteBind.text(stmt, 2, unitId)
            SQLiteBind.text(stmt, 3, id)
            _ = sqlite3_step(stmt)
        }
        try db.withStatement("DELETE FROM meeting WHERE id = ?") { stmt in
            SQLiteBind.text(stmt, 1, id)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw SQLiteError.step(db.errorMessage)
            }
        }
    }

    public func countMeetings(status: PipelineStatus) throws -> Int {
        try db.scalarInt(
            "SELECT COUNT(*) FROM meeting WHERE status = '\(status.rawValue.replacingOccurrences(of: "'", with: "''"))'"
        )
    }

    /// Apply a legal transition; logs pipeline_events. Rejects illegal edges (default deny).
    @discardableResult
    public func transition(
        meetingId: String,
        to: PipelineStatus,
        ctx: GuardContext? = nil,
        errorCode: String? = nil,
        event: String = "transition",
        mutate: ((inout MeetingRecord) -> Void)? = nil
    ) throws -> MeetingRecord {
        guard var meeting = try getMeeting(id: meetingId) else {
            throw SQLiteError.notFound
        }
        let context = ctx ?? meeting.toGuardContext()
        if let errorCode, PipelineGraph.isTimeoutSuccessViolation(to: to, errorCode: errorCode) {
            throw SQLiteError.exec("timeout cannot transition to \(to.rawValue)")
        }
        guard PipelineGraph.canTransition(from: meeting.status, to: to, ctx: context) else {
            throw SQLiteError.exec("illegal transition \(meeting.status.rawValue) -> \(to.rawValue)")
        }
        let from = meeting.status
        meeting.status = to
        meeting.updatedAt = ISO8601DateFormatter().string(from: Date())
        if let errorCode {
            meeting.errorCode = errorCode
        } else if !to.isFailure {
            meeting.errorCode = nil
        }
        mutate?(&meeting)
        try upsertMeeting(meeting)
        try appendEvent(PipelineEvent(
            meetingId: meetingId,
            fromStatus: from,
            toStatus: to,
            event: event,
            errorCode: errorCode
        ))
        return meeting
    }

    // MARK: - Events

    public func appendEvent(_ e: PipelineEvent) throws {
        try db.withStatement(
            """
            INSERT INTO pipeline_events(meeting_id, ts, from_status, to_status, event, error_code, detail_json)
            VALUES (?,?,?,?,?,?,?)
            """
        ) { stmt in
            SQLiteBind.text(stmt, 1, e.meetingId)
            SQLiteBind.text(stmt, 2, e.ts)
            SQLiteBind.text(stmt, 3, e.fromStatus?.rawValue)
            SQLiteBind.text(stmt, 4, e.toStatus?.rawValue)
            SQLiteBind.text(stmt, 5, e.event)
            SQLiteBind.text(stmt, 6, e.errorCode)
            SQLiteBind.text(stmt, 7, e.detailJSON)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw SQLiteError.step(db.errorMessage)
            }
        }
    }

    public func events(meetingId: String, limit: Int = 100) throws -> [PipelineEvent] {
        var rows: [PipelineEvent] = []
        try db.withStatement(
            """
            SELECT id, meeting_id, ts, from_status, to_status, event, error_code, detail_json
            FROM pipeline_events WHERE meeting_id = ? ORDER BY id DESC LIMIT ?
            """
        ) { stmt in
            SQLiteBind.text(stmt, 1, meetingId)
            SQLiteBind.int(stmt, 2, limit)
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(PipelineEvent(
                    id: Int64(sqlite3_column_int64(stmt, 0)),
                    meetingId: SQLiteColumn.text(stmt, 1),
                    ts: SQLiteColumn.text(stmt, 2) ?? "",
                    fromStatus: SQLiteColumn.text(stmt, 3).flatMap(PipelineStatus.init(rawValue:)),
                    toStatus: SQLiteColumn.text(stmt, 4).flatMap(PipelineStatus.init(rawValue:)),
                    event: SQLiteColumn.text(stmt, 5) ?? "",
                    errorCode: SQLiteColumn.text(stmt, 6),
                    detailJSON: SQLiteColumn.text(stmt, 7)
                ))
            }
        }
        return rows
    }

    // MARK: - FTS (derived index text only — S06)

    /// Upsert FTS document. `body` must be derived text, never claimed as body SoT.
    public func upsertFTS(docId: String, sourceType: String, title: String, body: String) throws {
        try db.withStatement("DELETE FROM fts_docs WHERE doc_id = ?") { stmt in
            SQLiteBind.text(stmt, 1, docId)
            _ = sqlite3_step(stmt)
        }
        try db.withStatement(
            "INSERT INTO fts_docs(doc_id, source_type, title, body) VALUES (?,?,?,?)"
        ) { stmt in
            SQLiteBind.text(stmt, 1, docId)
            SQLiteBind.text(stmt, 2, sourceType)
            SQLiteBind.text(stmt, 3, title)
            SQLiteBind.text(stmt, 4, body)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw SQLiteError.step(db.errorMessage)
            }
        }
    }

    public func searchFTS(query: String, limit: Int = 20) throws -> [FTSHit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        var hits: [FTSHit] = []
        // FTS5 unicode61: good for space-delimited tokens; Hangul continuous runs are one token.
        try db.withStatement(
            """
            SELECT doc_id, source_type, title, snippet(fts_docs, 3, '[', ']', '…', 12)
            FROM fts_docs WHERE fts_docs MATCH ? LIMIT ?
            """
        ) { stmt in
            SQLiteBind.text(stmt, 1, q)
            SQLiteBind.int(stmt, 2, limit)
            while sqlite3_step(stmt) == SQLITE_ROW {
                hits.append(FTSHit(
                    docId: SQLiteColumn.text(stmt, 0) ?? "",
                    sourceType: SQLiteColumn.text(stmt, 1) ?? "",
                    title: SQLiteColumn.text(stmt, 2),
                    snippet: SQLiteColumn.text(stmt, 3)
                ))
            }
        }
        if !hits.isEmpty { return hits }

        // Substring fallback (Korean ASR bodies often lack whitespace).
        let pattern = "%\(q.replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_"))%"
        try db.withStatement(
            """
            SELECT doc_id, source_type, title,
                   substr(body, max(1, instr(body, ?) - 20), 80)
            FROM fts_docs
            WHERE body LIKE ? ESCAPE '\\' OR title LIKE ? ESCAPE '\\'
            LIMIT ?
            """
        ) { stmt in
            SQLiteBind.text(stmt, 1, q)
            SQLiteBind.text(stmt, 2, pattern)
            SQLiteBind.text(stmt, 3, pattern)
            SQLiteBind.int(stmt, 4, limit)
            while sqlite3_step(stmt) == SQLITE_ROW {
                hits.append(FTSHit(
                    docId: SQLiteColumn.text(stmt, 0) ?? "",
                    sourceType: SQLiteColumn.text(stmt, 1) ?? "",
                    title: SQLiteColumn.text(stmt, 2),
                    snippet: SQLiteColumn.text(stmt, 3)
                ))
            }
        }
        return hits
    }

    // MARK: - Note mirror + source pointers

    public func upsertNoteMirror(_ n: NoteMirrorRecord) throws {
        try db.withStatement(
            """
            INSERT INTO note_mirror(
              notes_id, folder, title, body_text, content_hash, body_status, mirror_not_sot, updated_at
            ) VALUES (?,?,?,?,?,?,?,?)
            ON CONFLICT(notes_id) DO UPDATE SET
              folder=excluded.folder,
              title=excluded.title,
              body_text=excluded.body_text,
              content_hash=excluded.content_hash,
              body_status=excluded.body_status,
              mirror_not_sot=excluded.mirror_not_sot,
              updated_at=excluded.updated_at
            """
        ) { stmt in
            SQLiteBind.text(stmt, 1, n.notesId)
            SQLiteBind.text(stmt, 2, n.folder)
            SQLiteBind.text(stmt, 3, n.title)
            SQLiteBind.text(stmt, 4, n.bodyText)
            SQLiteBind.text(stmt, 5, n.contentHash)
            SQLiteBind.text(stmt, 6, n.bodyStatus)
            SQLiteBind.int(stmt, 7, n.mirrorNotSot ? 1 : 0)
            SQLiteBind.text(stmt, 8, n.updatedAt)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw SQLiteError.step(db.errorMessage)
            }
        }
    }

    public func countNoteMirrors() throws -> Int {
        try db.scalarInt("SELECT COUNT(*) FROM note_mirror;")
    }

    public func upsertSourcePointer(_ p: SourcePointerRecord) throws {
        try db.withStatement(
            """
            INSERT INTO source_pointer(
              id, source_type, external_id, title, scope, meeting_id, notes_id, vault_rel_path, updated_at
            ) VALUES (?,?,?,?,?,?,?,?,?)
            ON CONFLICT(source_type, external_id) DO UPDATE SET
              id=excluded.id,
              title=excluded.title,
              scope=excluded.scope,
              meeting_id=excluded.meeting_id,
              notes_id=excluded.notes_id,
              vault_rel_path=excluded.vault_rel_path,
              updated_at=excluded.updated_at
            """
        ) { stmt in
            SQLiteBind.text(stmt, 1, p.id)
            SQLiteBind.text(stmt, 2, p.sourceType)
            SQLiteBind.text(stmt, 3, p.externalId)
            SQLiteBind.text(stmt, 4, p.title)
            SQLiteBind.text(stmt, 5, p.scope)
            SQLiteBind.text(stmt, 6, p.meetingId)
            SQLiteBind.text(stmt, 7, p.notesId)
            SQLiteBind.text(stmt, 8, p.vaultRelPath)
            SQLiteBind.text(stmt, 9, p.updatedAt)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw SQLiteError.step(db.errorMessage)
            }
        }
    }

    public func countSourcePointers(sourceType: String? = nil) throws -> Int {
        if let sourceType {
            return try db.scalarInt(
                "SELECT COUNT(*) FROM source_pointer WHERE source_type = '\(sourceType.replacingOccurrences(of: "'", with: "''"))';"
            )
        }
        return try db.scalarInt("SELECT COUNT(*) FROM source_pointer;")
    }

    public func listSourcePointers(limit: Int = 50) throws -> [SourcePointerRecord] {
        var rows: [SourcePointerRecord] = []
        try db.withStatement(
            """
            SELECT id, source_type, external_id, title, scope, meeting_id, notes_id, vault_rel_path, updated_at
            FROM source_pointer ORDER BY updated_at DESC LIMIT ?
            """
        ) { stmt in
            SQLiteBind.int(stmt, 1, limit)
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(SourcePointerRecord(
                    id: SQLiteColumn.text(stmt, 0) ?? "",
                    sourceType: SQLiteColumn.text(stmt, 1) ?? "",
                    externalId: SQLiteColumn.text(stmt, 2) ?? "",
                    title: SQLiteColumn.text(stmt, 3),
                    scope: SQLiteColumn.text(stmt, 4) ?? "personal",
                    meetingId: SQLiteColumn.text(stmt, 5),
                    notesId: SQLiteColumn.text(stmt, 6),
                    vaultRelPath: SQLiteColumn.text(stmt, 7),
                    updatedAt: SQLiteColumn.text(stmt, 8) ?? ""
                ))
            }
        }
        return rows
    }

    // MARK: - Connected sources + knowledge units/chunks

    public func upsertConnectedSource(_ s: ConnectedSourceRecord) throws {
        try db.withStatement(
            """
            INSERT INTO connected_source(
              id, source_type, root_path, label, enabled, last_sync_at, last_error, unit_count, created_at, updated_at
            ) VALUES (?,?,?,?,?,?,?,?,?,?)
            ON CONFLICT(id) DO UPDATE SET
              source_type=excluded.source_type,
              root_path=excluded.root_path,
              label=excluded.label,
              enabled=excluded.enabled,
              last_sync_at=excluded.last_sync_at,
              last_error=excluded.last_error,
              unit_count=excluded.unit_count,
              updated_at=excluded.updated_at
            """
        ) { stmt in
            SQLiteBind.text(stmt, 1, s.id)
            SQLiteBind.text(stmt, 2, s.sourceType)
            SQLiteBind.text(stmt, 3, s.rootPath)
            SQLiteBind.text(stmt, 4, s.label)
            SQLiteBind.int(stmt, 5, s.enabled ? 1 : 0)
            SQLiteBind.text(stmt, 6, s.lastSyncAt)
            SQLiteBind.text(stmt, 7, s.lastError)
            SQLiteBind.int(stmt, 8, s.unitCount)
            SQLiteBind.text(stmt, 9, s.createdAt)
            SQLiteBind.text(stmt, 10, s.updatedAt)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw SQLiteError.step(db.errorMessage)
            }
        }
    }

    public func listConnectedSources() throws -> [ConnectedSourceRecord] {
        var rows: [ConnectedSourceRecord] = []
        try db.withStatement(
            """
            SELECT id, source_type, root_path, label, enabled, last_sync_at, last_error, unit_count, created_at, updated_at
            FROM connected_source ORDER BY source_type, label
            """
        ) { stmt in
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(ConnectedSourceRecord(
                    id: SQLiteColumn.text(stmt, 0) ?? "",
                    sourceType: SQLiteColumn.text(stmt, 1) ?? "",
                    rootPath: SQLiteColumn.text(stmt, 2),
                    label: SQLiteColumn.text(stmt, 3),
                    enabled: SQLiteColumn.int(stmt, 4) != 0,
                    lastSyncAt: SQLiteColumn.text(stmt, 5),
                    lastError: SQLiteColumn.text(stmt, 6),
                    unitCount: SQLiteColumn.int(stmt, 7),
                    createdAt: SQLiteColumn.text(stmt, 8) ?? "",
                    updatedAt: SQLiteColumn.text(stmt, 9) ?? ""
                ))
            }
        }
        return rows
    }

    public func getConnectedSource(id: String) throws -> ConnectedSourceRecord? {
        try listConnectedSources().first { $0.id == id }
    }

    public func deleteConnectedSource(id: String) throws {
        try db.withStatement("DELETE FROM connected_source WHERE id = ?") { stmt in
            SQLiteBind.text(stmt, 1, id)
            _ = sqlite3_step(stmt)
        }
    }

    public func upsertKnowledgeUnit(_ u: KnowledgeUnitRecord) throws {
        try db.withStatement(
            """
            INSERT INTO knowledge_unit(
              unit_id, source_type, title, scope, sot_kind, sot_ref, content_hash,
              meeting_status, in_corpus, rag_eligible, updated_at
            ) VALUES (?,?,?,?,?,?,?,?,?,?,?)
            ON CONFLICT(unit_id) DO UPDATE SET
              source_type=excluded.source_type,
              title=excluded.title,
              scope=excluded.scope,
              sot_kind=excluded.sot_kind,
              sot_ref=excluded.sot_ref,
              content_hash=excluded.content_hash,
              meeting_status=excluded.meeting_status,
              in_corpus=excluded.in_corpus,
              rag_eligible=excluded.rag_eligible,
              updated_at=excluded.updated_at
            """
        ) { stmt in
            SQLiteBind.text(stmt, 1, u.unitId)
            SQLiteBind.text(stmt, 2, u.sourceType)
            SQLiteBind.text(stmt, 3, u.title)
            SQLiteBind.text(stmt, 4, u.scope)
            SQLiteBind.text(stmt, 5, u.sotKind)
            SQLiteBind.text(stmt, 6, u.sotRef)
            SQLiteBind.text(stmt, 7, u.contentHash)
            SQLiteBind.text(stmt, 8, u.meetingStatus)
            SQLiteBind.int(stmt, 9, u.inCorpus ? 1 : 0)
            SQLiteBind.int(stmt, 10, u.ragEligible ? 1 : 0)
            SQLiteBind.text(stmt, 11, u.updatedAt)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw SQLiteError.step(db.errorMessage)
            }
        }
    }

    public func getKnowledgeUnit(id: String) throws -> KnowledgeUnitRecord? {
        var found: KnowledgeUnitRecord?
        try db.withStatement(
            """
            SELECT unit_id, source_type, title, scope, sot_kind, sot_ref, content_hash,
                   meeting_status, in_corpus, rag_eligible, updated_at
            FROM knowledge_unit WHERE unit_id = ?
            """
        ) { stmt in
            SQLiteBind.text(stmt, 1, id)
            if sqlite3_step(stmt) == SQLITE_ROW {
                found = KnowledgeUnitRecord(
                    unitId: SQLiteColumn.text(stmt, 0) ?? "",
                    sourceType: SQLiteColumn.text(stmt, 1) ?? "",
                    title: SQLiteColumn.text(stmt, 2),
                    scope: SQLiteColumn.text(stmt, 3) ?? "personal",
                    sotKind: SQLiteColumn.text(stmt, 4) ?? "",
                    sotRef: SQLiteColumn.text(stmt, 5) ?? "",
                    contentHash: SQLiteColumn.text(stmt, 6),
                    meetingStatus: SQLiteColumn.text(stmt, 7),
                    inCorpus: SQLiteColumn.int(stmt, 8) != 0,
                    ragEligible: SQLiteColumn.int(stmt, 9) != 0,
                    updatedAt: SQLiteColumn.text(stmt, 10) ?? ""
                )
            }
        }
        return found
    }

    public func countKnowledgeUnits(sourceType: String? = nil) throws -> Int {
        if let sourceType {
            let esc = sourceType.replacingOccurrences(of: "'", with: "''")
            return try db.scalarInt("SELECT COUNT(*) FROM knowledge_unit WHERE source_type = '\(esc)';")
        }
        return try db.scalarInt("SELECT COUNT(*) FROM knowledge_unit;")
    }

    public func listKnowledgeUnitIds(limit: Int = 50_000) throws -> [String] {
        var out: [String] = []
        try db.withStatement(
            "SELECT unit_id FROM knowledge_unit WHERE in_corpus = 1 LIMIT ?"
        ) { stmt in
            SQLiteBind.int(stmt, 1, limit)
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let id = SQLiteColumn.text(stmt, 0) { out.append(id) }
            }
        }
        return out
    }

    public func replaceChunks(unitId: String, chunks newChunks: [KnowledgeChunkRecord]) throws {
        // Drop vectors for this unit first (FK)
        for c in try self.chunks(forUnit: unitId) {
            try db.withStatement("DELETE FROM chunk_vector WHERE chunk_id = ?") { stmt in
                SQLiteBind.text(stmt, 1, c.chunkId)
                _ = sqlite3_step(stmt)
            }
        }
        try db.withStatement("DELETE FROM knowledge_chunk WHERE unit_id = ?") { stmt in
            SQLiteBind.text(stmt, 1, unitId)
            _ = sqlite3_step(stmt)
        }
        for c in newChunks {
            try db.withStatement(
                """
                INSERT INTO knowledge_chunk(chunk_id, unit_id, ordinal, text, t_start_ms, t_end_ms, content_hash)
                VALUES (?,?,?,?,?,?,?)
                """
            ) { stmt in
                SQLiteBind.text(stmt, 1, c.chunkId)
                SQLiteBind.text(stmt, 2, c.unitId)
                SQLiteBind.int(stmt, 3, c.ordinal)
                SQLiteBind.text(stmt, 4, c.text)
                SQLiteBind.int(stmt, 5, c.tStartMs)
                SQLiteBind.int(stmt, 6, c.tEndMs)
                SQLiteBind.text(stmt, 7, c.contentHash)
                guard sqlite3_step(stmt) == SQLITE_DONE else {
                    throw SQLiteError.step(db.errorMessage)
                }
            }
        }
    }

    public func upsertChunkVector(chunkId: String, dim: Int, floats: [Float]) throws {
        let data = floats.withUnsafeBufferPointer { Data(buffer: $0) }
        try db.withStatement(
            """
            INSERT INTO chunk_vector(chunk_id, dim, embedding) VALUES (?,?,?)
            ON CONFLICT(chunk_id) DO UPDATE SET dim=excluded.dim, embedding=excluded.embedding
            """
        ) { stmt in
            SQLiteBind.text(stmt, 1, chunkId)
            SQLiteBind.int(stmt, 2, dim)
            SQLiteBind.blob(stmt, 3, data)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw SQLiteError.step(db.errorMessage)
            }
        }
    }

    public func chunkVector(chunkId: String) throws -> [Float]? {
        var out: [Float]?
        try db.withStatement("SELECT dim, embedding FROM chunk_vector WHERE chunk_id = ?") { stmt in
            SQLiteBind.text(stmt, 1, chunkId)
            if sqlite3_step(stmt) == SQLITE_ROW {
                let dim = SQLiteColumn.int(stmt, 0)
                guard let data = SQLiteColumn.blob(stmt, 1), dim > 0 else { return }
                let count = data.count / MemoryLayout<Float>.size
                guard count == dim else { return }
                out = data.withUnsafeBytes { raw in
                    Array(raw.bindMemory(to: Float.self).prefix(dim))
                }
            }
        }
        return out
    }

    public func allChunkVectors(limit: Int = 5000) throws -> [(chunkId: String, unitId: String, title: String, text: String, ordinal: Int, vec: [Float])] {
        var out: [(String, String, String, String, Int, [Float])] = []
        try db.withStatement(
            """
            SELECT c.chunk_id, c.unit_id, COALESCE(u.title,''), c.text, c.ordinal, v.dim, v.embedding
            FROM chunk_vector v
            JOIN knowledge_chunk c ON c.chunk_id = v.chunk_id
            JOIN knowledge_unit u ON u.unit_id = c.unit_id
            WHERE u.in_corpus = 1 AND u.rag_eligible = 1
            LIMIT ?
            """
        ) { stmt in
            SQLiteBind.int(stmt, 1, limit)
            while sqlite3_step(stmt) == SQLITE_ROW {
                let chunkId = SQLiteColumn.text(stmt, 0) ?? ""
                let unitId = SQLiteColumn.text(stmt, 1) ?? ""
                let title = SQLiteColumn.text(stmt, 2) ?? ""
                let text = SQLiteColumn.text(stmt, 3) ?? ""
                let ord = SQLiteColumn.int(stmt, 4)
                let dim = SQLiteColumn.int(stmt, 5)
                guard let data = SQLiteColumn.blob(stmt, 6), dim > 0 else { continue }
                let count = data.count / MemoryLayout<Float>.size
                guard count == dim else { continue }
                let vec = data.withUnsafeBytes { raw in
                    Array(raw.bindMemory(to: Float.self).prefix(dim))
                }
                out.append((chunkId, unitId, title, text, ord, vec))
            }
        }
        return out
    }

    // MARK: - Action items

    public func replaceActionItems(meetingId: String, items: [(id: String, text: String, owner: String?, dueOn: String?)]) throws {
        try db.withStatement("DELETE FROM action_item WHERE meeting_id = ?") { stmt in
            SQLiteBind.text(stmt, 1, meetingId)
            _ = sqlite3_step(stmt)
        }
        let now = ISO8601DateFormatter().string(from: Date())
        for it in items {
            try db.withStatement(
                """
                INSERT INTO action_item(id, meeting_id, text, owner, due_on, status, evidence_json, created_at)
                VALUES (?,?,?,?,?,'open',NULL,?)
                """
            ) { stmt in
                SQLiteBind.text(stmt, 1, it.id)
                SQLiteBind.text(stmt, 2, meetingId)
                SQLiteBind.text(stmt, 3, it.text)
                SQLiteBind.text(stmt, 4, it.owner)
                SQLiteBind.text(stmt, 5, it.dueOn)
                SQLiteBind.text(stmt, 6, now)
                guard sqlite3_step(stmt) == SQLITE_DONE else {
                    throw SQLiteError.step(db.errorMessage)
                }
            }
        }
    }

    public func openActionItems(limit: Int = 50) throws -> [(id: String, meetingId: String, text: String, owner: String?, dueOn: String?)] {
        var out: [(String, String, String, String?, String?)] = []
        try db.withStatement(
            """
            SELECT id, meeting_id, text, owner, due_on FROM action_item
            WHERE status = 'open'
            ORDER BY due_on IS NULL, due_on ASC
            LIMIT ?
            """
        ) { stmt in
            SQLiteBind.int(stmt, 1, limit)
            while sqlite3_step(stmt) == SQLITE_ROW {
                out.append((
                    SQLiteColumn.text(stmt, 0) ?? "",
                    SQLiteColumn.text(stmt, 1) ?? "",
                    SQLiteColumn.text(stmt, 2) ?? "",
                    SQLiteColumn.text(stmt, 3),
                    SQLiteColumn.text(stmt, 4)
                ))
            }
        }
        return out
    }

    public func searchChunks(query: String, limit: Int = 12) throws -> [(chunk: KnowledgeChunkRecord, unitTitle: String?)] {
        // Prefer chunk text match via unit FTS body which includes chunk concat; direct LIKE on chunks.
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        var out: [(KnowledgeChunkRecord, String?)] = []
        let pattern = "%\(q.replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_"))%"
        try db.withStatement(
            """
            SELECT c.chunk_id, c.unit_id, c.ordinal, c.text, c.t_start_ms, c.t_end_ms, c.content_hash, u.title
            FROM knowledge_chunk c
            JOIN knowledge_unit u ON u.unit_id = c.unit_id
            WHERE u.in_corpus = 1 AND u.rag_eligible = 1
              AND c.text LIKE ? ESCAPE '\\'
            ORDER BY c.ordinal
            LIMIT ?
            """
        ) { stmt in
            SQLiteBind.text(stmt, 1, pattern)
            SQLiteBind.int(stmt, 2, limit)
            while sqlite3_step(stmt) == SQLITE_ROW {
                out.append((readChunkRow(stmt), SQLiteColumn.text(stmt, 7)))
            }
        }
        return out
    }

    /// All chunks for a unit (neighbor expansion / MMR).
    public func chunks(forUnit unitId: String) throws -> [KnowledgeChunkRecord] {
        var out: [KnowledgeChunkRecord] = []
        try db.withStatement(
            """
            SELECT chunk_id, unit_id, ordinal, text, t_start_ms, t_end_ms, content_hash
            FROM knowledge_chunk
            WHERE unit_id = ?
            ORDER BY ordinal ASC
            """
        ) { stmt in
            SQLiteBind.text(stmt, 1, unitId)
            while sqlite3_step(stmt) == SQLITE_ROW {
                out.append(readChunkRowNoTitle(stmt))
            }
        }
        return out
    }

    private func readChunkRow(_ stmt: OpaquePointer) -> KnowledgeChunkRecord {
        KnowledgeChunkRecord(
            chunkId: SQLiteColumn.text(stmt, 0) ?? "",
            unitId: SQLiteColumn.text(stmt, 1) ?? "",
            ordinal: SQLiteColumn.int(stmt, 2),
            text: SQLiteColumn.text(stmt, 3) ?? "",
            tStartMs: {
                let v = SQLiteColumn.int(stmt, 4)
                return sqlite3_column_type(stmt, 4) == SQLITE_NULL ? nil : v
            }(),
            tEndMs: {
                let v = SQLiteColumn.int(stmt, 5)
                return sqlite3_column_type(stmt, 5) == SQLITE_NULL ? nil : v
            }(),
            contentHash: SQLiteColumn.text(stmt, 6)
        )
    }

    private func readChunkRowNoTitle(_ stmt: OpaquePointer) -> KnowledgeChunkRecord {
        KnowledgeChunkRecord(
            chunkId: SQLiteColumn.text(stmt, 0) ?? "",
            unitId: SQLiteColumn.text(stmt, 1) ?? "",
            ordinal: SQLiteColumn.int(stmt, 2),
            text: SQLiteColumn.text(stmt, 3) ?? "",
            tStartMs: {
                let v = SQLiteColumn.int(stmt, 4)
                return sqlite3_column_type(stmt, 4) == SQLITE_NULL ? nil : v
            }(),
            tEndMs: {
                let v = SQLiteColumn.int(stmt, 5)
                return sqlite3_column_type(stmt, 5) == SQLITE_NULL ? nil : v
            }(),
            contentHash: SQLiteColumn.text(stmt, 6)
        )
    }

    // MARK: - S06 invariant

    /// S06: meeting table must not store full vault markdown body.
    /// We verify by ensuring no column named body/markdown/content_md exists.
    public func assertMeetingHasNoBodySOTColumn() throws {
        var names: [String] = []
        try db.withStatement("PRAGMA table_info(meeting)") { stmt in
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let n = SQLiteColumn.text(stmt, 1) {
                    names.append(n.lowercased())
                }
            }
        }
        let forbidden = ["body", "markdown", "content_md", "vault_body", "note_body"]
        for f in forbidden where names.contains(f) {
            throw SQLiteError.exec("S06 violation: meeting has body-like column \(f)")
        }
    }

    public func schemaVersion() throws -> Int {
        try db.scalarInt("SELECT version FROM schema_version LIMIT 1")
    }

    // MARK: - Private

    private func bindMeeting(_ stmt: OpaquePointer, _ m: MeetingRecord) {
        SQLiteBind.text(stmt, 1, m.id)
        SQLiteBind.text(stmt, 2, m.title)
        SQLiteBind.text(stmt, 3, m.mode)
        SQLiteBind.text(stmt, 4, m.status.rawValue)
        SQLiteBind.text(stmt, 5, m.scope)
        SQLiteBind.text(stmt, 6, m.audioPath)
        SQLiteBind.text(stmt, 7, m.audioSha256)
        SQLiteBind.int(stmt, 8, m.audioDurationMs)
        SQLiteBind.text(stmt, 9, m.transcriptPath)
        SQLiteBind.int(stmt, 10, m.transcriptSegmentCount)
        SQLiteBind.text(stmt, 11, m.asrModelId)
        SQLiteBind.text(stmt, 12, m.candidatePath)
        SQLiteBind.int(stmt, 13, m.stage1OK ? 1 : 0)
        SQLiteBind.text(stmt, 14, m.stage2Outcome?.rawValue)
        SQLiteBind.text(stmt, 15, m.vaultPath)
        SQLiteBind.text(stmt, 16, m.vaultContentHash)
        SQLiteBind.text(stmt, 17, m.acceptedAt)
        SQLiteBind.int(stmt, 18, m.stageAttempts)
        SQLiteBind.text(stmt, 19, m.errorCode)
        SQLiteBind.text(stmt, 20, m.createdAt)
        SQLiteBind.text(stmt, 21, m.updatedAt)
    }

    private func readMeeting(_ stmt: OpaquePointer) throws -> MeetingRecord {
        // Column order from SELECT * matches CREATE TABLE order + rowid? Prefer named indices via pragma is hard;
        // use fixed order from CREATE TABLE (no rowid first — sqlite includes only declared cols in SELECT * order).
        guard let id = SQLiteColumn.text(stmt, 0) else { throw SQLiteError.step("missing id") }
        let statusRaw = SQLiteColumn.text(stmt, 3) ?? ""
        guard let status = PipelineStatus(rawValue: statusRaw) else {
            throw SQLiteError.invalidStatus(statusRaw)
        }
        let stage2Raw = SQLiteColumn.text(stmt, 13)
        return MeetingRecord(
            id: id,
            title: SQLiteColumn.text(stmt, 1),
            mode: SQLiteColumn.text(stmt, 2) ?? "offline_mic",
            status: status,
            scope: SQLiteColumn.text(stmt, 4) ?? "personal",
            audioPath: SQLiteColumn.text(stmt, 5),
            audioSha256: SQLiteColumn.text(stmt, 6),
            audioDurationMs: {
                let v = SQLiteColumn.int(stmt, 7)
                return sqlite3_column_type(stmt, 7) == SQLITE_NULL ? nil : v
            }(),
            transcriptPath: SQLiteColumn.text(stmt, 8),
            transcriptSegmentCount: SQLiteColumn.int(stmt, 9),
            asrModelId: SQLiteColumn.text(stmt, 10),
            candidatePath: SQLiteColumn.text(stmt, 11),
            stage1OK: SQLiteColumn.int(stmt, 12) != 0,
            stage2Outcome: stage2Raw.flatMap(Stage2Outcome.init(rawValue:)),
            vaultPath: SQLiteColumn.text(stmt, 14),
            vaultContentHash: SQLiteColumn.text(stmt, 15),
            acceptedAt: SQLiteColumn.text(stmt, 16),
            stageAttempts: SQLiteColumn.int(stmt, 17),
            errorCode: SQLiteColumn.text(stmt, 18),
            createdAt: SQLiteColumn.text(stmt, 19) ?? "",
            updatedAt: SQLiteColumn.text(stmt, 20) ?? ""
        )
    }
}
