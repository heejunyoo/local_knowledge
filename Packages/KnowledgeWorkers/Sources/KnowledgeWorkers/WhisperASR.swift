import Foundation
import KnowledgeCore

public struct TranscriptSegment: Codable, Equatable, Sendable {
    public var index: Int
    public var tStartMs: Int
    public var tEndMs: Int
    public var text: String

    public init(index: Int, tStartMs: Int, tEndMs: Int, text: String) {
        self.index = index
        self.tStartMs = tStartMs
        self.tEndMs = tEndMs
        self.text = text
    }

    enum CodingKeys: String, CodingKey {
        case index
        case tStartMs = "t_start_ms"
        case tEndMs = "t_end_ms"
        case text
    }
}

public struct TranscriptDocument: Codable, Equatable, Sendable {
    public var meetingId: String
    public var asrModelId: String
    public var language: String
    public var segments: [TranscriptSegment]

    public init(meetingId: String, asrModelId: String, language: String, segments: [TranscriptSegment]) {
        self.meetingId = meetingId
        self.asrModelId = asrModelId
        self.language = language
        self.segments = segments
    }

    enum CodingKeys: String, CodingKey {
        case meetingId = "meeting_id"
        case asrModelId = "asr_model_id"
        case language, segments
    }
}

public struct WhisperASR {
    public var binaryURL: URL
    public var modelURL: URL
    public var language: String
    public var thresholds: Thresholds

    public init(
        binaryURL: URL,
        modelURL: URL,
        language: String = "ko",
        thresholds: Thresholds = .default
    ) {
        self.binaryURL = binaryURL
        self.modelURL = modelURL
        self.language = language
        self.thresholds = thresholds
    }

    /// Transcribe audio. Writes JSON transcript next to knowledge transcripts path.
    public func transcribe(
        meetingId: String,
        audioURL: URL,
        outputJSON: URL,
        audioDurationSeconds: Double
    ) throws -> TranscriptDocument {
        guard FileManager.default.fileExists(atPath: binaryURL.path) else {
            throw WorkerError.binaryMissing(binaryURL.path)
        }
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw WorkerError.modelMissing(modelURL.path)
        }

        let timeout = TimeInterval(thresholds.asrTimeoutSeconds(audioDurationSeconds: audioDurationSeconds))
        // whisper.cpp CLI common flags; if binary missing tests skip.
        // -oj writes {audio}.json next to input; we copy/normalize.
        let args = [
            "-m", modelURL.path,
            "-f", audioURL.path,
            "-l", language,
            "-oj",
            "-nt",
        ]
        let result = try WorkerProcess.run(
            executable: binaryURL,
            arguments: args,
            timeout: timeout
        )
        if result.timedOut {
            throw WorkerError.timeout
        }
        if !result.succeeded {
            throw WorkerError.failed(result)
        }

        // Prefer sidecar JSON from whisper.cpp
        let sidecar = audioURL.deletingPathExtension().appendingPathExtension("json")
        let segments: [TranscriptSegment]
        if FileManager.default.fileExists(atPath: sidecar.path),
           let data = try? Data(contentsOf: sidecar),
           let parsed = try? Self.parseWhisperJSON(data) {
            segments = parsed
        } else {
            // Fallback: single segment from stdout text
            let text = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                throw WorkerError.failed(result)
            }
            segments = [
                TranscriptSegment(
                    index: 0,
                    tStartMs: 0,
                    tEndMs: Int(audioDurationSeconds * 1000),
                    text: text
                ),
            ]
        }

        guard !segments.isEmpty else {
            throw WorkerError.failed(result)
        }

        let doc = TranscriptDocument(
            meetingId: meetingId,
            asrModelId: modelURL.lastPathComponent,
            language: language,
            segments: segments
        )
        try FileManager.default.createDirectory(
            at: outputJSON.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(doc).write(to: outputJSON, options: .atomic)
        return doc
    }

    /// Minimal parser for whisper.cpp json output variants.
    public static func parseWhisperJSON(_ data: Data) throws -> [TranscriptSegment] {
        let obj = try JSONSerialization.jsonObject(with: data)
        // Format A: { "transcription": [ { "offsets": {"from":ms,"to":ms}, "text": "..." } ] }
        if let dict = obj as? [String: Any],
           let arr = dict["transcription"] as? [[String: Any]] {
            return arr.enumerated().compactMap { i, item in
                let text = (item["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !text.isEmpty else { return nil }
                let offsets = item["offsets"] as? [String: Any]
                let from = offsets?["from"] as? Int ?? 0
                let to = offsets?["to"] as? Int ?? from
                return TranscriptSegment(index: i, tStartMs: from, tEndMs: to, text: text)
            }
        }
        // Format B: { "segments": [ { "start": sec, "end": sec, "text": } ] }
        if let dict = obj as? [String: Any],
           let arr = dict["segments"] as? [[String: Any]] {
            return arr.enumerated().compactMap { i, item in
                let text = (item["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !text.isEmpty else { return nil }
                let start = item["start"] as? Double ?? 0
                let end = item["end"] as? Double ?? start
                return TranscriptSegment(
                    index: i,
                    tStartMs: Int(start * 1000),
                    tEndMs: Int(end * 1000),
                    text: text
                )
            }
        }
        return []
    }
}
