import Foundation
import Speech
import AVFoundation
import CoreMedia

/// On-device speech recognition (UI process only — needs TCC).
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
        language: String = "ko",
        timeoutSeconds: TimeInterval = 45
    ) async throws -> TranscriptDocument {
        let status = await requestAuthorization()
        guard status == .authorized else {
            throw SpeechASRError.notAuthorized(status)
        }

        let localeId = language.hasPrefix("ko") ? "ko-KR" : (language == "en" ? "en-US" : language)
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeId)),
              recognizer.isAvailable else {
            throw SpeechASRError.unavailable
        }

        // Guard empty/near-empty files (previous AAC bug)
        let size = (try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? NSNumber)?.intValue ?? 0
        if size < 1600 {
            return try writeSilencePlaceholder(
                meetingId: meetingId,
                outputJSON: outputJSON,
                modelId: "apple-speech/\(localeId)",
                reason: "audio_too_small"
            )
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        if #available(macOS 13.0, *) {
            request.requiresOnDeviceRecognition = false
        }

        let result: Result<SFSpeechRecognitionResult, Error> = await withTaskGroup(
            of: Result<SFSpeechRecognitionResult, Error>.self
        ) { group in
            group.addTask {
                await withCheckedContinuation { cont in
                    var finished = false
                    let task = recognizer.recognitionTask(with: request) { res, err in
                        if finished { return }
                        if let err {
                            finished = true
                            cont.resume(returning: .failure(err))
                            return
                        }
                        if let res, res.isFinal {
                            finished = true
                            cont.resume(returning: .success(res))
                        }
                    }
                    // Retain task until callback
                    _ = task
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                return .failure(SpeechASRError.timeout)
            }
            let first = await group.next()!
            group.cancelAll()
            return first
        }

        switch result {
        case let .success(speech):
            var segments = segmentsFrom(result: speech)
            if segments.isEmpty {
                return try writeSilencePlaceholder(
                    meetingId: meetingId,
                    outputJSON: outputJSON,
                    modelId: "apple-speech/\(localeId)",
                    reason: "no_speech_detected"
                )
            }
            return try write(
                meetingId: meetingId,
                segments: segments,
                outputJSON: outputJSON,
                modelId: "apple-speech/\(localeId)"
            )
        case let .failure(err):
            if err is SpeechASRError || (err as? SpeechASRError) != nil {
                // timeout → still produce transcript so pipeline continues
                return try writeSilencePlaceholder(
                    meetingId: meetingId,
                    outputJSON: outputJSON,
                    modelId: "apple-speech/\(localeId)",
                    reason: "speech_timeout_or_empty"
                )
            }
            // Other errors: still soft-fail to placeholder so user sees review flow
            return try writeSilencePlaceholder(
                meetingId: meetingId,
                outputJSON: outputJSON,
                modelId: "apple-speech/\(localeId)",
                reason: "speech_error:\(err.localizedDescription.prefix(80))"
            )
        }
    }

    private static func writeSilencePlaceholder(
        meetingId: String,
        outputJSON: URL,
        modelId: String,
        reason: String
    ) throws -> TranscriptDocument {
        let segs = [
            TranscriptSegment(
                index: 0,
                tStartMs: 0,
                tEndMs: 1000,
                text: "(인식된 말이 없어요 — \(reason). 마이크에 말해 녹음했는지 확인해 주세요)"
            ),
        ]
        return try write(meetingId: meetingId, segments: segs, outputJSON: outputJSON, modelId: modelId)
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
        let best = result.bestTranscription
        if !best.segments.isEmpty {
            for seg in best.segments {
                let text = seg.substring.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let start = Int(seg.timestamp * 1000)
                let end = Int((seg.timestamp + max(seg.duration, 0.05)) * 1000)
                out.append(TranscriptSegment(
                    index: out.count,
                    tStartMs: max(0, start),
                    tEndMs: max(start + 1, end),
                    text: text
                ))
            }
        }
        if out.isEmpty {
            let text = best.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                out.append(TranscriptSegment(index: 0, tStartMs: 0, tEndMs: 1000, text: text))
            }
        }
        return out
    }
}

public enum SpeechASRError: Error, LocalizedError {
    case notAuthorized(SFSpeechRecognizerAuthorizationStatus)
    case unavailable
    case timeout

    public var errorDescription: String? {
        switch self {
        case .notAuthorized: return "음성 인식 권한이 없어요. 시스템 설정에서 허용해 주세요."
        case .unavailable: return "음성 인식을 사용할 수 없어요."
        case .timeout: return "받아쓰기 시간이 초과됐어요."
        }
    }
}
