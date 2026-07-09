import XCTest
@testable import KnowledgeUI

final class DaemonSupervisorTests: XCTestCase {
    func testResolveFindsBuildProductWhenPresent() {
        // May be nil in pure CI without build artifacts — only assert type safety / no crash
        let url = DaemonSupervisor.resolveDaemonBinary()
        if let url {
            XCTAssertTrue(url.lastPathComponent.contains("knowledged") || url.path.contains("knowledged"))
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        }
    }
}
