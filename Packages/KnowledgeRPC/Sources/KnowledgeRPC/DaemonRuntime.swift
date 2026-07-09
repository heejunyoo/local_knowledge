import Foundation
import KnowledgeIndex

/// Accept-loop for the pipeline daemon over UDS JSON-RPC.
public final class DaemonRuntime: @unchecked Sendable {
    private let service: PipelineService
    private let server: UnixDomainServer
    private let policy: PeerPolicy
    private var stopFlag = false

    public init(
        store: KnowledgeStore,
        knowledgeRoot: URL,
        socketPath: String,
        vaultPath: URL? = nil,
        policy: PeerPolicy = PeerPolicy()
    ) {
        self.policy = policy
        let vault = vaultPath ?? PipelineService.resolveVaultPath(knowledgeRoot: knowledgeRoot)
        self.service = PipelineService(
            store: store,
            knowledgeRoot: knowledgeRoot,
            vaultPath: vault,
            policy: policy
        )
        self.server = UnixDomainServer(socketPath: socketPath)
    }

    public var socketPath: String { server.socketPath }

    public func startListening() throws {
        try server.start()
    }

    public func runAcceptLoop() throws {
        while !stopFlag {
            let conn: UnixDomainConnection
            do {
                conn = try server.acceptClient()
            } catch {
                if stopFlag { break }
                throw error
            }
            do {
                let payload = try conn.readFrame()
                let request = try RPCCodec.decodeRequest(payload)
                let response = service.handle(request: request, peer: conn.peer)
                let data = try RPCCodec.encodeResponse(response)
                try conn.writeFrame(data)
            } catch RPCTransportError.closed {
                continue
            } catch {
                continue
            }
        }
        server.stop()
    }

    public func requestStop() {
        stopFlag = true
        server.stop()
    }

    public func handleOnce(
        request: JSONRPCRequest,
        peer: PeerIdentity = PeerIdentity(uid: getuid(), pid: getpid())
    ) -> JSONRPCResponse {
        service.handle(request: request, peer: peer)
    }
}
