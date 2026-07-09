import Foundation
import KnowledgeCore
import KnowledgeRPC

public enum CaptureMode: String, Sendable {
    case systemAudio = "system_audio"
    case offlineMic = "offline_mic"
}

/// Capture first, then register meeting — avoids orphan `recording` rows on SCK/TCC failure.
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
        // Provisional id used for audio filename before RPC create
        let id = UUID().uuidString

        // 1) Start capture FIRST (fail here → no DB row)
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

        // 2) Register meeting only after capture is live
        do {
            let client = UnixDomainClient(socketPath: socketPath)
            try client.connect()
            defer { client.close() }

            // Clear orphans so create isn't blocked
            _ = try? client.call(JSONRPCRequest(method: RPCMethod.meetingAbandonOrphans.rawValue))

            var params: [String: JSONValue] = [
                "id": .string(id),
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
                try cancelCaptureOnly()
                throw CaptureError.engine(err.message)
            }
        } catch {
            try cancelCaptureOnly()
            if let c = error as? CaptureError { throw c }
            throw CaptureError.engine(String(describing: error))
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
        try cancelCaptureOnly()
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
