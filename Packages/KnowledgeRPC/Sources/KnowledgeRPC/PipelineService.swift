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
            return .object([
                "ok": .bool(true),
                "version": .string(Self.version),
                "db_path": .string(store.path),
                "recording_count": .number(Double(recording)),
                "review_needed_count": .number(Double(review)),
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
            }
            return meetingJSON(m)

        case .meetingAsrComplete:
            return try handleAsrComplete(params: params)

        case .none:
            throw JSONRPCError.methodNotFound
        }
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

        return .object([
            "meeting": meetingJSON(committed),
            "vault_rel": .string(rel),
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
