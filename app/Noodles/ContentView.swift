import SwiftUI

private struct CardHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let v = nextValue()
        if v > 0 { value = v }
    }
}

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var cardHeight: CGFloat = 56

    private let mainPanelWidth: CGFloat = 380
    private let logPanelWidth: CGFloat = 440
    private let footerHeight: CGFloat = 32
    private let listPadding: CGFloat = 16
    private let cardSpacing: CGFloat = 4

    private var maxPanelHeight: CGFloat {
        guard let screen = NSScreen.main else { return 500 }
        return screen.visibleFrame.height * 0.5
    }

    private var panelHeight: CGFloat {
        if appState.projects.isEmpty { return 120 }
        let count = CGFloat(appState.projects.count)
        let listHeight = listPadding + count * cardHeight + (count - 1) * cardSpacing
        let maxListHeight = maxPanelHeight - footerHeight
        return min(listHeight, maxListHeight) + footerHeight
    }

    private var contentWidth: CGFloat {
        appState.activeLogPath != nil ? mainPanelWidth + logPanelWidth + 1 : mainPanelWidth
    }

    var body: some View {
        HStack(spacing: 0) {
            mainPanel
                .frame(width: mainPanelWidth, height: panelHeight)

            if appState.activeLogPath != nil {
                Rectangle()
                    .fill(Color(NSColor.separatorColor))
                    .frame(width: 1)

                LogPanel()
                    .frame(width: logPanelWidth, height: panelHeight)
            }
        }
        .frame(width: contentWidth, height: panelHeight)
        .onAppear { postPopoverSize() }
        .onChange(of: appState.activeLogPath != nil) { _ in postPopoverSize() }
        .onChange(of: appState.projects.count) { _ in postPopoverSize() }
        .onChange(of: cardHeight) { _ in postPopoverSize() }
        .onPreferenceChange(CardHeightKey.self) { height in
            if height > 0 { cardHeight = height }
        }
    }

    private var mainPanel: some View {
        VStack(spacing: 0) {
            if appState.projects.isEmpty {
                Spacer()
                Text("No servers seen yet")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: cardSpacing) {
                        ForEach(appState.projects) { project in
                            ServerCard(server: project)
                                .background(
                                    GeometryReader { geo in
                                        Color.clear.preference(key: CardHeightKey.self, value: geo.size.height)
                                    }
                                )
                        }
                    }
                    .padding(listPadding / 2)
                }
            }

            HStack {
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

                    Button {
                        showMenu()
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Options")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func showMenu() {
        let menu = NSMenu()

        let loginItem = NSMenuItem(
            title: "Launch on Login",
            action: #selector(AppDelegate.toggleLoginItem),
            keyEquivalent: ""
        )
        loginItem.state = appState.launchOnLogin ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Noodles",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        if let event = NSApp.currentEvent {
            NSMenu.popUpContextMenu(menu, with: event, for: NSApp.keyWindow?.contentView ?? NSView())
        }
    }

    private func postPopoverSize() {
        NotificationCenter.default.post(
            name: .popoverResize,
            object: nil,
            userInfo: ["width": contentWidth, "height": panelHeight]
        )
    }
}
