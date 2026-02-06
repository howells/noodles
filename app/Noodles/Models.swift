// LEARN: `import Foundation` is like `require('node:fs')` + `require('node:path')` + `require('node:url')` combined.
// Foundation gives you: strings, dates, JSON, file I/O, URLs, regex, and more.
// Unlike Node, there's no package.json — system frameworks are always available.
import Foundation

// LEARN: Swift enums are WAY more powerful than TS enums.
// TS enum:  enum ProjectStatus { Stopped = "stopped", Running = "running" }
// Swift enums can have:
//   - Raw values (like here, backed by String)
//   - Associated values (like TS discriminated unions: { type: "error", message: string })
//   - Methods and computed properties
//   - Protocol conformance (Codable here = automatic JSON serialization)
//
// `Codable` = TS equivalent of implementing both JSON.parse() and JSON.stringify() automatically.
// The compiler generates the serialization code for you — no zod, no io-ts, no manual parsing.
enum ProjectStatus: String, Codable {
    case stopped
    case starting
    case running
    case stopping
    case restarting
    case error
}

enum PackageManager: String, Codable {
    case npm
    case pnpm
    case yarn
    case bun

    // LEARN: Computed property — like a TS getter: `get command() { return this.rawValue }`
    // `rawValue` gives the String backing ("npm", "pnpm", etc.) — it's free with String enums.
    var command: String { rawValue }

    // LEARN: `switch` on enums is exhaustive — the compiler forces you to handle ALL cases.
    // If you add a new case later, every switch breaks until you handle it.
    // TS has nothing like this (you'd use `satisfies never` as a workaround).
    var devArgs: [String] {
        switch self {
        case .npm: return ["run", "dev"]
        default: return ["dev"]
        }
    }

    func workspaceDevArgs(filter: String) -> [String] {
        switch self {
        case .npm: return ["run", "dev", "--workspace", filter]
        case .yarn: return ["workspace", filter, "dev"]
        case .pnpm: return ["dev", "--filter", filter]
        case .bun: return ["dev", "--filter", filter]
        }
    }
}

// LEARN: `struct` vs `class` is THE most important distinction in Swift (no equivalent in TS).
//
// struct = VALUE TYPE (copied on assignment, like a number or string in JS)
//   let a = Project(...); var b = a; b.name = "X"  // a is UNCHANGED
//
// class = REFERENCE TYPE (shared on assignment, like objects in JS)
//   let a = AppState(); let b = a; b.filter = "X"  // a.filter is ALSO "X"
//
// Rule of thumb: Use struct for data/models, class for stateful services.
// All the models here are structs — they're pure data, like TS interfaces/types.
//
// `Identifiable` = protocol requiring an `id` property. SwiftUI uses this in ForEach loops
// (like needing a `key` prop in React's .map()).
struct Workspace: Identifiable {
    let id: String       // LEARN: `let` = truly immutable (not like JS let). More like TS `readonly`.
    let name: String     //        `var` = mutable. Swift has no `const` keyword — `let` IS const.
    let path: String
    let relativePath: String
    let devCommand: String?  // LEARN: `String?` = Optional<String>. Like TS's `string | undefined`.
    let expectedPorts: [Int] // LEARN: `[Int]` = Array<Int>. Swift uses [] for arrays, not Array<>.
    var status: ProjectStatus = .stopped  // LEARN: Default value, just like TS. `.stopped` is shorthand
    var runningPorts: [PortInfo] = []     //        for `ProjectStatus.stopped` — Swift infers the type.
    var error: String?

    // LEARN: Computed property with no setter = TS `get effectivePort(): number | undefined`
    // The `?` in the return type `Int?` means this can return nil (like returning undefined in TS).
    var effectivePort: Int? {
        expectedPorts.first  // `.first` on Array returns Optional — nil if array is empty.
    }
}

struct Project: Identifiable {
    let id: String
    let name: String
    let path: String
    let packageManager: PackageManager
    let devCommand: String?
    let expectedPorts: [Int]
    var customPort: Int?
    var status: ProjectStatus = .stopped
    var runningPorts: [PortInfo] = []
    var error: String?
    var workspaces: [Workspace] = []

    var isMonorepo: Bool {
        !workspaces.isEmpty
    }

