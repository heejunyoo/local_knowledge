import Foundation
import CryptoKit
import Security

/// Device pairing tokens for mobile Core gateway.
public final class PairingStore: @unchecked Sendable {
    public struct Device: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var tokenHash: String
        public var createdAt: String
        public var lastSeenAt: String?

        enum CodingKeys: String, CodingKey {
            case id, name
            case tokenHash = "token_hash"
            case createdAt = "created_at"
            case lastSeenAt = "last_seen_at"
        }
    }

    private struct FileModel: Codable {
        var devices: [Device]
        var pendingCode: String?
        var pendingExpires: String?

        enum CodingKeys: String, CodingKey {
            case devices
            case pendingCode = "pending_code"
            case pendingExpires = "pending_expires"
        }
    }

    private let url: URL
    private let lock = NSLock()
    private var model: FileModel

    public init(knowledgeRoot: URL) {
        self.url = knowledgeRoot.appendingPathComponent("config/mobile_devices.json")
        if let data = try? Data(contentsOf: url),
           let m = try? JSONDecoder().decode(FileModel.self, from: data) {
            self.model = m
        } else {
            self.model = FileModel(devices: [], pendingCode: nil, pendingExpires: nil)
        }
    }

    public func startPairing(ttlSeconds: Int = 300) throws -> (code: String, expiresIn: Int) {
        lock.lock(); defer { lock.unlock() }
        let code = String(format: "%06d", Int.random(in: 0...999_999))
        let exp = Date().addingTimeInterval(TimeInterval(ttlSeconds))
        model.pendingCode = code
        model.pendingExpires = iso(exp)
        try persist()
        return (code, ttlSeconds)
    }

    public func completePairing(code: String, deviceName: String) throws -> (token: String, deviceId: String) {
        lock.lock(); defer { lock.unlock() }
        guard let pending = model.pendingCode,
              let expS = model.pendingExpires,
              let exp = parseISO(expS),
              exp > Date() else {
            throw PairingError.expiredOrMissing
        }
        guard pending == code.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw PairingError.badCode
        }
        let token = randomToken()
        let id = UUID().uuidString
        let now = iso(Date())
        let dev = Device(
            id: id,
            name: deviceName.isEmpty ? "iPhone" : deviceName,
            tokenHash: hash(token),
            createdAt: now,
            lastSeenAt: now
        )
        model.devices.append(dev)
        model.pendingCode = nil
        model.pendingExpires = nil
        try persist()
        return (token, id)
    }

    public func authorize(bearer: String?) -> Device? {
        guard let raw = bearer?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let token = raw.hasPrefix("Bearer ") ? String(raw.dropFirst(7)) : raw
        let h = hash(token)
        lock.lock(); defer { lock.unlock() }
        guard let idx = model.devices.firstIndex(where: { $0.tokenHash == h }) else { return nil }
        model.devices[idx].lastSeenAt = iso(Date())
        try? persist()
        return model.devices[idx]
    }

    public func revoke(deviceId: String) throws {
        lock.lock(); defer { lock.unlock() }
        model.devices.removeAll { $0.id == deviceId }
        try persist()
    }

    public func listDevices() -> [Device] {
        lock.lock(); defer { lock.unlock() }
        return model.devices
    }

    private func persist() throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(model).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func hash(_ token: String) -> String {
        let d = SHA256.hash(data: Data(token.utf8))
        return d.map { String(format: "%02x", $0) }.joined()
    }

    private func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func iso(_ d: Date) -> String {
        ISO8601DateFormatter().string(from: d)
    }

    private func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

public enum PairingError: Error, CustomStringConvertible {
    case expiredOrMissing
    case badCode

    public var description: String {
        switch self {
        case .expiredOrMissing: return "pairing code expired or missing"
        case .badCode: return "invalid pairing code"
        }
    }
}
