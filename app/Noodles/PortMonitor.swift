import Foundation

private actor DataAccumulator {
    private var data = Data()
    func append(_ chunk: Data) { data.append(chunk) }
    func getData() -> Data { data }
}

struct PortMonitor {
    static let allowedProcesses: Set<String> = ["node", "bun", "deno", "next-server", "vite"]
    static let logDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cache/noodles/logs")

    static func scan() async -> [RunningServer] {
        let output = await runCommand("/usr/sbin/lsof", arguments: ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn"])
        var ports = parseListeningPorts(from: output)

        ports = ports.filter { allowedProcesses.contains($0.processName) && $0.port >= 3000 && $0.port <= 9999 }
        guard !ports.isEmpty else { return [] }

        let uniquePids = Array(Set(ports.map { $0.pid }))
        let pidToCwd = await batchGetProcessCwds(pids: uniquePids)

        ports = ports.map { port in
            var p = port
            p.cwd = pidToCwd[port.pid]
            return p
        }

        let grouped = Dictionary(grouping: ports) { $0.cwd ?? "unknown-\($0.pid)" }
        var servers: [RunningServer] = []

        for (cwd, portGroup) in grouped {
            let name = (cwd as NSString).lastPathComponent
            let displayPath = cwd.replacingOccurrences(of: NSHomeDirectory(), with: "~")
            let sortedPorts = portGroup.map(\.port).sorted()
            let pids = Array(Set(portGroup.map(\.pid)))
            let logFile = logDir.appendingPathComponent("\(name).log")
            let hasLogs = FileManager.default.fileExists(atPath: logFile.path)
            let terminalApp = TerminalResolver.resolve(pid: Int32(pids.first ?? 0))

            servers.append(RunningServer(
                id: cwd,
                ports: sortedPorts,
                pids: pids,
                name: name,
                path: cwd,
                displayPath: displayPath,
                hasLogs: hasLogs,
                terminalApp: terminalApp
            ))
        }

        return servers.sorted { ($0.ports.first ?? 0) < ($1.ports.first ?? 0) }
    }

    static func parseListeningPorts(from output: String) -> [PortInfo] {
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
                guard let pid = currentPid, let processName = currentCommand else { continue }
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

    static func batchGetProcessCwds(pids: [Int]) async -> [Int: String] {
        guard !pids.isEmpty else { return [:] }
        let pidArgs = pids.map(String.init).joined(separator: ",")
        let output = await runCommand("/usr/sbin/lsof", arguments: ["-a", "-p", pidArgs, "-d", "cwd", "-Fn"])

        var result: [Int: String] = [:]
        var currentPid: Int?
        for rawLine in output.split(whereSeparator: \.isNewline) {
            guard let prefix = rawLine.first else { continue }
            let value = rawLine.dropFirst()
            switch prefix {
            case "p": currentPid = Int(value)
            case "n":
                if let pid = currentPid {
                    let cwd = String(value)
                    if !cwd.isEmpty { result[pid] = cwd }
                }
            default: continue
            }
        }
        return result
    }

    static func runCommand(_ command: String, arguments: [String], timeout: TimeInterval = 5) async -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do { try process.run() } catch { return "" }

        let accumulator = DataAccumulator()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty { Task { await accumulator.append(chunk) } }
        }

        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            if process.isRunning { process.terminate() }
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in continuation.resume() }
        }

        timeoutTask.cancel()
        pipe.fileHandleForReading.readabilityHandler = nil
        let remainingData = pipe.fileHandleForReading.readDataToEndOfFile()
        let accumulated = await accumulator.getData()
        var allData = accumulated
        allData.append(remainingData)
        return String(data: allData, encoding: .utf8) ?? ""
    }
}
