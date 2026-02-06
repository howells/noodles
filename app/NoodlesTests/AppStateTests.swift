import XCTest
@testable import Noodles

@MainActor
final class AppStateTests: XCTestCase {
    func testUnmatchedPortsExcludesProjectAndWorkspacePorts() {
        let state = AppState()

        var project = Project(
            id: "p1",
            name: "Project",
            path: "/tmp/p1",
            packageManager: .npm,
            devCommand: "dev",
            expectedPorts: [],
            customPort: nil
        )

        project.runningPorts = [
            PortInfo(port: 3000, pid: 1, processName: "node", cwd: "/tmp/p1")
        ]

        var workspace = Workspace(
            id: "w1",
            name: "Workspace",
            path: "/tmp/p1/apps/w1",
            relativePath: "apps/w1",
            devCommand: "dev",
            expectedPorts: []
        )
        workspace.runningPorts = [
            PortInfo(port: 4000, pid: 2, processName: "node", cwd: "/tmp/p1/apps/w1")
        ]
        project.workspaces = [workspace]

        state.projects = [project]
        state.ports = [
            PortInfo(port: 3000, pid: 1, processName: "node", cwd: "/tmp/p1"),
            PortInfo(port: 4000, pid: 2, processName: "node", cwd: "/tmp/p1/apps/w1"),
            PortInfo(port: 5000, pid: 3, processName: "node", cwd: "/tmp/p2"),
        ]

        XCTAssertEqual(state.unmatchedPorts.map { $0.port }, [5000])
    }
}
