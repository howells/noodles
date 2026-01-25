# nodles - Implementation Plan

A visual Node.js dev server manager for ~/Sites projects.

## Overview

**Stack:** Tauri v2 + React 19 + TypeScript + Tailwind CSS + Zustand

**Features:**
- Scan ~/Sites for Node projects
- Show running vs available projects
- Start/stop/restart dev servers
- Open in browser or editor (Claude Code, Cursor, Zed)
- Detect monorepos (turborepo)
- Custom project labels
- Launch on login

---

## Phase 1: Project Scaffolding

### Tasks
- [ ] Initialize Tauri v2 project with React + TypeScript template
- [ ] Install and configure Tailwind CSS
- [ ] Add Tauri plugins: shell, fs, process, autostart
- [ ] Configure window: 400x600, dark theme, resizable
- [ ] Set up basic App.tsx with layout skeleton

### Commands
```bash
pnpm create tauri-app nodles --template react-ts
cd nodles
pnpm add -D tailwindcss postcss autoprefixer
pnpm add zustand
# Tauri plugins added via Cargo.toml
```

---

## Phase 2: Rust Backend Commands

### Tauri Commands to Implement

```rust
// src-tauri/src/commands.rs

#[tauri::command]
fn scan_sites(sites_path: String) -> Vec<ProjectInfo>
// Reads ~/Sites, finds package.json files, returns project metadata

#[tauri::command]
fn parse_package_json(path: String) -> PackageInfo
// Parses package.json, extracts scripts.dev, detects ports

#[tauri::command]
fn get_node_ports() -> Vec<PortInfo>
// Runs: lsof -i -P -n | grep LISTEN | grep node
// Returns: pid, port, protocol

#[tauri::command]
fn get_process_cwd(pid: u32) -> Option<String>
// Runs: lsof -p $pid | grep cwd
// Returns: working directory path

#[tauri::command]
fn start_dev_server(path: String, command: String) -> Result<u32, String>
// Spawns: cd $path && pnpm dev (detached)
// Returns: PID

#[tauri::command]
fn stop_process(pid: u32) -> Result<(), String>
// Sends SIGTERM, waits, then SIGKILL if needed

#[tauri::command]
fn open_in_browser(url: String) -> Result<(), String>
// Opens URL in default browser

#[tauri::command]
fn open_in_editor(path: String, editor: String) -> Result<(), String>
// Runs: claude/cursor/zed $path
```

### Structs

```rust
#[derive(Serialize)]
struct ProjectInfo {
    id: String,
    name: String,
    path: String,
    has_package_json: bool,
    is_monorepo: bool,
}

#[derive(Serialize)]
struct PackageInfo {
    name: Option<String>,
    dev_command: Option<String>,
    expected_ports: Vec<u16>,
    is_turborepo: bool,
    apps: Vec<MonorepoApp>,
}

#[derive(Serialize)]
struct PortInfo {
    port: u16,
    pid: u32,
    protocol: String,
}

#[derive(Serialize)]
struct MonorepoApp {
    name: String,
    path: String,
    dev_command: Option<String>,
    expected_ports: Vec<u16>,
}
```

---

## Phase 3: TypeScript Types & Store

### Types (src/types.ts)

```typescript
export interface Project {
  id: string
  name: string
  displayName?: string  // user override
  path: string
  devCommand: string | null
  expectedPorts: number[]
  isMonorepo: boolean
  apps: MonorepoApp[]
  favorite: boolean
  status: 'running' | 'stopped' | 'starting' | 'stopping'
  runningPorts: RunningPort[]
}

export interface MonorepoApp {
  name: string
  path: string
  devCommand: string | null
  expectedPorts: number[]
}

export interface RunningPort {
  port: number
  pid: number
  label?: string
}

export interface Config {
  sitesPath: string
  editor: 'claude' | 'cursor' | 'zed'
  favorites: string[]
  labels: Record<string, string>  // "obliq:9000" -> "Frontend"
  displayNames: Record<string, string>  // "obliq" -> "Obliq App"
}
```

### Store (src/store.ts)

```typescript
interface NodlesStore {
  projects: Project[]
  runningPorts: PortInfo[]
  config: Config
  filter: string

  // Actions
  setProjects: (projects: Project[]) => void
  setRunningPorts: (ports: PortInfo[]) => void
  setFilter: (filter: string) => void
  updateConfig: (config: Partial<Config>) => void

  // Computed
  runningProjects: () => Project[]
  stoppedProjects: () => Project[]
  filteredProjects: () => Project[]
}
```

---

## Phase 4: Frontend Components

### Component Tree

```
App.tsx
├── Header.tsx              # Title, settings gear
├── SearchFilter.tsx        # Filter input
├── ProjectList.tsx         # Main list container
│   ├── ProjectSection.tsx  # "RUNNING" / "AVAILABLE" headers
│   └── ProjectCard.tsx     # Individual project row
│       ├── StatusDot.tsx   # Green/gray dot
│       ├── PortBadges.tsx  # Port number pills
│       └── Controls.tsx    # Action buttons
└── SettingsModal.tsx       # Editor choice, paths
```

