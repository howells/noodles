import SwiftUI
import AppKit

@main
struct NoodlesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var appState: AppState!
    var keyboardMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState = AppState()

        // Create the popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 428, height: 608)
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: ContentView()
                .environmentObject(appState)
        )

        // Create the status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            updateStatusButton()
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Observe running count changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateStatusButton),
            name: NSNotification.Name("ProjectsDidChange"),
            object: nil
        )

        // Set up keyboard monitor for ⌘Q when popover is open
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.popover.isShown else { return event }

            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "q" {
                NSApplication.shared.terminate(nil)
                return nil
            }
            return event
        }

        // Sync launch on login state
        appState.syncLaunchOnLoginState()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Clean up keyboard monitor
        if let monitor = keyboardMonitor {
            NSEvent.removeMonitor(monitor)
        }

        // Remove NotificationCenter observer
        NotificationCenter.default.removeObserver(self)

        // Clean up AppState (invalidate timers, stop spawned processes)
        let semaphore = DispatchSemaphore(value: 0)
        Task { @MainActor in
            await appState.cleanup()
            semaphore.signal()
        }
        semaphore.wait()
    }

    @objc func updateStatusButton() {
        Task { @MainActor in
            guard let button = statusItem.button else { return }

            let runningCount = min(appState.projects.filter { $0.status == .running }.count, 4)
            button.image = createGridIcon(runningCount: runningCount)
            button.title = ""
        }
    }

    private func createGridIcon(runningCount: Int) -> NSImage {
        let size: CGFloat = 18
        let dotSize: CGFloat = 5
        let spacing: CGFloat = 2

        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let totalGridSize = dotSize * 2 + spacing
            let offsetX = (size - totalGridSize) / 2
            let offsetY = (size - totalGridSize) / 2

            // Dot positions: top-left, top-right, bottom-left, bottom-right
            let positions: [(CGFloat, CGFloat)] = [
                (offsetX, offsetY + dotSize + spacing),                    // top-left
                (offsetX + dotSize + spacing, offsetY + dotSize + spacing), // top-right
                (offsetX, offsetY),                                         // bottom-left
                (offsetX + dotSize + spacing, offsetY)                      // bottom-right
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

    func popoverDidClose(_ notification: Notification) {
        // Optional: handle popover close
    }
}
