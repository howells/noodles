# Noodles v2: Simplification

## What changed

Noodles was built as a full Node.js dev server manager — start, stop, configure, monitor. In practice, the only actions used are: **see what's running, kill it, open it in the browser, and check the logs**. This spec strips the app down to exactly that.

## Core concept

Noodles v2 is a **port monitor**, not a project manager. It watches for listening ports in the dev range, resolves them to project directories, and gives you three clicks: kill, open, view logs. It does not start servers, manage processes, or scan for projects.

## Features

### See what's running

Poll `lsof` for TCP ports in LISTEN state within the dev range (3000–9999). For each port:

- Resolve PID to working directory (`lsof -p PID | grep cwd`)
- Extract project name from the directory path (last path component)
- Show port number, project name, and display path

**Process filtering:** Only show processes whose executable is a known dev runtime: `node`, `bun`, `deno`, `next-server`, `vite`. This excludes system services like Postgres (:5432), Redis (:6379), etc. that happen to listen in the dev port range.

**Multiple ports, same project:** If two ports resolve to the same cwd, they are grouped into a single card showing multiple port badges (e.g., `:3000 :3001`). Kill kills the process group. Logs point to the same file.

**Card sort order:** Port number ascending (lowest port first).

**Poll interval:** 2 seconds (matches current app). Poll calls have a 5-second timeout — if `lsof` hangs (e.g., NFS mounts), the call is killed and the UI retains the last known state. The `isPolling` guard from v1 prevents overlapping polls.

**No project scanning.** The app never reads ~/Sites or looks for package.json files. It only knows about things that are actively listening on ports.

### Kill

Tree-kill the process owning a port. Same approach as current app:

1. `kill -TERM` to process group via `killpg`
2. Wait 2 seconds
3. `kill -KILL` if still alive
4. `pgrep -P pid` fallback for escaped children

**Kill transition state:** On click, the card immediately shows a "stopping" state — orange status dot, all action buttons disabled, spinner replacing the kill button. This state persists until the next poll confirms the port is gone (card removed) or the process refuses to die (card returns to green with buttons re-enabled after 5 seconds).

### Open in browser

Open `http://localhost:<port>` in the default browser. One click per port.

### View logs

Read from `~/.cache/noodles/logs/<project-name>.log`. This file is written by a fish shell wrapper (see below). The log viewer is read-only — the app never writes to or manages this file.

**Log viewer behavior:**
- Opens as an inline panel (right side, same as current app)
- Popover resizes horizontally when log panel opens/closes (carry over `popoverResize` notification from v1)
- Monospaced text, dark background
- ANSI escape codes stripped (not rendered as colors)
- Auto-follow on by default (resets each time panel opens)
- 1000-line display buffer (tail of file)
- **File reading:** backward seek from EOF to find the last 1000 lines. Never read the full file — dev server logs can grow to hundreds of MB on long-running sessions.
- File polling: check file every 1 second when panel is open
- Only one log panel open at a time. Clicking [logs] on a different card switches the panel.
- "No logs available" state when file doesn't exist

**Log panel lifecycle:** The panel tracks a log file path, not a server reference. If the server dies and its card disappears, the log panel stays open showing the last content with a "Server stopped" label in the header. The user can close it manually.

### Reveal terminal

Find the terminal window that owns the running process and bring it to focus:

1. Walk up the process tree from the server PID via `ppid`
2. Match parent chain against known terminal bundle IDs (Terminal.app, iTerm2, Kitty, Ghostty, Warp, Alacritty)
3. Use `NSRunningApplication` to activate the matched app
4. For VS Code (Electron parent), activate the VS Code window

This is best-effort — if the owning terminal can't be identified, the button is hidden for that entry. Terminal resolution runs once per server at detection time (not every poll). Uses `sysctl` / `proc_pidinfo` to walk the ppid chain, not `lsof`. Lives in its own `TerminalResolver.swift` file to keep `PortMonitor` focused on port detection.

## Fish shell wrapper

A `ndev` function (avoiding collision with the existing `dev` alias) that wraps the project's dev command with log capture:

