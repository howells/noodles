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
│   ├── app/
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

`internal/app`

Owns the core use cases:

- `Scan(ctx, query) Snapshot`
- `BuildKillPlan(ctx, request) KillPlan`
- `Kill(ctx, plan) KillResult`

This package is the shared orchestration layer for the Wails app and future CLI. `internal/desktop` and `cmd/noodles` should be thin adapters over it.

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

## Scanner Contract

The first implementation is macOS-only.

It scans TCP listeners across all ports with a single all-listeners pass. It must not perform per-port scanning. IPv4 and IPv6 listeners count, including `127.0.0.1`, `::1`, `0.0.0.0`, and `::`.

Scanning is two-phase:

1. Enumerate listening sockets and collect candidate PIDs.
2. Enrich only candidate PIDs plus required parent-chain and process-group PIDs.

Raw command or OS API collection should be isolated from pure parsers. Parser tests should use golden output fixtures. Permission gaps should be reported in scan metadata rather than silently ignored.

The scanner should avoid overlapping scans. Refresh policy:

- Scan on app open.
- Scan on app focus.
- Scan on manual refresh.
- Scan after kill completion.
- Poll only while the window is visible, at a bounded interval.
- Skip or back off when the previous scan exceeds the interval.

Scan metadata should include `snapshotId`, `scanStartedAt`, `scanFinishedAt`, `scanDurationMs`, `lastSuccessfulScanAt`, and `scanSkippedReason` when applicable.

CPU values are sampled. `cpuPercent` is unavailable until the app has two process CPU-time samples over a known interval. The UI should not show fake precision on the first scan.

Memory should be explicit. Use `residentMemoryBytes` for v1 unless the platform layer supports a better macOS physical-footprint measure. Project totals are best-effort sums and may overcount shared pages. Include `memoryUnavailableReason` when measurement fails.

Project-root detection should be cached by normalized CWD and process identity. Avoid Git/package/workspace filesystem walks on every row for every scan.

## Data Model

The desktop snapshot should include:

- Services: one row per meaningful local service.
- Projects: detected projects and aggregate usage.
- Groups: available grouping dimensions.
- Scan metadata: timestamp, duration, permission gaps, scanner warnings.

Service fields:

- `id`
- `snapshotId`
- `pid`
- `processGroupId`
- `parentPid`
- `command`
- `commandLine`
- `executablePath`
- `cwd`
- `projectId`
- `projectName`
- `projectDisplayName`
- `projectRoot`
- `workspaceRoot`
- `ports`
- `residentMemoryBytes`
- `memoryUnavailableReason`
- `cpuPercent`
- `cpuUnavailableReason`
- `startedAt`
- `ageSeconds`
- `sourceLabel`
- `sourceConfidence`
- `sourceEvidence`
- `killable`
- `warnings`

`service.id` is stable within a snapshot and should be based on process identity, not only PID. Use `pid + startedAt + executablePath/command + listener identity` where available. Kill actions must not trust a stale row ID without revalidation.

Canonical service aggregation:

- A row represents a primary listening process and its attached listening ports.
- Multiple ports owned by the same listener process render in one row.
- Child processes are metadata unless they also own listening sockets.
- Process tree data is used for kill planning, not for duplicating rows.

Project fields:

- `id`
- `name`
- `displayName`
- `root`
- `workspaceRoot`
- `serviceCount`
- `totalResidentMemoryBytes`
- `ports`
- `sourceLabels`
- `killableServiceCount`
- `excludedServiceCount`

## Main UI

The main screen is a dense operational table.

Default row sort:

1. Memory descending.
2. CPU descending when available.
3. Project name ascending.
4. Lowest port ascending.

Default project-group sort:

1. Aggregate memory descending.
2. Killable service count descending.
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

Supported filtering:

- Search text.
- Project.
- Source label.
- Port.
- Killable only.
- Hide system rows.
- Memory threshold.

Sorting, grouping, and filtering are owned by the Go core through `internal/app`. React renders the returned view model so the desktop UI and future CLI share identical behavior.

Row sorting and group sorting are separate. Row memory sort uses row memory; group memory sort uses aggregate group memory. Port sort uses the lowest displayed port as the primary key and the full port list as a tie-breaker.

Each row should show:

- Project or cwd.
- Process command.
- Ports.
- Memory.
- CPU.
- Age.
- Source label.
- One-click kill button.

Project groups should show aggregate memory, killable count, excluded count, ports, source-label mix, and a scoped `Kill N` action.

The UI should be compact and work-focused. It should avoid marketing-style cards and oversized dashboard treatment. This is an operational tool.

Main UI states:

- Scanning.
- Stale snapshot.
- Empty results.
- No killable services.
- Permission warning.
- Partial refresh failure.
- Backend unavailable.
- Killing.
- Killed and removed.
- Kill failed.

