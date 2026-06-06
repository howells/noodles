# Noodles v2 Design

## Product Definition

Noodles v2 is a local development service triage app.

Its job is to answer, quickly and concretely:

- What local services are running?
- Which project, tool, terminal, browser, or agent appears to own them?
- Which ones are consuming the most memory?
- What can I kill right now?

The app is cleanup-first. It is not a menu bar widget and it is not primarily a process dashboard. It is a sniper tool for reclaiming local machine state when development servers, agents, browsers, and related tools have left services running.

## Primary User Story

As a developer using coding agents and multiple local projects, I want to see all local development services grouped or sorted however I choose, identify the expensive or stale ones, and kill them with one click.

The default experience should favor decisive cleanup:

- Open app.
- See services sorted by memory descending.
- Kill one process tree, one port listener, or every service for a project.
- Immediately see the list update.

## Core Product Principles

- One-click kill is the primary action.
- The app should explain enough to make a kill decision without forcing confirmation.
- Grouping and sorting are user-controlled.
- The core must be testable without a desktop UI.
- The app must treat unknown processes honestly rather than pretending classification is certain.
- Swift is abandoned. The new architecture follows the Monogrove shape: Go core, Wails desktop shell, React frontend.

## Architecture

Noodles v2 should be a Wails app with a Go backend and a React frontend.

Repository shape:

```text
.
├── desktop_main.go
├── desktop_app.go
├── frontend/
├── internal/
│   ├── classifier/
│   ├── desktop/
│   ├── killer/
│   ├── ports/
│   ├── processes/
│   └── projects/
├── site/
└── script/
```

The Go core owns all process discovery and mutation. React only renders state and calls backend actions.

### Go Packages

`internal/processes`

Lists processes, parent chains, process groups, command names, command lines, CWD, memory, CPU, start time, and executable path where available.

`internal/ports`

Maps listening TCP ports to PIDs. This must not repeat the current hard-coded `3000...9999` mistake. The scanner should include all local listeners by default, then classify likely development services.

`internal/projects`

Maps process CWDs to project identity. It should detect Git roots, package roots, workspace package roots, and common repo layouts under `~/Sites`.

`internal/classifier`

Tags each service with best-effort source labels such as `dev-server`, `storybook`, `agent`, `browser`, `node-tool`, `unknown`, and `system`. These labels are confidence-bearing hints, not facts.

`internal/killer`

Provides kill operations:

- Kill selected process tree.
- Kill selected listener by PID.
- Kill all services for a project.
- Escalate from `SIGTERM` to `SIGKILL` when needed.

`internal/desktop`

Wails-facing service layer. Exposes snapshots, grouping/sorting options, refresh actions, and kill actions to the frontend.

## Data Model

The desktop snapshot should include:

- Services: one row per meaningful local service.
- Projects: detected projects and aggregate usage.
- Groups: available grouping dimensions.
- Scan metadata: timestamp, duration, permission gaps, scanner warnings.

Service fields:

- `id`
- `pid`
- `processGroupId`
- `parentPid`
- `command`
- `commandLine`
- `cwd`
- `projectName`
- `projectRoot`
- `ports`
- `memoryBytes`
- `cpuPercent`
- `startedAt`
- `ageSeconds`
- `sourceLabel`
- `sourceConfidence`
- `killable`
- `warnings`

Project fields:

- `name`
- `root`
- `serviceCount`
- `totalMemoryBytes`
- `ports`
- `sourceLabels`

## Main UI

The main screen is a dense operational table.

Default sort:

1. Memory descending.
2. Running service count descending.
3. Project name ascending.

Supported grouping:

- None.
- Project.
- Tool/source.
- Port range.
- Terminal/parent app, where detectable.

Supported sorting:

- Memory.
- CPU.
- Port.
- Age.
- Project.
- Process name.
- Source label.

Each row should show:

- Project or cwd.
- Process command.
- Ports.
- Memory.
- CPU.
- Age.
- Source label.
- One-click kill button.

Project groups should show aggregate memory and a `Kill project` action.

The UI should be compact and work-focused. It should avoid marketing-style cards and oversized dashboard treatment. This is an operational tool.

## Kill Semantics

One-click kill is intentional.

For a service row, kill the selected process tree. The UI should immediately mark the row as killing, then refresh after completion.

For a project group, kill every killable service associated with that project.

The app should not show a confirmation dialog by default. It may expose an optional setting later, but v1 should preserve the sniper posture.

Kill failures should stay visible. If a process cannot be killed, show the reason inline and keep the row in the list.

## Classification Rules

The first implementation should prefer transparent heuristics:

- Listening TCP port means candidate service.
- `node`, `bun`, `deno`, `vite`, `next`, `storybook`, `tsx`, and similar commands are likely development services.
- Known browser automation processes can be labeled separately from project dev servers.
- Parent chain can hint at terminal, editor, or agent source.
- CWD under `~/Sites` strongly suggests developer-owned process.
- Processes outside developer roots should be shown only when they expose local listener ports and match a development/tooling signature.

Unknowns should remain visible when useful, but clearly labeled `unknown`.

## CLI

A CLI should share the Go core. It can arrive after the first Wails UI, but the core should be designed so these commands are natural:

```bash
noodles list
noodles list --sort memory
noodles kill --pid 12345
noodles kill --port 3000
noodles kill --project materia
```

The CLI is valuable for agents, scripts, and terminal cleanup.

## Migration From Current App

The existing Swift app should be treated as disposable reference material, not a foundation.

Keep these product ideas:

- Port opening.
- Project memory.
- Process tree killing.
- Log viewing if it can be made collision-free.

Do not keep these constraints:

- Menu bar-first UI.
- Hard-coded `3000...9999` port window.
- Basename-only log identity.
- Swift/Xcode project as the main development loop.

The marketing site can remain in the repo and be updated after the product UI stabilizes.

## Testing Strategy

The Go core should have characterization tests for:

- Parsing process and port command output.
- Mapping CWDs to project roots.
- Grouping services by project.
- Sorting by memory, CPU, age, and port.
- Kill plan construction.
- Classification confidence.

Killer tests should avoid killing arbitrary real processes. Use spawned test processes in controlled fixtures.

The React UI should be tested through the desktop service contract and browser-level smoke checks once the Wails shell exists.

## Open Decisions

- Whether log viewing belongs in v1 or should wait.
- Whether the app should persist preferred grouping and sort order.
- Whether to include non-listening high-memory Node processes.
- Whether to expose an optional confirmation setting after v1.

## Recommended First Build Slice

Build the Go core first, then the Wails shell.

First slice:

- Scan local listeners across all ports.
- Attach process metadata: command, CWD, memory, CPU, parent PID, process group.
- Resolve project root.
- Render a sortable React table.
- Kill one service process tree.
- Kill all services for a project.

This slice directly addresses the original pain: agents and development tools leave local services running, and the user needs a fast way to identify and remove them.
