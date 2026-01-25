import SwiftUI

struct ProjectCard: View {
    let project: Project
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
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 12, height: 12)
                    }
                    .buttonStyle(.plain)
                } else {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
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
                    ActionButtons(project: project)
                } else {
                    // Just show editor button for monorepos without dev command
                    IconButton(icon: "rectangle.and.pencil.and.ellipsis", help: "Open in editor") {
                        appState.openInEditor(path: project.path)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .contextMenu {
                Button(appState.isFavorite(project) ? "Remove from Favorites" : "Add to Favorites") {
                    appState.toggleFavorite(project)
                }
                Button(appState.isHidden(project) ? "Unhide Project" : "Hide Project") {
                    appState.toggleHidden(project)
                }
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
                Divider()
                Button("Open in Finder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.path)
                }
                Button("Open in Terminal") {
                    appState.openInTerminal(path: project.path)
                }
            }

            // Workspaces section (for monorepos)
            if project.isMonorepo && isExpanded {
                VStack(spacing: 2) {
                    ForEach(project.workspaces) { workspace in
                        WorkspaceCard(workspace: workspace, project: project)
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
        case .starting, .stopping: return .orange
        case .error: return .red
        case .stopped: return Color.secondary.opacity(0.4)
        }
    }
}

struct WorkspaceCard: View {
    let workspace: Workspace
    let project: Project
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 8) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

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
            WorkspaceActionButtons(workspace: workspace, project: project)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))
        )
        .contextMenu {
            Button("Open in Finder") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: workspace.path)
            }
            Button("Open in Terminal") {
                appState.openInTerminal(path: workspace.path)
            }
        }
    }

    var statusColor: Color {
        switch workspace.status {
        case .running: return .green
        case .starting, .stopping: return .orange
        case .error: return .red
        case .stopped: return Color.secondary.opacity(0.4)
        }
    }
}

struct WorkspaceActionButtons: View {
    let workspace: Workspace
    let project: Project
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 2) {
            if workspace.status == .starting || workspace.status == .stopping {
                ProgressView()
                    .scaleEffect(0.4)
                    .frame(width: 18, height: 18)
            } else if workspace.status == .running {
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
            Text("\(port)")
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
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 2) {
            if project.status == .starting {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 20, height: 20)
            } else if project.status == .stopping {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 20, height: 20)
            } else if project.status == .running {
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

    var body: some View {
        VStack(spacing: 16) {
            Text("Set Port for \(project.name)")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                TextField("Port number", text: $portInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    .focused($isFocused)
                    .onSubmit { save() }

                if let expected = project.expectedPorts.first {
                    Text("Detected port: \(expected)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(portInput.isEmpty || Int(portInput) == nil)
            }
        }
        .padding(20)
        .frame(width: 280)
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
