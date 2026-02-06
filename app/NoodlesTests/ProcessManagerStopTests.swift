import XCTest
@testable import Noodles

final class ProcessManagerStopTests: XCTestCase {
    func testStopManagedServerKillsProcessIgnoringTerm() async throws {
        let manager = ProcessManager()
        let id = try await manager.startManagedCommand(
            executable: "/bin/sh",
            arguments: ["-c", "trap '' TERM; while true; do sleep 1; done"],
            path: "/tmp",
            label: "test-stop"
        )

        try await Task.sleep(nanoseconds: 200_000_000)
        await manager.stopManagedServer(id: id)

        let servers = await manager.getManagedServers()
        guard let info = servers.first(where: { $0.id == id }) else {
            XCTFail("Managed server missing")
            return
        }

        XCTAssertFalse(info.isRunning)
        XCTAssertNotNil(info.exitCode)
    }
}
