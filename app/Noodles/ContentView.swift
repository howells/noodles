import SwiftUI
import Foundation

// LEARN: SwiftUI views are STRUCTS, not classes. This is a key design decision:
//   - They're lightweight value types (cheap to create and destroy)
//   - SwiftUI recreates them frequently during re-renders (like React components)
//   - The actual view rendering is handled by the framework, not the struct itself
//
// `View` is a protocol requiring a `body` property. Every SwiftUI view must conform to it.
// Think of it as: `interface View { body: some View }` — but Swift's protocol system
// is more powerful than TS interfaces (it supports associated types, default implementations, etc.).
//
// TS/React equivalent of this whole struct:
//   const ContentView: React.FC = () => { ... return <div>...</div> }
struct ContentView: View {
    // LEARN: `@EnvironmentObject` — reads a shared object from the view tree (injected by a parent).
    // This is EXACTLY like React's `useContext()`. The parent calls `.environmentObject(appState)`
    // and any descendant can read it with @EnvironmentObject. Changes trigger re-renders.
    //
    // Key difference from React Context: SwiftUI re-renders are more granular. Only views that
    // actually READ the changed property re-render, not the entire subtree.
    @EnvironmentObject var appState: AppState

    // LEARN: `@State` = component-local state. EXACTLY like React's `useState()`.
    // `@State private var showingSettings = false` ≈ `const [showingSettings, setShowingSettings] = useState(false)`
    //
    // `private` is convention — @State should always be private because it's owned by this view.
    // SwiftUI manages the storage behind the scenes — the struct itself is recreated on every
    // re-render, but @State values persist across re-renders (just like useState in React).
    @State private var showingSettings = false
    @State private var logSelection: LogTarget?
    @State private var showOtherServers = false

    private let mainPanelWidth: CGFloat = 420
    private let logPanelWidth: CGFloat = 480
    private let panelHeight: CGFloat = 600
    private let outerHeight: CGFloat = 616
    private let chromeInset: CGFloat = 8
    private let dividerWidth: CGFloat = 1

