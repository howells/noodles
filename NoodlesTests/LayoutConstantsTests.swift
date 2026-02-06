import XCTest
@testable import Noodles

final class LayoutConstantsTests: XCTestCase {
    func testStatusDotContainerSize() {
        XCTAssertEqual(StatusDot.containerSize, 24)
    }
}
