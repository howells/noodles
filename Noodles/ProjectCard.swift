import SwiftUI

struct ProjectCard: View {
    // LEARN: `let` properties on a View struct = props in React. They're passed in by the parent
    // and are immutable within this view. `@State` properties are local mutable state.
    let project: Project
    let onShowLogs: (LogTarget) -> Void
    @EnvironmentObject var appState: AppState
    @State private var showingPortSheet = false
    @State private var portInput = ""
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            // Main project row
            HStack(spacing: 10) {
                // Status indicator / Expand toggle for monorepos
                if project.isMonorepo {
                    Button {
                        // LEARN: `withAnimation` wraps a state change in an animation.
                        // SwiftUI automatically animates any view changes caused by the
                        // state mutation inside this block. Like React's `framer-motion`
                        // but built into the framework — no extra library needed.
                        //
                        // `.toggle()` flips a Bool — like `setExpanded(!expanded)` in React.
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    StatusDot(color: statusColor, size: 8)
                }

                // Project info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(project.name)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)

                        if project.isMonorepo {
                            Text("monorepo")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15))
                                .cornerRadius(3)
                        }
                    }

                    Text(project.displayPath)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Port conflict warning
                if appState.hasPortConflict(project) {
                    ConflictBadge(project: project)
                }

                // Running ports (clickable) or expected ports (dimmed, for stopped)
                if !project.isMonorepo {
                    if project.status == .running && !project.runningPorts.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(project.runningPorts.prefix(3)) { port in
                                PortBadge(port: port.port, isActive: true) {
                                    appState.openInBrowser(port: port.port)
                                }
                            }
                        }
                    } else if project.status == .stopped {
                        // Show custom port (highlighted) or expected port (dimmed)
                        if let customPort = project.customPort {
                            PortBadge(port: customPort, isActive: false, isCustom: true) {}
                        } else if let expectedPort = project.expectedPorts.first {
                            PortBadge(port: expectedPort, isActive: false) {}
                        }
                    }
                }

                // Action buttons - show for non-monorepos, or monorepos with dev command
                if !project.isMonorepo || project.devCommand != nil {
                    let managedServerId = appState.managedServerId(for: project)
                    ActionButtons(
                        project: project,
                        showLogs: managedServerId != nil,
                        onShowLogs: {
                            guard let id = managedServerId else { return }
                            onShowLogs(LogTarget(id: id, title: project.name))
                        }
                    )
                } else {
                    // Just show editor button for monorepos without dev command
                    IconButton(icon: "rectangle.and.pencil.and.ellipsis", help: "Open in editor") {
                        appState.openInEditor(path: project.path)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            // LEARN: `.contentShape(Rectangle())` makes the ENTIRE row tappable/right-clickable,
            // not just the text/icons. Without this, only visible content receives clicks.
            // Like setting `pointer-events: all` on a flex container in CSS.
            .contentShape(Rectangle())
            // LEARN: `.contextMenu` = right-click menu. Like `onContextMenu` in React.
            // SwiftUI builds the menu declaratively — just list the items.
            .contextMenu {
                // Server actions
                if !project.isMonorepo || project.devCommand != nil {
                    if project.status == .running {
                        Button("Restart Server") {
                            appState.restartProject(project)
                        }
                        Button("Stop Server") {
                            appState.stopProject(project)
                        }
                    } else if project.status == .stopped || project.status == .error {
                        Button("Start Server") {
                            appState.startProject(project)
                        }
                    }
                }

                if let managedId = appState.managedServerId(for: project) {
                    Button("View Logs") {
                        onShowLogs(LogTarget(id: managedId, title: project.name))
                    }
                }

                Divider()

                // Open actions
                if project.status == .running, let port = project.browserPort {
                    Button("Open in Browser") {
                        appState.openInBrowser(port: port)
                    }
                }
                Button("Open in Editor") {
                    appState.openInEditor(path: project.path)
                }
                Button("Open in Terminal") {
                    appState.openInTerminal(path: project.path)
                }
                Button("Open in Finder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.path)
                }

                Divider()

                // Organization
                Button(appState.isPinned(project) ? "Unpin" : "Pin to Top") {
                    appState.togglePinned(project)
                }
                Button(appState.isHidden(project) ? "Unhide Project" : "Hide Project") {
                    appState.toggleHidden(project)
                }

                // Port config
                if !project.isMonorepo {
                    Divider()
                    Button("Set Custom Port...") {
                        portInput = project.customPort.map { String($0) } ?? ""
                        showingPortSheet = true
                    }
                    if project.customPort != nil {
                        Button("Clear Custom Port") {
                            appState.setCustomPort(for: project, port: nil)
                        }
                    }
                }
            }

            // Workspaces section (for monorepos)
            if project.isMonorepo && isExpanded {
                VStack(spacing: 2) {
                    ForEach(project.workspaces) { workspace in
                        WorkspaceCard(workspace: workspace, project: project, onShowLogs: onShowLogs)
                    }
                }
                .padding(.leading, 20)
                .padding(.trailing, 4)
                .padding(.vertical, 4)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .opacity(appState.isHidden(project) ? 0.5 : 1.0)
        .sheet(isPresented: $showingPortSheet) {
            PortConfigSheet(project: project, portInput: $portInput, isPresented: $showingPortSheet)
        }
    }

    var statusColor: Color {
        switch project.status {
        case .running: return .green
        case .starting, .stopping, .restarting: return .orange
        case .error: return .red
        case .stopped: return Color.secondary.opacity(0.4)
        }
    }
}

struct LogTarget: Identifiable {
    let id: UUID
    let title: String
}

struct WorkspaceCard: View {
    let workspace: Workspace
    let project: Project
    let onShowLogs: (LogTarget) -> Void
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 8) {
            // Status indicator
            StatusDot(color: statusColor, size: 6)

            // Workspace info
            VStack(alignment: .leading, spacing: 1) {
                Text(workspace.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                Text(workspace.relativePath)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Port badge
            if workspace.status == .running && !workspace.runningPorts.isEmpty {
                ForEach(workspace.runningPorts.prefix(2)) { port in
                    PortBadge(port: port.port, isActive: true) {
                        appState.openInBrowser(port: port.port)
                    }
                }
            } else if workspace.status == .stopped, let port = workspace.effectivePort {
                PortBadge(port: port, isActive: false) {}
            }

            // Action buttons
            let managedServerId = appState.managedServerId(for: workspace)
            WorkspaceActionButtons(
                workspace: workspace,
                project: project,
                showLogs: managedServerId != nil,
                onShowLogs: {
                    guard let id = managedServerId else { return }
                    onShowLogs(LogTarget(id: id, title: "\(project.name)/\(workspace.name)"))
                }
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))
        )
        .contextMenu {
            // Server actions
            if workspace.status == .running {
                Button("Stop Server") {
                    appState.stopWorkspace(workspace, in: project)
                }
            } else if workspace.status == .stopped || workspace.status == .error {
                Button("Start Server") {
                    appState.startWorkspace(workspace, in: project)
                }
            }

            if let managedId = appState.managedServerId(for: workspace) {
                Button("View Logs") {
                    onShowLogs(LogTarget(id: managedId, title: "\(project.name)/\(workspace.name)"))
                }
            }

            Divider()

            // Open actions
            if workspace.status == .running, let port = workspace.runningPorts.first?.port ?? workspace.effectivePort {
                Button("Open in Browser") {
                    appState.openInBrowser(port: port)
                }
            }
            Button("Open in Editor") {
                appState.openInEditor(path: workspace.path)
            }
            Button("Open in Terminal") {
                appState.openInTerminal(path: workspace.path)
            }
            Button("Open in Finder") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: workspace.path)
            }
        }
    }

    var statusColor: Color {
        switch workspace.status {
        case .running: return .green
        case .starting, .stopping, .restarting: return .orange
        case .error: return .red
        case .stopped: return Color.secondary.opacity(0.4)
        }
    }
}

