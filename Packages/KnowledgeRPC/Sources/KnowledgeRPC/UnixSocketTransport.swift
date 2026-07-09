import Foundation
import Darwin

/// Length-prefixed (UInt32 big-endian) JSON frames over a stream FD.
public enum FrameCodec {
    public static func encode(_ payload: Data) -> Data {
        var be = UInt32(payload.count).bigEndian
        var out = Data(bytes: &be, count: 4)
        out.append(payload)
        return out
    }

    /// Extract complete frames from `buffer`, removing them. Incomplete tail remains.
    public static func decodeFrames(from buffer: inout Data) throws -> [Data] {
        var frames: [Data] = []
        while buffer.count >= 4 {
            let be = buffer.prefix(4).withUnsafeBytes { raw -> UInt32 in
                raw.load(as: UInt32.self)
            }
            let len = Int(UInt32(bigEndian: be))
            if len < 0 || len > 16 * 1024 * 1024 {
                throw RPCTransportError.frameTooLarge(len)
            }
            let total = 4 + len
            guard buffer.count >= total else { break }
            frames.append(buffer.subdata(in: 4..<total))
            buffer.removeSubrange(0..<total)
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

        listenFD = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else {
            throw RPCTransportError.socket("socket() failed")
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8CString)
        guard pathBytes.count <= 104 else {
            throw RPCTransportError.socket("path too long")
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            for i in 0..<pathBytes.count {
                buf[i] = UInt8(bitPattern: pathBytes[i])
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(listenFD, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            throw RPCTransportError.socket("bind failed errno=\(errno)")
        }

        chmod(socketPath, S_IRUSR | S_IWUSR)

        guard Darwin.listen(listenFD, 8) == 0 else {
            throw RPCTransportError.socket("listen failed")
        }
    }

    public func acceptClient() throws -> UnixDomainConnection {
        var addr = sockaddr_un()
        var len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let fd = withUnsafeMutablePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.accept(listenFD, sockPtr, &len)
            }
        }
        guard fd >= 0 else {
            throw RPCTransportError.socket("accept failed")
        }
        return UnixDomainConnection(fd: fd, peer: try Self.peerIdentity(fd: fd))
    }

    public func stop() {
        if listenFD >= 0 {
            Darwin.close(listenFD)
            listenFD = -1
        }
        if FileManager.default.fileExists(atPath: socketPath) {
            try? FileManager.default.removeItem(atPath: socketPath)
        }
    }

    deinit { stop() }

    public static func peerIdentity(fd: Int32) throws -> PeerIdentity {
        var uid: uid_t = 0
        var gid: gid_t = 0
        if getpeereid(fd, &uid, &gid) != 0 {
            throw RPCTransportError.socket("getpeereid failed")
        }
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

    deinit { Darwin.close(fd) }

    public func readFrame() throws -> Data {
        while true {
            let frames = try FrameCodec.decodeFrames(from: &buffer)
            if let first = frames.first {
                // Only one frame expected per call; re-queue extras
                for extra in frames.dropFirst().reversed() {
                    buffer.insert(contentsOf: FrameCodec.encode(extra), at: 0)
                }
                return first
            }
            var chunk = [UInt8](repeating: 0, count: 8192)
            let n = Darwin.read(fd, &chunk, chunk.count)
            if n == 0 { throw RPCTransportError.closed }
            if n < 0 { throw RPCTransportError.socket("read errno=\(errno)") }
            buffer.append(contentsOf: chunk.prefix(n))
        }
    }

    public func writeFrame(_ data: Data) throws {
        let frame = FrameCodec.encode(data)
        try writeAll(frame)
    }

    private func writeAll(_ data: Data) throws {
        try data.withUnsafeBytes { raw in
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
        fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw RPCTransportError.socket("socket failed") }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8CString)
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            for i in 0..<pathBytes.count {
                buf[i] = UInt8(bitPattern: pathBytes[i])
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
        try writeAll(FrameCodec.encode(payload))
        while true {
            let frames = try FrameCodec.decodeFrames(from: &buffer)
            if let first = frames.first {
                return try RPCCodec.decoder.decode(JSONRPCResponse.self, from: first)
            }
            var chunk = [UInt8](repeating: 0, count: 8192)
            let n = Darwin.read(fd, &chunk, chunk.count)
            if n == 0 { throw RPCTransportError.closed }
            if n < 0 { throw RPCTransportError.socket("read errno=\(errno)") }
            buffer.append(contentsOf: chunk.prefix(n))
        }
    }

    private func writeAll(_ data: Data) throws {
        try data.withUnsafeBytes { raw in
            var written = 0
            while written < raw.count {
                let n = Darwin.write(fd, raw.baseAddress!.advanced(by: written), raw.count - written)
                if n <= 0 { throw RPCTransportError.socket("write errno=\(errno)") }
                written += n
            }
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
