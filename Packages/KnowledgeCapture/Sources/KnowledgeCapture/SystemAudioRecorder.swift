import Foundation
import AVFoundation
import ScreenCaptureKit
import CoreMedia
import CoreGraphics
import AudioToolbox

/// System audio via ScreenCaptureKit (display mix). Default for Mac mini.
///
/// Critical implementation details (macOS 13–26):
/// 1. Register **both** `.screen` and `.audio` outputs — audio-only often yields zero buffers.
/// 2. Extract PCM with `CMSampleBufferCopyPCMDataIntoAudioBufferList` (fixed `AudioBufferList` fails).
/// 3. Write via `MonoWavWriter` — `AVAudioFile` left `data` chunk size=0 so ASR saw empty files.
@available(macOS 13.0, *)
public final class SystemAudioRecorder: NSObject, @unchecked Sendable {
    public private(set) var isRecording = false
    public private(set) var meetingId: String?
    public private(set) var outputURL: URL?

    private var stream: SCStream?
    private var wav: MonoWavWriter?
    private var converter: AVAudioConverter?
    private var outFormat: AVAudioFormat!
    private var startedAt: Date?
    private var heartbeatTimer: Timer?
    private let knowledgeRoot: URL
    private let heartbeatInterval: TimeInterval
    private let writeQueue = DispatchQueue(label: "knowledge.systemaudio.write")
    private var sampleCount: Int64 = 0
    private var buffersReceived: Int = 0
    private var buffersWritten: Int = 0
    private var buffersDropped: Int = 0
    private var peakAbs: Int32 = 0
    private let targetSampleRate: Double = 16_000
    private var lastError: Error?

    public init(knowledgeRoot: URL, heartbeatInterval: TimeInterval = 5) {
        self.knowledgeRoot = knowledgeRoot
        self.heartbeatInterval = heartbeatInterval
        super.init()
    }

