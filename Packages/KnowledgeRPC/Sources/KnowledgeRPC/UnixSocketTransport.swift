import Foundation
import Darwin

/// Length-prefixed (UInt32 BE) JSON frames over a stream FD.
public enum FrameCodec {
    public static func encode(_ payload: Data) -> Data {
        var len = UInt32(payload.count).bigEndian
        var out = Data(bytes: &len, count: 4)
        out.append(payload)
        return out
    }

    public static func decodeFrames(from buffer: inout Data) throws -> [Data] {
        var frames: [Data] = []
        while buffer.count >= 4 {
            let len: UInt32 = buffer.prefix(4).withUnsafeBytes { raw in
                raw.load(as: UInt32.self).bigEndian
            }
            let total = 4 + Int(len)
            guard buffer.count >= total else { break }
            let payload = buffer.subdata(in: 4..<total)
            frames.append(payload)
            buffer.removeSubrange(0..<total)
            if len > 16 * 1024 * 1024 {
                throw RPCTransportError.frameTooLarge(Int(len))
            }
        }
        return frames
    }
}

public enum RPCTransportError: Error, Equatable {
    case frameTooLarge(Int)
    case socket(String)
    case peerUnauthorized
    case closed
}

public final class UnixDomainServer: @unchecked Sendable {
    private var listenFD: Int32 = -1
    public let socketPath: String

    public init(socketPath: String) {
        self.socketPath = socketPath
    }

    public func start() throws {
        let fm = FileManager.default
        let dir = URL(fileURLWithPath: socketPath).deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        if fm.fileExists(atPath: socketPath) {
            try fm.removeItem(atPath: socketPath)
        }

        listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else {
            throw RPCTransportError.socket("socket() failed")
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            throw RPCTransportError.socket("path too long")
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { cptr in
                for (i, b) in pathBytes.enumerated() {
                    cptr[i] = b
                }
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(listenFD, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            throw RPCTransportError.socket("bind failed errno=\(errno)")
        }

        // mode 0600
        chmod(socketPath, S_IRUSR | S_IWUSR)

        guard listen(listenFD, 8) == 0 else {
            throw RPCTransportError.socket("listen failed")
        }
    }

    public func acceptClient() throws -> UnixDomainConnection {
        var addr = sockaddr_un()
        var len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let fd = withUnsafeMutablePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                accept(listenFD, sockPtr, &len)
            }
        }
        guard fd >= 0 else {
            throw RPCTransportError.socket("accept failed")
        }
        let peer = try Self.peerIdentity(fd: fd)
        return UnixDomainConnection(fd: fd, peer: peer)
    }

    public func stop() {
        if listenFD >= 0 {
            close(listenFD)
            listenFD = -1
        }
        try? FileManager.default.removeItem(atPath: socketPath)
    }

    deinit { stop() }

    public static func peerIdentity(fd: Int32) throws -> PeerIdentity {
        var uid: uid_t = 0
        var gid: gid_t = 0
        if getpeereid(fd, &uid, &gid) != 0 {
            throw RPCTransportError.socket("getpeereid failed")
        }
        // pid via LOCAL_PEERPID when available
        var pid: pid_t = 0
        var pidLen = socklen_t(MemoryLayout<pid_t>.size)
        _ = getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &pidLen)
        return PeerIdentity(uid: uid, pid: pid)
    }
}

public final class UnixDomainConnection: @unchecked Sendable {
    private let fd: Int32
    public let peer: PeerIdentity
    private var buffer = Data()

    public init(fd: Int32, peer: PeerIdentity) {
        self.fd = fd
        self.peer = peer
    }

    deinit { close(fd) }

    public func readRequest() throws -> Data {
        while true {
            if let frames = try? FrameCodec.decodeFrames(from: &buffer), let first = frames.first {
                // put remaining frames back is complex; decode one frame only
                return first
            }
            // re-decode properly
            let frames = try FrameCodec.decodeFrames(from: &buffer)
            if let first = frames.first {
                // If multiple, prepend rest — simplify: only expect one outstanding
                if frames.count > 1 {
                    for extra in frames.dropFirst() {
                        buffer.insert(contentsOf: FrameCodec.encode(extra), at: 0)
                    }
                }
                return first
            }
            var chunk = [UInt8](repeating: 0, count: 4096)
            let n = read(fd, &chunk, chunk.count)
            if n == 0 { throw RPCTransportError.closed }
            if n < 0 { throw RPCTransportError.socket("read errno=\(errno)") }
            buffer.append(contentsOf: chunk.prefix(n))
        }
    }

    public func writeResponse(_ data: Data) throws {
        let frame = FrameCodec.encode(data)
        try frame.withUnsafeBytes { raw in
            var written = 0
            let total = raw.count
            while written < total {
                let n = Darwin.write(fd, raw.baseAddress!.advanced(by: written), total - written)
                if n <= 0 { throw RPCTransportError.socket("write errno=\(errno)") }
                written += n
            }
        }
    }
}

public final class UnixDomainClient: @unchecked Sendable {
    private var fd: Int32 = -1
    private var buffer = Data()
    public let socketPath: String

    public init(socketPath: String) {
        self.socketPath = socketPath
    }

    public func connect() throws {
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw RPCTransportError.socket("socket failed") }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { cptr in
                for (i, b) in pathBytes.enumerated() { cptr[i] = b }
            }
        }
        let rc = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard rc == 0 else { throw RPCTransportError.socket("connect errno=\(errno)") }
    }

    public func call(_ request: JSONRPCRequest) throws -> JSONRPCResponse {
        let payload = try RPCCodec.encoder.encode(request)
        let frame = FrameCodec.encode(payload)
        try frame.withUnsafeBytes { raw in
            var written = 0
            while written < raw.count {
                let n = Darwin.write(fd, raw.baseAddress!.advanced(by: written), raw.count - written)
                if n <= 0 { throw RPCTransportError.socket("write errno=\(errno)") }
                written += n
            }
        }
        // read one frame
        while true {
            let frames = try FrameCodec.decodeFrames(from: &buffer)
            if let first = frames.first {
                return try RPCCodec.decoder.decode(JSONRPCResponse.self, from: first)
            }
            var chunk = [UInt8](repeating: 0, count: 4096)
            let n = read(fd, &chunk, chunk.count)
            if n == 0 { throw RPCTransportError.closed }
            if n < 0 { throw RPCTransportError.socket("read errno=\(errno)") }
            buffer.append(contentsOf: chunk.prefix(n))
        }
    }

    public func close() {
        if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }
    }

    deinit { close() }
}
