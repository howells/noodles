# Noodles v2 Implementation Plan

Source spec: `docs/superpowers/specs/2026-06-07-noodles-v2-design.md`

## Scope Posture

Large-scope rebuild. This replaces the Swift menu bar implementation with a Monogrove-style Wails desktop app backed by a tested Go core and React frontend.

The first milestone proves the product's reliability surface before UI polish:

- all-port TCP listener scanning
- stable service identity
- project resolution
- classification evidence
- Go-owned sorting/filtering/grouping
- revalidated single-service kill plans

Project-level kill, CLI surface, and fuller UI states come after the core contract is proven.

## Detected Stack

- Current app: Swift/Xcode under `app/` and Next marketing site under `site/`
- Target app: Go + Wails v2 + React/Vite frontend
- Package manager: pnpm
- Go test runner: `go test ./...`
- Frontend typecheck/build: `pnpm --dir frontend build`
- Reference architecture: `/Users/danielhowells/Sites/monogrove`

No project-local `.ruler/` rules were found. Follow the existing Monogrove-style repository conventions and the reviewed Noodles v2 spec.

## File Structure

Create:

- `go.mod` — root Go module for the Wails app and core packages
- `wails.json` — Wails desktop configuration
- `desktop_main.go` — Wails entry point
- `desktop_app.go` — Wails-bound application methods
- `cmd/noodles/main.go` — CLI wrapper over the same Go core
- `internal/app/` — orchestration and view-model ownership
- `internal/ports/` — TCP listener parsing and collection
- `internal/processes/` — process metadata and parent-tree collection
- `internal/projects/` — CWD to project-root resolution
- `internal/classifier/` — source labels and evidence
- `internal/killer/` — kill-plan validation and signal execution
- `internal/desktop/` — thin service wrapper for Wails bindings
- `frontend/` — React/Vite operational table UI

Modify:

- `.gitignore` — keep Arc local activity log ignored
- `README.md` — update development commands after the new app exists

Defer:

- deleting `app/` Swift sources until v2 has equivalent characterization tests for scanning, project identity, and kill planning
- log viewing
- optional confirmation setting
- non-listening high-memory Node processes

## Test Coverage Plan

| Area | Test Files | Coverage |
| --- | --- | --- |
| Domain model | `internal/app/model_test.go` | stable IDs, port sorting, snapshot shape |
| Port scanning | `internal/ports/parser_test.go` | lsof fixtures, IPv4/IPv6, high ports, duplicate ports |
| Process metadata | `internal/processes/parser_test.go` | ps fixtures, parent chain fields, memory fields |
| Project resolution | `internal/projects/resolver_test.go` | Git roots, package roots, workspace roots, cache behavior |
| Classification | `internal/classifier/classifier_test.go` | labels, confidence, evidence |
| View model | `internal/app/view_test.go` | sort, filter, grouping, aggregate counts |
| Scan orchestration | `internal/app/scan_test.go` | two-phase scanning, metadata, skipped overlapping scan |
| Kill planning | `internal/killer/plan_test.go` | identity revalidation, stale PID rejection, exclusions |
| Kill execution | `internal/killer/executor_test.go` | signal order through fake signaler, per-target result |
| Desktop service | `internal/desktop/service_test.go` | Wails-safe methods call core |
| CLI | `cmd/noodles/main_test.go` or shell-level command test | ambiguous project handling and list command formatting |
| Frontend | `frontend/src/App.test.tsx` if test deps are added, otherwise build/typecheck and browser smoke | table states and action wiring |

## Tasks

<task id="1" depends="" type="auto">
  <name>Scaffold Go module and core domain model</name>
  <files>
    <create>go.mod</create>
    <create>internal/app/model.go</create>
    <test>internal/app/model_test.go</test>
  </files>
  <read_first>
    docs/superpowers/specs/2026-06-07-noodles-v2-design.md
    /Users/danielhowells/Sites/monogrove/go.mod
  </read_first>
  <action>
    Create module `github.com/howells/noodles` with Go 1.26.2 to match Monogrove.

    Define the core exported domain types in `internal/app/model.go`:
    - `Confidence string` constants: `low`, `medium`, `high`
    - `Service` with fields from the reviewed spec, using `ResidentMemoryBytes` instead of generic memory
    - `Project`
    - `Snapshot`
    - `ScanMetadata`
    - `Query` with SortBy, SortDirection, GroupBy, Search, ProjectID, SourceLabel, Port, KillableOnly, HideSystem, MemoryThresholdBytes
    - `ServiceID(pid int, startedAt time.Time, executablePath string, command string, ports []int) string`

    `ServiceID` must sort and include all ports, prefer executable path when present, fall back to command when absent, and include Unix nanos for startedAt.
  </action>
  <test_code>
    Create `internal/app/model_test.go` with tests that assert:
    - `ServiceID` is stable when ports are passed in different orders
    - `ServiceID` changes when PID changes
    - `ServiceID` changes when startedAt changes
    - `ServiceID` falls back to command when executablePath is empty
  </test_code>
  <verify>
    go test ./internal/app — all pass
  </verify>
  <done>Go module exists and app domain model has tested stable service IDs</done>
  <commit>feat(core): add service domain model</commit>
