import Foundation
import KnowledgeIndex

/// Accept-loop for the pipeline daemon over UDS JSON-RPC.
public final class DaemonRuntime: @unchecked Sendable {
    private let service: PipelineService
    private let server: UnixDomainServer
    private let policy: PeerPolicy
    private var stopFlag = false

    public init(store: KnowledgeStore, socketPath: String, policy: PeerPolicy = PeerPolicy()) {
        self.policy = policy
        self.service = PipelineService(store: store, policy: policy)
        self.server = UnixDomainServer(socketPath: socketPath)
    }

    public var socketPath: String { server.socketPath }

    public func startListening() throws {
        try server.start()
    }

    /// Blocking accept loop. Call `requestStop()` from another thread to exit after next accept interruption.
    public func runAcceptLoop() throws {
        while !stopFlag {
            let conn: UnixDomainConnection
            do {
                conn = try server.acceptClient()
            } catch {
                if stopFlag { break }
                throw error
            }
            // Handle one request per connection for simplicity (MVP)
            do {
                let payload = try conn.readFrame()
                let request = try RPCCodec.decodeRequest(payload)
                let response = service.handle(request: request, peer: conn.peer)
                let data = try RPCCodec.encodeResponse(response)
                try conn.writeFrame(data)
            } catch RPCTransportError.closed {
                continue
            } catch {
                // best-effort error response if we can
                continue
            }
        }
        server.stop()
    }

    public func requestStop() {
        stopFlag = true
        server.stop()
    }

    /// Serve a single connection payload (tests).
    public func handleOnce(request: JSONRPCRequest, peer: PeerIdentity = PeerIdentity(uid: getuid(), pid: getpid())) -> JSONRPCResponse {
        service.handle(request: request, peer: peer)
    }
}