```fish
function ndev
    set -l logdir ~/.cache/noodles/logs
    set -l logfile $logdir/(basename $PWD).log
    mkdir -p $logdir
    echo "" > $logfile

    if test -f bun.lockb; or test -f bun.lock
        bun run dev 2>&1 | tee $logfile
    else if test -f pnpm-lock.yaml
        pnpm run dev 2>&1 | tee $logfile
    else if test -f yarn.lock
        yarn dev 2>&1 | tee $logfile
    else
        npm run dev 2>&1 | tee $logfile
    end
end
```

This is **not part of the Swift app**. It ships as a separate dotfile/config that the user installs once. The app works without it — you just won't have logs.

**Log file naming:** Uses `basename $PWD` which means two projects with the same directory name (e.g., `~/Sites/app` and `~/work/app`) will collide. This is a known limitation — acceptable given the user's project layout is flat under ~/Sites.

## UI design

### Preserve the current aesthetic

The current app looks good. Keep:

- System NSColors (`windowBackgroundColor`, `controlBackgroundColor`, `separatorColor`)
- 8pt corner radii on cards, 4pt on badges
- 13pt medium project names, 11pt regular paths, 10pt monospaced ports
- Green/orange/red status dots (8px)
- Compact spacing (12px card padding, 4px between cards)
- 2x2 dot grid status bar icon (green = running count)
- Snappy 0.2s easeInOut animations
- Hover states at `color.opacity(0.15)`

### Layout

```
┌──────────────────────────────────────────┐
│  Noodles                        ⟳  ···  │  <- header: title, refresh, menu
├──────────────────────────────────────────┤
│                                          │
│  ┌────────────────────────────────────┐  │
│  │ ● my-app                          │  │
│  │   ~/Sites/my-app           :3000  │  │
│  │              [logs] [open] [kill]  │  │
│  └────────────────────────────────────┘  │
│                                          │
│  ┌────────────────────────────────────┐  │
│  │ ● dashboard                       │  │
│  │   ~/Sites/dashboard        :5173  │  │
│  │              [logs] [open] [kill]  │  │
│  └────────────────────────────────────┘  │
│                                          │
│  ┌────────────────────────────────────┐  │
│  │ ● api-server                      │  │
│  │   ~/Sites/api              :8080  │  │
│  │              [logs] [open] [kill]  │  │
│  └────────────────────────────────────┘  │
│                                          │
│              Nothing else running        │
│                                          │
└──────────────────────────────────────────┘
```

**Popover dimensions:** 380×500 (slightly narrower and shorter — less content to show).

### Card actions

Action buttons are always visible (right-aligned). With only 3–4 buttons per card, hover-to-reveal adds friction without saving space.

| Button | Icon | Action | Visibility |
|--------|------|--------|-----------|
| Reveal | `terminal` | Focus the owning terminal window | Only when terminal resolved |
| Logs | `text.justify.left` | Open/close log panel | Only when `hasLogs` is true |
| Open | `globe` | Open `localhost:port` in browser | Always |
| Kill | `xmark.circle` | Kill the process | Always (disabled during kill transition) |

During kill transition: kill button replaced with spinner, all other buttons disabled.

### Empty state

When nothing is running:

```
┌──────────────────────────────────────────┐
│  Noodles                        ⟳  ···  │
│                                          │
│                                          │
│           No servers running             │
│                                          │
│                                          │
└──────────────────────────────────────────┘
```

Centered, secondary text color, no further calls to action.

### Log panel

Opens to the right of the main panel (same pattern as current app):

```
┌──────────────────────┬───────────────────────────┐
│  main panel (380px)  │  log panel (440px)        │
│                      │                           │
│                      │  my-app :3000        ✕   │
│                      │  ─────────────────────── │
│                      │  > Ready on :3000        │
│                      │  > Compiled /page        │
│                      │  > GET / 200 12ms        │
│                      │                           │
└──────────────────────┴───────────────────────────┘
```

### Menu (gear icon)

Only two items:

- **Quit Noodles** (Cmd+Q)
- **Launch on Login** toggle

No settings panel. No editor/terminal selection. No project directory config.

## Architecture

### Files (target: ~600 lines total)

| File | Purpose | ~Lines |
|------|---------|--------|
| `NoodlesApp.swift` | App entry, menu bar, popover, status icon, launchOnLogin | ~100 |
| `Models.swift` | `RunningServer` struct | ~40 |
| `PortMonitor.swift` | `lsof` polling, PID→cwd resolution, process name filtering | ~140 |
| `TerminalResolver.swift` | ppid chain walk, terminal app matching | ~60 |
| `ProcessKiller.swift` | Tree-kill logic | ~80 |
| `ContentView.swift` | Server list, empty state | ~80 |
| `ServerCard.swift` | Card UI, action buttons, kill transition state | ~70 |
| `LogPanel.swift` | Log file tail reader (backward seek), scrollable output | ~100 |
| **Total** | | **~670** |

