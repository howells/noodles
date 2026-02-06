import SwiftUI
import AppKit

extension Notification.Name {
    static let popoverResize = Notification.Name("PopoverResize")
}

// LEARN: `@main` marks the entry point of the app — like `"main"` in package.json or the
// top-level `index.ts` that Node runs. There can only be one @main in the entire app.
//
// `struct NoodlesApp: App` — this conforms to the `App` protocol (like implementing an interface).
// SwiftUI apps declare their structure declaratively — "here's what my app looks like" rather
// than imperatively setting things up step by step.
@main
struct NoodlesApp: App {
    // LEARN: `@NSApplicationDelegateAdaptor` is a PROPERTY WRAPPER — a Swift feature with no TS equivalent.
    // Property wrappers add behavior to properties. This one bridges SwiftUI's declarative world
    // to AppKit's imperative world. Think of it like a decorator in TS, but for properties.
    //
    // Why do we need this? SwiftUI's `App` protocol is too high-level for a menu bar app —
    // we need AppKit's NSStatusBar, NSPopover, etc. This adaptor lets us use both systems.
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // LEARN: `body` is a computed property required by the App protocol. SwiftUI calls this
    // to build the app's scene hierarchy. It's like React's render() — you describe WHAT
    // the UI should be, not HOW to build it.
    //
    // `some Scene` — the `some` keyword means "an opaque type" — you're saying "I return
    // something that conforms to Scene, but I'm not telling you exactly what type."
    // TS equivalent: it's like returning `Scene` from a function but the compiler tracks
    // the concrete type internally for performance (avoids protocol overhead / boxing).
    var body: some Scene {
        // We use an empty Settings scene because the real UI lives in the NSPopover
        // managed by AppDelegate below. This is a common pattern for menu bar apps.
        Settings {
            EmptyView()
        }
    }
}

