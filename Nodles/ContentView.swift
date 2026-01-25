import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HeaderView()

            // Search
            SearchField(text: $appState.filter)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            // Project list
            ScrollView {
                LazyVStack(spacing: 4) {
                    let running = appState.projects.filter { $0.status == .running }
                    let stopped = appState.projects.filter { $0.status != .running }

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
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            appState.scan()
        }
    }
}

struct HeaderView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack {
            Text("nodles")
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

    var body: some View {
        HStack {
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