### No actors

The current app uses a Swift `actor` for `ProcessManager` because it manages concurrent process lifecycles. The simplified app doesn't manage processes — it polls `lsof` and reads files. A simple `@MainActor ObservableObject` is sufficient.

### Data model

```swift
struct RunningServer: Identifiable {
    let id: String       // cwd path (groups multiple ports from same project)
    let ports: [Int]     // all listening ports for this project
    let pids: [Int]      // corresponding PIDs
    let name: String     // last path component of cwd
    let path: String     // full cwd path
    let displayPath: String  // ~ substituted
    var hasLogs: Bool    // whether log file exists (checked at detection time)
    var terminalApp: String? // bundle ID of owning terminal, if resolved
}
```

### State

```swift
@MainActor
class AppState: ObservableObject {
    @Published var servers: [RunningServer] = []
    @Published var activeLogPath: String? = nil  // log file path, survives server death
    @Published var activeLogName: String? = nil   // display name for log panel header
    @Published var isKilling: Set<String> = []    // server IDs currently being killed
    @Published var launchOnLogin: Bool
}
```

### Launch on Login

Use `ServiceManagement.SMAppService` (macOS 13+). Carry forward the `syncLaunchOnLoginState` pattern from v1 — on app launch, read the actual system registration state and update the published `launchOnLogin` to match, in case the user toggled it externally via System Settings.

## What gets removed

| Current feature | Lines | Removed because |
|----------------|-------|-----------------|
| Project scanning | ~470 | No project discovery needed |
| Managed server mode | ~300 | App doesn't start processes |
| Server start/restart | ~200 | Never used |
| Log capture via pipes | ~150 | Replaced by file reading |
| Settings panel | ~350 | No settings to configure |
| Editor/terminal integration | ~100 | Not needed |
| Pin/hide projects | ~80 | No project list |
| Custom port config | ~80 | No port configuration |
| Workspace/monorepo support | ~200 | No project awareness |
| Search/filter | ~60 | Typically <10 servers running |
| Config file management | ~100 | Only `launchOnLogin` persists |
| **Total removed** | **~2,090** | |

## What stays (adapted)

| Current feature | Adaptation |
|----------------|------------|
| `lsof` port polling | Keep, but poll all dev ports instead of matching against known projects |
| Tree-kill | Keep as-is |
| Port badges | Become the primary identifier on each card |
| Status bar 2x2 dots | Keep |
| Log viewer UI | Keep layout, but read from file instead of pipe |
| Popover/panel pattern | Keep |

## Out of scope

- Starting servers
- Restarting servers
- Project configuration
- Package manager detection (in the app — the fish function handles this)
- Monorepo/workspace awareness
- Editor integration
- Terminal selection
- Settings beyond launch-on-login
- Search/filter (unnecessary at <10 items)

## Testing

Unit tests for:
- `PortMonitor`: lsof output parsing, process name filtering, cwd resolution, port grouping by project
- `ProcessKiller`: tree-kill sequencing (mock process signals)
- `TerminalResolver`: ppid chain walking, bundle ID matching
- `LogPanel`: backward-seek tail reading, ANSI stripping

No E2E tests (native macOS app, manual testing is sufficient for this scope).

## Migration

This is a full rewrite, not a refactor. The current codebase is 3,877 lines across 8 files with deeply coupled managed-server assumptions. Starting fresh with the ~670-line target is cleaner than trying to surgically remove features.

### Reusable from v1

These pieces from the current codebase can be carried forward with minimal changes:
- `createGridIcon` from `NoodlesApp.swift` (status bar icon rendering)
- `popoverResize` notification pattern from `NoodlesApp.swift`
- `killTree` logic from `ProcessManager.swift`
- `runCommandAsync` from `ProcessManager.swift`
- `batchGetProcessCwds` pattern from `ProcessManager.swift`

The current app's visual constants (colors, fonts, spacing, radii) should be referenced during the rewrite to maintain visual continuity.