</task>

<task id="2" depends="1" type="auto">
  <name>Parse all TCP listeners from lsof output</name>
  <files>
    <create>internal/ports/parser.go</create>
    <test>internal/ports/parser_test.go</test>
  </files>
  <read_first>
    app/Noodles/PortMonitor.swift
    internal/app/model.go
  </read_first>
  <action>
    Implement pure parser `ParseLsofListeners(output string) ([]Listener, error)` in `internal/ports`.

    `Listener` fields:
    - PID int
    - Command string
    - Address string
    - Port int
    - Protocol string

    Parse `lsof -nP -iTCP -sTCP:LISTEN -Fpcn` style output. Include IPv4 and IPv6. Include high ports such as 15070 and 30000. Deduplicate same PID+port+address. Do not filter to Node processes in this package.
  </action>
  <test_code>
    Tests must cover:
    - single `node` listener on `*:3000`
    - IPv6 listener on `[::1]:5173`
    - wildcard listener on `*:30000`
    - duplicate same PID/port is returned once
    - non-node command is still parsed
  </test_code>
  <verify>
    go test ./internal/ports — all pass
  </verify>
  <done>lsof listener parser includes all TCP listener ports without hard-coded dev-port filtering</done>
  <commit>feat(ports): parse TCP listener output</commit>
</task>

<task id="3" depends="2" type="auto">
  <name>Add listener collection command boundary</name>
  <files>
    <modify>internal/ports/parser.go</modify>
    <create>internal/ports/collector.go</create>
    <test>internal/ports/collector_test.go</test>
  </files>
  <read_first>
    internal/ports/parser.go
  </read_first>
  <action>
    Add `CommandRunner` interface and `Collector` type to run one all-listeners command:
    `/usr/sbin/lsof -nP -iTCP -sTCP:LISTEN -Fpcn`.

    Collector must call the runner exactly once per collection and feed output to `ParseLsofListeners`.
  </action>
  <test_code>
    Tests must use a fake runner and assert:
    - command path and arguments match the spec
    - runner is called once
    - parsed listeners are returned
    - runner error is returned with context
  </test_code>
  <verify>
    go test ./internal/ports — all pass
  </verify>
  <done>ports collector uses a single all-listeners command and remains fixture-testable</done>
  <commit>feat(ports): add listener collector</commit>
</task>

<task id="4" depends="1" type="auto">
  <name>Create process metadata model and fixture parser</name>
  <files>
    <create>internal/processes/model.go</create>
    <create>internal/processes/parser.go</create>
    <test>internal/processes/parser_test.go</test>
  </files>
  <read_first>
    docs/superpowers/specs/2026-06-07-noodles-v2-design.md
  </read_first>
  <action>
    Define `Process` with PID, ParentPID, ProcessGroupID, Command, CommandLine, CWD, ExecutablePath, ResidentMemoryBytes, CPUTimeSeconds, StartedAt.

    Implement a pure parser for tab-separated fixture rows:
    `pid\tppid\tpgid\trss\tetimes\tcomm\targs`

    The parser should convert RSS KB to bytes and derive StartedAt as `now - etimes seconds`.
  </action>
  <test_code>
    Tests must cover:
    - RSS KB converted to bytes
    - StartedAt derived from supplied now time and etimes
    - command and command line preserved
    - malformed row returns a useful error
  </test_code>
  <verify>
    go test ./internal/processes — all pass
  </verify>
  <done>process metadata parser is pure, tested, and suitable for fixture-driven scanner tests</done>
  <commit>feat(processes): add process metadata parser</commit>
</task>

