import Foundation
import AppKit

actor ProcessManager {
    private var spawnedProcesses: [Int32] = []

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
        // Use lsof directly with arguments (no shell interpolation)
        let output = runCommand("/usr/sbin/lsof", arguments: ["-p", String(pid)])
        let lines = output.components(separatedBy: "\n")

        for line in lines {
            if line.contains("cwd") {
                let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if let last = parts.last {
                    return last
                }
            }
        }

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

        // Track spawned process for cleanup
        spawnedProcesses.append(process.processIdentifier)
    }

    func cleanupSpawnedProcesses() async {
        for pid in spawnedProcesses {
            kill(pid, SIGTERM)
        }
        spawnedProcesses.removeAll()
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
        guard let url = URL(string: "http://localhost:\(port)") else { return }
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

    nonisolated func openInTerminal(path: String, terminal: String, command: String? = nil) {
        let expandedPath = (path as NSString).expandingTildeInPath
        let fullCommand = command.map { "cd '\(expandedPath)' && \($0)" } ?? "cd '\(expandedPath)'"

        NSLog("Noodles: Opening terminal '\(terminal)' with command: \(fullCommand)")

        switch terminal {
        case "iTerm2":
            let script = """
            tell application "iTerm"
                activate
                if (count of windows) = 0 then
                    create window with default profile
                else
                    tell current window
                        create tab with default profile
                    end tell
                end if
                delay 0.2
                tell current session of current window
                    write text "\(fullCommand)"
                end tell
            end tell
            """
            runAppleScript(script)

        case "Warp":
            // Warp supports AppleScript
            let script = """
            tell application "Warp"
                activate
                delay 0.3
                tell application "System Events"
                    keystroke "t" using command down
                    delay 0.2
                    keystroke "\(fullCommand)"
                    keystroke return
                end tell
            end tell
            """
            runAppleScript(script)

        case "Kitty":
            // Kitty: launch with command
            let shellCmd = command.map { "\($0); exec $SHELL" } ?? "exec $SHELL"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/Applications/kitty.app/Contents/MacOS/kitty")
            process.arguments = ["--single-instance", "--directory", expandedPath, "sh", "-c", shellCmd]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()

        case "Ghostty":
            // Ghostty: use -e for command execution
            let shellCmd = command ?? "$SHELL"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/Applications/Ghostty.app/Contents/MacOS/ghostty")
            process.arguments = ["--working-directory=\(expandedPath)", "-e", "sh", "-c", "cd '\(expandedPath)' && \(shellCmd); exec $SHELL"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()

        case "Alacritty":
            // Alacritty: use -e for command
            let shellCmd = command.map { "\($0); exec $SHELL" } ?? "exec $SHELL"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/Applications/Alacritty.app/Contents/MacOS/alacritty")
            process.arguments = ["--working-directory", expandedPath, "-e", "sh", "-c", shellCmd]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()

        default: // Terminal.app
            let script = """
            tell application "Terminal"
                activate
                do script "\(fullCommand)"
            end tell
            """
            runAppleScript(script)
        }
    }

    private nonisolated func runAppleScript(_ script: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    nonisolated static func detectInstalledTerminals() -> [(id: String, name: String)] {
        let allTerminals = [
            ("Terminal", "Terminal", "/System/Applications/Utilities/Terminal.app"),
            ("iTerm2", "iTerm2", "/Applications/iTerm.app"),
            ("Warp", "Warp", "/Applications/Warp.app"),
            ("Kitty", "Kitty", "/Applications/kitty.app"),
            ("Ghostty", "Ghostty", "/Applications/Ghostty.app"),
            ("Alacritty", "Alacritty", "/Applications/Alacritty.app"),
        ]

        return allTerminals.compactMap { (id, name, path) in
            if FileManager.default.fileExists(atPath: path) {
                return (id: id, name: name)
            }
            return nil
        }
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