    // LEARN: `body` is the render function. SwiftUI calls it whenever state changes.
    // `some View` = "returns something that conforms to View" (opaque return type).
    //
    // The body is a DECLARATIVE description — you say WHAT the UI should look like,
    // and SwiftUI figures out HOW to update the screen efficiently (like React's virtual DOM,
    // but SwiftUI uses a diffing algorithm on the view tree directly).
    var body: some View {
        // LEARN: `VStack` = vertical stack. Like `<div style="display: flex; flex-direction: column">`.
        // `HStack` = horizontal. `ZStack` = overlapping (like position: absolute).
        // `spacing: 0` removes the default gap between children.
        HStack(spacing: 0) {
            mainPanel
                .frame(width: mainPanelWidth, height: panelHeight, alignment: .top)

            if let selection = logSelection {
                Rectangle()
                    .fill(Color(NSColor.separatorColor))
                    .frame(width: dividerWidth)

                ServerLogView(
                    serverId: selection.id,
                    title: selection.title,
                    onClose: { logSelection = nil }
                )
                .id(selection.id)
                .frame(width: logPanelWidth, height: panelHeight)
            }
        }
        .frame(width: contentWidth, height: panelHeight, alignment: .top)
        .clipped()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.windowBackgroundColor))
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(chromeInset)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.075))
        .frame(width: outerWidth, height: outerHeight)
        // LEARN: `.onAppear` = React's `useEffect(() => { ... }, [])` — runs once when the
        // view first appears. There's also `.onDisappear` (like cleanup in useEffect).
        // `.task` is the async version — `.task { await something() }`.
        .onAppear {
            appState.scan()
            postPopoverSize()
        }
        .onChange(of: logSelection != nil) { _ in
            postPopoverSize()
        }
        // LEARN: `.sheet` presents a modal overlay — like `{showModal && <Modal />}` in React.
        // `isPresented:` is a Binding<Bool> — when it becomes true, the sheet appears.
        // When the sheet is dismissed, the binding is set back to false automatically.
        .sheet(isPresented: $showingSettings) {
            SettingsView(isPresented: $showingSettings)
        }
    }

    private var contentWidth: CGFloat {
        isLogPanelVisible ? mainPanelWidth + logPanelWidth + dividerWidth : mainPanelWidth
    }

    private var outerWidth: CGFloat {
        contentWidth + chromeInset * 2
    }

    private var isLogPanelVisible: Bool {
        logSelection != nil
    }

    private var mainPanel: some View {
        VStack(spacing: 0) {
            // Header
            // LEARN: `$showingSettings` — the `$` prefix gives you a BINDING.
            // A Binding is a two-way reference: the child can both read AND write the value.
            // Like passing both `value` and `onChange` as a single prop in React:
            //   React: <HeaderView showingSettings={showingSettings} onShowingSettingsChange={setShowingSettings} />
            //   Swift: HeaderView(showingSettings: $showingSettings)
            HeaderView(showingSettings: $showingSettings)

            // Search
            SearchField(text: $appState.filter)
                // LEARN: `.padding()` is a VIEW MODIFIER — a method that returns a new modified view.
                // This is like CSS but composable and chainable. Each modifier wraps the view
                // in a new layer. Order matters! `.padding().background()` ≠ `.background().padding()`.
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            // Project list
            ScrollView {
                // LEARN: `LazyVStack` = like a virtualized list in React (react-window/react-virtualized).
                // Only renders items that are visible on screen. `VStack` renders ALL items immediately.
                // Use LazyVStack for long lists, VStack for short ones.
                LazyVStack(spacing: 4) {
                    // LEARN: `let` inside `body` creates local variables for the render pass.
                    // These are recomputed every time body is called (every re-render).
                    // Running takes priority over pinned — a pinned project that's running
                    // should appear in the Running section, not buried in Pinned.
                    let running = appState.runningProjects
                    let pinned = appState.pinnedProjects.filter { $0.status != .running && $0.status != .restarting && $0.status != .stopping }
                    let stopped = appState.stoppedProjects.filter { !appState.isPinned($0) }
                    let unmatchedPorts = appState.unmatchedPorts

                    if !running.isEmpty {
                        Section {
                            ForEach(running) { project in
                                ProjectCard(project: project) { target in
                                    if logSelection?.id == target.id {
                                        logSelection = nil
                                    } else {
                                        logSelection = target
                                    }
                                }
                                .id("\(project.id)-\(project.status)")
                            }
                        } header: {
                            SectionHeader(title: "Running", count: running.count)
                        }
                    }

                    if !pinned.isEmpty {
                        Section {
                            ForEach(pinned) { project in
                                ProjectCard(project: project) { target in
                                    if logSelection?.id == target.id {
                                        logSelection = nil
                                    } else {
                                        logSelection = target
                                    }
                                }
                                .id("\(project.id)-\(project.status)")
                            }
                        } header: {
                            SectionHeader(title: "Pinned", count: pinned.count, icon: "pin.fill")
                        }
                    }

                    if !stopped.isEmpty {
                        Section {
                            ForEach(stopped) { project in
                                ProjectCard(project: project) { target in
                                    if logSelection?.id == target.id {
                                        logSelection = nil
                                    } else {
                                        logSelection = target
                                    }
                                }
                                .id("\(project.id)-\(project.status)")
                            }
                        } header: {
                            SectionHeader(title: "Available", count: stopped.count)
                        }
                    }

                    if !unmatchedPorts.isEmpty {
                        Section {
                            if showOtherServers {
                                ForEach(unmatchedPorts) { port in
                                    ServerRow(port: port)
                                }
                            }
                        } header: {
                            ExpandableSectionHeader(
                                title: "Other Servers",
                                count: unmatchedPorts.count,
                                isExpanded: $showOtherServers
                            )
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
    }

    private func postPopoverSize() {
        NotificationCenter.default.post(
            name: .popoverResize,
            object: nil,
            userInfo: ["width": outerWidth]
        )
    }
}

struct HeaderView: View {
    @EnvironmentObject var appState: AppState
    // LEARN: `@Binding` = a two-way reference to state owned by a PARENT view.
    // The parent passes `$showingSettings` and this view can read/write it.
    // React equivalent: receiving both `value` and `setValue` as props, bundled into one.
    //
    // Key rule: @State = you OWN it. @Binding = someone ELSE owns it, you just read/write it.
    @Binding var showingSettings: Bool

    var body: some View {
        HStack {
            Text("Noodles")
                .font(.system(size: 14, weight: .semibold))

            // LEARN: `Spacer()` pushes siblings apart — like `flex: 1` or `margin-left: auto` in CSS.
            // It fills all available space, pushing items to opposite ends.
            Spacer()

            HStack(spacing: 2) {
                IconButton(icon: "arrow.clockwise", help: "Refresh projects") {
                    appState.scan()
                }
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
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 26, height: 26)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 26)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            // Magnifying glass aligned with chevron/dot column in project cards
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 12))
                .frame(width: 24, height: 24)

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
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct SectionHeader: View {
    let title: String
    let count: Int
    // LEARN: `var icon: String? = nil` — an optional property with a default value.
    // Callers can omit it: `SectionHeader(title: "Running", count: 3)`
    // or provide it: `SectionHeader(title: "Favorites", count: 2, icon: "star.fill")`
    // Like optional props with defaults in React.
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            // LEARN: `if let icon = icon` — unwrap the optional inline.
            // The view inside only renders if icon is non-nil.
            // Like `{icon && <Image ... />}` in React JSX.
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

struct ExpandableSectionHeader: View {
    let title: String
    let count: Int
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)

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
        }
        .buttonStyle(.plain)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }
}

struct ServerRow: View {
    let port: PortInfo
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.orange.opacity(0.7))
                .frame(width: 8, height: 8)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(port.processName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                Text(displayPath)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            PortBadge(port: port.port, isActive: true) {
                appState.openInBrowser(port: port.port)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }

    private var displayPath: String {
        guard let cwd = port.cwd, !cwd.isEmpty else { return "Unknown path" }
        return cwd.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}
