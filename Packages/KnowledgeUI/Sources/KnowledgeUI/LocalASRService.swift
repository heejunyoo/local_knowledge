import Foundation
import KnowledgeCore
import KnowledgeWorkers
import KnowledgeRPC

/// Runs Apple Speech in the **UI process** (TCC / speech permission belong here, not daemon).
public enum LocalASRService {
    public static func transcribeIfNeeded(
        knowledgeRoot: URL,
        socketPath: String,
        meetingId: String,
        audioRelPath: String,
        language: String = "ko"
    ) async throws {
        let audioURL = knowledgeRoot.appendingPathComponent(audioRelPath)
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

        // Drive state machine via RPC: may be recorded or transcribe_failed/transcribing
        let client = UnixDomainClient(socketPath: socketPath)
        try client.connect()
        defer { client.close() }

        // Ensure we can land on transcribed with artifacts
        // If currently recorded → transcribing → transcribed
        // If stuck transcribing → just finish to transcribed
        // If failed → retry path
        let get = try client.call(JSONRPCRequest(
            method: RPCMethod.meetingGet.rawValue,
            params: .object(["id": .string(meetingId)])
        ))
        let status = get.result?["status"]?.stringValue ?? ""

        if status == "recorded" || status == "transcribe_failed" {
            if status == "transcribe_failed" {
                _ = try client.call(JSONRPCRequest(
                    method: RPCMethod.meetingRetry.rawValue,
                    params: .object(["id": .string(meetingId)])
                ))
            }
            // recorded → transcribing
            _ = try client.call(JSONRPCRequest(
                method: RPCMethod.meetingTransition.rawValue,
                params: .object([
                    "id": .string(meetingId),
                    "to": .string("transcribing"),
                    "audio_path": .string(audioRelPath),
                ])
            ))
        }

        // transcribing → transcribed
        let res = try client.call(JSONRPCRequest(
            method: RPCMethod.meetingTransition.rawValue,
            params: .object([
                "id": .string(meetingId),
                "to": .string("transcribed"),
                "transcript_path": .string(rel),
                "transcript_segment_count": .number(Double(doc.segments.count)),
                "audio_path": .string(audioRelPath),
            ])
        ))
        if let err = res.error {
            throw CaptureBridgeError.rpc(err.message)
        }
    }
}

public enum CaptureBridgeError: Error {
    case rpc(String)
}
