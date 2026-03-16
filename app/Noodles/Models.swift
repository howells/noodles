import Foundation

struct RunningServer: Identifiable {
    let id: String
    let ports: [Int]
    let pids: [Int]
    let name: String
    let path: String
    let displayPath: String
    var hasLogs: Bool
    var terminalApp: String?
}

struct PortInfo {
    let port: Int
    let pid: Int
    let processName: String
    var cwd: String?
}
