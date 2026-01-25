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

                // Check for dev script
                let scripts = packageJson["scripts"] as? [String: String]
                let devCommand = scripts?["dev"]

                guard devCommand != nil else { continue }

                // Detect package manager
                let packageManager = detectPackageManager(at: url)

                // Extract expected ports from multiple sources
                let expectedPorts = detectPorts(at: url, packageJson: packageJson, devCommand: devCommand)

                projects.append(Project(
                    id: folderName,
                    name: name,
                    path: url.path,
                    packageManager: packageManager,
                    devCommand: devCommand,
                    expectedPorts: expectedPorts
                ))
            }

            return projects

        } catch {
            return []
        }
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
