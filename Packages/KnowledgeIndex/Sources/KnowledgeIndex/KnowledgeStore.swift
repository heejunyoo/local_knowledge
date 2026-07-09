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
            try db.exec("INSERT INTO schema_version(version) VALUES (\(IndexSchema.currentVersion));")
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
        var hits: [FTSHit] = []
        // MATCH query — escape by requiring simple tokens for MVP tests
        try db.withStatement(
            """
            SELECT doc_id, source_type, title, snippet(fts_docs, 3, '[', ']', '…', 12)
            FROM fts_docs WHERE fts_docs MATCH ? LIMIT ?
            """
        ) { stmt in
            SQLiteBind.text(stmt, 1, query)
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
        return hits
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
