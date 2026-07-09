import Foundation
import AVFoundation
import ScreenCaptureKit
import CoreMedia

/// System audio capture via ScreenCaptureKit (display mix).
/// Default path for Mac mini (often no built-in mic).
@available(macOS 13.0, *)
public final class SystemAudioRecorder: NSObject, @unchecked Sendable {
    public private(set) var isRecording = false
    public private(set) var meetingId: String?
    public private(set) var outputURL: URL?

    private var stream: SCStream?
    private var audioFile: AVAudioFile?
    private var startedAt: Date?
    private var heartbeatTimer: Timer?
    private let knowledgeRoot: URL
    private let heartbeatInterval: TimeInterval
    private let writeQueue = DispatchQueue(label: "knowledge.systemaudio.write")
    private var sampleCount: Int64 = 0
    private let targetSampleRate: Double = 16_000
    private var converter: AVAudioConverter?
    private var lastError: Error?

    public init(knowledgeRoot: URL, heartbeatInterval: TimeInterval = 5) {
        self.knowledgeRoot = knowledgeRoot
        self.heartbeatInterval = heartbeatInterval
        super.init()
    }

    /// Start capturing **display system audio** (mixed app audio on main display).
    public func start(meetingId: String) async throws {
        guard !isRecording else { throw CaptureError.alreadyRecording }
        lastError = nil
        sampleCount = 0

        let url = AudioArtifactBuilder.rawURL(
            knowledgeRoot: knowledgeRoot,
            meetingId: meetingId,
            ext: "wav"
        )
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw CaptureError.engine("표시할 디스플레이를 찾지 못했어요")
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        if #available(macOS 13.0, *) {
            config.excludesCurrentProcessAudio = true
        }
        config.sampleRate = 48_000
        config.channelCount = 1
        // Minimal video (some OS builds require a stream dimension)
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.queueDepth = 8

        let outFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: true
        )!
        let file = try AVAudioFile(forWriting: url, settings: outFormat.settings)

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: writeQueue)

        self.audioFile = file
        self.stream = stream
        self.meetingId = meetingId
        self.outputURL = url
        self.startedAt = Date()

        try await stream.startCapture()
        self.isRecording = true
        try writeHeartbeat()
        startHeartbeatTimer()
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

        // Close file
        writeQueue.sync {
            self.audioFile = nil
            self.converter = nil
        }

        Thread.sleep(forTimeInterval: 0.1)

        if let lastError {
            throw CaptureError.engine(lastError.localizedDescription)
        }

        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        if size < 1600 || sampleCount < 800 {
            throw CaptureError.engine(
                "시스템 소리가 거의 없어요. Zoom/Meet 등 회의 오디오가 재생 중인지, 화면 기록 권한이 허용됐는지 확인해 주세요."
            )
        }

        let durationMs: Int
        if let startedAt {
            durationMs = max(1, Int(Date().timeIntervalSince(startedAt) * 1000))
        } else {
            durationMs = Int(Double(sampleCount) / targetSampleRate * 1000)
        }

        return try AudioArtifactBuilder.build(
            knowledgeRoot: knowledgeRoot,
            meetingId: meetingId,
            fileURL: url,
            durationMs: durationMs
        )
    }

    public func cancel() throws {
        guard isRecording else { return }
        let sem = DispatchSemaphore(value: 0)
        stream?.stopCapture { _ in sem.signal() }
        _ = sem.wait(timeout: .now() + 2)
        stream = nil
        writeQueue.sync {
            self.audioFile = nil
            self.converter = nil
        }
        if let url = outputURL {
            try? FileManager.default.removeItem(at: url)
        }
        stopHeartbeatTimer()
        isRecording = false
        meetingId = nil
        outputURL = nil
        try CaptureHeartbeat.clear(knowledgeRoot: knowledgeRoot)
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

    private func appendAudio(buffer: CMSampleBuffer) {
        guard let audioFile else { return }
        guard let formatDesc = CMSampleBufferGetFormatDescription(buffer),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            return
        }
        var asbd = asbdPtr.pointee

        guard let inFormat = AVAudioFormat(streamDescription: &asbd) else { return }

        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(buffer))
        guard frames > 0,
              let inBuffer = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: frames) else {
            return
        }
        inBuffer.frameLength = frames

        // Copy sample data into PCM buffer
        guard let blockBuffer = CMSampleBufferGetDataBuffer(buffer) else { return }
        var lengthAtOffset = 0
        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: &lengthAtOffset,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        )
        guard status == kCMBlockBufferNoErr, let dataPointer else { return }

        if let ch0 = inBuffer.floatChannelData?[0] {
            // Float non-interleaved
            memcpy(ch0, dataPointer, totalLength)
        } else if let int16 = inBuffer.int16ChannelData?[0] {
            memcpy(int16, dataPointer, totalLength)
        } else if let ch = inBuffer.audioBufferList.pointee.mBuffers.mData {
            memcpy(ch, dataPointer, min(Int(inBuffer.audioBufferList.pointee.mBuffers.mDataByteSize), totalLength))
        } else {
            return
        }

        let outFormat = audioFile.processingFormat
        if inFormat.sampleRate != outFormat.sampleRate || inFormat.channelCount != outFormat.channelCount {
            if converter == nil || converter?.inputFormat != inFormat {
                converter = AVAudioConverter(from: inFormat, to: outFormat)
            }
            guard let converter else { return }
            let ratio = outFormat.sampleRate / inFormat.sampleRate
            let outFrames = AVAudioFrameCount(Double(frames) * ratio) + 32
            guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: outFrames) else { return }
            var error: NSError?
            var consumed = false
            let inputBlock: AVAudioConverterInputBlock = { _, status in
                if consumed {
                    status.pointee = .noDataNow
                    return nil
                }
                consumed = true
                status.pointee = .haveData
                return inBuffer
            }
            converter.convert(to: outBuffer, error: &error, withInputFrom: inputBlock)
            if error == nil, outBuffer.frameLength > 0 {
                try? audioFile.write(from: outBuffer)
                sampleCount += Int64(outBuffer.frameLength)
            }
        } else {
            try? audioFile.write(from: inBuffer)
            sampleCount += Int64(inBuffer.frameLength)
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
        guard type == .audio, CMSampleBufferIsValid(sampleBuffer) else { return }
        appendAudio(buffer: sampleBuffer)
    }
}
