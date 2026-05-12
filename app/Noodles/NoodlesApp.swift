import SwiftUI
import AppKit

@main
struct NoodlesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var appState: AppState!
    var keyboardMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState = AppState()

        popover = NSPopover()
        popover.contentSize = NSSize(width: 380, height: 200)
        popover.behavior = .applicationDefined
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: ContentView().environmentObject(appState)
        )

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            updateStatusButton()
            button.action = #selector(togglePopover)
            button.target = self
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(updateStatusButton),
            name: .serversDidChange, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handlePopoverResize(_:)),
            name: .popoverResize, object: nil
        )

        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.popover.isShown else { return event }
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "q" {
                NSApplication.shared.terminate(nil)
                return nil
            }
            if event.keyCode == 53 {
                self.popover.performClose(nil)
                return nil
            }
            return event
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = keyboardMonitor { NSEvent.removeMonitor(monitor) }
        NotificationCenter.default.removeObserver(self)
        appState.pollTimer?.invalidate()
    }

    @objc private func handlePopoverResize(_ notification: Notification) {
        guard let width = notification.userInfo?["width"] as? CGFloat,
              let height = notification.userInfo?["height"] as? CGFloat else { return }
        popover.contentSize = NSSize(width: width, height: height)
    }

    @objc func updateStatusButton() {
        Task { @MainActor in
            guard let button = statusItem.button else { return }
            let runningCount = min(appState.projects.filter(\.isRunning).count, 4)
            button.image = createGridIcon(runningCount: runningCount)
            button.title = ""
        }
    }

    private func createGridIcon(runningCount: Int) -> NSImage {
        let size: CGFloat = 18
        let dotSize: CGFloat = 5
        let spacing: CGFloat = 2

        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let totalGridSize = dotSize * 2 + spacing
            let offsetX = (size - totalGridSize) / 2
            let offsetY = (size - totalGridSize) / 2

            let positions: [(CGFloat, CGFloat)] = [
                (offsetX, offsetY + dotSize + spacing),
                (offsetX + dotSize + spacing, offsetY + dotSize + spacing),
                (offsetX, offsetY),
                (offsetX + dotSize + spacing, offsetY),
            ]

            for (index, pos) in positions.enumerated() {
                let dotRect = NSRect(x: pos.0, y: pos.1, width: dotSize, height: dotSize)
                let path = NSBezierPath(ovalIn: dotRect)
                if index < runningCount {
                    NSColor.systemGreen.setFill()
                } else {
                    NSColor.secondaryLabelColor.setFill()
                }
                path.fill()
            }
            return true
        }

        image.isTemplate = false
        return image
    }

    @objc func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                popover.contentViewController?.view.window?.makeKey()
            }
        }
    }

    @objc func toggleLoginItem() {
        Task { @MainActor in
            appState.toggleLaunchOnLogin()
        }
    }

    func popoverDidClose(_ notification: Notification) {}
}
