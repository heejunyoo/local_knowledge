import Foundation
import KnowledgeCore
import KnowledgeRPC
#if canImport(Darwin)
import Darwin
#endif

/// Owns lifecycle of `knowledged` so the user never runs CLI.
/// - Auto-starts when socket/health is down
/// - Ensures mobile HTTP gateway (:8741) is up (restarts legacy daemons without --http-port)
/// - Detached process (survives UI quit so ASR can finish)
/// - Quiet: no user-facing "start the daemon" instructions
public final class DaemonSupervisor: @unchecked Sendable {
    public let knowledgeRoot: URL
    public let socketPath: String
    public let defaultHTTPPort: UInt16

    private let lock = NSLock()
    private var lastStartAttempt: Date?
    private let minRestartInterval: TimeInterval = 3

    public init(knowledgeRoot: URL, httpPort: UInt16 = 8741) {
        self.knowledgeRoot = knowledgeRoot
        self.socketPath = knowledgeRoot.appendingPathComponent("cache/daemon.sock").path
        if let env = ProcessInfo.processInfo.environment["KNOWLEDGE_HTTP_PORT"],
           let p = UInt16(env) {
            self.defaultHTTPPort = p
        } else {
            self.defaultHTTPPort = httpPort
        }
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
            // Bring up HTTP gateway if an old daemon is UDS-only.
            _ = ensureMobileGateway(timeout: min(timeout, 6))
            return .ready(version: v)
        }

        do {
            try startIfNeeded(force: false)
        } catch {
            return .failed(userSafeMessage(for: error))
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let v = probeHealth() {
                _ = ensureMobileGateway(timeout: 4)
                return .ready(version: v)
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return .failed("백그라운드 준비를 끝내지 못했어요. 앱을 다시 실행해 주세요.")
    }

    /// Mobile Core HTTP gateway must answer on loopback. Restarts daemon if legacy (no --http-port).
    @discardableResult
    public func ensureMobileGateway(port: UInt16? = nil, timeout: TimeInterval = 10) -> Bool {
        if ProcessInfo.processInfo.environment["KNOWLEDGE_HTTP_DISABLE"] == "1" {
            return false
        }
        let port = port ?? defaultHTTPPort
        if probeHTTP(port: port) { return true }

        // UDS-only or dead: stop and relaunch with --http-port
        stopDaemonsForThisRoot()
        do {
            try startIfNeeded(force: true)
        } catch {
            return false
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if probeHTTP(port: port) { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return probeHTTP(port: port)
    }

    public func probeHTTP(port: UInt16? = nil) -> Bool {
        let port = port ?? defaultHTTPPort
        guard let url = URL(string: "http://127.0.0.1:\(port)/v1/health") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 1.5
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            defer { sem.signal() }
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  obj["ok"] as? Bool == true else { return }
            ok = true
        }.resume()
        _ = sem.wait(timeout: .now() + 2)
        return ok
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

    public func startIfNeeded(force: Bool = false) throws {
        if !force, probeHealth() != nil { return }

        lock.lock()
        defer { lock.unlock() }
        if !force, let last = lastStartAttempt, Date().timeIntervalSince(last) < minRestartInterval {
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
        // Mobile Core gateway on by default (Tailscale). Disable with KNOWLEDGE_HTTP_DISABLE=1.
        var args = ["--root", knowledgeRoot.path]
        let env = ProcessInfo.processInfo.environment
        if env["KNOWLEDGE_HTTP_DISABLE"] != "1" {
            args += ["--http-port", "\(defaultHTTPPort)"]
        }
        proc.arguments = args
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
        fputs("knowledged: started pid=\(proc.processIdentifier) args=\(args.joined(separator: " "))\n", stderr)
    }

    /// Stop knowledged processes bound to this knowledge root (and pid file).
    public func stopDaemonsForThisRoot() {
        let rootPath = knowledgeRoot.path
        let pidPath = knowledgeRoot.appendingPathComponent("cache/knowledged.pid")
        if let s = try? String(contentsOf: pidPath, encoding: .utf8),
           let pid = Int32(s.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 1 {
            kill(pid, SIGTERM)
        }

        // Kill only our binary invocations with matching --root (avoid spotlightknowledged).
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-ax", "-o", "pid=,command="]
        let out = Pipe()
        task.standardOutput = out
        task.standardError = Pipe()
        try? task.run()
        task.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return }
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.contains("knowledged"),
                  !trimmed.contains("spotlightknowledged"),
                  !trimmed.contains("siriknowledged"),
                  trimmed.contains(rootPath) || trimmed.contains("--root \(rootPath)") || trimmed.contains("--root \(rootPath)/")
            else { continue }
            // command line must look like .../knowledged
            guard trimmed.contains("/knowledged") || trimmed.hasPrefix("knowledged") else { continue }
            let pidStr = trimmed.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
            if let pid = Int32(pidStr), pid > 1 {
                kill(pid, SIGTERM)
            }
        }
        Thread.sleep(forTimeInterval: 0.4)
        // Reap stubborn
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.contains("/knowledged"),
                  !trimmed.contains("spotlight"),
                  trimmed.contains(rootPath) else { continue }
            let pidStr = trimmed.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
            if let pid = Int32(pidStr), pid > 1 {
                kill(pid, SIGKILL)
            }
        }
        try? FileManager.default.removeItem(atPath: socketPath)
        Thread.sleep(forTimeInterval: 0.2)
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
