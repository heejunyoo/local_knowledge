import XCTest
import KnowledgeCore
import KnowledgeIndex
@testable import KnowledgeRPC

final class RPCTests: XCTestCase {
    func testFrameCodecRoundTrip() throws {
        let payload = Data("{\"a\":1}".utf8)
        var buf = FrameCodec.encode(payload)
        buf.append(FrameCodec.encode(Data("x".utf8)))
        let frames = try FrameCodec.decodeFrames(from: &buf)
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames[0], payload)
        XCTAssertEqual(String(data: frames[1], encoding: .utf8), "x")
        XCTAssertTrue(buf.isEmpty)
    }

    func testPeerPolicySameUID() {
        let policy = PeerPolicy(allowedUIDs: [getuid()], requireSameUID: true)
        XCTAssertTrue(policy.authorize(PeerIdentity(uid: getuid(), pid: 1)))
        XCTAssertFalse(policy.authorize(PeerIdentity(uid: getuid() &+ 1, pid: 1)))
    }

    func testServicePingAndCreateTransition() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rpc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = try KnowledgeStore(path: dir.appendingPathComponent("k.db").path)
        let root = dir
        let svc = PipelineService(
            store: store,
            knowledgeRoot: root,
            vaultPath: dir.appendingPathComponent("vault")
        )
        let peer = PeerIdentity(uid: getuid(), pid: getpid())

        let ping = svc.handle(
            request: JSONRPCRequest(method: "ping"),
            peer: peer
        )
        XCTAssertNil(ping.error)
        XCTAssertEqual(ping.result?["pong"], .bool(true))

        let create = svc.handle(
            request: JSONRPCRequest(
                method: "meeting.create",
                params: .object([
                    "id": .string("meet-1"),
                    "title": .string("테스트"),
                ])
            ),
            peer: peer
        )
        XCTAssertNil(create.error, "\(String(describing: create.error))")
        XCTAssertEqual(create.result?["status"], .string("recording"))

        let stop = svc.handle(
            request: JSONRPCRequest(
                method: "meeting.transition",
                params: .object([
                    "id": .string("meet-1"),
                    "to": .string("recorded"),
                    "audio_path": .string("audio/raw/meet-1.m4a"),
                    "audio_sha256": .string("deadbeef"),
                    "audio_duration_ms": .number(1500),
                ])
            ),
            peer: peer
        )
        XCTAssertNil(stop.error, "\(String(describing: stop.error))")
        XCTAssertEqual(stop.result?["status"], .string("recorded"))

        let health = svc.handle(request: JSONRPCRequest(method: "health"), peer: peer)
        XCTAssertEqual(health.result?["ok"], .bool(true))
        XCTAssertEqual(health.result?["recording_count"], .number(0))
    }

    func testUnauthorizedPeer() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rpc-unauth-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = try KnowledgeStore(path: dir.appendingPathComponent("k.db").path)
        let svc = PipelineService(
            store: store,
            knowledgeRoot: dir,
            vaultPath: dir.appendingPathComponent("vault"),
            policy: PeerPolicy(allowedUIDs: [getuid()])
        )
        let bad = PeerIdentity(uid: getuid() &+ 99, pid: 1)
        let res = svc.handle(request: JSONRPCRequest(method: "ping"), peer: bad)
        XCTAssertEqual(res.error?.code, -32001)
    }

    func testUDSEndToEnd() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rpc-uds-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let sock = dir.appendingPathComponent("e2e.sock").path
        let store = try KnowledgeStore(path: dir.appendingPathComponent("k.db").path)

        let server = UnixDomainServer(socketPath: sock)
        try server.start()
        defer { server.stop() }

        let acceptExp = expectation(description: "accept")
        DispatchQueue.global().async {
            do {
                let conn = try server.acceptClient()
                let frame = try conn.readFrame()
                let req = try RPCCodec.decodeRequest(frame)
                let svc = PipelineService(
                    store: store,
                    knowledgeRoot: dir,
                    vaultPath: dir.appendingPathComponent("vault")
                )
                let res = svc.handle(request: req, peer: conn.peer)
                try conn.writeFrame(try RPCCodec.encodeResponse(res))
            } catch {
                XCTFail("server side: \(error)")
            }
            acceptExp.fulfill()
        }

        Thread.sleep(forTimeInterval: 0.05)
        let client = UnixDomainClient(socketPath: sock)
        try client.connect()
        let response = try client.call(JSONRPCRequest(method: "ping"))
        XCTAssertNil(response.error)
        XCTAssertEqual(response.result?["pong"], .bool(true))
        client.close()
        wait(for: [acceptExp], timeout: 2)
    }
}