struct StatusDot: View {
    static let containerSize: CGFloat = 24
    let color: Color
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .frame(width: Self.containerSize, height: Self.containerSize)
    }
}

struct WorkspaceActionButtons: View {
    let workspace: Workspace
    let project: Project
    let showLogs: Bool
    let onShowLogs: () -> Void
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 2) {
            if workspace.status == .starting || workspace.status == .stopping {
                ProgressView()
                    .scaleEffect(0.4)
                    .frame(width: 18, height: 18)
            } else if workspace.status == .running {
                if showLogs {
                    SmallIconButton(icon: "terminal", help: "View logs") {
                        onShowLogs()
                    }
                }

                // Open in browser
                if let port = workspace.runningPorts.first?.port ?? workspace.effectivePort {
                    SmallIconButton(icon: "globe", help: "Open localhost:\(port)") {
                        appState.openInBrowser(port: port)
                    }
                }

                // Open in editor
                SmallIconButton(icon: "rectangle.and.pencil.and.ellipsis", help: "Open in editor") {
                    appState.openInEditor(path: workspace.path)
                }

                // Stop
                SmallIconButton(icon: "stop.fill", help: "Stop", color: .red) {
                    appState.stopWorkspace(workspace, in: project)
                }
            } else {
                if showLogs {
                    SmallIconButton(icon: "terminal", help: "View logs") {
                        onShowLogs()
                    }
                }

                // Open in editor
                SmallIconButton(icon: "rectangle.and.pencil.and.ellipsis", help: "Open in editor") {
                    appState.openInEditor(path: workspace.path)
                }

                // Start
                SmallIconButton(icon: "play.fill", help: "Start", color: .green) {
                    appState.startWorkspace(workspace, in: project)
                }
            }
        }
    }
}