<task id="5" depends="4" type="auto">
  <name>Add process collector and parent-chain enrichment</name>
  <files>
    <create>internal/processes/collector.go</create>
    <test>internal/processes/collector_test.go</test>
  </files>
  <read_first>
    internal/processes/model.go
    internal/processes/parser.go
  </read_first>
  <action>
    Add a collector interface that can return process metadata for a set of candidate PIDs and required parent-chain/process-group PIDs.

    Implement pure helper `ParentChain(processes map[int]Process, pid int) []int` with cycle protection.
  </action>
  <test_code>
    Tests must cover:
    - parent chain from child to root
    - cycle protection stops traversal
    - missing parent stops traversal without panic
  </test_code>
  <verify>
    go test ./internal/processes — all pass
  </verify>
  <done>process package can model parent chains needed by service classification and kill planning</done>
  <commit>feat(processes): add parent chain support</commit>
</task>

<task id="6" depends="1" type="auto">
  <name>Resolve project identity from CWD</name>
  <files>
    <create>internal/projects/resolver.go</create>
    <test>internal/projects/resolver_test.go</test>
  </files>
  <read_first>
    docs/superpowers/specs/2026-06-07-noodles-v2-design.md
  </read_first>
  <action>
    Implement `Resolver` that maps a CWD to project identity:
    - find nearest ancestor containing `.git` or `package.json`
    - set `Root`
    - set `WorkspaceRoot` to the nearest ancestor package with `workspaces` in package.json when present, otherwise Root
    - set display name from root basename
    - create stable project ID from absolute root path
    - cache by normalized CWD
  </action>
  <test_code>
    Tests must create temp directories and cover:
    - package root resolution
    - nested app under monorepo workspace
    - cache hit count or repeated resolution returns cached result
    - missing markers returns a low-information project with cwd as root
  </test_code>
  <verify>
    go test ./internal/projects — all pass
  </verify>
  <done>project resolver handles repo roots, workspace roots, and cached cwd lookups</done>
  <commit>feat(projects): resolve project identity</commit>
</task>

<task id="7" depends="1,2,4,6" type="auto">
  <name>Classify local services with confidence and evidence</name>
  <files>
    <create>internal/classifier/classifier.go</create>
    <test>internal/classifier/classifier_test.go</test>
  </files>
  <read_first>
    internal/app/model.go
    internal/ports/parser.go
    internal/processes/model.go
  </read_first>
  <action>
    Implement `Classify(command string, commandLine string, cwd string, parentCommands []string) Classification`.

    Labels: `dev-server`, `storybook`, `agent`, `browser`, `node-tool`, `system`, `unknown`.

    Confidence: `low`, `medium`, `high`.

    Include evidence strings such as command match, command line match, cwd under `/Users/`, parent command match.
  </action>
  <test_code>
    Tests must cover:
    - `next` command or args -> `dev-server` high confidence
    - storybook args -> `storybook` high confidence
    - agent-browser command -> `agent` high confidence
    - Google Chrome command -> `browser` medium confidence
    - unknown command under `/Users/danielhowells/Sites` -> `unknown` low confidence with cwd evidence
  </test_code>
  <verify>
    go test ./internal/classifier — all pass
  </verify>
  <done>classifier returns source labels, confidence, and evidence for UI/test use</done>
  <commit>feat(classifier): label local services</commit>
</task>

<task id="8" depends="2,4,6,7" type="auto">
  <name>Orchestrate scan into service snapshot</name>
  <files>
    <create>internal/app/scanner.go</create>
    <test>internal/app/scan_test.go</test>
  </files>
  <read_first>
    internal/app/model.go
    internal/ports/parser.go
    internal/processes/model.go
    internal/projects/resolver.go
    internal/classifier/classifier.go
  </read_first>
  <action>
    Implement injected scan orchestration:
    - collect listeners once
    - collect process metadata only for candidate listener PIDs
    - resolve project identity from process CWD
    - classify service with parent command evidence when available
    - aggregate one row per primary listening PID with all attached ports
    - produce scan metadata including snapshot ID and duration

    Do not execute real system commands in this package's tests.
  </action>
  <test_code>
    Tests must use fake collectors/resolvers and assert:
    - high ports are included
    - multiple ports for same PID become one service row
    - services get project fields and source evidence
    - snapshot metadata includes non-empty snapshot ID
  </test_code>
  <verify>
    go test ./internal/app — all pass
  </verify>
  <done>app scanner converts listener/process/project/classifier data into service snapshots</done>
  <commit>feat(core): build service snapshots</commit>
</task>

