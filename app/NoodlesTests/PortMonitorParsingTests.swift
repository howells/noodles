import XCTest
@testable import Noodles

final class PortMonitorParsingTests: XCTestCase {
    func testParseSinglePort() {
        let output = "p1234\ncnode\nn*:3000"
        let ports = PortMonitor.parseListeningPorts(from: output)
        XCTAssertEqual(ports.count, 1)
        XCTAssertEqual(ports[0].port, 3000)
        XCTAssertEqual(ports[0].pid, 1234)
        XCTAssertEqual(ports[0].processName, "node")
    }

    func testParseMultiplePorts() {
        let output = "p1234\ncnode\nn*:3000\nn*:3001\np5678\ncnode\nn*:5173"
        let ports = PortMonitor.parseListeningPorts(from: output)
        XCTAssertEqual(ports.count, 3)
        XCTAssertEqual(ports[0].port, 3000)
        XCTAssertEqual(ports[1].port, 3001)
        XCTAssertEqual(ports[2].port, 5173)
    }

    func testDeduplicatesSamePortSamePid() {
        let output = "p1234\ncnode\nn*:3000\nn*:3000"
        let ports = PortMonitor.parseListeningPorts(from: output)
        XCTAssertEqual(ports.count, 1)
    }

    func testParseIPv6Address() {
        let output = "p1234\ncnode\nn[::1]:3000"
        let ports = PortMonitor.parseListeningPorts(from: output)
        XCTAssertEqual(ports.count, 1)
        XCTAssertEqual(ports[0].port, 3000)
    }

    func testFiltersNonDevProcesses() {
        let output = "p1234\ncpostgres\nn*:5432"
        let ports = PortMonitor.parseListeningPorts(from: output)
        XCTAssertEqual(ports.count, 1)
        XCTAssertEqual(ports[0].processName, "postgres")
        // Filtering happens in scan(), not parseListeningPorts()
        // so the parser returns all ports regardless of process name
    }

    func testEmptyOutput() {
        let ports = PortMonitor.parseListeningPorts(from: "")
        XCTAssertTrue(ports.isEmpty)
    }
}