    var displayPath: String {
        // LEARN: NSHomeDirectory() is like `os.homedir()` in Node.
        // String methods in Swift are verbose compared to JS — no `.replace()`, you get
        // `.replacingOccurrences(of:with:)`. Swift favors clarity over brevity.
        path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    var browserPort: Int? {
        // LEARN: `??` is nil-coalescing, same as TS's `??` for nullish coalescing.
        // This chains: try customPort, then first running port, then first expected port.
        // Each `?.` is optional chaining — identical to TS's `?.` operator.
        customPort ?? runningPorts.first?.port ?? expectedPorts.first
    }

    var effectivePort: Int? {
        customPort ?? expectedPorts.first
    }
}

struct PortInfo: Identifiable {
    // LEARN: Computed `id` satisfies the Identifiable protocol without storing a separate field.
    // Protocol conformance = like implementing a TS interface, but enforced at compile time.
    var id: String { "\(pid):\(port)" }
    let port: Int
    let pid: Int
    let processName: String
    var cwd: String?  // LEARN: Optional with no default = must be provided OR is nil.
}

struct LogBuffer {
    let maxLines: Int
    private(set) var lines: [String] = []

    init(maxLines: Int) {
        self.maxLines = maxLines
    }

    mutating func append(_ line: String) {
        lines.append(line)
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
    }
}

struct LogFormatter {
    static func format(_ line: String) -> String {
        line.replacingOccurrences(of: "\r", with: "")
    }
}

struct ManagedServerInfo: Identifiable {
    let id: UUID
    let label: String
    let path: String
    let command: String
    let pid: Int32?
    let port: Int?
    let isRunning: Bool
    let exitCode: Int32?
    let stopRequestedAt: Date?
    let startedAt: Date
}

// LEARN: `Codable` on a struct auto-generates JSON encode/decode. Equivalent to:
//   interface Config { sitesPath: string; editor: string; ... }
//   const parse = (json: string): Config => JSON.parse(json) as Config
//   const stringify = (c: Config): string => JSON.stringify(c)
// But Swift's version is type-safe — malformed JSON throws an error, not silent wrong types.
struct Config: Codable {
    var sitesPath: String = "~/Sites"
    var editor: String = "cursor"
    var terminal: String = "Terminal"
    var launchOnLogin: Bool = true
    var runManagedServers: Bool = false
    var pollIntervalMs: Int = 2000
    var pinned: [String] = []
    var hiddenProjects: [String] = []
    var customPorts: [String: Int] = [:]  // LEARN: `[String: Int]` = Dictionary. Like TS Record<string, number>.
}

// LEARN: This is a "namespace struct" — using `static` methods to group related functions.
// In TS you'd use a module with exported functions, or a static class.
// Swift doesn't have standalone module-level functions that belong to a "namespace" —
// wrapping them in a struct is the idiomatic pattern.
struct ConfigManager {
    // LEARN: `static let` with a closure `= { ... }()` is a lazy-initialized constant.
    // The closure runs once on first access (like a module-level `const` in Node).
    // The return type `URL` is Swift's URL type — used for both file paths and web URLs.
    static let configPath: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/noodles/config.json")
    }()

    static func load() -> Config {
        // LEARN: `guard` is Swift's early-return pattern. It's like:
        //   if (!condition) { return fallback }
        // But `guard let` also UNWRAPS optionals — the unwrapped value is available
        // after the guard (in the rest of the function scope), unlike `if let` which
        // scopes the value inside the `if` block only.
        //
        // Chaining guard conditions with commas = all must pass (like && in TS).
        // `try?` = "try this, but give me nil if it throws" (swallows the error).
        //   TS equivalent: `const data = await fs.readFile(path).catch(() => null)`
        guard FileManager.default.fileExists(atPath: configPath.path),
              let data = try? Data(contentsOf: configPath),
              let config = try? JSONDecoder().decode(Config.self, from: data) else {
            return Config()  // Return default config if anything fails
        }
        return config
    }

    static func save(_ config: Config) {
        let dir = configPath.deletingLastPathComponent()
        // LEARN: `try?` silently ignores errors. In production Swift code you'd usually
        // use `do { try ... } catch { ... }` for proper error handling (like try/catch in TS).
        // `try?` is handy for fire-and-forget operations like saving config.
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(config) {
            try? data.write(to: configPath)
        }
    }
}
