import Foundation
import Speech
import AVFoundation
import CoreMedia

/// On-device / system speech recognition fallback when whisper.cpp is not installed.
/// User should not need CLI tool install for first offline dogfood.
public enum AppleSpeechASR {
    public static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }
    }

    public static func transcribe(
        meetingId: String,
        audioURL: URL,
        outputJSON: URL,
        language: String = "ko"
    ) async throws -> TranscriptDocument {
        let status = await requestAuthorization()
        guard status == .authorized else {
            throw WorkerError.failed(WorkerResult(
                exitCode: 1,
                stdout: "",
                stderr: "speech_auth_\(status.rawValue)",
                timedOut: false
            ))
        }

        let localeId = language.hasPrefix("ko") ? "ko-KR" : (language == "en" ? "en-US" : language)
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeId)),
              recognizer.isAvailable else {
            throw WorkerError.failed(WorkerResult(
                exitCode: 1,
                stdout: "",
                stderr: "speech_recognizer_unavailable",
                timedOut: false
            ))
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        if #available(macOS 13.0, *) {
            request.requiresOnDeviceRecognition = false // allow best available
        }

        let result: SFSpeechRecognitionResult = try await withCheckedThrowingContinuation { cont in
            var finished = false
            recognizer.recognitionTask(with: request) { res, err in
                if let err {
                    if !finished {
                        finished = true
                        cont.resume(throwing: err)
                    }
                    return
                }
                guard let res, res.isFinal else { return }
                if !finished {
                    finished = true
                    cont.resume(returning: res)
                }
            }
        }

        let segments = segmentsFrom(result: result)
        guard !segments.isEmpty else {
            // Empty audio / silence — still produce one segment so pipeline can continue honestly
            let durationMs = try audioDurationMs(url: audioURL)
            let segs = [
                TranscriptSegment(
                    index: 0,
                    tStartMs: 0,
                    tEndMs: max(durationMs, 1),
                    text: "(음성에서 인식된 말이 없어요)"
                ),
            ]
            return try write(meetingId: meetingId, segments: segs, outputJSON: outputJSON, modelId: "apple-speech/\(localeId)")
        }

        return try write(
            meetingId: meetingId,
            segments: segments,
            outputJSON: outputJSON,
            modelId: "apple-speech/\(localeId)"
        )
    }

    private static func write(
        meetingId: String,
        segments: [TranscriptSegment],
        outputJSON: URL,
        modelId: String
    ) throws -> TranscriptDocument {
        let doc = TranscriptDocument(
            meetingId: meetingId,
            asrModelId: modelId,
            language: "ko",
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

    private static func segmentsFrom(result: SFSpeechRecognitionResult) -> [TranscriptSegment] {
        var out: [TranscriptSegment] = []
        // Prefer per-segment timing when available
        let best = result.bestTranscription
        if !best.segments.isEmpty {
            for (i, seg) in best.segments.enumerated() {
                let text = seg.substring.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let start = Int(seg.timestamp * 1000)
                let end = Int((seg.timestamp + seg.duration) * 1000)
                out.append(TranscriptSegment(
                    index: out.count,
                    tStartMs: max(0, start),
                    tEndMs: max(start + 1, end),
                    text: text
                ))
                _ = i
            }
        }
        if out.isEmpty {
            let text = best.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                // Split roughly by sentence for evidence spans
                let parts = text
                    .components(separatedBy: CharacterSet(charactersIn: ".!?。！？\n"))
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                if parts.isEmpty {
                    out.append(TranscriptSegment(index: 0, tStartMs: 0, tEndMs: 1000, text: text))
                } else {
                    var t = 0
                    for (i, p) in parts.enumerated() {
                        let dur = max(800, p.count * 80)
                        out.append(TranscriptSegment(index: i, tStartMs: t, tEndMs: t + dur, text: p))
                        t += dur
                    }
                }
            }
        }
        return out
    }

    private static func audioDurationMs(url: URL) throws -> Int {
        let asset = AVURLAsset(url: url)
        let seconds = CMTimeGetSeconds(asset.duration)
        if seconds.isFinite && seconds > 0 {
            return Int(seconds * 1000)
        }
        return 1000
    }
}

// Bridge async ASR into sync pipeline tick via semaphore (daemon thread).
public enum AppleSpeechASRBridge {
    public static func transcribeSync(
        meetingId: String,
        audioURL: URL,
        outputJSON: URL,
        language: String,
        timeout: TimeInterval
    ) throws -> TranscriptDocument {
        let box = ResultBox<TranscriptDocument>()
        let sem = DispatchSemaphore(value: 0)
        Task {
            do {
                let doc = try await AppleSpeechASR.transcribe(
                    meetingId: meetingId,
                    audioURL: audioURL,
                    outputJSON: outputJSON,
                    language: language
                )
                box.result = .success(doc)
            } catch {
                box.result = .failure(error)
            }
            sem.signal()
        }
        let wait = sem.wait(timeout: .now() + timeout)
        if wait == .timedOut {
            throw WorkerError.timeout
        }
        switch box.result {
        case let .success(doc): return doc
        case let .failure(err): throw err
        case .none: throw WorkerError.failed(WorkerResult(exitCode: 1, stdout: "", stderr: "speech_no_result", timedOut: false))
        }
    }
}

private final class ResultBox<T>: @unchecked Sendable {
    var result: Result<T, Error>?
}
