import Foundation

/// Peer authentication for UDS connections (KD-15 MVP).
public struct PeerIdentity: Equatable, Sendable {
    public var uid: uid_t
    public var pid: pid_t
    public var path: String?

    public init(uid: uid_t, pid: pid_t, path: String? = nil) {
        self.uid = uid
        self.pid = pid
        self.path = path
    }
}

public struct PeerPolicy: Sendable {
    public var allowedUIDs: Set<uid_t>
    /// Optional executable path allowlist (empty = any path for same UID).
    public var allowedPaths: Set<String>
    public var requireSameUID: Bool

    public init(
        allowedUIDs: Set<uid_t> = [getuid()],
        allowedPaths: Set<String> = [],
        requireSameUID: Bool = true
    ) {
        self.allowedUIDs = allowedUIDs
        self.allowedPaths = allowedPaths
        self.requireSameUID = requireSameUID
    }

    public func authorize(_ peer: PeerIdentity) -> Bool {
        if requireSameUID && peer.uid != getuid() {
            return false
        }
        if !allowedUIDs.isEmpty && !allowedUIDs.contains(peer.uid) {
            return false
        }
        if !allowedPaths.isEmpty {
            guard let path = peer.path, allowedPaths.contains(path) else {
                return false
            }
        }
        return true
    }
}