struct SmallIconButton: View {
    let icon: String
    let help: String
    var color: Color = .secondary
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(isHovering ? color : .secondary)
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isHovering ? color.opacity(0.15) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

struct PortBadge: View {
    let port: Int
    var isActive: Bool = true
    var isCustom: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: "\(port)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(badgeColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(backgroundColor)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .disabled(!isActive)
        .help(helpText)
    }

    var badgeColor: Color {
        if isActive { return .secondary }
        if isCustom { return .blue.opacity(0.8) }
        return .secondary.opacity(0.5)
    }

    var backgroundColor: Color {
        if isActive { return Color.secondary.opacity(0.15) }
        if isCustom { return Color.blue.opacity(0.12) }
        return Color.secondary.opacity(0.08)
    }

    var helpText: String {
        if isActive { return "Open localhost:\(port)" }
        if isCustom { return "Custom port: \(port)" }
        return "Expected port: \(port)"
    }
}

struct ConflictBadge: View {
    let project: Project
    @EnvironmentObject var appState: AppState

    var body: some View {
        let conflicting = appState.projectsConflictingWith(project)
        let conflictingNames = conflicting.map { $0.name }.joined(separator: ", ")

        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 11))
            .foregroundColor(.orange)
            .help("Port conflict with: \(conflictingNames)")
    }
}

struct ActionButtons: View {
    let project: Project
    let showLogs: Bool
    let onShowLogs: () -> Void
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 2) {
            if project.status == .starting || project.status == .restarting {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 26, height: 26)
            } else if project.status == .stopping {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 26, height: 26)
            } else if project.status == .running {
                if showLogs {
                    IconButton(icon: "terminal", help: "View logs") {
                        onShowLogs()
                    }
                }

                // Open in browser (custom port takes precedence)
                if let port = project.browserPort {
                    IconButton(icon: "globe", help: "Open localhost:\(port)") {
                        appState.openInBrowser(port: port)
                    }
                }

                // Open in editor
                IconButton(icon: "rectangle.and.pencil.and.ellipsis", help: "Open in editor") {
                    appState.openInEditor(path: project.path)
                }

                // Restart
                IconButton(icon: "arrow.clockwise", help: "Restart") {
                    appState.restartProject(project)
                }

                // Stop
                IconButton(icon: "stop.fill", help: "Stop", color: .red) {
                    appState.stopProject(project)
                }
            } else {
                if showLogs {
                    IconButton(icon: "terminal", help: "View logs") {
                        onShowLogs()
                    }
                }

                // Open in editor
                IconButton(icon: "rectangle.and.pencil.and.ellipsis", help: "Open in editor") {
                    appState.openInEditor(path: project.path)
                }

                // Start
                IconButton(icon: "play.fill", help: "Start", color: .green) {
                    appState.startProject(project)
                }
            }
        }
    }
}

struct IconButton: View {
    let icon: String
    let help: String
    var color: Color = .secondary
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isHovering ? color : .secondary)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovering ? color.opacity(0.15) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

struct PortConfigSheet: View {
    let project: Project
    @Binding var portInput: String
    @Binding var isPresented: Bool
    @EnvironmentObject var appState: AppState
    @FocusState private var isFocused: Bool

