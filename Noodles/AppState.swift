import AppKit
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
    @Published var managedServers: [ManagedServerInfo] = []
    @Published var isScanning = false
    @Published var filter = ""
    @Published var config: Config
    @Published var showHidden = false

    // Exposed for cleanup in applicationWillTerminate
    var portPollingTimer: Timer?
    let processManager = ProcessManager()

    private let scanner = ProjectScanner()
    private var managedProjectServers: [String: UUID] = [:]
    private var managedWorkspaceServers: [String: UUID] = [:]
    private var isPolling = false

    init() {
        self.config = ConfigManager.load()
    }

    deinit {
        portPollingTimer?.invalidate()
        portPollingTimer = nil
    }

    // MARK: - Scanning

    func scan() {
        guard !isScanning else { return }
        NSLog("Noodles: scan() called")
        isScanning = true

        // Capture config as a value type before entering the detached task
        let capturedConfig = config

        Task.detached { [scanner] in
            let scannedProjects = scanner.scan(sitesPath: capturedConfig.sitesPath)
            NSLog("Noodles: Got %d scanned projects", scannedProjects.count)

            await MainActor.run { [weak self] in
                guard let self else { return }
                var projects = scannedProjects
                for i in projects.indices {
                    if let customPort = capturedConfig.customPorts[projects[i].id] {
                        projects[i].customPort = customPort
                    }
                }
                self.projects = projects.sorted { a, b in
                    a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                }
                NSLog("Noodles: Set projects array, count = %d", self.projects.count)
                self.isScanning = false
                self.startPortPolling()
            }
        }
    }

    // MARK: - Project Start/Stop

    func startProject(_ project: Project) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        if projects[index].status != .restarting {
            projects[index].status = .starting
        }
        projects[index].error = nil

        var args = [project.packageManager.command] + project.packageManager.devArgs
        if let port = project.customPort {
            args.append("--port")
            args.append(String(port))
        }
        let devCommand = args.joined(separator: " ")

        if config.runManagedServers {
            Task {
                do {
                    // Clean up old managed server if restarting
                    if let oldId = self.managedProjectServers[project.id] {
                        await processManager.removeManagedServer(id: oldId)
                    }

                    let id = try await processManager.startManagedServer(
                        path: project.path,
                        packageManager: project.packageManager,
                        customPort: project.customPort,
                        label: project.name
                    )
                    self.managedProjectServers[project.id] = id
                } catch {
                    if let idx = self.projects.firstIndex(where: { $0.id == project.id }) {
                        self.projects[idx].status = .error
                        self.projects[idx].error = error.localizedDescription
                    }
                }
            }
        } else {
            processManager.openInTerminal(path: project.path, terminal: config.terminal, command: devCommand)
            refocusSelf()
        }
    }

    func stopProject(_ project: Project) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[index].status = .stopping

        if let serverId = managedProjectServers[project.id] {
            Task {
                await processManager.stopManagedServer(id: serverId)
            }
            return
        }

        Task {
            do {
                try await processManager.stopProjectProcesses(projectPath: project.path)
            } catch {
                if let idx = self.projects.firstIndex(where: { $0.id == project.id }) {
                    self.projects[idx].status = .error
                    self.projects[idx].error = error.localizedDescription
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
        projects[projectIndex].workspaces[workspaceIndex].error = nil

        let args = [project.packageManager.command] + project.packageManager.workspaceDevArgs(filter: workspace.name)
        let devCommand = args.joined(separator: " ")

        if config.runManagedServers {
            Task {
                do {
                    // Clean up old managed server if restarting
                    if let oldId = self.managedWorkspaceServers[workspace.id] {
                        await processManager.removeManagedServer(id: oldId)
                    }

                    let id = try await processManager.startManagedServer(
                        path: project.path,
                        packageManager: project.packageManager,
                        customPort: nil,
                        filterWorkspace: workspace.name,
                        label: "\(project.name)/\(workspace.name)"
                    )
                    self.managedWorkspaceServers[workspace.id] = id
                } catch {
                    if let pIdx = self.projects.firstIndex(where: { $0.id == project.id }),
                       let wIdx = self.projects[pIdx].workspaces.firstIndex(where: { $0.id == workspace.id }) {
                        self.projects[pIdx].workspaces[wIdx].status = .error
                        self.projects[pIdx].workspaces[wIdx].error = error.localizedDescription
                    }
                }
            }
        } else {
            processManager.openInTerminal(path: project.path, terminal: config.terminal, command: devCommand)
            refocusSelf()
        }
    }

    func stopWorkspace(_ workspace: Workspace, in project: Project) {
        guard let projectIndex = projects.firstIndex(where: { $0.id == project.id }),
              let workspaceIndex = projects[projectIndex].workspaces.firstIndex(where: { $0.id == workspace.id }) else {
            return
        }

        projects[projectIndex].workspaces[workspaceIndex].status = .stopping

        if let serverId = managedWorkspaceServers[workspace.id] {
            Task {
                await processManager.stopManagedServer(id: serverId)
            }
            return
        }

        Task {
            do {
                try await processManager.stopProjectProcesses(projectPath: workspace.path)
            } catch {
                if let pIdx = self.projects.firstIndex(where: { $0.id == project.id }),
                   let wIdx = self.projects[pIdx].workspaces.firstIndex(where: { $0.id == workspace.id }) {
                    self.projects[pIdx].workspaces[wIdx].status = .error
                    self.projects[pIdx].workspaces[wIdx].error = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Restart

    func restartProject(_ project: Project) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[index].status = .restarting

        if let serverId = managedProjectServers[project.id] {
            Task {
                await processManager.stopManagedServer(id: serverId)
                do {
                    try await Task.sleep(nanoseconds: 500_000_000)
                } catch {
                    // Task.sleep cancelled — check if we should abort (e.g., app terminating)
                    guard !Task.isCancelled else { return }
                }
                self.managedProjectServers.removeValue(forKey: project.id)
                self.startProject(project)
            }
            return
        }

        Task {
            do {
                try await processManager.stopProjectProcesses(projectPath: project.path)
                try await Task.sleep(nanoseconds: 500_000_000)
                self.startProject(project)
            } catch {
                if !Task.isCancelled {
                    if let idx = self.projects.firstIndex(where: { $0.id == project.id }) {
                        self.projects[idx].status = .error
                        self.projects[idx].error = error.localizedDescription
                    }
                }
            }
        }
    }

    // MARK: - External Actions

    func openInBrowser(port: Int) {
        processManager.openInBrowser(port: port)
    }

    func openInEditor(path: String) {
        if config.editor == "claude-code" {
            processManager.openInTerminal(path: path, terminal: config.terminal, command: "claude")
        } else {
            processManager.openInEditor(path: path, editor: config.editor)
        }
    }

    func openInTerminal(path: String, command: String? = nil) {
        processManager.openInTerminal(path: path, terminal: config.terminal, command: command)
    }

    func managedServerId(for project: Project) -> UUID? {
        managedProjectServers[project.id]
    }

    func managedServerId(for workspace: Workspace) -> UUID? {
        managedWorkspaceServers[workspace.id]
    }

    func managedServerInfo(id: UUID) -> ManagedServerInfo? {
        managedServers.first { $0.id == id }
    }

    func stopManagedServer(id: UUID, force: Bool = false) {
        Task {
            await processManager.stopManagedServer(id: id, force: force)
        }
    }

    func logSnapshot(id: UUID, tail: Int) async -> [String] {
        await processManager.getLogSnapshot(id: id, tail: tail)
    }

    // MARK: - Port Polling

    private func startPortPolling() {
        // Initial port refresh
        refreshPorts()

        let interval = max(0.5, Double(config.pollIntervalMs) / 1000.0)
        portPollingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.refreshPorts()
            }
        }
    }

    /// Refresh port data from lsof. Guarded so only one poll runs at a time —
    /// if the previous poll is still in-flight, this call is skipped.
    private func refreshPorts() {
        guard !isPolling else { return }
        isPolling = true

        Task {
            let currentPorts = await processManager.getListeningPorts()
            let currentManagedServers = await processManager.getManagedServers()
            let managedById = Dictionary(uniqueKeysWithValues: currentManagedServers.map { ($0.id, $0) })

            self.ports = currentPorts
            self.managedServers = currentManagedServers

            var updatedProjects = self.projects

            for i in updatedProjects.indices {
                var project = updatedProjects[i]
                let projectPorts = currentPorts.filter { port in
                    guard let cwd = port.cwd else { return false }
                    return cwd.hasPrefix(project.path)
                }

                project.runningPorts = projectPorts

                // Update workspace statuses for monorepos
                for j in project.workspaces.indices {
                    var workspace = project.workspaces[j]
                    let workspacePath = workspace.path
                    let workspaceRelPath = workspace.relativePath

                    var workspacePorts = currentPorts.filter { port in
                        guard let cwd = port.cwd else { return false }
                        if cwd.hasPrefix(workspacePath) { return true }
                        if cwd.hasPrefix(project.path) && cwd.contains(workspaceRelPath) { return true }
                        return false
                    }

                    // Fallback: match by expected port for turbo dev
                    if workspacePorts.isEmpty {
                        let expectedPorts = Set(workspace.expectedPorts)
                        if !expectedPorts.isEmpty {
                            workspacePorts = currentPorts.filter { port in
                                guard expectedPorts.contains(port.port) else { return false }
                                if let cwd = port.cwd {
                                    return cwd.hasPrefix(project.path)
                                }
                                return true
                            }
                        }
                    }

                    workspace.runningPorts = workspacePorts

                    if workspace.status == .starting || workspace.status == .stopping {
                        if !workspacePorts.isEmpty && workspace.status == .starting {
                            workspace.status = .running
                        } else if workspacePorts.isEmpty && workspace.status == .stopping {
                            workspace.status = .stopped
                        }
                    } else if workspace.status != .error {
                        workspace.status = workspacePorts.isEmpty ? .stopped : .running
                    }

                    if let serverId = managedWorkspaceServers[workspace.id],
                       let managedInfo = managedById[serverId] {
                        var status = workspace.status
                        var error = workspace.error
                        applyManagedStatus(managedInfo, status: &status, error: &error)
                        workspace.status = status
                        workspace.error = error
                    }

                    project.workspaces[j] = workspace
                }

                if !project.isMonorepo {
                    let wasStarting = project.status == .starting

                    if project.status == .starting || project.status == .stopping || project.status == .restarting {
                        if !projectPorts.isEmpty && (project.status == .starting || project.status == .restarting) {
                            project.status = .running
                        } else if projectPorts.isEmpty && project.status == .stopping {
                            project.status = .stopped
                        }
                        // .restarting with no ports yet → stays .restarting
                    } else if project.status != .error {
                        project.status = projectPorts.isEmpty ? .stopped : .running
                    }

                    if let serverId = managedProjectServers[project.id],
                       let managedInfo = managedById[serverId] {
                        // While starting with no ports: process is alive but dev server
                        // hasn't bound a port yet. Stay .starting unless process died.
                        if wasStarting && projectPorts.isEmpty && managedInfo.isRunning && managedInfo.stopRequestedAt == nil {
                            project.status = .starting
                        } else {
                            var status = project.status
                            var error = project.error
                            applyManagedStatus(managedInfo, status: &status, error: &error)
                            project.status = status
                            project.error = error
                        }
                    }
                } else {
                    // Monorepo: check project-level managed server first (from startProject/restartProject)
                    if let serverId = managedProjectServers[project.id],
                       let managedInfo = managedById[serverId] {
                        var status = project.status
                        var error = project.error
                        applyManagedStatus(managedInfo, status: &status, error: &error)
                        project.status = status
                        project.error = error
                    } else {
                        // No project-level managed server — derive from workspace states
                        let anyWorkspaceRunning = project.workspaces.contains { $0.status == .running }
                        if project.status == .restarting {
                            // Only exit .restarting when a workspace comes up
                            if anyWorkspaceRunning { project.status = .running }
                        } else if project.status != .error {
                            if anyWorkspaceRunning {
                                project.status = .running
                            } else {
                                project.status = .stopped
                            }
                        }
                    }
                }

                updatedProjects[i] = project
            }

            self.projects = updatedProjects
            self.isPolling = false
        }
    }

    private func applyManagedStatus(_ info: ManagedServerInfo, status: inout ProjectStatus, error: inout String?) {
        // During restart, only allow transition to .running (when the new server is up)
        if status == .restarting {
            if info.isRunning && info.stopRequestedAt == nil {
                status = .running
                error = nil
            }
            return
        }

        if info.isRunning {
            status = info.stopRequestedAt == nil ? .running : .stopping
            error = nil
            return
        }

        if let exitCode = info.exitCode {
            if exitCode == 0 || info.stopRequestedAt != nil {
                status = .stopped
                error = nil
            } else {
                status = .error
                error = "Exited with code \(exitCode)"
            }
            return
        }

        if info.stopRequestedAt != nil {
            status = .stopped
            error = nil
            return
        }

        if status != .starting && status != .stopping {
            status = .stopped
        }
    }

    // MARK: - Computed Properties

    var filteredProjects: [Project] {
        var result = projects

        if !showHidden {
            result = result.filter { !isHidden($0) }
        }

        if !filter.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(filter) ||
                $0.path.localizedCaseInsensitiveContains(filter)
            }
        }

        return result
    }

    var runningProjects: [Project] {
        filteredProjects.filter {
            $0.status == .running || $0.status == .restarting || $0.status == .stopping
        }
    }

    var stoppedProjects: [Project] {
        filteredProjects.filter {
            $0.status != .running && $0.status != .restarting && $0.status != .stopping
        }
    }

    var unmatchedPorts: [PortInfo] {
        var matched = Set<String>()
        for project in projects {
            matched.formUnion(project.runningPorts.map { $0.id })
            for workspace in project.workspaces {
                matched.formUnion(workspace.runningPorts.map { $0.id })
            }
        }
        return ports.filter { !matched.contains($0.id) }
    }

    var pinnedProjects: [Project] {
        filteredProjects.filter { isPinned($0) }
    }

    // MARK: - Pinned Projects

    func isPinned(_ project: Project) -> Bool {
        config.pinned.contains(project.id)
    }

    func togglePinned(_ project: Project) {
        if isPinned(project) {
            config.pinned.removeAll { $0 == project.id }
        } else {
            config.pinned.append(project.id)
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

    // MARK: - Port Conflicts

    var portConflicts: [Int: [Project]] {
        var portToProjects: [Int: [Project]] = [:]

        for project in projects {
            if let port = project.effectivePort {
                portToProjects[port, default: []].append(project)
            }
        }

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

    private func refocusSelf() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func setCustomPort(for project: Project, port: Int?) {
        if let port = port {
            config.customPorts[project.id] = port
        } else {
            config.customPorts.removeValue(forKey: project.id)
        }
        ConfigManager.save(config)

        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index].customPort = port
        }
    }
}
