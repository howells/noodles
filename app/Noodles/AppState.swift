import SwiftUI
import ServiceManagement

extension Notification.Name {
    static let popoverResize = Notification.Name("PopoverResize")
    static let serversDidChange = Notification.Name("ServersDidChange")
}

@MainActor
class AppState: ObservableObject {
    @Published var servers: [RunningServer] = []
    @Published var activeLogPath: String?
    @Published var activeLogName: String?
    @Published var activeLogServerId: String?
    @Published var isKilling: Set<String> = []
    @Published var isRefreshing: Bool = false
    @Published var launchOnLogin: Bool = true

    var pollTimer: Timer?
    private var isPolling: Bool = false

    init() {
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
            let newServers = await PortMonitor.scan()
            let serverIds = Set(newServers.map(\.id))
            isKilling = isKilling.intersection(serverIds)
            servers = newServers
            isPolling = false
            isRefreshing = false
            NotificationCenter.default.post(name: .serversDidChange, object: nil)
        }
    }

    func poll() {
        isRefreshing = true
        backgroundPoll()
    }

    func kill(server: RunningServer) {
        isKilling.insert(server.id)
        Task {
            await ProcessKiller.killTree(pids: server.pids)
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            isKilling.remove(server.id)
        }
    }

    func openInBrowser(port: Int) {
        guard let url = URL(string: "http://localhost:\(port)") else { return }
        NSWorkspace.shared.open(url)
    }

    func revealTerminal(bundleId: String) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else { return }
        app.activate(options: .activateIgnoringOtherApps)
    }

    func toggleLog(server: RunningServer) {
        if activeLogServerId == server.id {
            closeLog()
        } else {
            let logFile = PortMonitor.logDir.appendingPathComponent("\(server.name).log")
            activeLogPath = logFile.path
            activeLogName = server.name
            activeLogServerId = server.id
        }
    }

    func closeLog() {
        activeLogPath = nil
        activeLogName = nil
        activeLogServerId = nil
    }

    var isLogServerRunning: Bool {
        guard let id = activeLogServerId else { return false }
        return servers.contains { $0.id == id }
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