<task id="9" depends="8" type="auto">
  <name>Add Go-owned sorting filtering and grouping</name>
  <files>
    <create>internal/app/view.go</create>
    <test>internal/app/view_test.go</test>
  </files>
  <read_first>
    internal/app/model.go
    internal/app/scanner.go
  </read_first>
  <action>
    Implement `BuildView(snapshot Snapshot, query Query) Snapshot`.

    Apply filters: search, project, source label, port, killable only, hide system, memory threshold.

    Sort rows by the query, defaulting to memory descending, CPU descending when available, project name, lowest port.

    Implement project grouping aggregates with total resident memory, ports, killable count, excluded count, and source labels.
  </action>
  <test_code>
    Tests must cover:
    - default row sort places highest memory first
    - port sort uses lowest port
    - hide system removes system-labeled rows
    - project grouping aggregates memory, ports, killable counts, excluded counts
    - search matches project name, cwd, command, and port text
  </test_code>
  <verify>
    go test ./internal/app — all pass
  </verify>
  <done>Go core owns deterministic view sorting filtering and grouping for UI and CLI reuse</done>
  <commit>feat(core): add service view model</commit>
</task>

<task id="10" depends="8" type="auto">
  <name>Build revalidated single-service kill plans</name>
  <files>
    <create>internal/killer/plan.go</create>
    <test>internal/killer/plan_test.go</test>
  </files>
  <read_first>
    internal/app/model.go
  </read_first>
  <action>
    Implement `BuildServiceKillPlan(request KillRequest, current app.Snapshot) (KillPlan, error)`.

    Revalidate snapshotId, serviceId, pid, processGroupId, startedAt, command or executablePath, cwd, projectRoot, and expected ports before returning targets.

    Reject stale identity with a typed error and do not include targets.
  </action>
  <test_code>
    Tests must cover:
    - valid request creates plan with target PID and SIGTERM then SIGKILL order
    - PID reused with different startedAt is rejected
    - changed ports are rejected
    - missing service ID is rejected
    - non-killable service is excluded with reason
  </test_code>
  <verify>
    go test ./internal/killer — all pass
  </verify>
  <done>single-service kill plans revalidate identity before any signal execution</done>
  <commit>feat(killer): add revalidated service kill plans</commit>
</task>

<task id="11" depends="10" type="auto">
  <name>Execute kill plans through testable signaler</name>
  <files>
    <create>internal/killer/executor.go</create>
    <test>internal/killer/executor_test.go</test>
  </files>
  <read_first>
    internal/killer/plan.go
  </read_first>
  <action>
    Implement `Executor` with injected `Signaler` interface.

    Execution should send SIGTERM to each included target, wait a bounded timeout, then SIGKILL for targets still reported alive by the signaler.

    Return per-target `KillResult` entries with success, signal attempts, and error reason.
  </action>
  <test_code>
    Tests must use fake signaler and fake clock/wait behavior to assert:
    - SIGTERM is attempted first
    - SIGKILL is attempted only for targets still alive
    - per-target failure is reported without hiding other targets
  </test_code>
  <verify>
    go test ./internal/killer — all pass
  </verify>
  <done>kill execution is signaler-injected and tested without killing arbitrary real processes</done>
  <commit>feat(killer): execute kill plans</commit>
</task>

<task id="12" depends="9,11" type="auto">
  <name>Add desktop service and Wails bindings</name>
  <files>
    <create>internal/desktop/service.go</create>
    <test>internal/desktop/service_test.go</test>
    <create>desktop_app.go</create>
    <create>desktop_main.go</create>
    <create>wails.json</create>
  </files>
  <read_first>
    /Users/danielhowells/Sites/monogrove/desktop_main.go
    /Users/danielhowells/Sites/monogrove/desktop_app.go
    /Users/danielhowells/Sites/monogrove/wails.json
    internal/app/model.go
    internal/app/view.go
    internal/killer/plan.go
  </read_first>
  <action>
    Create a thin Wails shell:
    - `App.Scan(query app.Query) (app.Snapshot, error)`
    - `App.KillService(request killer.KillRequest) (killer.KillResult, error)`
    - Wails title `Noodles`
    - frontend dist embedded from `frontend/dist`

    `internal/desktop.Service` should wrap the app core and be easy to fake in tests.
  </action>
  <test_code>
    Tests must cover:
    - desktop service delegates scan to injected core
    - desktop service delegates kill to injected core
    - errors are returned, not swallowed
  </test_code>
  <verify>
    go test ./internal/desktop ./... — all pass
  </verify>
  <done>Wails binding surface exists and delegates to tested Go core</done>
  <commit>feat(desktop): expose Noodles core to Wails</commit>
