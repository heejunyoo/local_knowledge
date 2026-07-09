import Foundation
import KnowledgeCore
import KnowledgeWorkers
import KnowledgeRPC

/// Apple Speech in the **UI process** (TCC). Completes via `meeting.asr.complete`.
public enum LocalASRService {
    public static func transcribeAndComplete(
        knowledgeRoot: URL,
        socketPath: String,
        meetingId: String,
        audioRelPath: String,
        language: String = "ko"
    ) async throws {
        let audioURL = knowledgeRoot.appendingPathComponent(audioRelPath)
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw CaptureBridgeError.rpc("audio file missing: \(audioRelPath)")
        }

        let outJSON = knowledgeRoot
            .appendingPathComponent("transcripts", isDirectory: true)
            .appendingPathComponent("\(meetingId).json")

        let doc = try await AppleSpeechASR.transcribe(
            meetingId: meetingId,
            audioURL: audioURL,
            outputJSON: outJSON,
            language: language
        )
        let rel = "transcripts/\(meetingId).json"

        let client = UnixDomainClient(socketPath: socketPath)
        try client.connect()
        defer { client.close() }

        let res = try client.call(JSONRPCRequest(
            method: RPCMethod.meetingAsrComplete.rawValue,
            params: .object([
                "id": .string(meetingId),
                "transcript_path": .string(rel),
                "transcript_segment_count": .number(Double(max(1, doc.segments.count))),
                "asr_model_id": .string(doc.asrModelId),
                "audio_path": .string(audioRelPath),
            ])
        ))
        if let err = res.error {
            throw CaptureBridgeError.rpc(err.message)
        }
    }
}

public enum CaptureBridgeError: Error, LocalizedError {
    case rpc(String)

    public var errorDescription: String? {
        switch self {
        case let .rpc(m): return m
        }
    }
}
