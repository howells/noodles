import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    @State private var sitesPath: String = ""
    @State private var selectedEditor: String = ""

    private let editors = [
        ("cursor", "Cursor"),
        ("code", "VS Code"),
        ("zed", "Zed")
    ]

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
                            Label("Default Editor", systemImage: "rectangle.and.pencil.and.ellipsis")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)

                            HStack(spacing: 6) {
                                ForEach(editors, id: \.0) { editor in
                                    EditorButton(
                                        name: editor.1,
                                        isSelected: selectedEditor == editor.0
                                    ) {
                                        selectedEditor = editor.0
                                    }
                                }
                            }
                        }
                    }

                    // Preferences
                    SettingsCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Preferences", systemImage: "slider.horizontal.3")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)

                            SettingsToggle(
                                title: "Launch on Login",
                                subtitle: "Start Noodles when you log in",
                                icon: "power",
                                isOn: Binding(
                                    get: { appState.config.launchOnLogin },
                                    set: { appState.setLaunchOnLogin($0) }
                                )
                            )

                            Divider()
                                .padding(.vertical, 2)

                            SettingsToggle(
                                title: "Show Hidden Projects",
                                subtitle: appState.hiddenProjectCount > 0
                                    ? "\(appState.hiddenProjectCount) project\(appState.hiddenProjectCount == 1 ? "" : "s") hidden"
                                    : "No hidden projects",
                                icon: "eye.slash",
                                isOn: $appState.showHidden
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
        .frame(width: 340, height: 380)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            sitesPath = appState.config.sitesPath
            selectedEditor = appState.config.editor
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

        ConfigManager.save(appState.config)

        if needsRescan {
            appState.scan()
        }

        isPresented = false
    }
}

struct SettingsCard<Content: View>: View {
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

struct EditorButton: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                .foregroundColor(isSelected ? .white : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.accentColor : Color(NSColor.controlBackgroundColor).opacity(0.5))
                )
        }
        .buttonStyle(.plain)
    }
}

struct SettingsToggle: View {
    let title: String
    let subtitle: String
    let icon: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .scaleEffect(0.8)
        }
    }
}
