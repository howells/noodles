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
        popover.contentSize = NSSize(width: 420, height: 600)
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

            let runningCount = appState.projects.filter { $0.status == .running }.count

            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            let image = NSImage(systemSymbolName: "circle.grid.2x2.fill", accessibilityDescription: "Noodles")?
                .withSymbolConfiguration(config)
            button.image = image

            if runningCount > 0 {
                button.title = " \(runningCount)"
            } else {
                button.title = ""
            }
        }
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