// LEARN: `class` (not struct!) because AppDelegate needs to be a REFERENCE TYPE:
//   1. It's stored by the system and mutated by callbacks
//   2. It inherits from NSObject (required for Objective-C interop with AppKit)
//   3. It conforms to NSApplicationDelegate and NSPopoverDelegate (lifecycle callbacks)
//
// In TS terms, this is like an EventEmitter subclass that the framework calls methods on.
// The methods like `applicationDidFinishLaunching` are delegate callbacks — like event handlers
// that macOS calls at specific lifecycle points.
//
// `NSObject` — base class for ALL Objective-C objects. Required because AppKit was written in
// Objective-C and Swift needs to interop with it. Think of it like extending EventTarget in the DOM.
class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    // LEARN: `var statusItem: NSStatusItem!` — the `!` is an "implicitly unwrapped optional."
    // It's like `statusItem: NSStatusItem | null` in TS, but you access it WITHOUT null-checking.
    // It WILL crash if accessed while nil — so only use it when you KNOW it'll be set before use.
    // Common pattern: properties that are nil at init time but set in a lifecycle method.
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var appState: AppState!
    var keyboardMonitor: Any?  // `Any?` = optional of Any = like `unknown | undefined` in TS

    // LEARN: This is a delegate method — macOS calls it when the app finishes launching.
    // The `_` means the external parameter name is suppressed (caller doesn't name it).
    // `Notification` is like a DOM Event — it carries info about what happened.
    func applicationDidFinishLaunching(_ notification: Notification) {
        appState = AppState()

        // Create the popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 436, height: 608)
        // `.applicationDefined` = popover never auto-closes. Dismissed only by
        // clicking the menu bar icon or pressing Escape. Stays open when opening
        // browser, editor, terminal — the user controls when it goes away.
        popover.behavior = .applicationDefined
        // LEARN: `delegate = self` is the DELEGATION PATTERN — extremely common in Apple frameworks.
        // Instead of passing callbacks (like JS), you set an object as a "delegate" and the
        // framework calls specific methods on it. Like implementing an interface of event handlers.
        popover.delegate = self
        // LEARN: `NSHostingController` bridges SwiftUI views into AppKit. It wraps a SwiftUI view
        // so it can be used where AppKit expects a view controller. Like mounting a React component
        // into a non-React container.
        //
        // `.environmentObject(appState)` — injects appState into the SwiftUI view tree.
        // This is like React Context — any descendant view can access it with @EnvironmentObject.
        // The data flows DOWN the tree, and changes trigger re-renders (like Context + useState).
        popover.contentViewController = NSHostingController(
            rootView: ContentView()
                .environmentObject(appState)
        )

        // Create the status bar item (the icon in your macOS menu bar)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            updateStatusButton()
            // LEARN: `#selector` is Objective-C's way of referencing a method by name.
            // It's like passing a string method name, but type-checked at compile time.
            // The method MUST be marked `@objc` to be visible to the Objective-C runtime.
            // This is a legacy pattern — in pure Swift you'd use closures instead.
            button.action = #selector(togglePopover)
            button.target = self
        }

        // LEARN: `NotificationCenter` is like Node's EventEmitter — a pub/sub system.
        // Objects post notifications (events) and other objects observe (subscribe to) them.
        // This is NOT push notifications — it's an in-process event bus.
        // TS equivalent: `eventBus.on("ProjectsDidChange", this.updateStatusButton)`
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateStatusButton),
            name: NSNotification.Name("ProjectsDidChange"),
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePopoverResize(_:)),
            name: .popoverResize,
            object: nil
        )

        // LEARN: `NSEvent.addLocalMonitorForEvents` is like `document.addEventListener("keydown", ...)`
        // but for the entire app. The closure receives each event and can:
        //   - Return the event (let it pass through) — like NOT calling preventDefault()
        //   - Return nil (swallow the event) — like calling preventDefault()
        //
        // `[weak self]` in the capture list prevents a RETAIN CYCLE (memory leak).
        // In JS, the garbage collector handles circular references. Swift uses reference counting
        // (ARC), so if A holds B and B holds A, neither gets freed. `weak` breaks the cycle
        // by not incrementing the reference count. The variable becomes nil if the object is freed.
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.popover.isShown else { return event }

            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "q" {
                NSApplication.shared.terminate(nil)
                return nil
            }
            if event.keyCode == 53 { // Escape key
                self.popover.performClose(nil)
                return nil
            }
            return event
        }

        // Sync launch on login state
        appState.syncLaunchOnLoginState()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = keyboardMonitor {
            NSEvent.removeMonitor(monitor)
        }
        NotificationCenter.default.removeObserver(self)

        // Stop the polling timer so no new Tasks are spawned
        appState.portPollingTimer?.invalidate()

        // Synchronous cleanup: SIGTERM → wait → SIGKILL all managed processes.
        // Uses the nonisolated cleanup registry — no async bridge needed, no deadlock.
        appState.processManager.cleanupAllSync()
    }

    @objc private func handlePopoverResize(_ notification: Notification) {
        guard let width = notification.userInfo?["width"] as? CGFloat else { return }
        popover.contentSize = NSSize(width: width, height: 608)
    }

    // LEARN: `@objc` exposes this method to the Objective-C runtime, required for #selector.
    // Without @objc, the method only exists in Swift's type system and can't be found by
    // the older Objective-C message-dispatch system that NSStatusBarButton uses.
    @objc func updateStatusButton() {
        // LEARN: `Task { @MainActor in ... }` — creates an async task guaranteed to run on
        // the main thread. In JS, everything is already on one thread. In Swift, you must be
        // explicit about which thread UI updates happen on (always the main thread).
        Task { @MainActor in
            guard let button = statusItem.button else { return }

            let runningCount = min(appState.projects.filter { $0.status == .running }.count, 4)
            button.image = createGridIcon(runningCount: runningCount)
            button.title = ""
        }
    }

    // LEARN: This creates a status bar icon programmatically using CoreGraphics drawing.
    // There's no canvas API like in the browser — instead you use NSImage with a drawing
    // handler closure. The closure receives a rect and draws into it using NSBezierPath
    // (like Canvas2D's arc/fill but with a different API).
    private func createGridIcon(runningCount: Int) -> NSImage {
        let size: CGFloat = 18
        let dotSize: CGFloat = 5
        let spacing: CGFloat = 2

        // LEARN: `NSImage(size:flipped:drawingHandler:)` — the closure is called whenever
        // the image needs to be rendered. `CGFloat` is like `number` but specifically for
        // Core Graphics coordinates (it's a Double under the hood on 64-bit systems).
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let totalGridSize = dotSize * 2 + spacing
            let offsetX = (size - totalGridSize) / 2
            let offsetY = (size - totalGridSize) / 2

            // LEARN: Tuple array — `[(CGFloat, CGFloat)]` is like `[number, number][]` in TS.
            // Swift tuples are lightweight pairs/triples without needing a struct or interface.
            let positions: [(CGFloat, CGFloat)] = [
                (offsetX, offsetY + dotSize + spacing),                    // top-left
                (offsetX + dotSize + spacing, offsetY + dotSize + spacing), // top-right
                (offsetX, offsetY),                                         // bottom-left
                (offsetX + dotSize + spacing, offsetY)                      // bottom-right
            ]

            // LEARN: `.enumerated()` = like JS `.entries()` — gives you (index, element) pairs.
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

    // LEARN: This is a delegate method from NSPopoverDelegate — the popover calls this
    // when it closes. You don't call it yourself. Like an event handler that fires automatically.
    func popoverDidClose(_ notification: Notification) {
        // Optional: handle popover close
    }
}
