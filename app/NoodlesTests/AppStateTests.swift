import XCTest
@testable import Noodles

@MainActor
final class AppStateTests: XCTestCase {
    func testInitialState() {
        let state = AppState()
        XCTAssertTrue(state.servers.isEmpty)
        XCTAssertNil(state.activeLogPath)
        XCTAssertTrue(state.isKilling.isEmpty)
        state.pollTimer?.invalidate()
    }
}