    public static func requestScreenAccessIfNeeded() {
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
        }
    }

    public static func screenAccessGranted() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    public static func identityDescription() -> String {
        let bid = Bundle.main.bundleIdentifier ?? "(no bundle id)"
        let path = Bundle.main.bundlePath
        let exec = Bundle.main.executablePath ?? CommandLine.arguments[0]
        return "bundle=\(bid)\npath=\(path)\nexec=\(exec)\nCGPreflight=\(CGPreflightScreenCaptureAccess())"
    }

    public func start(meetingId: String) async throws {
        if isRecording { try? cancel() }

        lastError = nil
        sampleCount = 0
        buffersReceived = 0
        buffersWritten = 0
        buffersDropped = 0
        peakAbs = 0
        converter = nil
        Self.requestScreenAccessIfNeeded()

        let url = AudioArtifactBuilder.rawURL(
            knowledgeRoot: knowledgeRoot,
            meetingId: meetingId,
            ext: "wav"
        )
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw mapSCKError(error, phase: "SCShareableContent")
        }
        guard let display = content.displays.first else {
            throw CaptureError.engine("디스플레이를 찾지 못했어요")
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        config.width = 32
        config.height = 32
        config.minimumFrameInterval = CMTime(value: 1, timescale: 5)
        config.queueDepth = 8
        config.showsCursor = false

        outFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: true
        )!
        let writer = try MonoWavWriter(url: url, sampleRate: Int(targetSampleRate))

        if let old = stream {
            let sem = DispatchSemaphore(value: 0)
            old.stopCapture { _ in sem.signal() }
            _ = sem.wait(timeout: .now() + 2)
            stream = nil
        }

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: writeQueue)
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: writeQueue)
        } catch {
            throw mapSCKError(error, phase: "addStreamOutput")
        }

        self.wav = writer
        self.stream = stream
        self.meetingId = meetingId
        self.outputURL = url
        self.startedAt = Date()

        do {
            try await stream.startCapture()
        } catch {
            self.stream = nil
            try? self.wav?.close()
            self.wav = nil
            self.meetingId = nil
            self.outputURL = nil
            throw mapSCKError(error, phase: "startCapture")
        }

        isRecording = true
        try writeHeartbeat()
        startHeartbeatTimer()
    }

    private func mapSCKError(_ error: Error, phase: String) -> CaptureError {
        let ns = error as NSError
        let desc = error.localizedDescription
        if ns.domain.contains("ScreenCaptureKit") || ns.domain.contains("SCStream") || ns.code == -3801
            || desc.contains("TCC") || desc.contains("거절") || desc.localizedCaseInsensitiveContains("denied")
            || desc.localizedCaseInsensitiveContains("not authorized") {
            return .engine(
                """
                시스템 오디오 캡처 거부 (phase=\(phase), code=\(ns.code)).
                \(desc)
                런타임 정체: \(Self.identityDescription())
                """
            )
        }
        return .engine("시스템 오디오 실패 (\(phase)): \(desc) [domain=\(ns.domain) code=\(ns.code)]")
    }

    public func stop() throws -> AudioArtifact {
        guard isRecording, let meetingId, let url = outputURL else {
            throw CaptureError.notRecording
        }

        let sem = DispatchSemaphore(value: 0)
        if let stream {
            stream.stopCapture { [weak self] err in
                if let err { self?.lastError = err }
                sem.signal()
            }
            _ = sem.wait(timeout: .now() + 5)
        }
        stream = nil
        stopHeartbeatTimer()
        isRecording = false
        try CaptureHeartbeat.clear(knowledgeRoot: knowledgeRoot)

        var finalSamples: Int64 = 0
        var finalPeak: Int32 = 0
        var recv = 0, written = 0, drop = 0
        try writeQueue.sync {
            try self.wav?.close()
            finalSamples = self.sampleCount
            finalPeak = self.peakAbs
            recv = self.buffersReceived
            written = self.buffersWritten
            drop = self.buffersDropped
            self.wav = nil
            self.converter = nil
        }

        if let lastError {
            throw mapSCKError(lastError, phase: "stop")
        }

        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        if size < 1600 || finalSamples < 800 {
            throw CaptureError.engine(
                """
                시스템 소리가 거의 캡처되지 않았어요 \
                (bytes=\(size), samples=\(finalSamples), peak=\(finalPeak), \
                recv=\(recv), written=\(written), drop=\(drop)).
                """
            )
        }
        if finalPeak < 8 {
            // Captured only digital silence — likely wrong display/device or muted output.
            throw CaptureError.engine(
                """
                녹음 버퍼는 채워졌지만 소리가 무음입니다 (samples=\(finalSamples), peak=\(finalPeak)). \
                시스템 출력 볼륨·재생 앱 음소거·다른 출력 장치(HDMI 등) 여부를 확인해 주세요.
                """
            )
        }

        let durationMs: Int
        if let startedAt {
            durationMs = max(1, Int(Date().timeIntervalSince(startedAt) * 1000))
        } else {
            durationMs = Int(Double(finalSamples) / targetSampleRate * 1000)
        }

        return try AudioArtifactBuilder.build(
            knowledgeRoot: knowledgeRoot,
            meetingId: meetingId,
            fileURL: url,
            durationMs: durationMs
        )
    }

    public func cancel() throws {
        if !isRecording && stream == nil { return }
        let sem = DispatchSemaphore(value: 0)
        stream?.stopCapture { _ in sem.signal() }
        _ = sem.wait(timeout: .now() + 2)
        stream = nil
        writeQueue.sync {
            try? self.wav?.close()
            self.wav = nil
            self.converter = nil
        }
        if let url = outputURL {
            try? FileManager.default.removeItem(at: url)
        }
        stopHeartbeatTimer()
        isRecording = false
        meetingId = nil
        outputURL = nil
        try? CaptureHeartbeat.clear(knowledgeRoot: knowledgeRoot)
    }

    private func writeHeartbeat() throws {
        guard let meetingId else { return }
        try CaptureHeartbeat(meetingId: meetingId, mode: "system_audio")
            .write(to: knowledgeRoot)
    }

    private func startHeartbeatTimer() {
        stopHeartbeatTimer()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.heartbeatTimer = Timer.scheduledTimer(
                withTimeInterval: self.heartbeatInterval,
                repeats: true
            ) { [weak self] _ in
                try? self?.writeHeartbeat()
            }
        }
    }

    private func stopHeartbeatTimer() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    private func appendAudio(sampleBuffer: CMSampleBuffer) {
        buffersReceived += 1
        guard let wav else {
            buffersDropped += 1
            return
        }
        guard CMSampleBufferIsValid(sampleBuffer) else {
            buffersDropped += 1
            return
        }
        let frames = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frames > 0,
              let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)
        else {
            buffersDropped += 1
            return
        }
        var asbd = asbdPtr.pointee
        guard let inFormat = AVAudioFormat(streamDescription: &asbd),
              let inBuffer = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: AVAudioFrameCount(frames))
        else {
            buffersDropped += 1
            return
        }
        inBuffer.frameLength = AVAudioFrameCount(frames)

        let copyStatus = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frames),
            into: inBuffer.mutableAudioBufferList
        )
        guard copyStatus == noErr else {
            buffersDropped += 1
            return
        }

        // Convert → mono int16 @ 16 kHz
        if converter == nil || converter?.inputFormat != inFormat {
            converter = AVAudioConverter(from: inFormat, to: outFormat)
            converter?.downmix = true
        }
        guard let converter else {
            buffersDropped += 1
            return
        }

        let ratio = outFormat.sampleRate / max(inFormat.sampleRate, 1)
        let outFrames = AVAudioFrameCount(Double(frames) * ratio) + 32
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: outFrames) else {
            buffersDropped += 1
            return
        }

        var convError: NSError?
        var consumed = false
        let result = converter.convert(to: outBuffer, error: &convError) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return inBuffer
        }
        if convError != nil || result == .error || outBuffer.frameLength == 0 {
            buffersDropped += 1
            return
        }

        guard let ch = outBuffer.int16ChannelData else {
            buffersDropped += 1
            return
        }
        let n = Int(outBuffer.frameLength)
        let ptr = UnsafeBufferPointer(start: ch[0], count: n)
        for s in ptr {
            let a = Int32(abs(Int(s)))
            if a > peakAbs { peakAbs = a }
        }
        do {
            try wav.write(int16Samples: ptr)
            sampleCount += Int64(n)
            buffersWritten += 1
        } catch {
            buffersDropped += 1
        }
    }
}

@available(macOS 13.0, *)
extension SystemAudioRecorder: SCStreamDelegate {
    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        lastError = error
    }
}

@available(macOS 13.0, *)
extension SystemAudioRecorder: SCStreamOutput {
    public func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        if type == .audio {
            appendAudio(sampleBuffer: sampleBuffer)
        }
    }
}