Keyboard interaction should be fast but deliberate. Table navigation, refresh, sort, and filter shortcuts are allowed. Killing should require focus on the row/group kill control or a deliberate shortcut such as `Cmd+Backspace`; there should be no global single-key kill.

## Kill Semantics

One-click kill is intentional.

For a service row, the UI triggers a backend kill request. The backend builds a `KillPlan`, revalidates it, and then kills the selected process tree. The UI should immediately mark the row as killing, then refresh after completion.

For a project group, kill every killable service directly associated with that project.

The app should not show a confirmation dialog by default. It may expose an optional setting later, but v1 should preserve the sniper posture.

Kill failures should stay visible. If a process cannot be killed, show the reason inline and keep the row in the list.

Kill requests should include:

- `snapshotId`
- `serviceId` or `projectId`
- `pid`
- `processGroupId`
- `startedAt`
- `command`
- `executablePath`
- `cwd`
- `projectRoot`
- expected `ports`

Before signaling, the backend revalidates `pid + startedAt + command/executablePath + cwd/projectRoot + ports`. If identity changed, the kill fails visibly instead of signaling a reused PID.

`KillPlan` should list every target PID, signal order, and inclusion/exclusion reason. `KillResult` should report success or failure per target.

Project kill boundaries:

- Include killable service rows whose primary listener process is associated with the selected project.
- Exclude parent terminals, editors, browsers, and agent hosts unless they are the selected service process itself.
- Exclude system rows.
- Exclude low-confidence unknowns outside developer roots.
- Exclude ambiguous project matches.
- Surface excluded counts and reasons instead of silently ignoring them.

Escalation is `SIGTERM`, wait a bounded timeout, then `SIGKILL` for remaining targets.

## Classification Rules

The first implementation should prefer transparent heuristics:

- Listening TCP port means candidate service.
- `node`, `bun`, `deno`, `vite`, `next`, `storybook`, `tsx`, and similar commands are likely development services.
- Known browser automation processes can be labeled separately from project dev servers.
- Parent chain can hint at terminal, editor, or agent source.
- CWD under `~/Sites` strongly suggests developer-owned process.
- Processes outside developer roots should be shown only when they expose local listener ports and match a development/tooling signature.

Unknowns should remain visible when useful, but clearly labeled `unknown`.

`sourceConfidence` should be one of `low`, `medium`, or `high`. Each label should include `sourceEvidence`, a short list of facts used to classify the row, so the UI can explain the label and tests can assert behavior.

## CLI

A CLI should share the Go core. It can arrive after the first Wails UI, but the core should be designed so these commands are natural:

```bash
noodles list
noodles list --sort memory
noodles kill --pid 12345
noodles kill --port 3000
noodles kill --project materia
noodles kill --project-root /Users/danielhowells/Sites/materia
```

The CLI is valuable for agents, scripts, and terminal cleanup.

Project display names may collide. CLI project-name kills should fail with candidate roots when the name is ambiguous. `--project-root` should be accepted for exact targeting.

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

Migration inventory:

- Port useful parser fixtures from the Swift tests into Go golden fixtures.
- Preserve the current failure examples, especially ignored high ports and basename log collisions, as v2 tests.
- Delete Swift only after equivalent v2 characterization tests exist for scanning, project identity, and process-tree kill planning.

The marketing site can remain in the repo and be updated after the product UI stabilizes.

## Testing Strategy

The Go core should have characterization tests for:

- Parsing process and port command output.
- Mapping CWDs to project roots.
- Grouping services by project.
- Sorting by memory, CPU, age, and port.
- Kill plan construction.
- Classification confidence.
- Scanner refresh policy and skipped-scan behavior.
- CPU sampling with first-scan unavailable state.
- Project-root cache hits.
- Synthetic many-listener snapshots.
- Ambiguous project names.

Killer tests should avoid killing arbitrary real processes. Use spawned test processes in controlled fixtures.

The React UI should be tested through the desktop service contract and browser-level smoke checks once the Wails shell exists.

## Open Decisions

- Whether log viewing belongs in v1 or should wait.
- Whether to include non-listening high-memory Node processes.
- Whether to expose an optional confirmation setting after v1.
- Exact visible polling interval and backoff thresholds.

## Recommended First Build Slice

Build the Go core first, then the Wails shell.

Milestone 1:

- Scan local listeners across all ports.
- Attach process metadata: command, CWD, memory, CPU, parent PID, process group.
- Resolve project root.
- Produce a sorted/grouped/filtered view model from Go.
- Render a sortable React table from that view model.
- Build and execute a revalidated kill plan for one service process tree.

Milestone 2:

- Add project group headers with included/excluded counts.
- Kill all services for a project.
- Add ambiguous project handling.
- Add UI states for scanning, stale snapshots, permission gaps, and kill failures.

This slice directly addresses the original pain: agents and development tools leave local services running, and the user needs a fast way to identify and remove them.
