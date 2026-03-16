import SwiftUI

struct ServerCard: View {
    let server: RunningServer
    @EnvironmentObject var appState: AppState

    private var isKilling: Bool {
        appState.isKilling.contains(server.id)
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(isKilling ? Color.orange : Color.green)
                .frame(width: 8, height: 8)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(server.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                Text(server.displayPath)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 4) {
                ForEach(server.ports.prefix(3), id: \.self) { port in
                    PortBadge(port: port) {
                        appState.openInBrowser(port: port)
                    }
                }
            }

            HStack(spacing: 2) {
                if let bundleId = server.terminalApp {
                    IconButton(icon: "terminal", help: "Reveal terminal") {
                        appState.revealTerminal(bundleId: bundleId)
                    }
                    .disabled(isKilling)
                }

                if server.hasLogs {
                    IconButton(icon: "text.justify.left", help: "View logs") {
                        appState.toggleLog(server: server)
                    }
                    .disabled(isKilling)
                }

                IconButton(icon: "globe", help: "Open in browser") {
                    if let port = server.ports.first {
                        appState.openInBrowser(port: port)
                    }
                }
                .disabled(isKilling)

                if isKilling {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 26, height: 26)
                } else {
                    IconButton(icon: "xmark.circle", help: "Kill", color: .red) {
                        appState.kill(server: server)
                    }
                }
            }
        }
        .padding(.leading, 2)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
}

struct PortBadge: View {
    let port: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: "\(port)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .help("Open localhost:\(port)")
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
        .onHover { hovering in isHovering = hovering }
    }
}
