import Foundation

// LEARN: This is a plain `class` (not struct, not actor, not ObservableObject).
// It's a simple service — no UI bindings, no concurrency concerns.
// All methods are synchronous and called from the main thread.
// In TS terms, this would just be a module with exported functions, or a plain class.
class ProjectScanner {

    func scan(sitesPath: String) -> [Project] {
        let expandedPath = (sitesPath as NSString).expandingTildeInPath
        // LEARN: `URL(fileURLWithPath:)` creates a file:// URL from a path.
        // Swift uses URL for both web URLs and file paths — one type for everything.
        // In Node you'd use `path.resolve()` for file paths and `new URL()` for web URLs.
        let sitesURL = URL(fileURLWithPath: expandedPath)

        // LEARN: `do { ... } catch { ... }` — the entire scan is wrapped in error handling.
        // `try` before `FileManager.default.contentsOfDirectory` means this call can throw.
        // If the directory doesn't exist or can't be read, we fall through to `catch` and return [].
        do {
            // LEARN: `FileManager.default` is a singleton — like Node's `fs` module.
            // `.contentsOfDirectory(at:...)` = like `fs.readdirSync()` but returns URL objects.
            // `includingPropertiesForKeys: [.isDirectoryKey]` — pre-fetches directory metadata
            // in one system call instead of calling stat() separately for each entry. Performance trick.
            let contents = try FileManager.default.contentsOfDirectory(
                at: sitesURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            var projects: [Project] = []

            for url in contents {
                guard let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey]),
                      resourceValues.isDirectory == true else {
                    continue
                }

                let folderName = url.lastPathComponent

                // Try the directory directly (has its own package.json)
                if let project = processProjectDirectory(url, id: folderName) {
                    projects.append(project)
                    continue
                }

                // No package.json at root — scan one level deeper for nested projects
                // (e.g. ~/Sites/noodles/site/ where the Swift app root has no package.json)
                let skipDirs: Set<String> = ["node_modules", "build", "dist"]
                guard let subContents = try? FileManager.default.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                ) else {
                    continue
                }

                for subURL in subContents {
                    guard let subValues = try? subURL.resourceValues(forKeys: [.isDirectoryKey]),
                          subValues.isDirectory == true,
                          !skipDirs.contains(subURL.lastPathComponent) else {
                        continue
                    }

                    let subId = "\(folderName)/\(subURL.lastPathComponent)"
                    if let project = processProjectDirectory(subURL, id: subId) {
                        projects.append(project)
                    }
                }
            }

