# Reliability Hardening Plan (v2 — post-review)

## Problem
Noodles suffers from beach balls and unreliable start/stop behavior. Root causes:
- Blocking `lsof` calls on the ProcessManager actor freeze the entire process management pipeline
- Overlapping poll tasks can overwrite each other's results
- Potential deadlock on app quit leaves orphaned processes
- Process group management fails silently, leaving grandchild processes alive
- 95 projects scanned synchronously on the main thread
- Managed server entries leak memory indefinitely
- O(n) lsof calls per PID for CWD resolution (11+ process spawns per poll cycle)

## Design Principles
1. **Never block the main thread** — all IO moves to background threads
2. **Never block the actor** — replace `waitUntilExit()` with async process execution
3. **One poll at a time** — cancel stale polls before starting new ones
4. **Reliable process trees** — signal groups first, tree-kill as fallback
5. **Graceful shutdown** — parallel SIGTERM → shared wait → SIGKILL
6. **Clean up after yourself** — remove terminated servers from memory on replacement

## Changes

### 1. Make `runCommand` non-blocking (ProcessManager.swift)
**The biggest win.** Replace the blocking `waitUntilExit()` with an async pattern.

The naive approach of calling `readDataToEndOfFile()` before the continuation causes a
**pipe buffer deadlock** — if output exceeds ~64KB, the subprocess blocks writing, but
we're blocking reading. Instead, use `readabilityHandler` to stream data into a buffer
(same pattern already used for managed server stdout/stderr).

```swift
private func runCommandAsync(_ command: String, arguments: [String]) async -> String {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: command)
    process.arguments = arguments
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    do {
        try process.run()
    } catch {
        return ""
    }

    // Stream data via readabilityHandler to avoid pipe buffer deadlock.
    // readDataToEndOfFile() blocks until the write end closes — if the subprocess
    // output exceeds the ~64KB pipe buffer, the process blocks writing while we
    // block reading. Using readabilityHandler avoids this by draining incrementally.
    let dataActor = DataAccumulator()
    pipe.fileHandleForReading.readabilityHandler = { handle in
        let chunk = handle.availableData
        if !chunk.isEmpty {
            Task { await dataActor.append(chunk) }
        }
    }

    // Wait for process exit without blocking the actor
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        process.terminationHandler = { _ in
            continuation.resume()
        }
    }

    // Process has exited — read any remaining data and clean up
    pipe.fileHandleForReading.readabilityHandler = nil
    let remainingData = pipe.fileHandleForReading.readDataToEndOfFile()
    let accumulated = await dataActor.getData()
    var allData = accumulated
    allData.append(remainingData)

    return String(data: allData, encoding: .utf8) ?? ""
}

// Simple actor to accumulate data from readabilityHandler callbacks
private actor DataAccumulator {
    private var data = Data()
    func append(_ chunk: Data) { data.append(chunk) }
    func getData() -> Data { data }
}
```

Update `getListeningPorts()` and `getProcessCwdFast()` to use the async version.

### 2. Batch CWD resolution into a single lsof call (ProcessManager.swift)
**10x reduction in process spawns per poll cycle.**

Currently: 1 global `lsof` for ports + N per-PID `lsof` calls for CWDs = 11+ spawns.
Instead, batch all PID CWD lookups into a single `lsof` call:

```swift
private func batchGetProcessCwds(pids: [Int]) async -> [Int: String] {
    guard !pids.isEmpty else { return [:] }

    // Filter out cached PIDs
    var needed: [Int] = []
    var result: [Int: String] = [:]
    for pid in pids {
        if let cached = cachedCwd(pid: pid) {
            result[pid] = cached
        } else {
            needed.append(pid)
        }
    }

    guard !needed.isEmpty else { return result }

    // Single lsof call for ALL PIDs at once
    let pidArgs = needed.map(String.init).joined(separator: ",")
    let output = await runCommandAsync("/usr/sbin/lsof", arguments: ["-a", "-p", pidArgs, "-d", "cwd", "-Fn"])

    // Parse: lines alternate between "p<pid>" and "n<path>"
    var currentPid: Int?
    for rawLine in output.split(whereSeparator: \.isNewline) {
        guard let prefix = rawLine.first else { continue }
        let value = rawLine.dropFirst()
        switch prefix {
        case "p":
            currentPid = Int(value)
        case "n":
            if let pid = currentPid {
                let cwd = String(value)
                if !cwd.isEmpty {
                    result[pid] = cwd
                    cacheCwd(pid: pid, path: cwd)
                }
            }
        default:
            continue
        }
    }

    return result
}
```

Update `getListeningPorts()` to call `batchGetProcessCwds` once instead of
`getProcessCwdFast` per PID. Total: 2 lsof calls per poll (ports + CWDs) regardless of PID count.

