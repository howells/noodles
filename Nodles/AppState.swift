import Foundation
import Combine

@MainActor
class AppState: ObservableObject {
    @Published var projects: [Project] = []
    @Published var ports: [PortInfo] = []
    @Published var isScanning = false
    @Published var filter = ""
    @Published var config: Config

    private var portPollingTimer: Timer?
    private let processManager = ProcessManager()
    private let scanner = ProjectScanner()

    init() {
        self.config = ConfigManager.load()
    }

    func scan() {
        NSLog("Nodles: scan() called")
        isScanning = true

        var scannedProjects = scanner.scan(sitesPath: config.sitesPath)
        NSLog("Nodles: Got %d scanned projects", scannedProjects.count)

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

        NSLog("Nodles: Set projects array, count = %d", self.projects.count)
        self.isScanning = false

        // Start port polling after initial load
        startPortPolling()
    }

    func startProject(_ project: Project) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[index].status = .starting

        Task {
            do {
                try await processManager.startDevServer(
                    path: project.path,
                    packageManager: project.packageManager,
                    customPort: project.customPort
                )
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

    func restartProject(_ project: Project) {
        stopProject(project)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.startProject(project)
        }
    }

    func openInBrowser(port: Int) {
        processManager.openInBrowser(port: port)
    }

    func openInEditor(path: String) {
        processManager.openInEditor(path: path, editor: config.editor)
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

            await MainActor.run {
                self.ports = currentPorts

                // Create updated projects array to trigger SwiftUI update
                var updatedProjects = self.projects

                for i in updatedProjects.indices {
                    let projectPorts = currentPorts.filter { port in
                        guard let cwd = port.cwd else { return false }
                        return cwd.hasPrefix(updatedProjects[i].path)
                    }

                    updatedProjects[i].runningPorts = projectPorts

                    if updatedProjects[i].status == .starting || updatedProjects[i].status == .stopping {
                        if !projectPorts.isEmpty && updatedProjects[i].status == .starting {
                            updatedProjects[i].status = .running
                        } else if projectPorts.isEmpty && updatedProjects[i].status == .stopping {
                            updatedProjects[i].status = .stopped
                        }
                    } else if updatedProjects[i].status != .error {
                        updatedProjects[i].status = projectPorts.isEmpty ? .stopped : .running
                    }
                }

                // Assign new array to trigger @Published update
                self.projects = updatedProjects
            }
        }
    }

    var filteredProjects: [Project] {
        if filter.isEmpty {
            return projects
        }
        return projects.filter {
            $0.name.localizedCaseInsensitiveContains(filter) ||
            $0.path.localizedCaseInsensitiveContains(filter)
        }
    }

    var runningProjects: [Project] {
        filteredProjects.filter { $0.status == .running }
    }

    var stoppedProjects: [Project] {
        filteredProjects.filter { $0.status != .running }
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
