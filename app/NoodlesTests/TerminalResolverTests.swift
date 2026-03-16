import XCTest
@testable import Noodles

final class TerminalResolverTests: XCTestCase {
    func testResolveInvalidPid() {
        XCTAssertNil(TerminalResolver.resolve(pid: 0))
        XCTAssertNil(TerminalResolver.resolve(pid: -1))
    }

    func testResolveNonExistentPid() {
        // PID 99999 is unlikely to exist
        XCTAssertNil(TerminalResolver.resolve(pid: 99999))
    }
}
