# Dev Server Visibility Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make dev server detection deterministic and add an in-app managed dev server with streaming logs and full visibility of all running servers.

**Architecture:** Introduce a managed server registry inside ProcessManager that owns Process objects, captures stdout/stderr into a bounded log buffer, and exposes per-server streams/snapshots. Replace ad-hoc lsof parsing with structured -F output parsing plus cwd caching. AppState integrates managed server state into status resolution, and the UI adds a log viewer plus a section for unmatched listening ports.

**Tech Stack:** Swift, SwiftUI, AppKit, Foundation, Combine, XCTest.

---

### Task 1: Add a minimal XCTest target and harness

**Files:**
- Create: `NoodlesTests/Info.plist`
- Create: `NoodlesTests/NoodlesTests.swift`
- Modify: `Noodles.xcodeproj/project.pbxproj`

**Step 1: Write the failing test**

Create `NoodlesTests/NoodlesTests.swift` with a placeholder failing test so the harness is wired.

```swift
import XCTest
@testable import Noodles

final class NoodlesTests: XCTestCase {
    func testTestHarnessIsWired() {
        XCTAssertTrue(false)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Noodles.xcodeproj -scheme NoodlesTests -destination 'platform=macOS'`
Expected: FAIL with `XCTAssertTrue failed`.

**Step 3: Write minimal implementation**

Wire up a new test target in `Noodles.xcodeproj/project.pbxproj` that builds the `Noodles` target as a host app and includes `NoodlesTests/NoodlesTests.swift`.

**Step 4: Run test to verify it passes**

Update the test to pass:

```swift
XCTAssertTrue(true)
```

Run: `xcodebuild test -project Noodles.xcodeproj -scheme NoodlesTests -destination 'platform=macOS'`
Expected: PASS.

**Step 5: Commit**

```bash
git add NoodlesTests Noodles.xcodeproj/project.pbxproj
git commit -m "test: add XCTest target"
```

---

### Task 2: Add a pure lsof parser with tests

**Files:**
- Modify: `Noodles/ProcessManager.swift`
- Create: `NoodlesTests/ProcessManagerParsingTests.swift`

**Step 1: Write the failing test**

Create `NoodlesTests/ProcessManagerParsingTests.swift`:

```swift
import XCTest
@testable import Noodles

final class ProcessManagerParsingTests: XCTestCase {
    func testParseLsofFieldsToPorts() {
        let sample = """
        p1234
        cnode
        n*:3000
        n127.0.0.1:3000
        p2222
        cpython
        n*:8000
        """

        let ports = ProcessManager.parseListeningPorts(from: sample)

        XCTAssertEqual(ports.count, 2)
        XCTAssertTrue(ports.contains { $0.pid == 1234 && $0.port == 3000 && $0.processName == "node" })
        XCTAssertTrue(ports.contains { $0.pid == 2222 && $0.port == 8000 && $0.processName == "python" })
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Noodles.xcodeproj -scheme NoodlesTests -destination 'platform=macOS'`
Expected: FAIL because `parseListeningPorts` does not exist.

**Step 3: Write minimal implementation**