### 3. Prevent overlapping poll tasks (AppState.swift)
Add a guard so only one poll runs at a time. Since `refreshPortsSync()` is `@MainActor`,
the flag check and set are atomic within the same synchronous execution context.

```swift
private var isPolling = false

private func refreshPortsSync() {
    guard !isPolling else { return }
    isPolling = true

    Task {
        let currentPorts = await processManager.getListeningPorts()
        let currentManagedServers = await processManager.getManagedServers()
        // ... rest of existing update logic ...
        self.isPolling = false
    }
}
```

Note: `isPolling = false` is set at the END of the Task body (which resumes on MainActor),
not in a defer block, ensuring it's cleared only after all state updates complete.

### 4. Fix app quit — parallel cleanup without deadlock (NoodlesApp.swift + ProcessManager.swift)

**Problem:** The current semaphore pattern deadlocks because `applicationWillTerminate` blocks
the main thread, but `Task { @MainActor in }` needs the main thread.

**Problem with plan v1:** `cleanupSync()` can't access actor-isolated `managedServers`.

**Solution:** Maintain a `nonisolated` cleanup registry alongside the actor state. This is a
simple array of `(pid: Int32, groupId: Int32?)` updated whenever a server starts or terminates.
Since it's only written from within the actor and only read during cleanup (when no other code
is running), this is safe.

```swift
actor ProcessManager {
    // Atomic cleanup registry — updated on start/terminate, read during sync cleanup
    // nonisolated(unsafe) because it's ONLY read in applicationWillTerminate
    // after the run loop has stopped, so no concurrent access is possible.
    nonisolated(unsafe) private var cleanupRegistry: [(pid: Int32, groupId: Int32?)] = []

    // Called from startManagedCommand after process.run()
    private func registerForCleanup(pid: Int32, groupId: Int32?) {
        cleanupRegistry.append((pid: pid, groupId: groupId))
    }

    // Called from handleManagedServerTermination
    private func unregisterFromCleanup(pid: Int32) {
        cleanupRegistry.removeAll { $0.pid == pid }
    }

    // Called ONLY from applicationWillTerminate — synchronous, no actor isolation needed
    nonisolated func cleanupAllSync() {
        let entries = cleanupRegistry

        // Phase 1: SIGTERM all process groups and PIDs in parallel
        for entry in entries {
            if let groupId = entry.groupId, groupId > 0 {
                kill(-groupId, SIGTERM)
            }
            kill(entry.pid, SIGTERM)
        }

        // Phase 2: Shared wait (max 2 seconds total, not per-process)
        let deadline = Date().addingTimeInterval(2.0)
        var remaining = entries
        while !remaining.isEmpty && Date() < deadline {
            usleep(100_000) // 100ms
            remaining = remaining.filter { kill($0.pid, 0) == 0 }
        }

        // Phase 3: SIGKILL survivors
        for entry in remaining {
            if let groupId = entry.groupId, groupId > 0 {
                kill(-groupId, SIGKILL)
            }
            kill(entry.pid, SIGKILL)
        }
    }
}
```

AppDelegate:
```swift
func applicationWillTerminate(_ notification: Notification) {
    if let monitor = keyboardMonitor {
        NSEvent.removeMonitor(monitor)
    }
    NotificationCenter.default.removeObserver(self)
    appState.portPollingTimer?.invalidate()
    appState.processManager.cleanupAllSync()
}
```

This never blocks for more than ~2 seconds total (regardless of server count), well under
the macOS ANR threshold of ~5 seconds. No async bridge, no deadlock.

### 5. Fix process group creation + tree-kill fallback (ProcessManager.swift)
Keep `setpgid` after `process.run()` (Option A) but improve the stop flow:

1. Signal the process GROUP first (if setpgid succeeded)
2. Use `pgrep -P` tree traversal as a fallback
3. Accept that `pgrep` has a TOCTOU race (processes can exit between discovery and signaling) —
   this is inherent to user-space tree killing and harmless (kill on a dead PID returns ESRCH)

```swift
private func killTree(pid: Int32, groupId: Int32?, signal: Int32) {
    // Strategy: group signal first (catches most children), then tree walk for stragglers
    if let groupId = groupId, groupId > 0 {
        kill(-groupId, signal)
    }

    // Fallback: walk the process tree for any children that escaped the group
    killChildrenRecursive(parentPid: pid, signal: signal)

    // Finally signal the parent itself (may be redundant if group signal hit it)
    kill(pid, signal)
}

// nonisolated because it uses a synchronous runCommand variant and is also
// called from cleanupAllSync. Uses /usr/bin/pgrep which is fast (<5ms).
private nonisolated func killChildrenRecursive(parentPid: Int32, signal: Int32) {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    process.arguments = ["-P", String(parentPid)]
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""

    for line in output.split(whereSeparator: \.isNewline) {
        if let childPid = Int32(line) {
            killChildrenRecursive(parentPid: childPid, signal: signal)
            kill(childPid, signal)
        }
    }
}
```

