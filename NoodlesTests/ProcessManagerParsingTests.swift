import XCTest
@testable import Noodles

final class ProcessManagerParsingTests: XCTestCase {
    func testParseLsofFieldsToPorts() {
        let sample = """
        p1234
        cnode
        n*:3000
        n127.0.0.1:3000
        p2222
        cpython
        n*:8000
        """

        let ports = ProcessManager.parseListeningPorts(from: sample)

        XCTAssertEqual(ports.count, 2)
        XCTAssertTrue(ports.contains { $0.pid == 1234 && $0.port == 3000 && $0.processName == "node" })
        XCTAssertTrue(ports.contains { $0.pid == 2222 && $0.port == 8000 && $0.processName == "python" })
    }

    func testPortInfoIdIsUniquePerPidPort() {
        let p1 = PortInfo(port: 3000, pid: 1234, processName: "node", cwd: nil)
        let p2 = PortInfo(port: 3000, pid: 5678, processName: "node", cwd: nil)
        XCTAssertNotEqual(p1.id, p2.id)
    }

    func testLogBufferKeepsTail() {
        var buffer = LogBuffer(maxLines: 3)
        buffer.append("a")
        buffer.append("b")
        buffer.append("c")
        buffer.append("d")
        XCTAssertEqual(buffer.lines, ["b", "c", "d"])
    }

    func testLogFormatterStripsCarriageReturns() {
        XCTAssertEqual(LogFormatter.format("line\r"), "line")
    }
}
