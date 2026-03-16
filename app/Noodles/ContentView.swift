import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    private let mainPanelWidth: CGFloat = 380
    private let logPanelWidth: CGFloat = 440
    private let panelHeight: CGFloat = 500
    private let chromeInset: CGFloat = 8

    var body: some View {
        HStack(spacing: 0) {
            mainPanel
                .frame(width: mainPanelWidth, height: panelHeight, alignment: .top)

            if appState.activeLogPath != nil {
                Rectangle()
                    .fill(Color(NSColor.separatorColor))
                    .frame(width: 1)

                LogPanel()
                    .frame(width: logPanelWidth, height: panelHeight)
            }
        }
        .frame(width: contentWidth, height: panelHeight, alignment: .top)
        .clipped()
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.windowBackgroundColor)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(chromeInset)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.075))
        .frame(width: outerWidth, height: panelHeight + chromeInset * 2)
        .onAppear { postPopoverSize() }
        .onChange(of: appState.activeLogPath != nil) { _ in postPopoverSize() }
    }

    private var contentWidth: CGFloat {
        appState.activeLogPath != nil ? mainPanelWidth + logPanelWidth + 1 : mainPanelWidth
    }

    private var outerWidth: CGFloat {
        contentWidth + chromeInset * 2
    }

    private var mainPanel: some View {
        VStack(spacing: 0) {
            headerView

            if appState.servers.isEmpty {
                Spacer()
                Text("No servers running")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(appState.servers) { server in
                            ServerCard(server: server)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private var headerView: some View {
        HStack {
            Text("Noodles")
                .font(.system(size: 14, weight: .semibold))

            Spacer()

            HStack(spacing: 12) {
                Button {
                    appState.poll()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(appState.isRefreshing ? 0.4 : 1)
                .disabled(appState.isRefreshing)
                .help("Refresh")

                Menu {
                    Toggle("Launch on Login", isOn: Binding(
                        get: { appState.launchOnLogin },
                        set: { _ in appState.toggleLaunchOnLogin() }
                    ))
                    Divider()
                    Button("Quit Noodles") {
                        NSApplication.shared.terminate(nil)
                    }
                    .keyboardShortcut("q", modifiers: .command)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func postPopoverSize() {
        NotificationCenter.default.post(
            name: .popoverResize,
            object: nil,
            userInfo: ["width": outerWidth]
        )
    }
}