            return projects

        } catch {
            return []
        }
    }

    // MARK: - Project Processing

    private func processProjectDirectory(_ url: URL, id: String) -> Project? {
        let packageJsonURL = url.appendingPathComponent("package.json")
        guard FileManager.default.fileExists(atPath: packageJsonURL.path),
              let packageData = try? Data(contentsOf: packageJsonURL),
              let packageJson = try? JSONSerialization.jsonObject(with: packageData) as? [String: Any] else {
            return nil
        }

        let folderName = url.lastPathComponent
        let name = (packageJson["name"] as? String) ?? folderName
        let packageManager = detectPackageManager(at: url)
        let workspaces = scanWorkspaces(at: url, packageJson: packageJson, packageManager: packageManager)
        let scripts = packageJson["scripts"] as? [String: String]
        let devCommand = scripts?["dev"]

        guard devCommand != nil || !workspaces.isEmpty else { return nil }

        let expectedPorts = detectPorts(at: url, packageJson: packageJson, devCommand: devCommand)

        var project = Project(
            id: id,
            name: name,
            path: url.path,
            packageManager: packageManager,
            devCommand: devCommand,
            expectedPorts: expectedPorts
        )
        project.workspaces = workspaces
        return project
    }

    // MARK: - Monorepo/Workspace Detection

    private func scanWorkspaces(at url: URL, packageJson: [String: Any], packageManager: PackageManager) -> [Workspace] {
        // Detect workspace globs from various sources
        var workspaceGlobs: [String] = []

        // 1. Check pnpm-workspace.yaml
        let pnpmWorkspaceURL = url.appendingPathComponent("pnpm-workspace.yaml")
        // LEARN: `try? String(contentsOf:encoding:)` — reads an entire file into a String.
        // Like `fs.readFileSync(path, 'utf8')` in Node. The `try?` returns nil if the file
        // doesn't exist or can't be read (instead of throwing).
        if let pnpmContent = try? String(contentsOf: pnpmWorkspaceURL, encoding: .utf8) {
            // LEARN: `.append(contentsOf:)` adds all elements of another array — like JS `.push(...items)`.
            // `.append()` (without contentsOf) adds a single element — like JS `.push(item)`.
            workspaceGlobs.append(contentsOf: parseWorkspaceGlobs(from: pnpmContent))
        }

        // 2. Check package.json workspaces field (npm/yarn)
        if let workspaces = packageJson["workspaces"] as? [String] {
            workspaceGlobs.append(contentsOf: workspaces)
        } else if let workspacesObj = packageJson["workspaces"] as? [String: Any],
                  let packages = workspacesObj["packages"] as? [String] {
            workspaceGlobs.append(contentsOf: packages)
        }

        // No workspace configuration found
        guard !workspaceGlobs.isEmpty else { return [] }

        // Also verify it's actually a monorepo tool (turbo, nx, lerna)
        let hasTurbo = FileManager.default.fileExists(atPath: url.appendingPathComponent("turbo.json").path)
        let hasNx = FileManager.default.fileExists(atPath: url.appendingPathComponent("nx.json").path)
        let hasLerna = FileManager.default.fileExists(atPath: url.appendingPathComponent("lerna.json").path)

        guard hasTurbo || hasNx || hasLerna || !workspaceGlobs.isEmpty else { return [] }

        // Expand globs and find workspace directories
        var workspaces: [Workspace] = []

        for glob in workspaceGlobs {
            let expandedDirs = expandWorkspaceGlob(glob, at: url)
            for workspaceDir in expandedDirs {
                if let workspace = scanWorkspaceDirectory(workspaceDir, relativeTo: url, packageManager: packageManager) {
                    workspaces.append(workspace)
                }
            }
        }

        // In turborepo projects, only show workspaces under apps/ — packages/ are
        // shared libraries that aren't runnable dev servers even if they have a dev script.
        if hasTurbo {
            workspaces = workspaces.filter { $0.relativePath.hasPrefix("apps/") }
        }

        return workspaces.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func parseWorkspaceGlobs(from yamlContent: String) -> [String] {
        // Simple YAML parsing for packages field
        // Looking for: packages:\n  - apps/*\n  - packages/*
        var globs: [String] = []
        var inPackages = false

        for line in yamlContent.components(separatedBy: .newlines) {
            // LEARN: `.trimmingCharacters(in:)` = like `.trim()` in JS.
            // `.whitespaces` trims spaces/tabs. `.whitespacesAndNewlines` also trims \n.
            // You can use predefined CharacterSets or create custom ones.
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("packages:") {
                inPackages = true
                continue
            }

            if inPackages {
                if trimmed.hasPrefix("- ") {
                    // LEARN: `.dropFirst(2)` returns a Substring with the first 2 characters removed.
                    // Like `.slice(2)` in JS. Returns a Substring (view), not a new String.
                    let glob = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                    // LEARN: `CharacterSet(charactersIn:)` creates a custom set of characters.
                    // Used here to strip quotes — like a regex `/['"]/g` replacement in JS.
                    let cleanGlob = glob.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    globs.append(cleanGlob)
                } else if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                    // End of packages section
                    break
                }
            }
        }

        return globs
    }

    private func expandWorkspaceGlob(_ glob: String, at baseURL: URL) -> [URL] {
        // Handle globs like "apps/*", "packages/*", "apps/**"
        var dirs: [URL] = []

        // Normalize glob - treat "/**" same as "/*" (we only go one level deep)
        let normalizedGlob = glob
            .replacingOccurrences(of: "/**", with: "/*")
            .replacingOccurrences(of: "/**/", with: "/*/")

        // LEARN: `.hasSuffix()` = like `.endsWith()` in JS. `.hasPrefix()` = `.startsWith()`.
        if normalizedGlob.hasSuffix("/*") {
            let parentPath = String(normalizedGlob.dropLast(2))
            let parentURL = baseURL.appendingPathComponent(parentPath)

            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: parentURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                return []
            }

            for item in contents {
                if let resourceValues = try? item.resourceValues(forKeys: [.isDirectoryKey]),
                   resourceValues.isDirectory == true {
                    dirs.append(item)
                }
            }
        } else if normalizedGlob.contains("*") {
            // Other glob patterns - try treating the prefix before * as a directory
            let parts = normalizedGlob.components(separatedBy: "*")
            if let prefix = parts.first, !prefix.isEmpty {
                let parentPath = prefix.hasSuffix("/") ? String(prefix.dropLast()) : prefix
                let parentURL = baseURL.appendingPathComponent(parentPath)

                if let contents = try? FileManager.default.contentsOfDirectory(
                    at: parentURL,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                ) {
                    for item in contents {
                        if let resourceValues = try? item.resourceValues(forKeys: [.isDirectoryKey]),
                           resourceValues.isDirectory == true {
                            dirs.append(item)
                        }
                    }
                }
            }
        } else {
            // Direct path (no wildcards)
            let directURL = baseURL.appendingPathComponent(normalizedGlob)
            if FileManager.default.fileExists(atPath: directURL.path) {
                dirs.append(directURL)
            }
        }

        return dirs
    }

    private func scanWorkspaceDirectory(_ url: URL, relativeTo baseURL: URL, packageManager: PackageManager) -> Workspace? {
        // Skip if workspace points to the monorepo root itself
        if url.path == baseURL.path { return nil }

        let packageJsonURL = url.appendingPathComponent("package.json")

        guard let packageData = try? Data(contentsOf: packageJsonURL),
              let packageJson = try? JSONSerialization.jsonObject(with: packageData) as? [String: Any] else {
            return nil
        }

        // Check for dev script - only show workspaces that can be run
        let scripts = packageJson["scripts"] as? [String: String]
        guard let devCommand = scripts?["dev"] else {
            return nil  // No dev script = library package, skip
        }

        let folderName = url.lastPathComponent
        let name = (packageJson["name"] as? String) ?? folderName

        // Calculate relative path from monorepo root
        let relativePath = url.path.replacingOccurrences(of: baseURL.path + "/", with: "")

        // Extract expected ports
        let expectedPorts = detectPorts(at: url, packageJson: packageJson, devCommand: devCommand)

        return Workspace(
            id: "\(baseURL.lastPathComponent)/\(relativePath)",
            name: name,
            path: url.path,
            relativePath: relativePath,
            devCommand: devCommand,
            expectedPorts: expectedPorts
        )
    }

    private func detectPorts(at url: URL, packageJson: [String: Any], devCommand: String?) -> [Int] {
        // LEARN: `Set<Int>` is used to avoid duplicates during collection.
        // At the end, it's converted to a sorted Array.
        // Same pattern as `new Set()` → `[...set].sort()` in JS.
        var ports = Set<Int>()

        // 1. Extract from dev command
        if let cmd = devCommand {
            // LEARN: `.formUnion()` = mutating union. Adds all elements from another set.
            // Like `otherSet.forEach(s => mySet.add(s))` in JS, but one method call.
            ports.formUnion(extractPortsFromCommand(cmd))
        }

        // 2. Check package.json config section
        if let config = packageJson["config"] as? [String: Any] {
            if let port = config["port"] as? Int {
                ports.insert(port)
            }
        }

        // 3. Check .env file
        let envURL = url.appendingPathComponent(".env")
        if let envContent = try? String(contentsOf: envURL, encoding: .utf8) {
            ports.formUnion(extractPortsFromEnv(envContent))
        }

        // 4. Check .env.local file
        let envLocalURL = url.appendingPathComponent(".env.local")
        if let envContent = try? String(contentsOf: envLocalURL, encoding: .utf8) {
            ports.formUnion(extractPortsFromEnv(envContent))
        }

        // 5. Check next.config.js/mjs for Next.js projects
        for configFile in ["next.config.js", "next.config.mjs", "next.config.ts"] {
            let configURL = url.appendingPathComponent(configFile)
            if let content = try? String(contentsOf: configURL, encoding: .utf8) {
                if let port = extractPortFromNextConfig(content) {
                    ports.insert(port)
                }
            }
        }

        // 6. Check vite.config.ts/js for Vite projects
        for configFile in ["vite.config.ts", "vite.config.js", "vite.config.mts"] {
            let configURL = url.appendingPathComponent(configFile)
            if let content = try? String(contentsOf: configURL, encoding: .utf8) {
                if let port = extractPortFromViteConfig(content) {
                    ports.insert(port)
                }
            }
        }

        // 7. Framework defaults if nothing found
        if ports.isEmpty, let cmd = devCommand {
            if cmd.contains("next") {
                ports.insert(3000)
            } else if cmd.contains("storybook") {
                ports.insert(6006)
            } else if cmd.contains("vite") || cmd.contains("astro") {
                ports.insert(5173)
            } else if cmd.contains("nuxt") {
                ports.insert(3000)
            } else if cmd.contains("remix") {
                ports.insert(3000)
            } else if cmd.contains("gatsby") {
                ports.insert(8000)
            } else if cmd.contains("webpack") && cmd.contains("serve") {
                ports.insert(8080)
            } else if cmd.contains("expo") {
                ports.insert(8081)
            } else if cmd.contains("turbo") {
                // turbo dev doesn't have a default port - it runs workspace scripts
            }
        }

        return Array(ports).sorted()
    }

    private func extractPortsFromCommand(_ cmd: String) -> Set<Int> {
        var ports = Set<Int>()

        // --port 3000 or --port=3000 or -p 3000
        let patterns = [
            "--port[=\\s]+(\\d+)",
            "-p\\s+(\\d+)",
            "-p=(\\d+)",
            "PORT=(\\d+)",
            "localhost:(\\d+)",
            // Catch bare port numbers as script arguments (e.g., "node script.mjs 4310")
            "\\s(3\\d{3})(?:\\s|$)",   // 3000-3999
            "\\s(4\\d{3})(?:\\s|$)",   // 4000-4999
            "\\s(5\\d{3})(?:\\s|$)",   // 5000-5999
            "\\s(6\\d{3})(?:\\s|$)",   // 6000-6999
            "\\s(8\\d{3})(?:\\s|$)",   // 8000-8999
            "\\s(9\\d{3})(?:\\s|$)",   // 9000-9999
        ]

        // LEARN: `NSRegularExpression` is Swift's regex API — more verbose than JS's `/pattern/`.
        // `try?` because the pattern might be invalid (returns nil instead of crashing).
        // Swift 5.7+ also supports `/regex/` literals (like JS), but this code uses the older API.
        //
        // `NSRange(cmd.startIndex..., in: cmd)` — converts a Swift String range to an NSRange.
        // This bridging is needed because NSRegularExpression is an Objective-C API that uses
        // NSRange (integer-based) while Swift strings use String.Index (Unicode-aware).
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let matches = regex.matches(in: cmd, range: NSRange(cmd.startIndex..., in: cmd))
                for match in matches {
                    // LEARN: `Range(match.range(at: 1), in: cmd)` — converts NSRange back to Swift Range.
                    // `range(at: 1)` gets the first capture group (like `match[1]` in JS regex).
                    if let range = Range(match.range(at: 1), in: cmd),
                       let port = Int(cmd[range]) {
                        ports.insert(port)
                    }
                }
            }
        }

        return ports
    }

    private func extractPortsFromEnv(_ content: String) -> Set<Int> {
        var ports = Set<Int>()

        // Match PORT=3000 or VITE_PORT=3000 etc.
        let pattern = "(?:^|\\n)\\s*(?:VITE_)?PORT\\s*=\\s*(\\d+)"
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let matches = regex.matches(in: content, range: NSRange(content.startIndex..., in: content))
            for match in matches {
                if let range = Range(match.range(at: 1), in: content),
                   let port = Int(content[range]) {
                    ports.insert(port)
                }
            }
        }

        return ports
    }

    private func extractPortFromNextConfig(_ content: String) -> Int? {
        // Look for: port: 3001 or port: Number(process.env.PORT) || 3001
        let pattern = "port\\s*:\\s*(\\d+)"
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
           let range = Range(match.range(at: 1), in: content) {
            return Int(content[range])
        }
        return nil
    }

    private func extractPortFromViteConfig(_ content: String) -> Int? {
        // Look for: port: 5174 in server config
        let pattern = "port\\s*:\\s*(\\d+)"
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
           let range = Range(match.range(at: 1), in: content) {
            return Int(content[range])
        }
        return nil
    }

    private func detectPackageManager(at url: URL) -> PackageManager {
        if FileManager.default.fileExists(atPath: url.appendingPathComponent("bun.lockb").path) {
            return .bun
        }
        if FileManager.default.fileExists(atPath: url.appendingPathComponent("pnpm-lock.yaml").path) {
            return .pnpm
        }
        if FileManager.default.fileExists(atPath: url.appendingPathComponent("yarn.lock").path) {
            return .yarn
        }
        return .npm
    }
}
