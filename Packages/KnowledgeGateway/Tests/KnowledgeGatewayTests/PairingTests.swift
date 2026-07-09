import XCTest
@testable import KnowledgeGateway

final class PairingTests: XCTestCase {
    func testPairRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pair-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = PairingStore(knowledgeRoot: dir)
        let start = try store.startPairing(ttlSeconds: 60)
        XCTAssertEqual(start.code.count, 6)
        let done = try store.completePairing(code: start.code, deviceName: "TestPhone")
        XCTAssertFalse(done.token.isEmpty)
        let dev = store.authorize(bearer: "Bearer \(done.token)")
        XCTAssertEqual(dev?.id, done.deviceId)
        XCTAssertNil(store.authorize(bearer: "Bearer bad"))
    }
}