### ProjectCard Layout

```
┌─────────────────────────────────────────────────────────┐
│  ● obliq                                                │
│  ~/Sites/obliq                                          │
│  ┌──────┐                                               │
│  │ 9000 │                          🌐  📝  ⟳  ⏹        │
│  └──────┘                                               │
└─────────────────────────────────────────────────────────┘
```

---

## Phase 5: Hooks & Logic

### useProjects.ts
- Call `scan_sites` on mount
- Call `parse_package_json` for each project
- Merge with running port data
- Re-scan on window focus

### usePorts.ts
- Poll `get_node_ports` every 2 seconds
- For each port, call `get_process_cwd` to match project
- Update store with running ports

### useProcessControl.ts
- `startProject(id)` - calls start_dev_server
- `stopProject(id)` - calls stop_process for all PIDs
- `restartProject(id)` - stop then start
- `openInBrowser(port)` - calls open_in_browser
- `openInEditor(path)` - calls open_in_editor

---

## Phase 6: Port Parsing Logic

### Regex patterns for extracting ports from dev scripts

```typescript
const PORT_PATTERNS = [
  /--port[=\s]+(\d+)/,           // --port 3000, --port=3000
  /-p[=\s]+(\d+)/,               // -p 3000
  /PORT[=:](\d+)/,               // PORT=3000
  /localhost:(\d+)/,             // localhost:3000
  /127\.0\.0\.1:(\d+)/,          // 127.0.0.1:3000
]

function extractPorts(devScript: string): number[] {
  const ports: number[] = []
  for (const pattern of PORT_PATTERNS) {
    const matches = devScript.matchAll(new RegExp(pattern, 'g'))
    for (const match of matches) {
      ports.push(parseInt(match[1]))
    }
  }
  // Default to 3000 if Next.js and no port specified
  if (ports.length === 0 && devScript.includes('next dev')) {
    ports.push(3000)
  }
  return [...new Set(ports)]
}
```

---

## Phase 7: Config & Persistence

### Config file: ~/.config/nodles/config.json

```json
{
  "sitesPath": "/Users/danielhowells/Sites",
  "editor": "cursor",
  "launchOnLogin": true,
  "pollInterval": 2000,
  "favorites": ["obliq", "siteinspire"],
  "labels": {
    "tersa:6000": "Web",
    "tersa:6001": "Email"
  },
  "displayNames": {
    "siteinspire": "siteInspire"
  }
}
```

### Tauri autostart plugin for launch on login

```rust
// Cargo.toml
tauri-plugin-autostart = "2"

// main.rs
.plugin(tauri_plugin_autostart::init(
    MacosLauncher::LaunchAgent,
    Some(vec!["--hidden"])
))
```

---

## Phase 8: Polish & Ship

- [ ] App icon (simple node/noodle graphic)
- [ ] Keyboard shortcuts (Cmd+R restart, Cmd+S stop)
- [ ] Notification on process crash
- [ ] Drag to reorder favorites
- [ ] Right-click context menu
- [ ] Build & sign for macOS distribution
- [ ] DMG installer

---

## File Structure

```
nodles/
├── src/
│   ├── App.tsx
│   ├── main.tsx
│   ├── index.css
│   ├── types.ts
│   ├── store.ts
│   ├── components/
│   │   ├── Header.tsx
│   │   ├── SearchFilter.tsx
│   │   ├── ProjectList.tsx
│   │   ├── ProjectCard.tsx
│   │   ├── PortBadge.tsx
│   │   ├── Controls.tsx
│   │   ├── StatusDot.tsx
│   │   └── SettingsModal.tsx
│   ├── hooks/
│   │   ├── useProjects.ts
│   │   ├── usePorts.ts
│   │   ├── useProcessControl.ts
│   │   └── useConfig.ts
│   └── lib/
│       ├── tauri.ts
│       ├── portParser.ts
│       └── constants.ts
├── src-tauri/
│   ├── src/
│   │   ├── main.rs
│   │   ├── lib.rs
│   │   └── commands/
│   │       ├── mod.rs
│   │       ├── scanner.rs
│   │       ├── ports.rs
│   │       └── process.rs
│   ├── Cargo.toml
│   ├── tauri.conf.json
│   └── icons/
├── package.json
├── tailwind.config.js
├── tsconfig.json
├── vite.config.ts
└── PLAN.md
```

---

## Estimated Phases

| Phase | Description |
|-------|-------------|
| 1 | Project scaffolding, Tauri + React + Tailwind |
| 2 | Rust backend commands |
| 3 | TypeScript types, Zustand store |
| 4 | React components |
| 5 | Hooks connecting frontend to backend |
| 6 | Port parsing and project matching |
| 7 | Config persistence, autostart |
| 8 | Polish, icons, distribution |

---

Ready to build?
