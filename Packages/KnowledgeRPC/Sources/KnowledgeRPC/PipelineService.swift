import Foundation
import KnowledgeCore
import KnowledgeIndex

/// In-process request handler used by the daemon (and tests).
public final class PipelineService: @unchecked Sendable {
    public static let version = DaemonVersion.current
    private let store: KnowledgeStore
    private let policy: PeerPolicy

    public init(store: KnowledgeStore, policy: PeerPolicy = PeerPolicy()) {
        self.store = store
        self.policy = policy
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
                // all statuses: cheap scan via union of known statuses for MVP
                meetings = try PipelineStatus.allCases.flatMap { try store.meetings(withStatus: $0) }
            }
            let arr = meetings.map { meetingJSON($0) }
            return .array(arr)

        case .meetingGet:
            guard let id = params?["id"]?.stringValue else {
                throw JSONRPCError.invalidParams
            }
            guard let m = try store.getMeeting(id: id) else {
                throw JSONRPCError.app("not found", code: -32004)
            }
            return meetingJSON(m)

        case .meetingCreate:
            let id = params?["id"]?.stringValue ?? UUID().uuidString
            let title = params?["title"]?.stringValue
            let mode = params?["mode"]?.stringValue ?? "offline_mic"
            let scope = params?["scope"]?.stringValue ?? "personal"
            if try store.countActiveRecordings() > 0 {
                throw JSONRPCError.app("another recording active", code: -32010)
            }
            let preflightOK = true
            guard PipelineGraph.canStartRecording(ctx: GuardContext(
                otherRecordingActive: false,
                capturePreflightOK: preflightOK
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
            guard let id = params?["id"]?.stringValue,
                  let toRaw = params?["to"]?.stringValue,
                  let to = PipelineStatus(rawValue: toRaw) else {
                throw JSONRPCError.invalidParams
            }
            let errorCode = params?["error_code"]?.stringValue
            guard var meeting = try store.getMeeting(id: id) else {
                throw JSONRPCError.app("not found", code: -32004)
            }
            // Apply optional artifact updates from params before guard eval
            if let audioPath = params?["audio_path"]?.stringValue {
                meeting.audioPath = audioPath
            }
            if let sha = params?["audio_sha256"]?.stringValue {
                meeting.audioSha256 = sha
            }
            if case let .number(ms) = params?["audio_duration_ms"] {
                meeting.audioDurationMs = Int(ms)
            }
            if let tp = params?["transcript_path"]?.stringValue {
                meeting.transcriptPath = tp
            }
            if case let .number(sc) = params?["transcript_segment_count"] {
                meeting.transcriptSegmentCount = Int(sc)
            }
            if case let .bool(ok) = params?["stage1_ok"] {
                meeting.stage1OK = ok
            }
            if let s2 = params?["stage2_outcome"]?.stringValue {
                meeting.stage2Outcome = Stage2Outcome(rawValue: s2)
            }
            if let acc = params?["accepted_at"]?.stringValue {
                meeting.acceptedAt = acc
            }
            if let vp = params?["vault_path"]?.stringValue {
                meeting.vaultPath = vp
            }
            try store.upsertMeeting(meeting)

            var ctx = meeting.toGuardContext()
            if case let .bool(w) = params?["worker_slot_free"] {
                ctx.workerSlotFree = w
            }
            if case let .bool(c) = params?["critic_enabled"] {
                ctx.criticEnabled = c
            }
            if case let .bool(o) = params?["open_anyway"] {
                ctx.openAnywayAllowed = o
            }

            let updated = try store.transition(
                meetingId: id,
                to: to,
                ctx: ctx,
                errorCode: errorCode,
                event: "meeting.transition"
            )
            return meetingJSON(updated)

        case .none:
            throw JSONRPCError.methodNotFound
        }
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
            "stage1_ok": .bool(m.stage1OK),
            "stage2_outcome": m.stage2Outcome.map { .string($0.rawValue) } ?? .null,
            "vault_path": m.vaultPath.map { .string($0) } ?? .null,
            "error_code": m.errorCode.map { .string($0) } ?? .null,
        ])
    }
}
