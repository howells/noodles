import Foundation

class ProjectScanner {

    func scan(sitesPath: String) -> [Project] {
        let expandedPath = (sitesPath as NSString).expandingTildeInPath
        let sitesURL = URL(fileURLWithPath: expandedPath)

        do {
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

                let packageJsonURL = url.appendingPathComponent("package.json")
                guard FileManager.default.fileExists(atPath: packageJsonURL.path) else {
                    continue
                }

                guard let packageData = try? Data(contentsOf: packageJsonURL),
                      let packageJson = try? JSONSerialization.jsonObject(with: packageData) as? [String: Any] else {
                    continue
                }

                let folderName = url.lastPathComponent
                let name = (packageJson["name"] as? String) ?? folderName

                // Detect package manager
                let packageManager = detectPackageManager(at: url)

                // Check if this is a monorepo
                let workspaces = scanWorkspaces(at: url, packageJson: packageJson, packageManager: packageManager)

                // Check for dev script (monorepos might not have one at root)
                let scripts = packageJson["scripts"] as? [String: String]
                let devCommand = scripts?["dev"]

                // Skip if no dev command AND no workspaces
                guard devCommand != nil || !workspaces.isEmpty else { continue }

                // Extract expected ports from multiple sources
                let expectedPorts = detectPorts(at: url, packageJson: packageJson, devCommand: devCommand)

                var project = Project(
                    id: folderName,
                    name: name,
                    path: url.path,
                    packageManager: packageManager,
                    devCommand: devCommand,
                    expectedPorts: expectedPorts
                )
                project.workspaces = workspaces

                projects.append(project)
            }

            return projects

        } catch {
            return []
        }
    }

    // MARK: - Monorepo/Workspace Detection

    private func scanWorkspaces(at url: URL, packageJson: [String: Any], packageManager: PackageManager) -> [Workspace] {
        // Detect workspace globs from various sources
        var workspaceGlobs: [String] = []

        // 1. Check pnpm-workspace.yaml
        let pnpmWorkspaceURL = url.appendingPathComponent("pnpm-workspace.yaml")
        if let pnpmContent = try? String(contentsOf: pnpmWorkspaceURL, encoding: .utf8) {
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

        return workspaces.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func parseWorkspaceGlobs(from yamlContent: String) -> [String] {
        // Simple YAML parsing for packages field
        // Looking for: packages:\n  - apps/*\n  - packages/*
        var globs: [String] = []
        var inPackages = false

        for line in yamlContent.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("packages:") {
                inPackages = true
                continue
            }

            if inPackages {
                if trimmed.hasPrefix("- ") {
                    let glob = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                    // Remove quotes if present
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
        // Handle globs like "apps/*", "packages/*"
        // For simplicity, we only support single-level wildcards
        var dirs: [URL] = []

        if glob.hasSuffix("/*") {
            let parentPath = String(glob.dropLast(2))
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
        } else if glob.contains("*") {
            // More complex globs - skip for now
            return []
        } else {
            // Direct path
            let directURL = baseURL.appendingPathComponent(glob)
            if FileManager.default.fileExists(atPath: directURL.path) {
                dirs.append(directURL)
            }
        }

        return dirs
    }

    private func scanWorkspaceDirectory(_ url: URL, relativeTo baseURL: URL, packageManager: PackageManager) -> Workspace? {
        let packageJsonURL = url.appendingPathComponent("package.json")

        guard let packageData = try? Data(contentsOf: packageJsonURL),
              let packageJson = try? JSONSerialization.jsonObject(with: packageData) as? [String: Any] else {
            return nil
        }

        // Check for dev script
        let scripts = packageJson["scripts"] as? [String: String]
        guard let devCommand = scripts?["dev"] else {
            return nil  // No dev script, skip this workspace
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
        var ports = Set<Int>()

        // 1. Extract from dev command
        if let cmd = devCommand {
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
            "PORT=(\\d+)",
            "localhost:(\\d+)"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let matches = regex.matches(in: cmd, range: NSRange(cmd.startIndex..., in: cmd))
                for match in matches {
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
