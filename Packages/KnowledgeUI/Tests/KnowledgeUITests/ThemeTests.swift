import XCTest
@testable import KnowledgeUI

final class ThemeTests: XCTestCase {
    func testStatusCopyKorean() {
        XCTAssertEqual(StatusCopy.label("review_needed"), "확인 필요")
        XCTAssertEqual(StatusCopy.label("transcribe_failed"), "받아쓰기 실패")
        XCTAssertEqual(StatusCopy.badgeKind("transcribe_failed"), .danger)
        XCTAssertEqual(StatusCopy.badgeKind("review_needed"), .info)
    }
}
