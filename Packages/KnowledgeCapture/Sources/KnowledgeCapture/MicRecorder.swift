import Foundation
import AVFoundation

/// Offline meeting mic capture. Owns TCC mic usage in the **UI process** (KD-16).
public final class MicRecorder: NSObject, @unchecked Sendable {
    public private(set) var isRecording = false
    public private(set) var meetingId: String?
    public private(set) var outputURL: URL?

    private var recorder: AVAudioRecorder?
    private var startedAt: Date?
    private var heartbeatTimer: Timer?
    private let knowledgeRoot: URL
    private let heartbeatInterval: TimeInterval

    public init(knowledgeRoot: URL, heartbeatInterval: TimeInterval = 5) {
        self.knowledgeRoot = knowledgeRoot
        self.heartbeatInterval = heartbeatInterval
        super.init()
    }

    public func requestPermission() async -> Bool {
        await withCheckedContinuation { cont in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                cont.resume(returning: granted)
            }
        }
    }

    public func start(meetingId: String) throws {
        guard !isRecording else { throw CaptureError.alreadyRecording }

        let url = AudioArtifactBuilder.rawURL(knowledgeRoot: knowledgeRoot, meetingId: meetingId)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        let rec = try AVAudioRecorder(url: url, settings: settings)
        rec.isMeteringEnabled = true
        guard rec.prepareToRecord(), rec.record() else {
            throw CaptureError.engine("AVAudioRecorder failed to start")
        }

        self.recorder = rec
        self.meetingId = meetingId
        self.outputURL = url
        self.startedAt = Date()
        self.isRecording = true
        try writeHeartbeat()
        startHeartbeatTimer()
    }

    public func stop() throws -> AudioArtifact {
        guard isRecording, let meetingId, let url = outputURL else {
            throw CaptureError.notRecording
        }
        recorder?.stop()
        recorder = nil
        stopHeartbeatTimer()
        isRecording = false
        try CaptureHeartbeat.clear(knowledgeRoot: knowledgeRoot)

        let durationMs: Int
        if let startedAt {
            durationMs = max(1, Int(Date().timeIntervalSince(startedAt) * 1000))
        } else {
            durationMs = 1
        }
        // Brief settle for file finalize
        Thread.sleep(forTimeInterval: 0.05)
        return try AudioArtifactBuilder.build(
            knowledgeRoot: knowledgeRoot,
            meetingId: meetingId,
            fileURL: url,
            durationMs: durationMs
        )
    }

    public func cancel() throws {
        guard isRecording else { return }
        recorder?.stop()
        recorder = nil
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
        try CaptureHeartbeat(meetingId: meetingId, mode: "offline_mic")
            .write(to: knowledgeRoot)
    }

    private func startHeartbeatTimer() {
        stopHeartbeatTimer()
        // Timer needs runloop; for library use, fire on main
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
}
