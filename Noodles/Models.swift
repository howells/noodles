import Foundation

enum ProjectStatus: String, Codable {
    case stopped
    case starting
    case running
    case stopping
    case error
}

enum PackageManager: String, Codable {
    case npm
    case pnpm
    case yarn
    case bun

    var command: String { rawValue }

    var devArgs: [String] {
        switch self {
        case .npm: return ["run", "dev"]
        default: return ["dev"]
        }
    }
}

struct Workspace: Identifiable {
    let id: String
    let name: String
    let path: String
    let relativePath: String  // e.g., "apps/web"
    let devCommand: String?
    let expectedPorts: [Int]
    var status: ProjectStatus = .stopped
    var runningPorts: [PortInfo] = []
    var error: String?

    var effectivePort: Int? {
        expectedPorts.first
    }
}

struct Project: Identifiable {
    let id: String
    let name: String
    let path: String
    let packageManager: PackageManager
    let devCommand: String?
    let expectedPorts: [Int]
    var customPort: Int?  // User-configured port override
    var status: ProjectStatus = .stopped
    var runningPorts: [PortInfo] = []
    var error: String?
    var workspaces: [Workspace] = []  // For monorepos

    var isMonorepo: Bool {
        !workspaces.isEmpty
    }

    var displayPath: String {
        path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    // Port to open in browser - custom port takes precedence
    var browserPort: Int? {
        customPort ?? runningPorts.first?.port ?? expectedPorts.first
    }

    // The port this project will start on
    var effectivePort: Int? {
        customPort ?? expectedPorts.first
    }
}

struct PortInfo: Identifiable {
    var id: Int { port }
    let port: Int
    let pid: Int
    let processName: String
    var cwd: String?
}

struct Config: Codable {
    var sitesPath: String = "~/Sites"
    var editor: String = "cursor"
    var terminal: String = "Terminal"
    var launchOnLogin: Bool = true
    var pollIntervalMs: Int = 2000
    var favorites: [String] = []
    var hiddenProjects: [String] = []
    var customPorts: [String: Int] = [:]  // projectId -> custom port
}

struct ConfigManager {
    static let configPath: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/noodles/config.json")
    }()

    static func load() -> Config {
        guard FileManager.default.fileExists(atPath: configPath.path),
              let data = try? Data(contentsOf: configPath),
              let config = try? JSONDecoder().decode(Config.self, from: data) else {
            return Config()
        }
        return config
    }

    static func save(_ config: Config) {
        let dir = configPath.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(config) {
            try? data.write(to: configPath)
        }
    }
}