    private var isValid: Bool {
        guard let port = Int(portInput) else { return false }
        return port >= 1 && port <= 65535
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text(project.name)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if let expected = project.expectedPorts.first {
                    Text("detected: \(expected)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            // Input row
            HStack(spacing: 8) {
                TextField("Port", text: $portInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 24, weight: .medium, design: .monospaced))
                    .focused($isFocused)
                    .onSubmit { if isValid { save() } }
                    .frame(maxWidth: .infinity)

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)

                Button {
                    save()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 24, height: 24)
                        .background(isValid ? Color.accentColor : Color.secondary.opacity(0.3))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }

            // Validation hint
            if !portInput.isEmpty && !isValid {
                Text("Enter a port between 1–65535")
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
            }
        }
        .padding(16)
        .frame(width: 280)
        .background(Color(NSColor.controlBackgroundColor))
        .onAppear {
            isFocused = true
        }
    }

    func save() {
        if let port = Int(portInput) {
            appState.setCustomPort(for: project, port: port)
        }
        isPresented = false
    }
}

struct ServerLogView: View {
    @EnvironmentObject var appState: AppState
    let serverId: UUID
    let title: String?
    let onClose: () -> Void
    @State private var logLines: [String] = []
    @State private var autoFollow = true
    @State private var isStopping = false
    @State private var logTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            // Compact header
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Text(serverTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)

                    Spacer()

                    // Port badge (clickable to open in browser)
                    if let info = serverInfo, let port = info.port {
                        PortBadge(port: port, isActive: info.isRunning) {
                            appState.openInBrowser(port: port)
                        }
                    }

                    // Auto-follow toggle (highlighted when active)
                    Button {
                        autoFollow.toggle()
                    } label: {
                        Image(systemName: "arrow.down.to.line")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(autoFollow ? .accentColor : .secondary)
                            .frame(width: 26, height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(autoFollow ? Color.accentColor.opacity(0.12) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(autoFollow ? "Auto-follow on" : "Auto-follow off")

                    // Stop button (only when running)
                    if let info = serverInfo, info.isRunning {
                        if isStopping {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 26, height: 26)
                        } else {
                            IconButton(icon: "stop.fill", help: "Stop server", color: .red) {
                                isStopping = true
                                appState.stopManagedServer(id: serverId)
                            }
                        }
                    }

                    // Close
                    IconButton(icon: "xmark", help: "Close") {
                        onClose()
                    }
                }

                // Status line with colored dot
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                    Text(statusText)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // Log output
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if logLines.isEmpty {
                            Text("No output yet")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(logLines.indices, id: \.self) { idx in
                                Text(LogFormatter.format(logLines[idx]))
                                    .font(.system(size: 11, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(idx)
                            }
                        }
                    }
                    .padding(12)
                }
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .onChange(of: logLines.count) { _ in
                    guard autoFollow, let last = logLines.indices.last else { return }
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            startLogTask()
        }
        .onDisappear {
            logTask?.cancel()
            logTask = nil
        }
        .onChange(of: serverInfo?.isRunning ?? false) { running in
            if running {
                isStopping = false
            } else if isStopping {
                isStopping = false
            }
        }
    }

    private var serverInfo: ManagedServerInfo? {
        appState.managedServerInfo(id: serverId)
    }

    private var serverTitle: String {
        title ?? serverInfo?.label ?? "Server Logs"
    }

    private var statusColor: Color {
        guard let info = serverInfo else { return Color.secondary.opacity(0.4) }
        if isStopping { return .orange }
        if info.isRunning { return .green }
        if let exitCode = info.exitCode, exitCode != 0, info.stopRequestedAt == nil {
            return .red
        }
        return Color.secondary.opacity(0.4)
    }

    private var statusText: String {
        guard let info = serverInfo else { return "Unknown" }
        if isStopping { return "Stopping..." }
        if info.isRunning { return "Running" }
        if info.stopRequestedAt != nil { return "Stopped" }
        if let exitCode = info.exitCode {
            return exitCode == 0 ? "Stopped" : "Exited with code \(exitCode)"
        }
        return "Stopped"
    }

    private func startLogTask() {
        logTask?.cancel()
        logTask = Task {
            while !Task.isCancelled {
                let snapshot = await appState.logSnapshot(id: serverId, tail: 500)
                await MainActor.run {
                    self.logLines = snapshot
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }
}
