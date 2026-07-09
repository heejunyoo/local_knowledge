import Foundation
import CryptoKit

public struct AudioArtifact: Equatable, Sendable {
    public var path: String
    public var sha256: String
    public var durationMs: Int
    public var byteCount: Int

    public init(path: String, sha256: String, durationMs: Int, byteCount: Int) {
        self.path = path
        self.sha256 = sha256
        self.durationMs = durationMs
        self.byteCount = byteCount
    }
}

public enum AudioArtifactBuilder {
    public static func rawURL(knowledgeRoot: URL, meetingId: String, ext: String = "m4a") -> URL {
        knowledgeRoot
            .appendingPathComponent("audio/raw", isDirectory: true)
            .appendingPathComponent("\(meetingId).\(ext)")
    }

    public static func derivedURL(knowledgeRoot: URL, meetingId: String) -> URL {
        knowledgeRoot
            .appendingPathComponent("audio/derived", isDirectory: true)
            .appendingPathComponent("\(meetingId).wav")
    }

    public static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let chunk = handle.readData(ofLength: 1024 * 1024)
            if chunk.isEmpty { return false }
            hasher.update(data: chunk)
            return true
        }) {}
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func build(
        knowledgeRoot: URL,
        meetingId: String,
        fileURL: URL,
        durationMs: Int
    ) throws -> AudioArtifact {
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        guard size > 0 else {
            throw CaptureError.emptyAudio
        }
        let hash = try sha256(of: fileURL)
        // Store relative path from knowledge root when possible
        let rootPath = knowledgeRoot.standardizedFileURL.path
        let abs = fileURL.standardizedFileURL.path
        let rel: String
        if abs.hasPrefix(rootPath + "/") {
            rel = String(abs.dropFirst(rootPath.count + 1))
        } else {
            rel = abs
        }
        return AudioArtifact(path: rel, sha256: hash, durationMs: durationMs, byteCount: size)
    }
}

public enum CaptureError: Error, Equatable, CustomStringConvertible {
    case alreadyRecording
    case notRecording
    case permissionDenied
    case emptyAudio
    case engine(String)
    case cancelled

    public var description: String {
        switch self {
        case .alreadyRecording: return "already recording"
        case .notRecording: return "not recording"
        case .permissionDenied: return "microphone permission denied"
        case .emptyAudio: return "empty audio file"
        case let .engine(m): return m
        case .cancelled: return "cancelled"
        }
    }
}
