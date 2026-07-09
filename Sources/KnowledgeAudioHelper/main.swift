import Foundation
import AVFoundation
import ScreenCaptureKit
import CoreMedia
import CoreGraphics
import AudioToolbox

/// Stable capture helper. Screen Recording TCC is granted to THIS binary.
/// Main app may rebuild often; this helper should be re-signed only when its sources change.
///
/// Usage:
///   KnowledgeAudioHelper record --out /path/file.wav --seconds 0
///     (seconds 0 = until SIGTERM / stdin "stop\n")
///   KnowledgeAudioHelper probe
///
/// Exit codes: 0 ok, 2 usage, 3 tcc denied, 4 capture error

@main
struct KnowledgeAudioHelperMain {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let cmd = args.first else {
            fputs("usage: KnowledgeAudioHelper probe|record --out PATH\n", stderr)
            exit(2)
        }
        switch cmd {
        case "probe":
            await probe()
        case "record":
            var out: String?
            var i = 1
            while i < args.count {
                if args[i] == "--out", i + 1 < args.count {
                    out = args[i + 1]
                    i += 2
                } else {
                    i += 1
                }
            }
            guard let out else {
                fputs("record requires --out PATH\n", stderr)
                exit(2)
            }
            await record(outPath: out)
        default:
            fputs("unknown command \(cmd)\n", stderr)
            exit(2)
        }
    }

    static func probe() async {
        let pre = CGPreflightScreenCaptureAccess()
        print("CGPreflight=\(pre)")
        print("bundle=\(Bundle.main.bundleIdentifier ?? "nil")")
        print("exec=\(CommandLine.arguments[0])")
        if !pre {
            _ = CGRequestScreenCaptureAccess()
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            print("SCShareableContent OK displays=\(content.displays.count)")
            exit(0)
        } catch {
            let ns = error as NSError
            print("SCShareableContent FAIL domain=\(ns.domain) code=\(ns.code) \(error.localizedDescription)")
            exit(ns.code == -3801 ? 3 : 4)
        }
    }

    static func record(outPath: String) async {
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        let url = URL(fileURLWithPath: outPath)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            let ns = error as NSError
            fputs("TCC/SCK content error code=\(ns.code) \(error.localizedDescription)\n", stderr)
            exit(ns.code == -3801 ? 3 : 4)
        }
        guard let display = content.displays.first else {
            fputs("no display\n", stderr)
            exit(4)
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
        config.showsCursor = false

        let outFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        )!
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forWriting: url, settings: outFormat.settings)
        } catch {
            fputs("file open: \(error)\n", stderr)
            exit(4)
        }

        let writer = AudioWriter(file: file)
        let stream = SCStream(filter: filter, configuration: config, delegate: writer)
        do {
            // Screen + audio: audio-only output often yields zero samples.
            try stream.addStreamOutput(writer, type: .screen, sampleHandlerQueue: writer.queue)
            try stream.addStreamOutput(writer, type: .audio, sampleHandlerQueue: writer.queue)
            try await stream.startCapture()
        } catch {
            let ns = error as NSError
            fputs("startCapture code=\(ns.code) \(error.localizedDescription)\n", stderr)
            exit(ns.code == -3801 ? 3 : 4)
        }

        fputs("RECORDING\n", stderr)
        fflush(stderr)

        // Stop when stdin receives a line or process is killed
        let stop = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = readLine()
            stop.signal()
        }
        // Also stop after SIGTERM via dispatch source
        signal(SIGTERM) { _ in }
        stop.wait()

        let sem = DispatchSemaphore(value: 0)
        stream.stopCapture { _ in sem.signal() }
        _ = sem.wait(timeout: .now() + 3)
        writer.close()
        let samples = writer.sampleCount
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        fputs("STOPPED samples=\(samples) bytes=\(size)\n", stderr)
        if size < 1600 {
            exit(4)
        }
        print(url.path)
        exit(0)
    }
}

@available(macOS 13.0, *)
final class AudioWriter: NSObject, SCStreamDelegate, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(label: "helper.audio")
    private var file: AVAudioFile?
    private(set) var sampleCount: Int64 = 0
    private let targetRate: Double = 16_000

    init(file: AVAudioFile) {
        self.file = file
    }

    func close() {
        queue.sync { self.file = nil }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        fputs("stream stop error: \(error.localizedDescription)\n", stderr)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, let file else { return }
        guard CMSampleBufferIsValid(sampleBuffer),
              let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        let frames = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frames > 0 else { return }
        guard let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else { return }
        var asbd = asbdPtr.pointee
        guard let inFormat = AVAudioFormat(streamDescription: &asbd),
              let inBuffer = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: AVAudioFrameCount(frames))
        else { return }
        inBuffer.frameLength = AVAudioFrameCount(frames)
        let st = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frames),
            into: inBuffer.mutableAudioBufferList
        )
        guard st == noErr else { return }

        let outFormat = file.processingFormat
        if inFormat.sampleRate == outFormat.sampleRate && inFormat.channelCount == outFormat.channelCount {
            try? file.write(from: inBuffer)
            sampleCount += Int64(inBuffer.frameLength)
            return
        }
        guard let converter = AVAudioConverter(from: inFormat, to: outFormat) else { return }
        let ratio = outFormat.sampleRate / max(inFormat.sampleRate, 1)
        let outFrames = AVAudioFrameCount(Double(frames) * ratio) + 64
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: outFrames) else { return }
        var err: NSError?
        var consumed = false
        converter.convert(to: outBuffer, error: &err) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return inBuffer
        }
        if err == nil, outBuffer.frameLength > 0 {
            try? file.write(from: outBuffer)
            sampleCount += Int64(outBuffer.frameLength)
        }
    }
}
