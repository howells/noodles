import Foundation
import AppKit

actor ProcessManager {

    func getListeningPorts() async -> [PortInfo] {
        let output = runCommand("/usr/sbin/lsof", arguments: ["-i", "-P", "-n"])
        var ports: [PortInfo] = []
        var seenPorts = Set<Int>()
        var nodePids = Set<Int>()

        let lines = output.components(separatedBy: "\n")
        let listenLines = lines.filter { $0.contains("LISTEN") }

        // First pass: collect all ports and node PIDs
        for line in listenLines {
            let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 9 else { continue }

            let processName = parts[0]
            guard let pid = Int(parts[1]) else { continue }

            let name = parts[8]
            guard let colonIndex = name.lastIndex(of: ":") else { continue }
            var portStr = String(name[name.index(after: colonIndex)...])
            portStr = portStr.replacingOccurrences(of: "(LISTEN)", with: "")
            guard let port = Int(portStr) else { continue }

            guard !seenPorts.contains(port) else { continue }
            seenPorts.insert(port)

            // Only track node/bun processes for cwd lookup
            if processName == "node" || processName == "bun" {
                nodePids.insert(pid)
            }

            ports.append(PortInfo(port: port, pid: pid, processName: processName, cwd: nil))
        }

        // Batch lookup cwds for node processes only
        var pidToCwd: [Int: String] = [:]
        for pid in nodePids {
            if let cwd = getProcessCwdFast(pid: pid) {
                pidToCwd[pid] = cwd
            }
        }

        // Update ports with cwds
        ports = ports.map { port in
            var p = port
            p.cwd = pidToCwd[port.pid]
            return p
        }

        return ports.sorted { $0.port < $1.port }
    }

    private func getProcessCwdFast(pid: Int) -> String? {
        // Use procfs-style approach on macOS
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "lsof -p \(pid) 2>/dev/null | grep cwd | awk '{print $NF}'"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                return path
            }
        } catch {}

        return nil
    }

    func startDevServer(path: String, packageManager: PackageManager, customPort: Int? = nil) async throws {
        let expandedPath = (path as NSString).expandingTildeInPath

        var args = [packageManager.command] + packageManager.devArgs

        // Inject custom port if specified
        if let port = customPort {
            args.append("--port")
            args.append(String(port))
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: expandedPath)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
    }

    func stopProcess(pid: Int, force: Bool = false) async throws {
        let signal = force ? "KILL" : "TERM"
        _ = runCommand("/bin/kill", arguments: ["-\(signal)", String(pid)])
    }

    func stopProjectProcesses(projectPath: String) async throws {
        let ports = await getListeningPorts()
        for port in ports {
            if let cwd = port.cwd, cwd.hasPrefix(projectPath) {
                try await stopProcess(pid: port.pid)
            }
        }
    }

    nonisolated func openInBrowser(port: Int) {
        let url = URL(string: "http://localhost:\(port)")!
        NSWorkspace.shared.open(url)
    }

    nonisolated func openInEditor(path: String, editor: String) {
        let expandedPath = (path as NSString).expandingTildeInPath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [editor, expandedPath]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    private func runCommand(_ command: String, arguments: [String]) -> String {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}