</task>

<task id="13" depends="9" type="auto">
  <name>Add CLI wrapper over Go core</name>
  <files>
    <create>cmd/noodles/main.go</create>
    <test>cmd/noodles/main_test.go</test>
  </files>
  <read_first>
    internal/app/model.go
    internal/app/view.go
  </read_first>
  <action>
    Implement minimal CLI commands:
    - `noodles list`
    - `noodles list --sort memory`
    - `noodles kill --project-root <path>` should parse arguments and route to core shape, but real kill may return a clear not-wired error until system collectors are active.

    Implement project-name ambiguity helper used by CLI tests.
  </action>
  <test_code>
    Tests must cover:
    - list command formats service rows with port and memory
    - ambiguous project display name returns candidate roots
    - `--project-root` selects exact root
  </test_code>
  <verify>
    go test ./cmd/noodles ./... — all pass
  </verify>
  <done>CLI package shares the Go view model and handles project ambiguity</done>
  <commit>feat(cli): add Noodles command wrapper</commit>
</task>

<task id="14" depends="12" type="auto">
  <name>Scaffold React Wails frontend</name>
  <files>
    <create>frontend/package.json</create>
    <create>frontend/vite.config.ts</create>
    <create>frontend/tsconfig.json</create>
    <create>frontend/index.html</create>
    <create>frontend/src/main.tsx</create>
    <create>frontend/src/App.tsx</create>
    <create>frontend/src/style.css</create>
  </files>
  <read_first>
    /Users/danielhowells/Sites/monogrove/frontend/package.json
    /Users/danielhowells/Sites/monogrove/frontend/vite.config.ts
    docs/superpowers/specs/2026-06-07-noodles-v2-design.md
  </read_first>
  <action>
    Create a Vite React frontend using a compact operational table.

    The initial UI may use mock data when Wails generated bindings are absent, but must define TypeScript types matching the Go snapshot shape and show:
    - scanning state
    - empty state
    - permission warning area
    - table rows with project/cwd, command, ports, memory, CPU, age, source label, kill button
    - project group header shape with `Kill N`

    Use restrained operational styling, not marketing cards.
  </action>
  <test_code>
    Frontend verification is build/typecheck first. Add component tests only if test dependencies are introduced in this task.
  </test_code>
  <verify>
    pnpm --dir frontend install
    pnpm --dir frontend build — succeeds
  </verify>
  <done>React frontend builds and renders the operational Noodles table shell</done>
  <commit>feat(frontend): add Noodles operational table</commit>
</task>

<task id="15" depends="12,14" type="auto">
  <name>Wire frontend actions to Wails API shape</name>
  <files>
    <modify>frontend/src/App.tsx</modify>
    <modify>frontend/src/style.css</modify>
  </files>
  <read_first>
    frontend/src/App.tsx
    desktop_app.go
    internal/app/model.go
    internal/killer/plan.go
  </read_first>
  <action>
    Add Wails API adapter functions that call generated Wails bindings when present and fall back to mock data in browser-only development.

    Implement refresh and kill button state transitions:
    - scanning
    - killing
    - killed/removed
    - kill failed
    - stale snapshot warning
  </action>
  <test_code>
    Frontend verification is build/typecheck first. If component test dependencies exist, add tests for loading, empty, and kill failure states.
  </test_code>
  <verify>
    pnpm --dir frontend build — succeeds
  </verify>
  <done>Frontend uses the Wails API shape and handles core operational UI states</done>
  <commit>feat(frontend): wire scan and kill actions</commit>
</task>

<task id="16" depends="13,15" type="auto">
  <name>Update docs and verify whole app</name>
  <files>
    <modify>README.md</modify>
    <modify>.gitignore</modify>
  </files>
  <read_first>
    README.md
    docs/superpowers/specs/2026-06-07-noodles-v2-design.md
    docs/arc/plans/2026-06-07-noodles-v2-implementation.md
  </read_first>
  <action>
    Update README to describe v2 development commands:
    - `go test ./...`
    - `pnpm --dir frontend build`
    - `wails dev`

    Keep Swift migration status honest: Swift app remains as legacy until v2 characterization and release pipeline fully replace it.
  </action>
  <test_code>
    No new unit test needed. This is documentation and whole-plan verification.
  </test_code>
  <verify>
    go test ./...
    pnpm --dir frontend build
    git status --short — only intentional files changed
  </verify>
  <done>README reflects v2 and full verification commands pass</done>
  <commit>docs: document Noodles v2 development</commit>
</task>

