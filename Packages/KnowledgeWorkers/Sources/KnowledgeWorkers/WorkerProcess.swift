import Foundation

public struct WorkerResult: Equatable, Sendable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String
    public var timedOut: Bool

    public var succeeded: Bool { exitCode == 0 && !timedOut }
}

public enum WorkerError: Error, Equatable, CustomStringConvertible {
    case binaryMissing(String)
    case modelMissing(String)
    case failed(WorkerResult)
    case timeout

    public var description: String {
        switch self {
        case let .binaryMissing(p): return "binary missing: \(p)"
        case let .modelMissing(p): return "model missing: \(p)"
        case let .failed(r): return "worker failed exit=\(r.exitCode) stderr=\(r.stderr.prefix(200))"
        case .timeout: return "worker timeout"
        }
    }
}

public enum WorkerProcess {
    /// Run external CLI with optional timeout. Never reports success on timeout.
    public static func run(
        executable: URL,
        arguments: [String],
        timeout: TimeInterval,
        currentDirectory: URL? = nil
    ) throws -> WorkerResult {
        guard FileManager.default.isExecutableFile(atPath: executable.path)
            || FileManager.default.fileExists(atPath: executable.path) else {
            throw WorkerError.binaryMissing(executable.path)
        }

        let proc = Process()
        proc.executableURL = executable
        proc.arguments = arguments
        if let currentDirectory {
            proc.currentDirectoryURL = currentDirectory
        }
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        try proc.run()

        let group = DispatchGroup()
        var timedOut = false
        group.enter()
        DispatchQueue.global().async {
            proc.waitUntilExit()
            group.leave()
        }
        let waitResult = group.wait(timeout: .now() + timeout)
        if waitResult == .timedOut {
            timedOut = true
            proc.terminate()
            // ensure reaped
            proc.waitUntilExit()
        }

        let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return WorkerResult(
            exitCode: proc.terminationStatus,
            stdout: stdout,
            stderr: stderr,
            timedOut: timedOut
        )
    }
}
