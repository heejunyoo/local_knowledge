import Foundation
import KnowledgeCore
import KnowledgeRPC

/// Owns lifecycle of `knowledged` so the user never runs CLI.
/// - Auto-starts when socket/health is down
/// - Detached process (survives UI quit so ASR can finish)
/// - Quiet: no user-facing "start the daemon" instructions
public final class DaemonSupervisor: @unchecked Sendable {
    public let knowledgeRoot: URL
    public let socketPath: String

    private let lock = NSLock()
    private var lastStartAttempt: Date?
    private let minRestartInterval: TimeInterval = 3

    public init(knowledgeRoot: URL) {
        self.knowledgeRoot = knowledgeRoot
        self.socketPath = knowledgeRoot.appendingPathComponent("cache/daemon.sock").path
    }

    public enum Health: Equatable {
        case ready(version: String)
        case starting
        case failed(String)
    }

    /// Ensure layout + process + health. Call from UI; may block briefly on spawn.
    public func ensureReady(timeout: TimeInterval = 8) -> Health {
        try? KnowledgePaths.ensureLayout(at: knowledgeRoot)

        if let v = probeHealth() {
            return .ready(version: v)
        }

        do {
            try startIfNeeded()
        } catch {
            return .failed(userSafeMessage(for: error))
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let v = probeHealth() {
                return .ready(version: v)
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return .failed("백그라운드 준비를 끝내지 못했어요. 앱을 다시 실행해 주세요.")
    }

    public func probeHealth() -> String? {
        do {
            let client = UnixDomainClient(socketPath: socketPath)
            try client.connect()
            defer { client.close() }
            let health = try client.call(JSONRPCRequest(method: "health"))
            if health.error != nil { return nil }
            if case let .string(v) = health.result?["version"] { return v }
            return "ok"
        } catch {
            return nil
        }
    }

    public func startIfNeeded() throws {
        if probeHealth() != nil { return }

        lock.lock()
        defer { lock.unlock() }
        if let last = lastStartAttempt, Date().timeIntervalSince(last) < minRestartInterval {
            return
        }
        lastStartAttempt = Date()

        // Stale socket from dead process blocks connect sometimes
        if FileManager.default.fileExists(atPath: socketPath), probeHealth() == nil {
            try? FileManager.default.removeItem(atPath: socketPath)
        }

        guard let binary = Self.resolveDaemonBinary() else {
            throw SupervisorError.binaryNotFound
        }

        let logDir = knowledgeRoot.appendingPathComponent("logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        let logURL = logDir.appendingPathComponent("knowledged.stdout.log")

        let proc = Process()
        proc.executableURL = binary
        proc.arguments = ["--root", knowledgeRoot.path]
        proc.currentDirectoryURL = binary.deletingLastPathComponent()

        // Detach: don't kill when UI exits
        proc.standardInput = FileHandle.nullDevice
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        let logHandle = try FileHandle(forWritingTo: logURL)
        try logHandle.seekToEnd()
        proc.standardOutput = logHandle
        proc.standardError = logHandle

        try proc.run()
        // Don't wait — leave running
        let pidPath = knowledgeRoot.appendingPathComponent("cache/knowledged.pid")
        try "\(proc.processIdentifier)\n".write(to: pidPath, atomically: true, encoding: .utf8)
    }

    /// Locate knowledged next to the UI binary / inside .app / common build outputs.
    public static func resolveDaemonBinary() -> URL? {
        if let env = ProcessInfo.processInfo.environment["KNOWLEDGE_DAEMON_PATH"] {
            let u = URL(fileURLWithPath: env)
            if FileManager.default.isExecutableFile(atPath: u.path) { return u }
        }

        // .app/Contents/MacOS/knowledged (package-app.sh)
        if let aux = Bundle.main.url(forAuxiliaryExecutable: "knowledged"),
           FileManager.default.isExecutableFile(atPath: aux.path) {
            return aux
        }
        if let res = Bundle.main.resourceURL?
            .deletingLastPathComponent()
            .appendingPathComponent("MacOS/knowledged"),
           FileManager.default.isExecutableFile(atPath: res.path) {
            return res
        }

        // Same folder as running executable
        let exec = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let sibling = exec.deletingLastPathComponent().appendingPathComponent("knowledged")
        if FileManager.default.isExecutableFile(atPath: sibling.path) {
            return sibling
        }

        // SPM: .../debug/KnowledgeApp → .../debug/knowledged
        // or .../Knowledge.app/Contents/MacOS/Knowledge → MacOS/knowledged
        let candidates = [
            exec.deletingLastPathComponent().appendingPathComponent("knowledged"),
            exec.deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("debug/knowledged"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("IdeaProjects/KnowledgeApp/.build/debug/knowledged"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("IdeaProjects/KnowledgeApp/.build/arm64-apple-macosx/debug/knowledged"),
        ]
        for c in candidates {
            if FileManager.default.isExecutableFile(atPath: c.path) {
                return c
            }
        }
        return nil
    }

    private func userSafeMessage(for error: Error) -> String {
        if let e = error as? SupervisorError {
            switch e {
            case .binaryNotFound:
                return "앱 구성 파일을 찾지 못했어요. 설치를 다시 해 주세요."
            }
        }
        return "백그라운드를 시작하지 못했어요."
    }
}

public enum SupervisorError: Error {
    case binaryNotFound
}
