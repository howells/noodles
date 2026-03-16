import XCTest
@testable import Noodles

final class LogReaderTests: XCTestCase {
    func testStripAnsiCodes() {
        let input = "\u{1B}[32mSuccess\u{1B}[0m: built in 1.2s"
        let result = LogReader.stripAnsi(input)
        XCTAssertEqual(result, "Success: built in 1.2s")
    }

    func testStripAnsiPreservesPlainText() {
        let input = "No ANSI codes here"
        let result = LogReader.stripAnsi(input)
        XCTAssertEqual(result, input)
    }

    func testStripAnsiMultipleCodes() {
        let input = "\u{1B}[1m\u{1B}[31mError\u{1B}[0m: something failed"
        let result = LogReader.stripAnsi(input)
        XCTAssertEqual(result, "Error: something failed")
    }

    func testTailFileNonExistent() {
        let lines = LogReader.tailFile(at: "/nonexistent/path/file.log")
        XCTAssertTrue(lines.isEmpty)
    }

    func testTailFileWithContent() throws {
        let tmpDir = FileManager.default.temporaryDirectory
        let tmpFile = tmpDir.appendingPathComponent("noodles-test-\(UUID().uuidString).log")
        let content = (1...2000).map { "Line \($0)" }.joined(separator: "\n")
        try content.write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let lines = LogReader.tailFile(at: tmpFile.path, lines: 1000)
        XCTAssertEqual(lines.count, 1000)
        XCTAssertEqual(lines.last, "Line 2000")
        XCTAssertEqual(lines.first, "Line 1001")
    }

    func testTailFileSmallFile() throws {
        let tmpDir = FileManager.default.temporaryDirectory
        let tmpFile = tmpDir.appendingPathComponent("noodles-test-\(UUID().uuidString).log")
        let content = "Line 1\nLine 2\nLine 3"
        try content.write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let lines = LogReader.tailFile(at: tmpFile.path, lines: 1000)
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines, ["Line 1", "Line 2", "Line 3"])
    }
}
