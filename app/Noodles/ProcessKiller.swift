import Foundation
import Darwin

struct ProcessKiller {
    static func killTree(pids: [Int]) async {
        for pid in pids {
            let pid32 = Int32(pid)
            let pgid = getpgid(pid32)
            if pgid > 0 { kill(-pgid, SIGTERM) }
            killChildrenRecursive(parentPid: pid32, signal: SIGTERM)
            kill(pid32, SIGTERM)
        }

        let deadline = Date().addingTimeInterval(2.0)
        var remaining = pids.map(Int32.init)
        while !remaining.isEmpty && Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
            remaining = remaining.filter { kill($0, 0) == 0 }
        }

        for pid in remaining {
            let pgid = getpgid(pid)
            if pgid > 0 { kill(-pgid, SIGKILL) }
            killChildrenRecursive(parentPid: pid, signal: SIGKILL)
            kill(pid, SIGKILL)
        }
    }

    private static func killChildrenRecursive(parentPid: Int32, signal: Int32) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-P", String(parentPid)]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return }
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
}
