import Foundation
import AVFoundation
import ScreenCaptureKit
import CoreMedia
import CoreGraphics
import AudioToolbox

/// System audio via ScreenCaptureKit (display mix). Default for Mac mini.
///
/// TCC note: Screen Recording is granted per **app identity** (bundle id + path),
/// not "admin". CGPreflight can lag; we treat SCShareableContent / SCStream as source of truth.
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

    /// Soft prompt only — never treat CGPreflight false as hard failure (can lag after grant).
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
        stateLock.lock()
        if isRecording {
            stateLock.unlock()
            try? cancel()
        } else {
            stateLock.unlock()
        }

        lastError = nil
        sampleCount = 0
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
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        // Source of truth: actual SCK call (not CGPreflight alone)
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

        if let old = stream {
            old.stopCapture { _ in }
            stream = nil
        }

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        do {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: writeQueue)
        } catch {
            throw mapSCKError(error, phase: "addStreamOutput")
        }

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
            self.meetingId = nil
            self.outputURL = nil
            throw mapSCKError(error, phase: "startCapture")
        }

        stateLock.lock()
        self.isRecording = true
        stateLock.unlock()
        try writeHeartbeat()
        startHeartbeatTimer()
    }

    private func mapSCKError(_ error: Error, phase: String) -> CaptureError {
        let ns = error as NSError
        let desc = error.localizedDescription
        // SCStreamErrorDomain -3801 = user denied TCC
        if ns.domain.contains("ScreenCaptureKit") || ns.domain.contains("SCStream") || ns.code == -3801
            || desc.contains("TCC") || desc.contains("거절") || desc.localizedCaseInsensitiveContains("denied")
            || desc.localizedCaseInsensitiveContains("not authorized") {
            let id = Self.identityDescription()
            return .engine(
                """
                화면 기록(TCC)이 이 앱에 허용되지 않았습니다. (phase=\(phase), code=\(ns.code))
                \(desc)

                허용해야 할 앱 정체:
                \(id)

                조치: 시스템 설정 → 개인정보 보호 및 보안 → 화면 기록 에서 위 path 의 Knowledge를 켠 뒤,
                앱을 완전히 종료(⌘Q)하고 ~/Applications/Knowledge.app 을 다시 실행하세요.
                터미널 실행은 다른 TCC 클라이언트라서 설정과 어긋날 수 있습니다.
                """
            )
        }
        return .engine("시스템 오디오 실패 (\(phase)): \(desc) [domain=\(ns.domain) code=\(ns.code)]")
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

        writeQueue.sync { self.audioFile = nil }
        Thread.sleep(forTimeInterval: 0.15)

        if let lastError {
            throw mapSCKError(lastError, phase: "stop")
        }

        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        if size < 1600 || sampleCount < 800 {
            throw CaptureError.engine(
                "시스템 소리가 거의 캡처되지 않았어요 (bytes=\(size), samples=\(sampleCount)). 회의 소리가 실제로 재생 중인지 확인해 주세요."
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
        if inFormat.sampleRate == outFormat.sampleRate
            && inFormat.channelCount == outFormat.channelCount
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
