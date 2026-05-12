import Foundation

struct ServerItem: Identifiable {
    let id: String
    let name: String
    let path: String
    let displayPath: String
    var isRunning: Bool
    var ports: [Int]
    var pids: [Int]
    var hasLogs: Bool
    var terminalApp: String?
}

struct PortInfo {
    let port: Int
    let pid: Int
    let processName: String
    var cwd: String?
}

struct CachedProject: Codable {
    let path: String
    let name: String
    let displayPath: String
    var lastSeen: Date
}

struct ProjectCache {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cache/noodles/projects.json")

    static func load() -> [CachedProject] {
        guard let data = try? Data(contentsOf: url),
              let projects = try? JSONDecoder().decode([CachedProject].self, from: data)
        else { return [] }
        return projects
    }

    static func save(_ projects: [CachedProject]) {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(projects) {
            try? data.write(to: url)
        }
    }
}
