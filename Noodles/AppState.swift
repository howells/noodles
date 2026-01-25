import Foundation
import Combine
import ServiceManagement

@MainActor
class AppState: ObservableObject {
    @Published var projects: [Project] = [] {
        didSet {
            NotificationCenter.default.post(name: NSNotification.Name("ProjectsDidChange"), object: nil)
        }
    }
    @Published var ports: [PortInfo] = []
    @Published var isScanning = false
    @Published var filter = ""
    @Published var config: Config
    @Published var showHidden = false

    private var portPollingTimer: Timer?
    private let processManager = ProcessManager()
    private let scanner = ProjectScanner()

    init() {
        self.config = ConfigManager.load()
    }

    deinit {
        portPollingTimer?.invalidate()
        portPollingTimer = nil
    }

    func cleanup() async {
        portPollingTimer?.invalidate()
        portPollingTimer = nil
        await processManager.cleanupSpawnedProcesses()
    }

    func scan() {
        NSLog("Noodles: scan() called")
        isScanning = true

        var scannedProjects = scanner.scan(sitesPath: config.sitesPath)
        NSLog("Noodles: Got %d scanned projects", scannedProjects.count)

        // Apply custom ports from config
        for i in scannedProjects.indices {
            if let customPort = config.customPorts[scannedProjects[i].id] {
                scannedProjects[i].customPort = customPort
            }
        }

        // Set projects immediately (without port matching first)
        self.projects = scannedProjects.sorted { a, b in
            a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }

        NSLog("Noodles: Set projects array, count = %d", self.projects.count)
        self.isScanning = false

        // Start port polling after initial load
        startPortPolling()
    }

    func startProject(_ project: Project) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[index].status = .starting

        // Build the dev command
        var args = [project.packageManager.command] + project.packageManager.devArgs
        if let port = project.customPort {
            args.append("--port")
            args.append(String(port))
        }
        let devCommand = args.joined(separator: " ")