Update `stopManagedServer` to use `killTree` instead of `signalProcess`.

### 6. Move filesystem scan off main thread (AppState.swift)
Capture `config` by value in the closure to avoid accessing @MainActor state from
the detached task.

```swift
func scan() {
    guard !isScanning else { return }
    isScanning = true

    let capturedConfig = config  // Capture the struct (value type) here

    Task.detached { [scanner] in
        let scanned = scanner.scan(sitesPath: capturedConfig.sitesPath)
        await MainActor.run { [weak self] in
            guard let self else { return }
            var projects = scanned
            for i in projects.indices {
                if let customPort = capturedConfig.customPorts[projects[i].id] {
                    projects[i].customPort = customPort
                }
            }
            self.projects = projects.sorted { a, b in
                a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
            self.isScanning = false
            self.startPortPolling()
        }
    }
}
```

### 7. Clean up terminated managed servers (ProcessManager.swift)
**Don't use a 5-minute timer** — this creates UUID collision problems with restarts.

Instead: remove from `managedServers` immediately when the UUID mapping is overwritten
by a new server start. Keep terminated servers until then (for log viewing). If a project
is restarted, the old entry is evicted at the point the new UUID is stored.

In AppState, when `startProject` succeeds:
```swift
// If there was an old managed server, clean it up
if let oldId = managedProjectServers[project.id] {
    Task { await processManager.removeManagedServer(id: oldId) }
}
managedProjectServers[project.id] = newId
```

In ProcessManager, add:
```swift
func removeManagedServer(id: UUID) {
    guard let server = managedServers[id] else { return }
    // Close write ends of pipes
    try? server.stdout.fileHandleForWriting.close()
    try? server.stderr.fileHandleForWriting.close()
    managedServers.removeValue(forKey: id)
    unregisterFromCleanup(pid: server.process.processIdentifier)
}
```

### 8. Remove dead code (ProcessManager.swift)
- Delete `startDevServer()` — never called
- Remove `spawnedProcesses` array — only populated by dead code
- Simplify `cleanupSpawnedProcesses` → rename to `cleanupManagedServers`
  (only iterates `managedServers`, which is now handled by `cleanupAllSync`)

### 9. Fix restart race condition (AppState.swift)
Wrap the managed restart path in proper error handling. Also check `Task.isCancelled`
before proceeding with restart to avoid starting a server during app termination.

```swift
if let serverId = managedProjectServers[project.id] {
    Task {
        await processManager.stopManagedServer(id: serverId)
        do {
            try await Task.sleep(nanoseconds: 500_000_000)
        } catch {
            // Task.sleep was cancelled — check if we should abort
            guard !Task.isCancelled else { return }
        }
        await MainActor.run {
            self.managedProjectServers.removeValue(forKey: project.id)
            self.startProject(project)
        }
    }
    return
}
```

### 10. Clean up managed server tracking on stop (AppState.swift)
Clear the UUID mapping when a stop completes (inside the polling loop or after
the stop call returns). The mapping is cleared in `restartProject` (step 9) and
when a new server starts (step 7), ensuring no stale entries.

Add to the polling loop: when `applyManagedStatus` detects a server has exited
(not running, has exit code), and no stop was requested (crash), mark it clearly
in the UI.

### 11. Fix workspace stop path for turborepo (AppState.swift)
When stopping a workspace in a monorepo, the code calls
`stopProjectProcesses(projectPath: workspace.path)` but turbo runs from the
monorepo root. For unmanaged mode, use the project root path and filter by
the workspace's expected ports.

## Implementation Order
1. **Make `runCommand` async** (with readabilityHandler, not readDataToEndOfFile)
2. **Batch CWD resolution** — single lsof call for all PIDs
3. **Prevent overlapping polls** — isPolling guard
4. **Fix app quit** — cleanup registry + parallel SIGTERM/SIGKILL
5. **Fix process group / tree killing** — group signal + pgrep fallback
6. **Move scan off main thread** — Task.detached with captured config
7. **Clean up terminated servers** — evict on replacement, not on timer
8. **Remove dead code** — startDevServer, spawnedProcesses
9. **Fix restart race** — Task.isCancelled check
10. **Clean up managed server tracking** — clear stale UUID mappings
11. **Fix workspace stop path** — use project root for turbo

## What This Does NOT Change
- The UI layer (ContentView, ProjectCard, SettingsView) — no changes needed
- The project scanning logic (ProjectScanner) — the scan itself is fine, just needs to run off main thread
- The config system — works fine as-is
- The AppleScript terminal integration — not relevant for managed mode
