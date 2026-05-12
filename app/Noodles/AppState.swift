import SwiftUI
import ServiceManagement

extension Notification.Name {
    static let popoverResize = Notification.Name("PopoverResize")
    static let serversDidChange = Notification.Name("ServersDidChange")
}

@MainActor
class AppState: ObservableObject {
    @Published var projects: [ServerItem] = []
    @Published var activeLogPath: String?
    @Published var activeLogName: String?
    @Published var activeLogServerId: String?
    @Published var isKilling: Set<String> = []
    @Published var isRefreshing: Bool = false
    @Published var launchOnLogin: Bool = true

    private var cachedProjects: [CachedProject] = []
    var pollTimer: Timer?
    private var isPolling: Bool = false

    init() {
        cachedProjects = ProjectCache.load()
        syncLaunchOnLoginState()
        startPolling()
    }

    func startPolling() {
        backgroundPoll()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.backgroundPoll() }
        }
    }

    private func backgroundPoll() {
        guard !isPolling else { return }
        isPolling = true
        Task {
            let runningServers = await PortMonitor.scan()

            // Update cache with running servers
            let now = Date()
            for server in runningServers {
                if let idx = cachedProjects.firstIndex(where: { $0.path == server.id }) {
                    cachedProjects[idx].lastSeen = now
                } else {
                    cachedProjects.append(CachedProject(
                        path: server.id,
                        name: server.name,
                        displayPath: server.displayPath,
                        lastSeen: now
                    ))
                }
            }
            ProjectCache.save(cachedProjects)

            // Merge: running servers + cached stopped projects
            let runningIds = Set(runningServers.map(\.id))
            isKilling = isKilling.intersection(runningIds)

            var items: [ServerItem] = runningServers.map { server in
                ServerItem(
                    id: server.id,
                    name: server.name,
                    path: server.path,
                    displayPath: server.displayPath,
                    isRunning: true,
                    ports: server.ports,
                    pids: server.pids,
                    hasLogs: server.hasLogs,
                    terminalApp: server.terminalApp
                )
            }

            for cached in cachedProjects where !runningIds.contains(cached.path) {
                let logFile = PortMonitor.logDir.appendingPathComponent("\(cached.name).log")
                let hasLogs = FileManager.default.fileExists(atPath: logFile.path)
                items.append(ServerItem(
                    id: cached.path,
                    name: cached.name,
                    path: cached.path,
                    displayPath: cached.displayPath,
                    isRunning: false,
                    ports: [],
                    pids: [],
                    hasLogs: hasLogs,
                    terminalApp: nil
                ))
            }

            // Sort: running first (by port), then stopped (alphabetical)
            items.sort { a, b in
                if a.isRunning != b.isRunning { return a.isRunning }
                if a.isRunning { return (a.ports.first ?? 0) < (b.ports.first ?? 0) }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }

            projects = items
            isPolling = false
            isRefreshing = false
            NotificationCenter.default.post(name: .serversDidChange, object: nil)
        }
    }

    func poll() {
        isRefreshing = true
        backgroundPoll()
    }

    func kill(server: ServerItem) {
        isKilling.insert(server.id)
        Task {
            await ProcessKiller.killTree(pids: server.pids)
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            isKilling.remove(server.id)
        }
    }

    func forget(project: ServerItem) {
        cachedProjects.removeAll { $0.path == project.id }
        ProjectCache.save(cachedProjects)
        projects.removeAll { $0.id == project.id }
    }

    func openInBrowser(port: Int) {
        guard let url = URL(string: "http://localhost:\(port)") else { return }
        NSWorkspace.shared.open(url)
    }

    func revealTerminal(bundleId: String) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else { return }
        app.activate(options: .activateIgnoringOtherApps)
    }

    func toggleLog(project: ServerItem) {
        if activeLogServerId == project.id {
            closeLog()
        } else {
            let logFile = PortMonitor.logDir.appendingPathComponent("\(project.name).log")
            activeLogPath = logFile.path
            activeLogName = project.name
            activeLogServerId = project.id
        }
    }

    func closeLog() {
        activeLogPath = nil
        activeLogName = nil
        activeLogServerId = nil
    }

    var isLogServerRunning: Bool {
        guard let id = activeLogServerId else { return false }
        return projects.contains { $0.id == id && $0.isRunning }
    }

    func syncLaunchOnLoginState() {
        launchOnLogin = SMAppService.mainApp.status == .enabled
    }

    func toggleLaunchOnLogin() {
        do {
            if launchOnLogin {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Noodles: Failed to toggle launch on login: \(error)")
        }
        syncLaunchOnLoginState()
    }
}