In `Noodles/ProcessManager.swift`, add a `nonisolated static func parseListeningPorts(from:) -> [PortInfo]` that parses `lsof -Fpcn` output into `PortInfo` entries (dedupe by pid+port, not by port alone).

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -project Noodles.xcodeproj -scheme NoodlesTests -destination 'platform=macOS'`
Expected: PASS.

**Step 5: Commit**

```bash
git add Noodles/ProcessManager.swift NoodlesTests/ProcessManagerParsingTests.swift
git commit -m "test: add lsof parser coverage"
```

---

### Task 3: Make port scanning deterministic and cache cwd lookups

**Files:**
- Modify: `Noodles/ProcessManager.swift`
- Modify: `Noodles/Models.swift`

**Step 1: Write the failing test**

Add a test that ensures duplicate listen entries for the same pid+port are de-duped and that PortInfo identifiers are stable.

```swift
func testPortInfoIdIsUniquePerPidPort() {
    let p1 = PortInfo(port: 3000, pid: 1234, processName: "node", cwd: nil)
    let p2 = PortInfo(port: 3000, pid: 5678, processName: "node", cwd: nil)
    XCTAssertNotEqual(p1.id, p2.id)
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Noodles.xcodeproj -scheme NoodlesTests -destination 'platform=macOS'`
Expected: FAIL because `PortInfo.id` is currently just the port.

**Step 3: Write minimal implementation**

- Update `PortInfo.id` in `Noodles/Models.swift` to be unique per pid+port (for example: `"\(pid):\(port)"`).
- Update `getListeningPorts` to call `lsof -nP -iTCP -sTCP:LISTEN -Fpcn` and parse via `parseListeningPorts`.
- Add a lightweight cwd cache in ProcessManager (pid -> (path, timestamp)) with a TTL (for example 10s).
- Update cwd lookup to use `lsof -a -p <pid> -d cwd -Fn` and cache results for all processes, not just node/bun.

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -project Noodles.xcodeproj -scheme NoodlesTests -destination 'platform=macOS'`
Expected: PASS.

**Step 5: Commit**

```bash
git add Noodles/ProcessManager.swift Noodles/Models.swift NoodlesTests/ProcessManagerParsingTests.swift
git commit -m "feat: deterministic port scanning"
```

---

### Task 4: Add managed dev servers with streaming logs

**Files:**
- Modify: `Noodles/ProcessManager.swift`
- Modify: `Noodles/AppState.swift`
- Modify: `Noodles/Models.swift`

**Step 1: Write the failing test**

Add tests for a new bounded log buffer helper:

```swift
func testLogBufferKeepsTail() {
    var buffer = LogBuffer(maxLines: 3)
    buffer.append("a")
    buffer.append("b")
    buffer.append("c")
    buffer.append("d")
    XCTAssertEqual(buffer.lines, ["b", "c", "d"])
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Noodles.xcodeproj -scheme NoodlesTests -destination 'platform=macOS'`
Expected: FAIL because LogBuffer does not exist.

**Step 3: Write minimal implementation**

- Add `LogBuffer` (struct) and `ManagedServerInfo` (struct) to `Noodles/Models.swift`.
- Extend `ProcessManager` with a managed server registry keyed by `UUID`, plus:
  - `startManagedServer(path:packageManager:customPort:label:) async throws -> UUID`
  - `stopManagedServer(id: UUID, force: Bool)`
  - `getManagedServers() async -> [ManagedServerInfo]`
  - `getLogSnapshot(id: UUID, tail: Int) async -> [String]`
- Capture stdout/stderr via `Pipe` and append to LogBuffer; trim to max lines.
- Ensure termination updates server state, exit code, and stops log streaming.
- In `AppState`, add maps from project/workspace id to managed server UUID and update `startProject`/`startWorkspace` to use managed start when configured.

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -project Noodles.xcodeproj -scheme NoodlesTests -destination 'platform=macOS'`
Expected: PASS.

**Step 5: Commit**

```bash
git add Noodles/ProcessManager.swift Noodles/AppState.swift Noodles/Models.swift NoodlesTests/ProcessManagerParsingTests.swift
git commit -m "feat: managed servers and log buffer"
```

---

### Task 5: Expose log streaming and full server visibility in UI

**Files:**
- Modify: `Noodles/ContentView.swift`
- Modify: `Noodles/ProjectCard.swift`
- Modify: `Noodles/SettingsView.swift`
- Modify: `Noodles/AppState.swift`

**Step 1: Write the failing test**

Add a simple view-level smoke test to ensure `ServerLogView` formats lines (if view tests are not feasible, add a small unit test for the formatter in `Models.swift`).

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Noodles.xcodeproj -scheme NoodlesTests -destination 'platform=macOS'`
Expected: FAIL because the formatter/view does not exist.

**Step 3: Write minimal implementation**

- Add a `ServerLogView` sheet that shows a scrollable log tail with auto-follow toggle and a stop button.
- Add a new “Servers” section in `ContentView` that shows unmatched `PortInfo` entries (not mapped to any project/workspace), with process name, port, and cwd.
- Add a per-project “Logs” action for managed servers to open `ServerLogView`.
- Add a `Run dev servers inside Noodles` toggle in Settings and store it in Config.
- Update the port polling timer to use `config.pollIntervalMs` (default remains 2000).

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -project Noodles.xcodeproj -scheme NoodlesTests -destination 'platform=macOS'`
Expected: PASS.

**Step 5: Commit**

```bash
git add Noodles/ContentView.swift Noodles/ProjectCard.swift Noodles/SettingsView.swift Noodles/AppState.swift
git commit -m "feat: server log view and visibility"
```

---

### Task 6: Manual verification

**Files:**
- None

**Step 1: Run the app**

Run: `xcodebuild -project Noodles.xcodeproj -scheme Noodles -destination 'platform=macOS' build`
Expected: Build succeeds.

**Step 2: Validate managed server flow**

- Start a project with “Run dev servers inside Noodles” enabled.
- Verify status changes to running and logs stream in the log view.
- Stop it and verify the process is terminated and status moves to stopped.

**Step 3: Validate external visibility**

- Start a dev server in a terminal outside Noodles.
- Verify it shows up in the “Servers” section with port and process name.

---

Plan complete and saved to `docs/plans/2026-02-03-dev-server-visibility.md`. Two execution options:

1. Subagent-Driven (this session) - I dispatch a fresh subagent per task, review between tasks, fast iteration
2. Parallel Session (separate) - Open new session with executing-plans, batch execution with checkpoints

Which approach?
