import Foundation
import KnowledgeCore
import KnowledgeRPC

public enum CaptureMode: String, Sendable {
    /// ScreenCaptureKit display system audio (default for Mac mini).
    case systemAudio = "system_audio"
    /// Optional external mic path.
    case offlineMic = "offline_mic"
}

/// Coordinates capture + daemon RPC handoff. Default = system audio.
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
        let client = UnixDomainClient(socketPath: socketPath)
        try client.connect()
        defer { client.close() }

        var params: [String: JSONValue] = [
            "mode": .string(mode.rawValue),
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

        switch mode {
        case .systemAudio:
            if #available(macOS 13.0, *),
               let rec = systemRecorder as? SystemAudioRecorder {
                do {
                    try await rec.start(meetingId: id)
                } catch {
                    // Map common TCC failures
                    let msg = error.localizedDescription
                    if msg.localizedCaseInsensitiveContains("deny")
                        || msg.localizedCaseInsensitiveContains("not authorized")
                        || msg.localizedCaseInsensitiveContains("permission") {
                        throw CaptureError.engine(
                            "화면 기록 권한이 필요해요. 시스템 설정 → 개인정보 보호 및 보안 → 화면 기록 에서 Knowledge를 허용한 뒤 다시 시도해 주세요."
                        )
                    }
                    throw CaptureError.engine(msg)
                }
            } else {
                throw CaptureError.engine("이 macOS 버전에서는 시스템 오디오 녹음을 지원하지 않아요")
            }
        case .offlineMic:
            try micRecorder.start(meetingId: id)
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
        switch mode {
        case .systemAudio:
            if #available(macOS 13.0, *),
               let rec = systemRecorder as? SystemAudioRecorder {
                try rec.cancel()
            }
        case .offlineMic:
            try micRecorder.cancel()
        }
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
