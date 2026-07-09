import Foundation
import KnowledgeCore
import KnowledgeIndex
import KnowledgeWorkers

/// In-process request handler used by the daemon (and tests).
public final class PipelineService: @unchecked Sendable {
    public static let version = DaemonVersion.current
    private let store: KnowledgeStore
    private let policy: PeerPolicy
    private let knowledgeRoot: URL
    private let vaultPath: URL

    public init(
        store: KnowledgeStore,
        knowledgeRoot: URL,
        vaultPath: URL,
        policy: PeerPolicy = PeerPolicy()
    ) {
        self.store = store
        self.knowledgeRoot = knowledgeRoot
        self.vaultPath = vaultPath
        self.policy = policy
    }

    /// Loads vault_path from app.json when present.
    public static func resolveVaultPath(knowledgeRoot: URL) -> URL {
        let appJSON = knowledgeRoot.appendingPathComponent("config/app.json")
        if let data = try? Data(contentsOf: appJSON),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let vp = obj["vault_path"] as? String {
            let expanded: String
            if vp.hasPrefix("~/") {
                expanded = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(String(vp.dropFirst(2))).path
            } else {
                expanded = (vp as NSString).expandingTildeInPath
            }
            return URL(fileURLWithPath: expanded, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Obsidian/Main", isDirectory: true)
    }

    public func handle(request: JSONRPCRequest, peer: PeerIdentity) -> JSONRPCResponse {
        guard policy.authorize(peer) else {
            return JSONRPCResponse(id: request.id, error: .app("peer unauthorized", code: -32001))
        }
        guard request.jsonrpc == "2.0" else {
            return JSONRPCResponse(id: request.id, error: .invalidRequest)
        }

        do {
            let result = try dispatch(method: request.method, params: request.params)
            return JSONRPCResponse(id: request.id, result: result)
        } catch let e as JSONRPCError {
            return JSONRPCResponse(id: request.id, error: e)
        } catch {
            return JSONRPCResponse(id: request.id, error: .app(String(describing: error)))
        }
    }

    private func dispatch(method: String, params: JSONValue?) throws -> JSONValue {
        switch RPCMethod(rawValue: method) {
        case .ping:
            return .object(["pong": .bool(true)])

        case .health:
            let recording = try store.countActiveRecordings()
            let review = try store.meetings(withStatus: .reviewNeeded).count
            let engines = ToolBootstrap(knowledgeRoot: knowledgeRoot).fieldEngineStatus()
            let vaultOK = FileManager.default.fileExists(atPath: vaultPath.path)
            return .object([
                "ok": .bool(true),
                "version": .string(Self.version),
                "db_path": .string(store.path),
                "recording_count": .number(Double(recording)),
                "review_needed_count": .number(Double(review)),
                "vault_path": .string(vaultPath.path),
                "vault_ok": .bool(vaultOK),
                "asr_engine": .string(engines.asr),
                "llm_engine": .string(engines.llm),
                "whisper_ready": .bool(engines.whisperReady),
                "llama_ready": .bool(engines.llamaReady),
            ])

        case .search:
            return try handleSearch(params: params)

        case .searchReindex:
            let n = try reindexCommittedFTS()
            // Also rebuild meeting corpus units/chunks
            let corpus = makeCorpus()
            let m = try corpus.syncMeetings()
            return .object([
                "reindexed": .number(Double(n)),
                "meetings_corpus": .number(Double(m)),
            ])

        case .corpusSync:
            let corpus = makeCorpus()
            try corpus.ensureDefaultConnections()
            let report = try corpus.syncAll(notesProvider: nil)
            return .object([
                "meetings": .number(Double(report.meetings)),
                "obsidian": .number(Double(report.obsidian)),
                "notes": .number(Double(report.notes)),
                "files": .number(Double(report.files)),
                "message": .string(report.message),
            ])

        case .corpusStatus:
            return try corpusStatusJSON()

        case .meetingDelete:
            guard let id = params?["id"]?.stringValue else { throw JSONRPCError.invalidParams }
            let r = try MeetingCleanup.deleteMeeting(
                id: id,
                store: store,
                knowledgeRoot: knowledgeRoot,
                deleteLocalFiles: true
            )
            return .object([
                "deleted_meetings": .number(Double(r.deletedMeetings)),
                "deleted_files": .number(Double(r.deletedFiles)),
                "freed_bytes": .number(Double(r.freedBytes)),
                "message": .string(r.message),
            ])

        case .meetingPurgeAbandoned:
            let r = try MeetingCleanup.purgeAbandoned(store: store, knowledgeRoot: knowledgeRoot)
            return .object([
                "deleted_meetings": .number(Double(r.deletedMeetings)),
                "deleted_files": .number(Double(r.deletedFiles)),
                "freed_bytes": .number(Double(r.freedBytes)),
                "message": .string(r.message),
            ])

        case .meetingList:
            let statusFilter = params?["status"]?.stringValue
            let meetings: [MeetingRecord]
            if let statusFilter, let st = PipelineStatus(rawValue: statusFilter) {
                meetings = try store.meetings(withStatus: st)
            } else {
                meetings = try PipelineStatus.allCases.flatMap { try store.meetings(withStatus: $0) }
            }
            return .array(meetings.map { meetingJSON($0) })

        case .meetingGet:
            guard let id = params?["id"]?.stringValue else { throw JSONRPCError.invalidParams }
            guard let m = try store.getMeeting(id: id) else {
                throw JSONRPCError.app("not found", code: -32004)
            }
            return meetingJSON(m)

        case .meetingAbandonOrphans:
            let n = try abandonOrphanRecordings()
            return .object(["abandoned": .number(Double(n))])

        case .meetingCreate:
            // Auto-clear stale recordings (app crash / force quit left status=recording)
            _ = try abandonOrphanRecordings()
            let id = params?["id"]?.stringValue ?? UUID().uuidString
            let title = params?["title"]?.stringValue
            let mode = params?["mode"]?.stringValue ?? "system_audio"
            let scope = params?["scope"]?.stringValue ?? "personal"
            if try store.countActiveRecordings() > 0 {
                throw JSONRPCError.app("another recording active", code: -32010)
            }
            guard PipelineGraph.canStartRecording(ctx: GuardContext(
                otherRecordingActive: false,
                capturePreflightOK: true
            )) else {
                throw JSONRPCError.app("cannot start recording", code: -32011)
            }
            let m = MeetingRecord(id: id, title: title, mode: mode, status: .recording, scope: scope)
            try store.insertMeeting(m)
            try store.appendEvent(PipelineEvent(
                meetingId: id,
                fromStatus: nil,
                toStatus: .recording,
                event: "meeting.create"
            ))
            return meetingJSON(m)

        case .meetingTransition:
            return try handleTransition(params: params)

        case .meetingSummaryGet:
            guard let id = params?["id"]?.stringValue else { throw JSONRPCError.invalidParams }
            guard let m = try store.getMeeting(id: id), let rel = m.candidatePath else {
                throw JSONRPCError.app("summary not found", code: -32005)
            }
            let url = knowledgeRoot.appendingPathComponent(rel)
            guard let data = try? Data(contentsOf: url),
                  let obj = try? JSONSerialization.jsonObject(with: data) else {
                throw JSONRPCError.app("summary unreadable", code: -32006)
            }
            return jsonValue(from: obj)

        case .meetingReviewAccept:
            return try handleReviewAccept(params: params)

        case .meetingRetry:
            guard let id = params?["id"]?.stringValue else { throw JSONRPCError.invalidParams }
            guard var m = try store.getMeeting(id: id) else {
                throw JSONRPCError.app("not found", code: -32004)
            }
            if m.status == .transcribeFailed || m.status == .transcribing {
                // Park as recorded so UI can ASR without race with daemon
                m.status = .recorded
                m.stageAttempts = 0
                m.errorCode = nil
                try store.upsertMeeting(m)
            } else if m.status == .summaryFailed, m.transcriptPath != nil {
                m.status = .transcribed
                m.stageAttempts = 0
                m.errorCode = nil
                try store.upsertMeeting(m)
            } else if (m.status == .reviewNeeded || m.status == .summarizedCandidate),
                      m.transcriptPath != nil {
                // Re-summarize from existing transcript (improved extractive / coalesce)
                m.status = .transcribed
                m.stageAttempts = 0
                m.errorCode = nil
                m.candidatePath = nil
                m.stage1OK = false
                m.stage2Outcome = nil
                try store.upsertMeeting(m)
            }
            return meetingJSON(m)

        case .meetingAsrComplete:
            return try handleAsrComplete(params: params)

        case .none:
            throw JSONRPCError.methodNotFound
        }
    }

    private func handleSearch(params: JSONValue?) throws -> JSONValue {
        let q = (params?["q"]?.stringValue ?? params?["query"]?.stringValue ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            return .object(["hits": .array([]), "q": .string(q)])
        }
        let limit: Int
        if case let .number(n) = params?["limit"] {
            limit = max(1, min(50, Int(n)))
        } else {
            limit = 20
        }
        // FTS5: simple token query; strip characters that break MATCH
        let safe = q
            .replacingOccurrences(of: "\"", with: " ")
            .replacingOccurrences(of: "*", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !safe.isEmpty else {
            return .object(["hits": .array([]), "q": .string(q)])
        }
        let hits = try store.searchFTS(query: safe, limit: limit)
        return .object([
            "q": .string(q),
            "hits": .array(hits.map { h in
                .object([
                    "doc_id": .string(h.docId),
                    "source_type": .string(h.sourceType),
                    "title": h.title.map { .string($0) } ?? .null,
                    "snippet": h.snippet.map { .string($0) } ?? .null,
                ])
            }),
        ])
    }

    /// Rebuild FTS rows for committed meetings from candidate JSON / title.
    @discardableResult
    private func reindexCommittedFTS() throws -> Int {
        let committed = try store.meetings(withStatus: .committed)
        var n = 0
        for m in committed {
            let title = m.title ?? "미팅"
            var body = title
            if let rel = m.candidatePath {
                let url = knowledgeRoot.appendingPathComponent(rel)
                if let data = try? Data(contentsOf: url),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let parts: [String] = [
                        obj["one_line_summary"] as? String,
                        ((obj["key_discussion_points"] as? [[String: Any]]) ?? []).compactMap { $0["text"] as? String }.joined(separator: " "),
                        ((obj["decisions"] as? [[String: Any]]) ?? []).compactMap { $0["text"] as? String }.joined(separator: " "),
                        ((obj["action_items"] as? [[String: Any]]) ?? []).compactMap { $0["text"] as? String }.joined(separator: " "),
                    ].compactMap { $0 }
                    body = parts.joined(separator: "\n")
                }
            }
            try store.upsertFTS(docId: m.id, sourceType: "meeting", title: title, body: body)
            n += 1
        }
        return n
    }

    /// Idempotent: from recorded|transcribing|transcribe_failed → transcribed with artifacts.
    private func handleAsrComplete(params: JSONValue?) throws -> JSONValue {
        guard let id = params?["id"]?.stringValue,
              let transcriptPath = params?["transcript_path"]?.stringValue else {
            throw JSONRPCError.invalidParams
        }
        let segmentCount: Int
        if case let .number(n) = params?["transcript_segment_count"] {
            segmentCount = max(1, Int(n))
        } else {
            segmentCount = 1
        }
        let asrModel = params?["asr_model_id"]?.stringValue
        guard var meeting = try store.getMeeting(id: id) else {
            throw JSONRPCError.app("not found", code: -32004)
        }
        guard meeting.audioPath != nil || params?["audio_path"]?.stringValue != nil else {
            throw JSONRPCError.app("audio missing", code: -32030)
        }
        if let ap = params?["audio_path"]?.stringValue {
            meeting.audioPath = ap
        }
        meeting.transcriptPath = transcriptPath
        meeting.transcriptSegmentCount = segmentCount
        meeting.asrModelId = asrModel
        meeting.errorCode = nil

        // Normalize status to transcribing then transcribed for legal graph edges
        switch meeting.status {
        case .recorded, .transcribeFailed, .recordFailed:
            meeting.status = .transcribing
            try store.upsertMeeting(meeting)
        case .transcribing, .transcribed:
            try store.upsertMeeting(meeting)
        default:
            // Already past ASR — just return
            try store.upsertMeeting(meeting)
            return meetingJSON(meeting)
        }

        let ctx = GuardContext(
            hasAudioArtifact: true,
            audioDurationMs: meeting.audioDurationMs ?? 1,
            transcriptSegmentCount: segmentCount,
            hasTranscriptPath: true,
            asrModelId: asrModel,
            workerSlotFree: true
        )
        let updated = try store.transition(
            meetingId: id,
            to: .transcribed,
            ctx: ctx,
            event: "meeting.asr.complete"
        ) { rec in
            rec.transcriptPath = transcriptPath
            rec.transcriptSegmentCount = segmentCount
            rec.asrModelId = asrModel
            rec.errorCode = nil
        }
        return meetingJSON(updated)
    }

    /// Mark leftover `recording` rows as abandoned (no live capture).
    @discardableResult
    private func abandonOrphanRecordings() throws -> Int {
        let active = try store.meetings(withStatus: .recording)
        var n = 0
        for m in active {
            _ = try? store.transition(
                meetingId: m.id,
                to: .abandoned,
                ctx: GuardContext(),
                errorCode: "stale_recording_cleared",
                event: "meeting.abandon_orphan"
            )
            // transition recording→abandoned is legal (userOnly)
            if (try? store.getMeeting(id: m.id))?.status == .abandoned {
                n += 1
            } else {
                // Force if transition failed
                var copy = m
                copy.status = .abandoned
                copy.errorCode = "stale_recording_cleared"
                try store.upsertMeeting(copy)
                n += 1
            }
        }
        return n
    }

    private func handleTransition(params: JSONValue?) throws -> JSONValue {
        guard let id = params?["id"]?.stringValue,
              let toRaw = params?["to"]?.stringValue,
              let to = PipelineStatus(rawValue: toRaw) else {
            throw JSONRPCError.invalidParams
        }
        let errorCode = params?["error_code"]?.stringValue
        guard var meeting = try store.getMeeting(id: id) else {
            throw JSONRPCError.app("not found", code: -32004)
        }
        if let audioPath = params?["audio_path"]?.stringValue { meeting.audioPath = audioPath }
        if let sha = params?["audio_sha256"]?.stringValue { meeting.audioSha256 = sha }
        if case let .number(ms) = params?["audio_duration_ms"] { meeting.audioDurationMs = Int(ms) }
        if let tp = params?["transcript_path"]?.stringValue { meeting.transcriptPath = tp }
        if case let .number(sc) = params?["transcript_segment_count"] {
            meeting.transcriptSegmentCount = Int(sc)
        }
        if case let .bool(ok) = params?["stage1_ok"] { meeting.stage1OK = ok }
        if let s2 = params?["stage2_outcome"]?.stringValue {
            meeting.stage2Outcome = Stage2Outcome(rawValue: s2)
        }
        if let acc = params?["accepted_at"]?.stringValue { meeting.acceptedAt = acc }
        if let vp = params?["vault_path"]?.stringValue { meeting.vaultPath = vp }
        try store.upsertMeeting(meeting)

        var ctx = meeting.toGuardContext()
        if case let .bool(w) = params?["worker_slot_free"] { ctx.workerSlotFree = w }
        if case let .bool(c) = params?["critic_enabled"] { ctx.criticEnabled = c }
        if case let .bool(o) = params?["open_anyway"] { ctx.openAnywayAllowed = o }

        let updated = try store.transition(
            meetingId: id,
            to: to,
            ctx: ctx,
            errorCode: errorCode,
            event: "meeting.transition"
        )
        return meetingJSON(updated)
    }

    private func handleReviewAccept(params: JSONValue?) throws -> JSONValue {
        guard let id = params?["id"]?.stringValue else { throw JSONRPCError.invalidParams }
        guard var meeting = try store.getMeeting(id: id) else {
            throw JSONRPCError.app("not found", code: -32004)
        }
        guard meeting.status == .reviewNeeded else {
            throw JSONRPCError.app("not in review_needed", code: -32020)
        }
        guard let candRel = meeting.candidatePath else {
            throw JSONRPCError.app("no candidate", code: -32021)
        }
        let candURL = knowledgeRoot.appendingPathComponent(candRel)
        let data = try Data(contentsOf: candURL)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let summary = try dec.decode(MeetingSummaryV1.self, from: data)
        let issues = MeetingSummaryValidator.validate(summary)
        if !issues.isEmpty {
            throw JSONRPCError.app("stage1 invalid", code: -32022)
        }

        let acceptedAt = ISO8601DateFormatter().string(from: Date())
        meeting.acceptedAt = acceptedAt
        meeting.stage1OK = true
        try store.upsertMeeting(meeting)

        let humanCtx = GuardContext(
            stage1OK: true,
            stage2: meeting.stage2Outcome ?? .pass,
            humanAccepted: true
        )
        _ = try store.transition(
            meetingId: id,
            to: .commitPending,
            ctx: humanCtx,
            event: "meeting.review.accept"
        )

        let title = meeting.title ?? "미팅"
        try FileManager.default.createDirectory(at: vaultPath, withIntermediateDirectories: true)
        let (rel, hash) = try VaultCommit.commit(
            vaultPath: vaultPath,
            meetingId: id,
            title: title,
            summary: summary,
            transcriptRel: meeting.transcriptPath
        )

        let ftsBody = [
            summary.oneLineSummary,
            summary.keyDiscussionPoints.map(\.text).joined(separator: " "),
            summary.decisions.map(\.text).joined(separator: " "),
            summary.actionItems.map(\.text).joined(separator: " "),
        ].joined(separator: "\n")
        try store.upsertFTS(docId: id, sourceType: "meeting", title: title, body: ftsBody)

        let commitCtx = GuardContext(vaultFinalExists: true, indexCommittedOK: true)
        let committed = try store.transition(
            meetingId: id,
            to: .committed,
            ctx: commitCtx,
            event: "meeting.commit.ok"
        ) { rec in
            rec.vaultPath = rel
            rec.vaultContentHash = hash
            rec.acceptedAt = acceptedAt
        }

        // Action items index for due notifications
        let actions = summary.actionItems.enumerated().map { i, a in
            (
                id: "\(id)-a\(i)",
                text: a.text,
                owner: a.owner,
                dueOn: a.dueOn
            )
        }
        try? store.replaceActionItems(meetingId: id, items: actions)

        // Meeting is first-class knowledge — always enter corpus on commit (no manual import).
        try? makeCorpus().indexMeeting(committed)

        return .object([
            "meeting": meetingJSON(committed),
            "vault_rel": .string(rel),
            "action_count": .number(Double(actions.count)),
        ])
    }

    private func makeCorpus() -> KnowledgeCorpus {
        KnowledgeCorpus(store: store, knowledgeRoot: knowledgeRoot, vaultURL: vaultPath)
    }

    private func corpusStatusJSON() throws -> JSONValue {
        let corpus = makeCorpus()
        try corpus.ensureDefaultConnections()
        let sources = try store.listConnectedSources()
        let unitsMeeting = try store.countKnowledgeUnits(sourceType: "meeting")
        let unitsNotes = try store.countKnowledgeUnits(sourceType: "notes")
        let unitsObs = try store.countKnowledgeUnits(sourceType: "obsidian")
        let unitsFile = try store.countKnowledgeUnits(sourceType: "file")
        let total = try store.countKnowledgeUnits()
        return .object([
            "total_units": .number(Double(total)),
            "meetings": .number(Double(unitsMeeting)),
            "notes": .number(Double(unitsNotes)),
            "obsidian": .number(Double(unitsObs)),
            "files": .number(Double(unitsFile)),
            "sources": .array(sources.map { s in
                .object([
                    "id": .string(s.id),
                    "source_type": .string(s.sourceType),
                    "label": s.label.map { .string($0) } ?? .null,
                    "root_path": s.rootPath.map { .string($0) } ?? .null,
                    "enabled": .bool(s.enabled),
                    "last_sync_at": s.lastSyncAt.map { .string($0) } ?? .null,
                    "last_error": s.lastError.map { .string($0) } ?? .null,
                    "unit_count": .number(Double(s.unitCount)),
                ])
            }),
        ])
    }

    private func meetingJSON(_ m: MeetingRecord) -> JSONValue {
        .object([
            "id": .string(m.id),
            "title": m.title.map { .string($0) } ?? .null,
            "mode": .string(m.mode),
            "status": .string(m.status.rawValue),
            "scope": .string(m.scope),
            "audio_path": m.audioPath.map { .string($0) } ?? .null,
            "audio_duration_ms": m.audioDurationMs.map { .number(Double($0)) } ?? .null,
            "transcript_path": m.transcriptPath.map { .string($0) } ?? .null,
            "candidate_path": m.candidatePath.map { .string($0) } ?? .null,
            "stage1_ok": .bool(m.stage1OK),
            "stage2_outcome": m.stage2Outcome.map { .string($0.rawValue) } ?? .null,
            "vault_path": m.vaultPath.map { .string($0) } ?? .null,
            "error_code": m.errorCode.map { .string($0) } ?? .null,
        ])
    }

    private func jsonValue(from any: Any) -> JSONValue {
        switch any {
        case is NSNull: return .null
        case let b as Bool: return .bool(b)
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                return .bool(n.boolValue)
            }
            return .number(n.doubleValue)
        case let s as String: return .string(s)
        case let a as [Any]: return .array(a.map { jsonValue(from: $0) })
        case let d as [String: Any]:
            return .object(d.mapValues { jsonValue(from: $0) })
        default: return .string(String(describing: any))
        }
    }
}
