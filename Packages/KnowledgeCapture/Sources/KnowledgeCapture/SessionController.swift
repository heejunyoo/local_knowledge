import Foundation
import KnowledgeCore
import KnowledgeIndex
import KnowledgeRPC

public enum CaptureMode: String, Sendable {
    case systemAudio = "system_audio"
    case offlineMic = "offline_mic"
}

/// Capture first, then register meeting. RPC uses **fresh connection per call**
/// (and daemon now multiplexes, but one-call-per-conn remains safest).
public final class CaptureSessionController: @unchecked Sendable {
    private let knowledgeRoot: URL
    private let socketPath: String
    public let mode: CaptureMode
    private let micRecorder: MicRecorder
    private var systemRecorder: AnyObject?
    public private(set) var meetingId: String?

    public init(
        knowledgeRoot: URL,
        socketPath: String? = nil,
        mode: CaptureMode = .systemAudio
    ) {
        self.knowledgeRoot = knowledgeRoot
        self.socketPath = socketPath
            ?? knowledgeRoot.appendingPathComponent("cache/daemon.sock").path
        self.mode = mode
        self.micRecorder = MicRecorder(knowledgeRoot: knowledgeRoot)
        if #available(macOS 13.0, *), mode == .systemAudio {
            self.systemRecorder = SystemAudioRecorder(knowledgeRoot: knowledgeRoot)
        }
    }

    public func startSession(title: String? = nil) async throws -> String {
        let id = UUID().uuidString

        // 1) Capture first
        switch mode {
        case .systemAudio:
            if #available(macOS 13.0, *),
               let rec = systemRecorder as? SystemAudioRecorder {
                try await rec.start(meetingId: id)
            } else {
                throw CaptureError.engine("이 macOS 버전에서는 시스템 오디오 녹음을 지원하지 않아요")
            }
        case .offlineMic:
            try micRecorder.start(meetingId: id)
        }

        // 2) Register meeting (RPC with retry, then local DB fallback)
        do {
            try registerMeeting(id: id, title: title)
        } catch {
            // Capture is live — prefer local DB insert over aborting good SCK session
            do {
                try registerMeetingLocally(id: id, title: title)
            } catch {
                try cancelCaptureOnly()
                throw CaptureError.engine(
                    "녹음은 시작됐지만 목록 등록에 실패했어요: \(error.localizedDescription)"
                )
            }
        }

        meetingId = id
        return id
    }

    public func stopSession() throws -> AudioArtifact {
        guard let id = meetingId else { throw CaptureError.notRecording }

        let artifact: AudioArtifact
        switch mode {
        case .systemAudio:
            if #available(macOS 13.0, *),
               let rec = systemRecorder as? SystemAudioRecorder {
                artifact = try rec.stop()
            } else {
                throw CaptureError.notRecording
            }
        case .offlineMic:
            artifact = try micRecorder.stop()
        }

        // Transition to recorded — RPC then local fallback
        do {
            try rpcOnce(JSONRPCRequest(
                method: RPCMethod.meetingTransition.rawValue,
                params: .object([
                    "id": .string(id),
                    "to": .string(PipelineStatus.recorded.rawValue),
                    "audio_path": .string(artifact.path),
                    "audio_sha256": .string(artifact.sha256),
                    "audio_duration_ms": .number(Double(artifact.durationMs)),
                ])
            ))
        } catch {
            try markRecordedLocally(
                id: id,
                audioPath: artifact.path,
                sha: artifact.sha256,
                durationMs: artifact.durationMs
            )
        }
        meetingId = nil
        return artifact
    }

    public func failSession() throws {
        try cancelCaptureOnly()
        guard let id = meetingId else { return }
        meetingId = nil
        _ = try? rpcOnce(JSONRPCRequest(
            method: RPCMethod.meetingTransition.rawValue,
            params: .object([
                "id": .string(id),
                "to": .string(PipelineStatus.recordFailed.rawValue),
                "error_code": .string("capture_cancelled"),
            ])
        ))
    }

    // MARK: - RPC helpers (one connection per call)

    @discardableResult
    private func rpcOnce(_ request: JSONRPCRequest, retries: Int = 2) throws -> JSONRPCResponse {
        var last: Error?
        for attempt in 0...retries {
            do {
                let client = UnixDomainClient(socketPath: socketPath)
                try client.connect()
                defer { client.close() }
                let res = try client.call(request)
                if let err = res.error {
                    throw CaptureError.engine(err.message)
                }
                return res
            } catch {
                last = error
                // Brief backoff on broken pipe / closed
                Thread.sleep(forTimeInterval: 0.15 * Double(attempt + 1))
            }
        }
        throw last ?? CaptureError.engine("RPC failed")
    }

    private func registerMeeting(id: String, title: String?) throws {
        _ = try? rpcOnce(JSONRPCRequest(method: RPCMethod.meetingAbandonOrphans.rawValue))
        var params: [String: JSONValue] = [
            "id": .string(id),
            "mode": .string(mode.rawValue),
        ]
        if let title { params["title"] = .string(title) }
        _ = try rpcOnce(JSONRPCRequest(
            method: RPCMethod.meetingCreate.rawValue,
            params: .object(params)
        ))
    }

    private func registerMeetingLocally(id: String, title: String?) throws {
        let db = knowledgeRoot.appendingPathComponent("index/knowledge.db").path
        let store = try KnowledgeStore(path: db)
        // abandon orphans
        for m in try store.meetings(withStatus: .recording) {
            var c = m
            c.status = .abandoned
            c.errorCode = "stale_recording_cleared"
            try store.upsertMeeting(c)
        }
        let row = MeetingRecord(
            id: id,
            title: title,
            mode: mode.rawValue,
            status: .recording
        )
        try store.insertMeeting(row)
        try store.appendEvent(PipelineEvent(
            meetingId: id,
            fromStatus: nil,
            toStatus: .recording,
            event: "meeting.create.local"
        ))
    }

    private func markRecordedLocally(id: String, audioPath: String, sha: String, durationMs: Int) throws {
        let db = knowledgeRoot.appendingPathComponent("index/knowledge.db").path
        let store = try KnowledgeStore(path: db)
        guard var m = try store.getMeeting(id: id) else {
            throw CaptureError.engine("meeting missing for local recorded mark")
        }
        m.status = .recorded
        m.audioPath = audioPath
        m.audioSha256 = sha
        m.audioDurationMs = durationMs
        m.errorCode = nil
        try store.upsertMeeting(m)
        try store.appendEvent(PipelineEvent(
            meetingId: id,
            fromStatus: .recording,
            toStatus: .recorded,
            event: "meeting.transition.local"
        ))
    }

    private func cancelCaptureOnly() throws {
        switch mode {
        case .systemAudio:
            if #available(macOS 13.0, *),
               let rec = systemRecorder as? SystemAudioRecorder {
                try rec.cancel()
            }
        case .offlineMic:
            try micRecorder.cancel()
        }
    }
}
