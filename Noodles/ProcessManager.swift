import Foundation
import AppKit
import Darwin

// Simple actor to accumulate data from readabilityHandler callbacks.
// Used by runCommandAsync to avoid pipe buffer deadlocks.
private actor DataAccumulator {
    private var data = Data()
    func append(_ chunk: Data) { data.append(chunk) }
    func getData() -> Data { data }
}

actor ProcessManager {
    private struct ManagedServer {
        let id: UUID
        let label: String
        let path: String
        let command: String
        let port: Int?
        let process: Process
        let stdout: Pipe
        let stderr: Pipe
        var logBuffer: LogBuffer
        var partialLine: String
        let startedAt: Date
        var exitCode: Int32?
        var stopRequestedAt: Date?
        var processGroupId: Int32?
    }

    private var cwdCache: [Int: (path: String, timestamp: Date)] = [:]
    private let cwdCacheTtl: TimeInterval = 10
    private let logBufferMaxLines = 1000
    private var managedServers: [UUID: ManagedServer] = [:]

    // Cleanup registry — tracks live managed process PIDs and their process group IDs.
    // nonisolated(unsafe) because it's written from within the actor (serialized) and
    // only read externally in applicationWillTerminate after the run loop has stopped,
    // so no concurrent access is possible.
    nonisolated(unsafe) private var cleanupRegistry: [(pid: Int32, groupId: Int32?)] = []

    // MARK: - Port Detection

    func getListeningPorts() async -> [PortInfo] {
        let output = await runCommandAsync("/usr/sbin/lsof", arguments: ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn"])
        var ports = Self.parseListeningPorts(from: output)

        let uniquePids = Array(Set(ports.map { $0.pid }))
        let pidToCwd = await batchGetProcessCwds(pids: uniquePids)

        ports = ports.map { port in
            var p = port
            p.cwd = pidToCwd[port.pid]
            return p
        }

        return ports.sorted { $0.port < $1.port }
    }

    nonisolated static func parseListeningPorts(from output: String) -> [PortInfo] {
        var ports: [PortInfo] = []
        var seen = Set<String>()
        var currentPid: Int?
        var currentCommand: String?

        for rawLine in output.split(whereSeparator: \.isNewline) {
            guard let prefix = rawLine.first else { continue }
            let value = rawLine.dropFirst()

            switch prefix {
            case "p":
                currentPid = Int(value)
            case "c":
                currentCommand = String(value)
            case "n":
                guard let pid = currentPid,
                      let processName = currentCommand else { continue }

                let name = String(value)
                guard let colonIndex = name.lastIndex(of: ":") else { continue }
                let portPart = name[name.index(after: colonIndex)...]
                let digits = portPart.prefix { $0.isNumber }
                guard let port = Int(digits) else { continue }

                let key = "\(pid):\(port)"
                guard !seen.contains(key) else { continue }
                seen.insert(key)

                ports.append(PortInfo(port: port, pid: pid, processName: processName, cwd: nil))
            default:
                continue
            }
        }

        return ports
    }

    // MARK: - CWD Resolution (Batched)

    /// Resolve CWDs for multiple PIDs in a single lsof call instead of one per PID.
    private func batchGetProcessCwds(pids: [Int]) async -> [Int: String] {
        guard !pids.isEmpty else { return [:] }

        var needed: [Int] = []
        var result: [Int: String] = [:]
        for pid in pids {
            if let cached = cachedCwd(pid: pid) {
                result[pid] = cached
            } else {
                needed.append(pid)
            }
        }

        guard !needed.isEmpty else { return result }

        // Single lsof call for ALL PIDs at once
        let pidArgs = needed.map(String.init).joined(separator: ",")
        let output = await runCommandAsync("/usr/sbin/lsof", arguments: ["-a", "-p", pidArgs, "-d", "cwd", "-Fn"])

        var currentPid: Int?
        for rawLine in output.split(whereSeparator: \.isNewline) {
            guard let prefix = rawLine.first else { continue }
            let value = rawLine.dropFirst()
            switch prefix {
            case "p":
                currentPid = Int(value)
            case "n":
                if let pid = currentPid {
                    let cwd = String(value)
                    if !cwd.isEmpty {
                        result[pid] = cwd
                        cacheCwd(pid: pid, path: cwd)
                    }
                }
            default:
                continue
            }
        }

        return result
    }

    private func cachedCwd(pid: Int) -> String? {
        guard let entry = cwdCache[pid] else { return nil }
        if Date().timeIntervalSince(entry.timestamp) < cwdCacheTtl {
            return entry.path
        }
        cwdCache.removeValue(forKey: pid)
        return nil
    }

    private func cacheCwd(pid: Int, path: String) {
        cwdCache[pid] = (path: path, timestamp: Date())
    }

    // MARK: - Managed Server Lifecycle

    func startManagedServer(path: String, packageManager: PackageManager, customPort: Int? = nil, filterWorkspace: String? = nil, label: String) throws -> UUID {
        var args: [String]
        if let filter = filterWorkspace {
            args = [packageManager.command] + packageManager.workspaceDevArgs(filter: filter)
        } else {
            args = [packageManager.command] + packageManager.devArgs
        }
        if let port = customPort {
            args.append("--port")
            args.append(String(port))
        }

        let shellCommand = args.joined(separator: " ")

        // GUI apps don't inherit the user's shell PATH (homebrew, fnm, pnpm, etc.),
        // so /usr/bin/env can't find CLI tools. Run through a login shell instead,
        // which loads the user's PATH from their shell config.
        let userShell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

        return try startManagedCommand(
            executable: userShell,
            arguments: ["-l", "-c", shellCommand],
            path: path,
            label: label,
            commandDescription: shellCommand,
            port: customPort
        )
    }

    func startManagedCommand(
        executable: String,
        arguments: [String],
        path: String,
        label: String,
        commandDescription: String? = nil,
        port: Int? = nil
    ) throws -> UUID {
        let expandedPath = (path as NSString).expandingTildeInPath

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: expandedPath)
        process.standardInput = FileHandle.nullDevice

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let id = UUID()
        let server = ManagedServer(
            id: id,
            label: label,
            path: expandedPath,
            command: commandDescription ?? ([executable] + arguments).joined(separator: " "),
            port: port,
            process: process,
            stdout: stdout,
            stderr: stderr,
            logBuffer: LogBuffer(maxLines: logBufferMaxLines),
            partialLine: "",
            startedAt: Date(),
            exitCode: nil,
            stopRequestedAt: nil,
            processGroupId: nil
        )

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { await self?.appendOutput(id: id, text: text) }
        }

        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { await self?.appendOutput(id: id, text: text) }
        }

        process.terminationHandler = { [weak self] proc in
            Task { await self?.handleManagedServerTermination(id: id, exitCode: proc.terminationStatus) }
        }

        managedServers[id] = server

        do {
            try process.run()
        } catch {
            managedServers.removeValue(forKey: id)
            throw error
        }

        let pid = process.processIdentifier
        var groupId: Int32? = nil
        if pid > 0 {
            if setpgid(pid, pid) == 0 {
                groupId = pid
                updateManagedServer(id: id) { server in
                    server.processGroupId = pid
                }
            }
        }

        // Register for synchronous cleanup on app quit
        registerForCleanup(pid: pid, groupId: groupId)

        return id
    }

    func stopManagedServer(id: UUID, force: Bool = false) async {
        guard let server = managedServers[id] else { return }
        let pid = server.process.processIdentifier
        guard pid > 0 else { return }

        if server.stopRequestedAt == nil {
            updateManagedServer(id: id) { server in
                server.stopRequestedAt = Date()
            }
        }

        let groupId = server.processGroupId
        let termSignal = force ? SIGKILL : SIGTERM

        // Use killTree for thorough cleanup — signals group first, then walks the tree
        killTree(pid: pid, groupId: groupId, signal: termSignal)

        if force {
            return
        }

        let exited = await waitForProcessExit(pid: pid, timeout: 2.0)
        if exited {
            return
        }

        // Escalate to SIGKILL
        killTree(pid: pid, groupId: groupId, signal: SIGKILL)
        _ = await waitForProcessExit(pid: pid, timeout: 2.0)
    }

    /// Remove a terminated managed server's resources.
    /// Called when a new server replaces the old one for the same project.
    func removeManagedServer(id: UUID) {
        guard let server = managedServers[id] else { return }
        try? server.stdout.fileHandleForWriting.close()
        try? server.stderr.fileHandleForWriting.close()
        managedServers.removeValue(forKey: id)
        unregisterFromCleanup(pid: server.process.processIdentifier)
    }

    // MARK: - Managed Server Queries

    func getManagedServers() -> [ManagedServerInfo] {
        managedServers.values.map { server in
            ManagedServerInfo(
                id: server.id,
                label: server.label,
                path: server.path,
                command: server.command,
                pid: server.process.processIdentifier == 0 ? nil : server.process.processIdentifier,
                port: server.port,
                isRunning: server.process.isRunning,
                exitCode: server.exitCode,
                stopRequestedAt: server.stopRequestedAt,
                startedAt: server.startedAt
            )
        }
        .sorted { $0.startedAt < $1.startedAt }
    }

    func getLogSnapshot(id: UUID, tail: Int) -> [String] {
        guard let server = managedServers[id], tail > 0 else { return [] }
        let lines = server.logBuffer.lines
        if lines.count <= tail {
            return lines
        }
        return Array(lines.suffix(tail))
    }

    // MARK: - Log Output

    private func appendOutput(id: UUID, text: String) {
        updateManagedServer(id: id) { server in
            let combined = server.partialLine + text
            var parts = combined.components(separatedBy: .newlines)
            let endsWithNewline = combined.hasSuffix("\n") || combined.hasSuffix("\r")

            if !endsWithNewline, let last = parts.last {
                server.partialLine = last
                parts.removeLast()
            } else {
                server.partialLine = ""
                if parts.last == "" {
                    parts.removeLast()
                }
            }

            for line in parts {
                server.logBuffer.append(line)
            }
        }
    }

    // MARK: - Termination Handling

    private func handleManagedServerTermination(id: UUID, exitCode: Int32) {
        if let server = managedServers[id] {
            unregisterFromCleanup(pid: server.process.processIdentifier)
        }

        updateManagedServer(id: id) { server in
            server.exitCode = exitCode
            server.stdout.fileHandleForReading.readabilityHandler = nil
            server.stderr.fileHandleForReading.readabilityHandler = nil
            try? server.stdout.fileHandleForReading.close()
            try? server.stderr.fileHandleForReading.close()
        }
    }

    private func updateManagedServer(id: UUID, _ update: (inout ManagedServer) -> Void) {
        guard var server = managedServers[id] else { return }
        update(&server)
        managedServers[id] = server
    }

    // MARK: - Process Killing

    /// Kill a process and its entire tree. Signals the process group first (if available),
    /// then walks the tree with pgrep as a fallback for any children that escaped the group.
    private func killTree(pid: Int32, groupId: Int32?, signal: Int32) {
        // Strategy: group signal first (catches most children), then tree walk for stragglers
        if let groupId = groupId, groupId > 0 {
            kill(-groupId, signal)
        }

        // Fallback: walk the process tree for any children that escaped the group
        Self.killChildrenRecursive(parentPid: pid, signal: signal)

        // Finally signal the parent itself (may be redundant if group signal hit it)
        kill(pid, signal)
    }

    /// Recursively kill all children of a process using pgrep.
    /// nonisolated because it's also called from cleanupAllSync during app termination.
    nonisolated private static func killChildrenRecursive(parentPid: Int32, signal: Int32) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-P", String(parentPid)]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return
        }
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        for line in output.split(whereSeparator: \.isNewline) {
            if let childPid = Int32(line) {
                killChildrenRecursive(parentPid: childPid, signal: signal)
                kill(childPid, signal)
            }
        }
    }

    private func waitForProcessExit(pid: Int32, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !Self.isProcessRunning(pid: pid) {
                return true
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return !Self.isProcessRunning(pid: pid)
    }

    nonisolated static func isProcessRunning(pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0
    }

    // MARK: - Cleanup Registry

    private func registerForCleanup(pid: Int32, groupId: Int32?) {
        cleanupRegistry.append((pid: pid, groupId: groupId))
    }

    private func unregisterFromCleanup(pid: Int32) {
        cleanupRegistry.removeAll { $0.pid == pid }
    }

    /// Synchronous cleanup called ONLY from applicationWillTerminate.
    /// Sends SIGTERM to all process groups/PIDs in parallel, waits up to 2 seconds,
    /// then SIGKILLs any survivors. Max ~2 seconds regardless of server count.
    nonisolated func cleanupAllSync() {
        let entries = cleanupRegistry
        guard !entries.isEmpty else { return }

        // Phase 1: SIGTERM all process groups and PIDs, plus tree-kill
        for entry in entries {
            if let groupId = entry.groupId, groupId > 0 {
                kill(-groupId, SIGTERM)
            }
            Self.killChildrenRecursive(parentPid: entry.pid, signal: SIGTERM)
            kill(entry.pid, SIGTERM)
        }

        // Phase 2: Shared wait (max 2 seconds total, not per-process)
        let deadline = Date().addingTimeInterval(2.0)
        var remaining = entries
        while !remaining.isEmpty && Date() < deadline {
            usleep(100_000) // 100ms
            remaining = remaining.filter { kill($0.pid, 0) == 0 }
        }

        // Phase 3: SIGKILL survivors
        for entry in remaining {
            if let groupId = entry.groupId, groupId > 0 {
                kill(-groupId, SIGKILL)
            }
            Self.killChildrenRecursive(parentPid: entry.pid, signal: SIGKILL)
            kill(entry.pid, SIGKILL)
        }
    }

    // MARK: - Stop by Project Path (for unmanaged terminal mode)

    func stopProcess(pid: Int, force: Bool = false) async throws {
        let signal = force ? "KILL" : "TERM"
        _ = await runCommandAsync("/bin/kill", arguments: ["-\(signal)", String(pid)])
    }

    func stopProjectProcesses(projectPath: String) async throws {
        let ports = await getListeningPorts()
        for port in ports {
            if let cwd = port.cwd, cwd.hasPrefix(projectPath) {
                try await stopProcess(pid: port.pid)
            }
        }
    }

    // MARK: - External App Integration

    nonisolated func openInBrowser(port: Int) {
        guard let url = URL(string: "http://localhost:\(port)") else { return }
        NSWorkspace.shared.open(url)
    }

    nonisolated func openInEditor(path: String, editor: String) {
        let expandedPath = (path as NSString).expandingTildeInPath

        // GUI apps don't inherit the shell's PATH, so /usr/bin/env can't find
        // CLIs in /usr/local/bin. Use a login shell to resolve the command.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "\(editor) '\(expandedPath)'"]
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
            let shellCmd = command.map { "\($0); exec $SHELL" } ?? "exec $SHELL"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/Applications/kitty.app/Contents/MacOS/kitty")
            process.arguments = ["--single-instance", "--directory", expandedPath, "sh", "-c", shellCmd]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()

        case "Ghostty":
            let shellCmd = command ?? "$SHELL"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/Applications/Ghostty.app/Contents/MacOS/ghostty")
            process.arguments = ["--working-directory=\(expandedPath)", "-e", "sh", "-c", "cd '\(expandedPath)' && \(shellCmd); exec $SHELL"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()

        case "Alacritty":
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

    // MARK: - Terminal/Editor Detection

    nonisolated static func detectInstalledTerminals() -> [(id: String, name: String, installed: Bool)] {
        let allTerminals = [
            ("Terminal", "Terminal", "/System/Applications/Utilities/Terminal.app"),
            ("iTerm2", "iTerm2", "/Applications/iTerm.app"),
            ("Warp", "Warp", "/Applications/Warp.app"),
            ("Kitty", "Kitty", "/Applications/kitty.app"),
            ("Ghostty", "Ghostty", "/Applications/Ghostty.app"),
            ("Alacritty", "Alacritty", "/Applications/Alacritty.app"),
        ]

        return allTerminals.map { (id, name, path) in
            (id: id, name: name, installed: FileManager.default.fileExists(atPath: path))
        }
    }

    nonisolated static func detectInstalledEditors() -> [(id: String, name: String, installed: Bool)] {
        let allEditors = [
            ("cursor", "Cursor", "/Applications/Cursor.app"),
            ("code", "VS Code", "/Applications/Visual Studio Code.app"),
            ("zed", "Zed", "/Applications/Zed.app"),
            ("subl", "Sublime Text", "/Applications/Sublime Text.app"),
            ("webstorm", "WebStorm", "/Applications/WebStorm.app"),
        ]

        var results = allEditors.map { (id, name, path) in
            (id: id, name: name, installed: FileManager.default.fileExists(atPath: path))
        }

        // Claude Code is a CLI, not an .app — check if the binary is in PATH
        let claudeInstalled = isCLIInstalled("claude")
        results.append((id: "claude-code", name: "Claude Code", installed: claudeInstalled))

        return results
    }

    private nonisolated static func isCLIInstalled(_ command: String) -> Bool {
        let process = Process()
        let userShell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        process.executableURL = URL(fileURLWithPath: userShell)
        process.arguments = ["-l", "-c", "which \(command)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    // MARK: - Async Command Runner

    /// Run a subprocess and return its stdout as a string, without blocking the actor.
    /// Uses readabilityHandler to drain the pipe incrementally, avoiding the pipe buffer
    /// deadlock that occurs when using readDataToEndOfFile() on large outputs.
    private func runCommandAsync(_ command: String, arguments: [String]) async -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return ""
        }

        // Stream data via readabilityHandler to avoid pipe buffer deadlock.
        let dataActor = DataAccumulator()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty {
                Task { await dataActor.append(chunk) }
            }
        }

        // Wait for process exit without blocking the actor
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in
                continuation.resume()
            }
        }

        // Process has exited — clean up handler and read any remaining buffered data
        pipe.fileHandleForReading.readabilityHandler = nil
        let remainingData = pipe.fileHandleForReading.readDataToEndOfFile()
        let accumulated = await dataActor.getData()
        var allData = accumulated
        allData.append(remainingData)

        return String(data: allData, encoding: .utf8) ?? ""
    }
}
