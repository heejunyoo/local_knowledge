import Foundation

/// Drives `KnowledgeAudioHelper` — stable TCC client for Screen Recording.
/// Main app can rebuild freely; helper binary is only re-signed when its sources change.
public final class HelperAudioRecorder: @unchecked Sendable {
    public private(set) var isRecording = false
    public private(set) var meetingId: String?
    public private(set) var outputURL: URL?

    private var process: Process?
    private var stdinPipe: Pipe?
    private let knowledgeRoot: URL
    private var startedAt: Date?

    public init(knowledgeRoot: URL) {
        self.knowledgeRoot = knowledgeRoot
    }

    public static func resolveHelperURL() -> URL? {
        // 1) Next to main executable inside .app
        if let exec = Bundle.main.executableURL {
            let sibling = exec.deletingLastPathComponent().appendingPathComponent("KnowledgeAudioHelper")
            if FileManager.default.isExecutableFile(atPath: sibling.path) { return sibling }
        }
        // 2) Fixed install location (stable TCC)
        let installed = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/Knowledge.app/Contents/MacOS/KnowledgeAudioHelper")
        if FileManager.default.isExecutableFile(atPath: installed.path) { return installed }
        // 3) Build products
        let candidates = [
            "IdeaProjects/KnowledgeApp/.build/debug/KnowledgeAudioHelper",
            "IdeaProjects/KnowledgeApp/.build/arm64-apple-macosx/debug/KnowledgeAudioHelper",
        ].map { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent($0) }
        for c in candidates where FileManager.default.isExecutableFile(atPath: c.path) {
            return c
        }
        return nil
    }

    public func start(meetingId: String) throws {
        guard !isRecording else { throw CaptureError.alreadyRecording }
        guard let helper = Self.resolveHelperURL() else {
            throw CaptureError.engine(
                "KnowledgeAudioHelper 가 없어요. scripts/package-app.sh 로 설치해 주세요."
            )
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

        let stdin = Pipe()
        let err = Pipe()
        let proc = Process()
        proc.executableURL = helper
        proc.arguments = ["record", "--out", url.path]
        proc.standardInput = stdin
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = err

        try proc.run()

        // Wait until helper prints RECORDING on stderr (or fails quickly)
        let deadline = Date().addingTimeInterval(8)
        var stderrBuf = Data()
        var started = false
        while Date() < deadline {
            let chunk = err.fileHandleForReading.availableData
            if !chunk.isEmpty {
                stderrBuf.append(chunk)
                if let s = String(data: stderrBuf, encoding: .utf8) {
                    if s.contains("RECORDING") {
                        started = true
                        break
                    }
                    if s.contains("TCC") || s.contains("3801") || s.contains("거절") {
                        proc.terminate()
                        throw CaptureError.engine(Self.tccMessage(helper: helper, detail: s))
                    }
                    if s.contains("error") || s.contains("FAIL") {
                        // keep reading a bit
                    }
                }
            }
            if !proc.isRunning {
                let s = String(data: stderrBuf, encoding: .utf8) ?? ""
                if s.contains("3801") || s.contains("TCC") || s.contains("거절") {
                    throw CaptureError.engine(Self.tccMessage(helper: helper, detail: s))
                }
                throw CaptureError.engine("오디오 헬퍼가 바로 종료됐어요: \(s.suffix(200))")
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        if !started {
            // Still running without banner — treat as started (some buffering)
            if proc.isRunning {
                started = true
            } else {
                let s = String(data: stderrBuf, encoding: .utf8) ?? ""
                throw CaptureError.engine("오디오 헬퍼 시작 실패: \(s.suffix(300))")
            }
        }

        self.process = proc
        self.stdinPipe = stdin
        self.meetingId = meetingId
        self.outputURL = url
        self.startedAt = Date()
        self.isRecording = true
        try CaptureHeartbeat(meetingId: meetingId, mode: "system_audio_helper")
            .write(to: knowledgeRoot)
    }

    public func stop() throws -> AudioArtifact {
        guard isRecording, let meetingId, let url = outputURL, let proc = process else {
            throw CaptureError.notRecording
        }
        // Signal stop
        if let stdin = stdinPipe {
            stdin.fileHandleForWriting.write(Data("stop\n".utf8))
            try? stdin.fileHandleForWriting.close()
        }
        // Wait up to 5s
        let deadline = Date().addingTimeInterval(5)
        while proc.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if proc.isRunning {
            proc.terminate()
        }
        process = nil
        stdinPipe = nil
        isRecording = false
        try? CaptureHeartbeat.clear(knowledgeRoot: knowledgeRoot)

        Thread.sleep(forTimeInterval: 0.1)
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        if size < 1600 {
            throw CaptureError.engine(
                "시스템 소리가 거의 없어요 (bytes=\(size)). 회의 소리가 재생 중인지 확인해 주세요. 헬퍼 종료코드=\(proc.terminationStatus)"
            )
        }
        let durationMs: Int
        if let startedAt {
            durationMs = max(1, Int(Date().timeIntervalSince(startedAt) * 1000))
        } else {
            durationMs = 1000
        }
        return try AudioArtifactBuilder.build(
            knowledgeRoot: knowledgeRoot,
            meetingId: meetingId,
            fileURL: url,
            durationMs: durationMs
        )
    }

    public func cancel() throws {
        if let stdin = stdinPipe {
            try? stdin.fileHandleForWriting.write(contentsOf: Data("stop\n".utf8))
            try? stdin.fileHandleForWriting.close()
        }
        process?.terminate()
        process = nil
        stdinPipe = nil
        if let url = outputURL {
            try? FileManager.default.removeItem(at: url)
        }
        isRecording = false
        meetingId = nil
        outputURL = nil
        try? CaptureHeartbeat.clear(knowledgeRoot: knowledgeRoot)
    }

    private static func tccMessage(helper: URL, detail: String) -> String {
        """
        화면 기록(TCC)이 캡처 헬퍼에 허용되지 않았습니다.
        허용 대상 실행 파일:
          \(helper.path)

        시스템 설정 → 개인정보 보호 및 보안 → 화면 기록 에서
        「KnowledgeAudioHelper」 또는 위 경로를 켠 뒤,
        Knowledge 앱을 ⌘Q 로 종료하고 ~/Applications/Knowledge.app 을 다시 실행하세요.

        (메인 앱이 아니라 헬퍼에 권한이 붙습니다. 메인 앱만 켜면 계속 실패합니다.)

        detail: \(detail.suffix(200))
        """
    }
}
