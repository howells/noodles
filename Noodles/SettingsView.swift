import SwiftUI

// LEARN: Tuples can't be used with @State because they don't conform to Equatable in the way
// SwiftUI needs. A lightweight struct solves this while keeping things simple.
struct AppOption: Identifiable {
    let id: String
    let name: String
    let installed: Bool
}

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    // LEARN: These @State vars are local COPIES of the config values.
    // On `.onAppear`, they're populated from appState.config.
    // On save, they're written back. This is a common pattern for "draft" state —
    // the user can edit freely and only commit on save (or discard by closing).
    // In React, you'd do: `const [sitesPath, setSitesPath] = useState(config.sitesPath)`
    @State private var sitesPath: String = ""
    @State private var selectedEditor: String = ""
    @State private var selectedTerminal: String = ""
    @State private var runManagedServers: Bool = false

    // LEARN: Computed once in onAppear instead of every render — avoids repeated
    // filesystem I/O (FileManager.fileExists) on the main thread during re-renders.
    @State private var editorOptions: [AppOption] = []
    @State private var terminalOptions: [AppOption] = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Content
            ScrollView {
                VStack(spacing: 12) {
                    // Projects Directory
                    SettingsCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Projects Directory", systemImage: "folder")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)

                            HStack(spacing: 8) {
                                HStack(spacing: 6) {
                                    Image(systemName: "folder.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                    TextField("~/Sites", text: $sitesPath)
                                        .textFieldStyle(.plain)
                                        .font(.system(size: 13))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(6)

                                Button("Browse") {
                                    browseForFolder()
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(6)
                            }
                        }
                    }

                    // Editor
                    SettingsCard {
                        VStack(alignment: .leading, spacing: 8) {
                            // LEARN: `Label("text", systemImage: "icon.name")` = icon + text combo.
                            // Like `<span><Icon /> Default Editor</span>` in React.
                            Label("Default Editor", systemImage: "rectangle.and.pencil.and.ellipsis")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)

                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: 6) {
                                ForEach(editorOptions) { editor in
                                    OptionButton(
                                        name: editor.name,
                                        isSelected: selectedEditor == editor.id,
                                        isAvailable: editor.installed
                                    ) {
                                        selectedEditor = editor.id
                                    }
                                }
                            }
                        }
                    }

                    // Terminal
                    SettingsCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Default Terminal", systemImage: "terminal")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)

                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: 6) {
                                ForEach(terminalOptions) { terminal in
                                    OptionButton(
                                        name: terminal.name,
                                        isSelected: selectedTerminal == terminal.id,
                                        isAvailable: terminal.installed
                                    ) {
                                        selectedTerminal = terminal.id
                                    }
                                }
                            }
                        }
                    }

                    // Preferences
                    SettingsCard {
                        VStack(spacing: 0) {
                            Label("Preferences", systemImage: "slider.horizontal.3")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.bottom, 10)

                            SettingsToggle(
                                title: "Managed dev servers",
                                icon: "waveform.path.ecg",
                                isOn: $runManagedServers
                            )

                            Divider().padding(.vertical, 6)

                            SettingsToggle(
                                title: "Launch on login",
                                icon: "power",
                                isOn: Binding(
                                    get: { appState.config.launchOnLogin },
                                    set: { appState.setLaunchOnLogin($0) }
                                )
                            )

                            Divider().padding(.vertical, 6)

                            SettingsToggle(
                                title: "Show hidden projects",
                                icon: "eye.slash",
                                isOn: $appState.showHidden,
                                badge: appState.hiddenProjectCount > 0
                                    ? "\(appState.hiddenProjectCount)"
                                    : nil
                            )
                        }
                    }
                }
                .padding(12)
            }

            // Footer
            HStack {
                Spacer()
                Button {
                    save()
                } label: {
                    Text("Done")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.accentColor)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 340, height: 500)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            sitesPath = appState.config.sitesPath
            selectedEditor = appState.config.editor
            selectedTerminal = appState.config.terminal
            runManagedServers = appState.config.runManagedServers

            // Detect installed apps once (avoids filesystem I/O on every render)
            editorOptions = ProcessManager.detectInstalledEditors().map {
                AppOption(id: $0.id, name: $0.name, installed: $0.installed)
            }
            terminalOptions = ProcessManager.detectInstalledTerminals().map {
                AppOption(id: $0.id, name: $0.name, installed: $0.installed)
            }

            // If saved editor isn't installed, fall back to first installed one
            if !(editorOptions.first { $0.id == selectedEditor }?.installed ?? false),
               let fallback = editorOptions.first(where: { $0.installed }) {
                selectedEditor = fallback.id
            }

            // Same for terminal
            if !(terminalOptions.first { $0.id == selectedTerminal }?.installed ?? false),
               let fallback = terminalOptions.first(where: { $0.installed }) {
                selectedTerminal = fallback.id
            }
        }
    }

    private func browseForFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: (sitesPath as NSString).expandingTildeInPath)

        if panel.runModal() == .OK, let url = panel.url {
            sitesPath = url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        }
    }

    private func save() {
        var needsRescan = false

        if appState.config.sitesPath != sitesPath {
            appState.config.sitesPath = sitesPath
            needsRescan = true
        }

        if appState.config.editor != selectedEditor {
            appState.config.editor = selectedEditor
        }

        if appState.config.terminal != selectedTerminal {
            appState.config.terminal = selectedTerminal
        }

        if appState.config.runManagedServers != runManagedServers {
            appState.config.runManagedServers = runManagedServers
        }

        ConfigManager.save(appState.config)

        if needsRescan {
            appState.scan()
        }

        isPresented = false
    }
}

// LEARN: GENERICS in Swift — `<Content: View>` means "Content is any type that conforms to View."
// Like `interface SettingsCardProps<Content extends View>` in TS.
//
// This lets SettingsCard wrap ANY view content — it's a reusable container component.
// In React: `const SettingsCard: FC<{ children: ReactNode }> = ({ children }) => ...`
struct SettingsCard<Content: View>: View {
    // LEARN: `@ViewBuilder` is a property wrapper that enables SwiftUI's declarative syntax.
    // It lets you pass multiple views as a single closure (like `children` in React).
    // Without @ViewBuilder, you could only return ONE view from the closure.
    // With it, you can write `if/else`, multiple views, etc. — the compiler combines them.
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
    }
}

struct OptionButton: View {
    let name: String
    let isSelected: Bool
    var isAvailable: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                .foregroundColor(isSelected ? .white : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.accentColor : Color(NSColor.controlBackgroundColor).opacity(0.5))
                )
        }
        .buttonStyle(.plain)
        .opacity(isAvailable ? 1.0 : 0.35)
        .disabled(!isAvailable)
        .help(isAvailable ? name : "\(name) — Not installed")
    }
}

struct SettingsToggle: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool
    var badge: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 16)

            Text(title)
                .font(.system(size: 12))

            if let badge = badge {
                Text(badge)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15))
                    .cornerRadius(4)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .scaleEffect(0.7)
        }
    }
}