        // Open terminal and run dev command
        processManager.openInTerminal(path: project.path, terminal: config.terminal, command: devCommand)
    }

    func stopProject(_ project: Project) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[index].status = .stopping

        Task {
            do {
                try await processManager.stopProjectProcesses(projectPath: project.path)
            } catch {
                await MainActor.run {
                    if let idx = self.projects.firstIndex(where: { $0.id == project.id }) {
                        self.projects[idx].status = .error
                        self.projects[idx].error = error.localizedDescription
                    }
                }
            }
        }
    }

    // MARK: - Workspace Management

    func startWorkspace(_ workspace: Workspace, in project: Project) {
        guard let projectIndex = projects.firstIndex(where: { $0.id == project.id }),
              let workspaceIndex = projects[projectIndex].workspaces.firstIndex(where: { $0.id == workspace.id }) else {
            return
        }

        projects[projectIndex].workspaces[workspaceIndex].status = .starting

        // Build the turbo filter command
        // For pnpm monorepos: pnpm dev --filter=workspace-name
        let args = [project.packageManager.command, "dev", "--filter", workspace.name]
        let devCommand = args.joined(separator: " ")

        // Open terminal and run dev command from the monorepo root
        processManager.openInTerminal(path: project.path, terminal: config.terminal, command: devCommand)
    }

    func stopWorkspace(_ workspace: Workspace, in project: Project) {
        guard let projectIndex = projects.firstIndex(where: { $0.id == project.id }),
              let workspaceIndex = projects[projectIndex].workspaces.firstIndex(where: { $0.id == workspace.id }) else {
            return
        }

        projects[projectIndex].workspaces[workspaceIndex].status = .stopping

        Task {
            do {
                try await processManager.stopProjectProcesses(projectPath: workspace.path)
            } catch {
                await MainActor.run {
                    if let pIdx = self.projects.firstIndex(where: { $0.id == project.id }),
                       let wIdx = self.projects[pIdx].workspaces.firstIndex(where: { $0.id == workspace.id }) {
                        self.projects[pIdx].workspaces[wIdx].status = .error
                        self.projects[pIdx].workspaces[wIdx].error = error.localizedDescription
                    }
                }
            }
        }
    }

    func restartProject(_ project: Project) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[index].status = .stopping

        Task {
            do {
                try await processManager.stopProjectProcesses(projectPath: project.path)
                // Wait for port to be released
                try await Task.sleep(nanoseconds: 500_000_000)
                await MainActor.run {
                    self.startProject(project)
                }
            } catch {
                await MainActor.run {
                    if let idx = self.projects.firstIndex(where: { $0.id == project.id }) {
                        self.projects[idx].status = .error
                        self.projects[idx].error = error.localizedDescription
                    }
                }
            }
        }
    }

    func openInBrowser(port: Int) {
        processManager.openInBrowser(port: port)
    }

    func openInEditor(path: String) {
        processManager.openInEditor(path: path, editor: config.editor)
    }

    func openInTerminal(path: String, command: String? = nil) {
        processManager.openInTerminal(path: path, terminal: config.terminal, command: command)
    }

    private func startPortPolling() {
        // Initial port refresh
        refreshPortsSync()

        portPollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.refreshPortsSync()
            }
        }
    }

    private func refreshPortsSync() {
        Task {
            let currentPorts = await processManager.getListeningPorts()

            // AppState is @MainActor so we're already on main
            self.ports = currentPorts

            // Create updated projects array to trigger SwiftUI update
            var updatedProjects = self.projects

            for i in updatedProjects.indices {
                let projectPorts = currentPorts.filter { port in
                    guard let cwd = port.cwd else { return false }
                    return cwd.hasPrefix(updatedProjects[i].path)
                }

                updatedProjects[i].runningPorts = projectPorts

                // Update workspace statuses for monorepos
                for j in updatedProjects[i].workspaces.indices {
                    let workspacePath = updatedProjects[i].workspaces[j].path
                    let workspaceRelPath = updatedProjects[i].workspaces[j].relativePath  // e.g., "apps/web"

                    // Match by cwd - try multiple strategies
                    var workspacePorts = currentPorts.filter { port in
                        guard let cwd = port.cwd else { return false }
                        // Direct prefix match
                        if cwd.hasPrefix(workspacePath) { return true }
                        // Check if cwd contains the relative path within the project
                        if cwd.hasPrefix(updatedProjects[i].path) && cwd.contains(workspaceRelPath) { return true }
                        return false
                    }

                    // Fallback: match by expected port when cwd matching fails
                    // This handles turbo dev where processes may run from monorepo root
                    if workspacePorts.isEmpty {
                        let expectedPorts = Set(updatedProjects[i].workspaces[j].expectedPorts)
                        if !expectedPorts.isEmpty {
                            // Match from all project ports OR all current ports with matching expected port
                            workspacePorts = currentPorts.filter { port in
                                guard expectedPorts.contains(port.port) else { return false }
                                // Verify it's related to this project (cwd within project, or no cwd)
                                if let cwd = port.cwd {
                                    return cwd.hasPrefix(updatedProjects[i].path)
                                }
                                return true  // No cwd info, trust the port match
                            }
                        }
                    }

                    updatedProjects[i].workspaces[j].runningPorts = workspacePorts

                    if updatedProjects[i].workspaces[j].status == .starting || updatedProjects[i].workspaces[j].status == .stopping {
                        if !workspacePorts.isEmpty && updatedProjects[i].workspaces[j].status == .starting {
                            updatedProjects[i].workspaces[j].status = .running
                        } else if workspacePorts.isEmpty && updatedProjects[i].workspaces[j].status == .stopping {
                            updatedProjects[i].workspaces[j].status = .stopped
                        }
                    } else if updatedProjects[i].workspaces[j].status != .error {
                        updatedProjects[i].workspaces[j].status = workspacePorts.isEmpty ? .stopped : .running
                    }
                }

                // For non-monorepos, update project status as before
                if !updatedProjects[i].isMonorepo {
                    if updatedProjects[i].status == .starting || updatedProjects[i].status == .stopping {
                        if !projectPorts.isEmpty && updatedProjects[i].status == .starting {
                            updatedProjects[i].status = .running
                        } else if projectPorts.isEmpty && updatedProjects[i].status == .stopping {
                            updatedProjects[i].status = .stopped
                        }
                    } else if updatedProjects[i].status != .error {
                        updatedProjects[i].status = projectPorts.isEmpty ? .stopped : .running
                    }
                } else {
                    // For monorepos, project is "running" if any workspace is running
                    let anyWorkspaceRunning = updatedProjects[i].workspaces.contains { $0.status == .running }
                    if updatedProjects[i].status != .starting && updatedProjects[i].status != .stopping && updatedProjects[i].status != .error {
                        updatedProjects[i].status = anyWorkspaceRunning ? .running : .stopped
                    }
                }
            }

            // Assign new array to trigger @Published update
            self.projects = updatedProjects
        }
    }

    var filteredProjects: [Project] {
        var result = projects

        // Exclude hidden projects unless showHidden is true
        if !showHidden {
            result = result.filter { !isHidden($0) }
        }

        // Apply search filter
        if !filter.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(filter) ||
                $0.path.localizedCaseInsensitiveContains(filter)
            }
        }

        return result
    }

    var runningProjects: [Project] {
        filteredProjects.filter { $0.status == .running }
    }

    var stoppedProjects: [Project] {
        filteredProjects.filter { $0.status != .running }
    }

    var favoriteProjects: [Project] {
        filteredProjects.filter { isFavorite($0) }
    }

    // MARK: - Favorites

    func isFavorite(_ project: Project) -> Bool {
        config.favorites.contains(project.id)
    }

    func toggleFavorite(_ project: Project) {
        if isFavorite(project) {
            config.favorites.removeAll { $0 == project.id }
        } else {
            config.favorites.append(project.id)
        }
        ConfigManager.save(config)
    }

    // MARK: - Hidden Projects

    func isHidden(_ project: Project) -> Bool {
        config.hiddenProjects.contains(project.id)
    }

    func toggleHidden(_ project: Project) {
        if isHidden(project) {
            config.hiddenProjects.removeAll { $0 == project.id }
        } else {
            config.hiddenProjects.append(project.id)
        }
        ConfigManager.save(config)
    }

    var hiddenProjectCount: Int {
        config.hiddenProjects.count
    }

    // MARK: - Launch on Login

    func setLaunchOnLogin(_ enabled: Bool) {
        config.launchOnLogin = enabled
        ConfigManager.save(config)

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Noodles: Failed to set launch on login: \(error)")
        }
    }

    func syncLaunchOnLoginState() {
        let status = SMAppService.mainApp.status
        let isRegistered = status == .enabled
        if config.launchOnLogin != isRegistered {
            config.launchOnLogin = isRegistered
            ConfigManager.save(config)
        }
    }

    // Port conflict detection (uses effective port: custom if set, else first expected)
    var portConflicts: [Int: [Project]] {
        var portToProjects: [Int: [Project]] = [:]

        for project in projects {
            if let port = project.effectivePort {
                portToProjects[port, default: []].append(project)
            }
        }

        // Only return ports with conflicts (more than one project)
        return portToProjects.filter { $0.value.count > 1 }
    }

    func projectsConflictingWith(_ project: Project) -> [Project] {
        var conflicting: [Project] = []
        for port in project.expectedPorts {
            if let others = portConflicts[port] {
                for other in others where other.id != project.id {
                    if !conflicting.contains(where: { $0.id == other.id }) {
                        conflicting.append(other)
                    }
                }
            }
        }
        return conflicting
    }

    func hasPortConflict(_ project: Project) -> Bool {
        if let port = project.effectivePort {
            return portConflicts[port] != nil
        }
        return false
    }

    func setCustomPort(for project: Project, port: Int?) {
        // Update config
        if let port = port {
            config.customPorts[project.id] = port
        } else {
            config.customPorts.removeValue(forKey: project.id)
        }
        ConfigManager.save(config)

        // Update project in memory
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index].customPort = port
        }
    }
}
