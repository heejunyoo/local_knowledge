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

/// Bridge so UI can log identity without importing ScreenCaptureKit availability awkwardly.
public enum SystemAudioRecorderIdentity {
    public static func snapshot() -> String {
        if #available(macOS 13.0, *) {
            return SystemAudioRecorder.identityDescription()
        }
        return "macOS < 13"
    }
}

public enum CaptureError: Error, Equatable, CustomStringConvertible, LocalizedError {
    case alreadyRecording
    case notRecording
    case permissionDenied
    case emptyAudio
    case engine(String)
    case cancelled

    public var description: String {
        switch self {
        case .alreadyRecording: return "이미 녹음 중이에요"
        case .notRecording: return "녹음이 시작되지 않았어요"
        case .permissionDenied: return "녹음 권한이 없어요"
        case .emptyAudio: return "녹음 파일이 비어 있어요"
        case let .engine(m): return m
        case .cancelled: return "녹음이 취소됐어요"
        }
    }

    public var errorDescription: String? { description }
}
