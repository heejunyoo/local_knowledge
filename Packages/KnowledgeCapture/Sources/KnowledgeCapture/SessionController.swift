import Foundation
import KnowledgeCore
import KnowledgeRPC

/// Coordinates mic capture with daemon RPC handoff (offline path).
public final class CaptureSessionController: @unchecked Sendable {
    private let knowledgeRoot: URL
    private let socketPath: String
    private let recorder: MicRecorder
    public private(set) var meetingId: String?

    public init(knowledgeRoot: URL, socketPath: String? = nil) {
        self.knowledgeRoot = knowledgeRoot
        self.socketPath = socketPath
            ?? knowledgeRoot.appendingPathComponent("cache/daemon.sock").path
        self.recorder = MicRecorder(knowledgeRoot: knowledgeRoot)
    }

    public func startSession(title: String? = nil) throws -> String {
        let client = UnixDomainClient(socketPath: socketPath)
        try client.connect()
        defer { client.close() }

        var params: [String: JSONValue] = [
            "mode": .string("offline_mic"),
        ]
        if let title {
            params["title"] = .string(title)
        }
        let res = try client.call(JSONRPCRequest(
            method: RPCMethod.meetingCreate.rawValue,
            params: .object(params)
        ))
        if let err = res.error {
            throw CaptureError.engine(err.message)
        }
        guard let id = res.result?["id"]?.stringValue else {
            throw CaptureError.engine("meeting.create missing id")
        }
        try recorder.start(meetingId: id)
        meetingId = id
        return id
    }

    public func stopSession() throws -> AudioArtifact {
        let artifact = try recorder.stop()
        guard let id = meetingId else { throw CaptureError.notRecording }

        let client = UnixDomainClient(socketPath: socketPath)
        try client.connect()
        defer { client.close() }

        let res = try client.call(JSONRPCRequest(
            method: RPCMethod.meetingTransition.rawValue,
            params: .object([
                "id": .string(id),
                "to": .string(PipelineStatus.recorded.rawValue),
                "audio_path": .string(artifact.path),
                "audio_sha256": .string(artifact.sha256),
                "audio_duration_ms": .number(Double(artifact.durationMs)),
            ])
        ))
        if let err = res.error {
            throw CaptureError.engine(err.message)
        }
        meetingId = nil
        return artifact
    }

    public func failSession() throws {
        try recorder.cancel()
        guard let id = meetingId else { return }
        meetingId = nil
        let client = UnixDomainClient(socketPath: socketPath)
        try client.connect()
        defer { client.close() }
        _ = try client.call(JSONRPCRequest(
            method: RPCMethod.meetingTransition.rawValue,
            params: .object([
                "id": .string(id),
                "to": .string(PipelineStatus.recordFailed.rawValue),
                "error_code": .string("capture_cancelled"),
            ])
        ))
    }
}
