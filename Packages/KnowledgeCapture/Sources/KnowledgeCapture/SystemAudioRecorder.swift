import Foundation
import AVFoundation
import ScreenCaptureKit
import CoreMedia
import CoreGraphics
import AudioToolbox

/// System audio via ScreenCaptureKit (display mix). Default for Mac mini (no built-in mic).
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
    private var lastError: Error?
    private let stateLock = NSLock()

    public init(knowledgeRoot: URL, heartbeatInterval: TimeInterval = 5) {
        self.knowledgeRoot = knowledgeRoot
        self.heartbeatInterval = heartbeatInterval
        super.init()
    }

    public func start(meetingId: String) async throws {
        stateLock.lock()
        if isRecording {
            stateLock.unlock()
            // Recover stuck state instead of opaque "error 0"
            try? cancel()
        } else {
            stateLock.unlock()
        }

        lastError = nil
        sampleCount = 0

        // Screen Recording TCC (system audio uses the same grant)
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
            // Wait for user to flip the toggle (first launch)
            for _ in 0..<20 {
                if CGPreflightScreenCaptureAccess() { break }
                try await Task.sleep(nanoseconds: 250_000_000)
            }
            if !CGPreflightScreenCaptureAccess() {
                throw CaptureError.engine(
                    "화면 기록 권한이 꺼져 있어요. 시스템 설정 → 개인정보 보호 및 보안 → 화면 기록 에서 「Knowledge」를 켠 다음, 앱을 종료하고 다시 실행해 주세요."
                )
            }
        }

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

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw CaptureError.engine(
                "화면/시스템 오디오에 접근하지 못했어요. 화면 기록 권한에 Knowledge가 있는지 확인하고 앱을 재시작해 주세요. (\(error.localizedDescription))"
            )
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

        // Tear down previous stream if any
        if let old = stream {
            old.stopCapture { _ in }
            stream = nil
        }

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: writeQueue)

        self.audioFile = file
        self.stream = stream
        self.meetingId = meetingId
        self.outputURL = url
        self.startedAt = Date()

        do {
            try await stream.startCapture()
        } catch {
            self.stream = nil
            self.audioFile = nil
            throw CaptureError.engine(
                "시스템 오디오 캡처를 시작하지 못했어요. 화면 기록 권한 및 다른 캡처 앱 사용 여부를 확인해 주세요. (\(error.localizedDescription))"
            )
        }

        stateLock.lock()
        self.isRecording = true
        stateLock.unlock()
        try writeHeartbeat()
        startHeartbeatTimer()
    }

    public func stop() throws -> AudioArtifact {
        stateLock.lock()
        let was = isRecording
        stateLock.unlock()
        guard was, let meetingId, let url = outputURL else {
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
        stateLock.lock()
        isRecording = false
        stateLock.unlock()
        try CaptureHeartbeat.clear(knowledgeRoot: knowledgeRoot)

        writeQueue.sync {
            self.audioFile = nil
        }
        Thread.sleep(forTimeInterval: 0.15)

        if let lastError {
            let msg = lastError.localizedDescription
            throw CaptureError.engine(msg)
        }

        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        if size < 1600 || sampleCount < 800 {
            throw CaptureError.engine(
                "시스템 소리가 거의 없어요. 회의 탭에서 소리가 나고 있는지, 화면 기록이 허용됐는지 확인해 주세요."
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
        stateLock.lock()
        let was = isRecording
        stateLock.unlock()
        if !was && stream == nil { return }

        let sem = DispatchSemaphore(value: 0)
        stream?.stopCapture { _ in sem.signal() }
        _ = sem.wait(timeout: .now() + 2)
        stream = nil
        writeQueue.sync { self.audioFile = nil }
        if let url = outputURL {
            try? FileManager.default.removeItem(at: url)
        }
        stopHeartbeatTimer()
        stateLock.lock()
        isRecording = false
        stateLock.unlock()
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
        guard let audioFile else { return }
        guard CMSampleBufferIsValid(sampleBuffer),
              let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }

        var audioBufferList = AudioBufferList()
        var blockBuffer: CMBlockBuffer?
        let frames = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frames > 0 else { return }

        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return }
        defer { if let blockBuffer { /* retained, released by ARC via CF */ } }

        guard let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else { return }
        var asbd = asbdPtr.pointee
        guard let inFormat = AVAudioFormat(streamDescription: &asbd) else { return }
        guard let inBuffer = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: AVAudioFrameCount(frames)) else { return }
        inBuffer.frameLength = AVAudioFrameCount(frames)

        let absList = UnsafeMutableAudioBufferListPointer(&audioBufferList)
        if inFormat.isInterleaved {
            if let src = absList[0].mData, let dst = inBuffer.audioBufferList.pointee.mBuffers.mData {
                memcpy(dst, src, Int(absList[0].mDataByteSize))
            }
        } else if let channels = inBuffer.floatChannelData {
            for i in 0..<min(Int(inFormat.channelCount), absList.count) {
                if let src = absList[i].mData {
                    memcpy(channels[i], src, Int(absList[i].mDataByteSize))
                }
            }
        } else if let channels = inBuffer.int16ChannelData {
            for i in 0..<min(Int(inFormat.channelCount), absList.count) {
                if let src = absList[i].mData {
                    memcpy(channels[i], src, Int(absList[i].mDataByteSize))
                }
            }
        }

        let outFormat = audioFile.processingFormat
        if inFormat.sampleRate == outFormat.sampleRate && inFormat.channelCount == outFormat.channelCount
            && inFormat.commonFormat == outFormat.commonFormat {
            try? audioFile.write(from: inBuffer)
            sampleCount += Int64(inBuffer.frameLength)
            return
        }

        guard let converter = AVAudioConverter(from: inFormat, to: outFormat) else { return }
        let ratio = outFormat.sampleRate / max(inFormat.sampleRate, 1)
        let outFrames = AVAudioFrameCount(Double(frames) * ratio) + 64
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: outFrames) else { return }
        var error: NSError?
        var consumed = false
        let block: AVAudioConverterInputBlock = { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return inBuffer
        }
        converter.convert(to: outBuffer, error: &error, withInputFrom: block)
        if error == nil, outBuffer.frameLength > 0 {
            try? audioFile.write(from: outBuffer)
            sampleCount += Int64(outBuffer.frameLength)
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
        guard type == .audio else { return }
        appendAudio(sampleBuffer: sampleBuffer)
    }
}
