import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HeaderView(showingSettings: $showingSettings)

            // Search
            SearchField(text: $appState.filter)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            // Project list
            ScrollView {
                LazyVStack(spacing: 4) {
                    let favorites = appState.favoriteProjects
                    let running = appState.runningProjects.filter { !appState.isFavorite($0) }
                    let stopped = appState.stoppedProjects.filter { !appState.isFavorite($0) }

                    if !favorites.isEmpty {
                        Section {
                            ForEach(favorites) { project in
                                ProjectCard(project: project)
                                    .id("\(project.id)-\(project.status)")
                            }
                        } header: {
                            SectionHeader(title: "Favorites", count: favorites.count, icon: "star.fill")
                        }
                    }

                    if !running.isEmpty {
                        Section {
                            ForEach(running) { project in
                                ProjectCard(project: project)
                                    .id("\(project.id)-\(project.status)")
                            }
                        } header: {
                            SectionHeader(title: "Running", count: running.count)
                        }
                    }

                    if !stopped.isEmpty {
                        Section {
                            ForEach(stopped) { project in
                                ProjectCard(project: project)
                                    .id("\(project.id)-\(project.status)")
                            }
                        } header: {
                            SectionHeader(title: "Available", count: stopped.count)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .frame(width: 420, height: 600, alignment: .top)
        .clipped()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.windowBackgroundColor))
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(4)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.6))
        .frame(width: 428, height: 608)
        .onAppear {
            appState.scan()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(isPresented: $showingSettings)
        }
    }
}

struct HeaderView: View {
    @EnvironmentObject var appState: AppState
    @Binding var showingSettings: Bool

    var body: some View {
        HStack {
            Text("noodles")
                .font(.system(size: 14, weight: .semibold))

            Spacer()

            Button {
                appState.scan()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .opacity(appState.isScanning ? 0.5 : 1)
            .disabled(appState.isScanning)

            Menu {
                Button("Settings...") {
                    showingSettings = true
                }
                Divider()
                Button("Quit Noodles") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 20)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 12))

            TextField("Filter projects...", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }
}

struct SectionHeader: View {
    let title: String
    let count: Int
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            Text("\(count)")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.2))
                .cornerRadius(4)
            Spacer()
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
    }
}
