# noodles - Implementation Plan

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

## Key Design Decisions

### Process Detection Strategy

We detect running processes by **port first**, then match to projects:

1. Run `lsof -i -P -n | grep LISTEN` (no filtering by process name)
2. For each listening port, get the PID
3. For each PID, get cwd via `lsof -p $pid | grep cwd`
4. Match cwd to known project paths

This approach handles node, bun, deno, and any other runtime.

### Package Manager Detection

Detect via lockfile presence (checked in order):
1. `bun.lockb` → `bun run dev`
2. `pnpm-lock.yaml` → `pnpm dev`
3. `yarn.lock` → `yarn dev`
4. `package-lock.json` → `npm run dev`
5. Fallback → `npm run dev`

### Monorepo Handling

**MVP (v1):** Treat monorepo as single unit
- Show one entry for "siteinspire"
- Start/stop runs root `dev` command (e.g., `turbo dev`)
- All spawned ports grouped under parent project

**Future (v2):** Per-app granularity
- Expand monorepo to show individual apps
- Start/stop individual workspace apps
- Track which app owns which port

### Port Detection Strategy

**Static analysis** (from package.json scripts.dev):
- Regex patterns for explicit ports
- Env var detection with fallback parsing
- Framework defaults (Next.js → 3000, Vite → 5173)

**Runtime detection** (from lsof):
- Actual port is authoritative
- Static analysis only for "expected" port display when stopped

### Error State Handling

Projects can be in these states:
- `stopped` - Not running, can be started
- `starting` - Process spawned, waiting for port
- `running` - Process healthy, port listening
- `stopping` - SIGTERM sent, waiting for exit
- `error` - Start failed, port conflict, or crash detected
- `partial` - Monorepo with some apps running (v2)

---

## Phase 1: Project Scaffolding

### Tasks
- [ ] Initialize Tauri v2 project with React + TypeScript template
- [ ] Install and configure Tailwind CSS v4
- [ ] Add Tauri plugins: shell, fs, process, autostart
- [ ] Configure window: 420x700, dark theme, resizable, min 320x400
- [ ] Set up basic App.tsx with layout skeleton

### Commands
```bash
pnpm create tauri-app@latest --template react-ts
pnpm add -D tailwindcss @tailwindcss/vite
pnpm add zustand
```

### Tauri Plugins (Cargo.toml)
```toml
[dependencies]
tauri-plugin-shell = "2"
tauri-plugin-fs = "2"
tauri-plugin-process = "2"
tauri-plugin-autostart = "2"
serde = { version = "1", features = ["derive"] }
serde_json = "1"
```

---

## Phase 2: Rust Backend Commands

### Commands Overview

```rust
// Project discovery
scan_sites(sites_path: String) -> Result<Vec<ProjectInfo>, String>
parse_package_json(path: String) -> Result<PackageInfo, String>
detect_package_manager(path: String) -> PackageManager

// Port monitoring
get_listening_ports() -> Result<Vec<PortInfo>, String>
get_process_cwd(pid: u32) -> Result<Option<String>, String>
get_process_info(pid: u32) -> Result<ProcessInfo, String>

// Process control
start_dev_server(path: String, pkg_manager: PackageManager) -> Result<SpawnedProcess, String>
stop_process(pid: u32, force: bool) -> Result<(), String>
stop_project_processes(project_path: String) -> Result<u32, String>  // returns count killed

// Utilities
open_in_browser(url: String) -> Result<(), String>
open_in_editor(path: String, editor: Editor) -> Result<(), String>
read_config() -> Result<Config, String>
write_config(config: Config) -> Result<(), String>
```

### Structs

```rust
#[derive(Serialize, Deserialize)]
pub struct ProjectInfo {
    pub id: String,           // folder name, used as unique key
    pub name: String,         // from package.json name or folder
    pub path: String,         // absolute path
    pub has_dev_script: bool,
    pub dev_command: Option<String>,
    pub expected_ports: Vec<u16>,
    pub package_manager: PackageManager,
    pub project_type: ProjectType,
}

#[derive(Serialize, Deserialize)]
pub enum ProjectType {
    Standard,
    Turborepo { apps: Vec<String> },
    PnpmWorkspace { packages: Vec<String> },
    NxWorkspace { projects: Vec<String> },
}

#[derive(Serialize, Deserialize)]
pub enum PackageManager {
    Pnpm,
    Npm,
    Yarn,
    Bun,
}

#[derive(Serialize, Deserialize)]
pub struct PortInfo {
    pub port: u16,
    pub pid: u32,
    pub process_name: String,  // "node", "bun", "next-server", etc.
    pub cwd: Option<String>,   // working directory if resolvable
}

#[derive(Serialize, Deserialize)]
pub struct ProcessInfo {
    pub pid: u32,
    pub name: String,
    pub cwd: Option<String>,
    pub cpu_percent: Option<f32>,
    pub memory_mb: Option<u32>,
}

#[derive(Serialize, Deserialize)]
pub struct SpawnedProcess {
    pub pid: u32,
    pub started_at: u64,  // unix timestamp
}

#[derive(Serialize, Deserialize)]
pub struct Config {
    pub sites_path: String,
    pub editor: Editor,
    pub launch_on_login: bool,
    pub poll_interval_ms: u32,
    pub favorites: Vec<String>,
    pub labels: HashMap<String, String>,      // "project:port" -> "Label"
    pub display_names: HashMap<String, String>, // "project" -> "Display Name"
    pub hidden_projects: Vec<String>,
}

#[derive(Serialize, Deserialize)]
pub enum Editor {
    Claude,
    Cursor,
    Zed,
}
```

### Port Detection Implementation

```rust
// Get all listening ports (not filtered by process type)
fn get_listening_ports() -> Result<Vec<PortInfo>, String> {
    // Run: lsof -i -P -n | grep LISTEN
    // Parse output format:
    // COMMAND   PID   USER   FD   TYPE   DEVICE   SIZE/OFF   NODE   NAME
    // node    18698  dan    13u  IPv6   0x123    0t0        TCP    *:3000 (LISTEN)

    // Extract: process_name, pid, port
    // Then for each pid, call get_process_cwd
}

fn get_process_cwd(pid: u32) -> Result<Option<String>, String> {
    // Run: lsof -p $pid 2>/dev/null | grep cwd | awk '{print $NF}'
    // Returns the working directory
}
```

### Package Manager Detection

```rust
fn detect_package_manager(path: &str) -> PackageManager {
    let path = Path::new(path);

    if path.join("bun.lockb").exists() {
        PackageManager::Bun
    } else if path.join("pnpm-lock.yaml").exists() {
        PackageManager::Pnpm
    } else if path.join("yarn.lock").exists() {
        PackageManager::Yarn
    } else {
        PackageManager::Npm
    }
}
```

---

## Phase 3: TypeScript Types & Store

### Types (src/types.ts)

```typescript
export type ProjectStatus =
  | 'stopped'
  | 'starting'
  | 'running'
  | 'stopping'
  | 'error'

export interface Project {
  id: string
  name: string
  displayName?: string
  path: string
  devCommand: string | null
  expectedPorts: number[]
  packageManager: 'pnpm' | 'npm' | 'yarn' | 'bun'
  projectType: ProjectType
  favorite: boolean
  hidden: boolean

  // Runtime state (merged from port detection)
  status: ProjectStatus
  runningPorts: RunningPort[]
  error?: string
  lastStarted?: number
}

export type ProjectType =
  | { type: 'standard' }
  | { type: 'turborepo'; apps: string[] }
  | { type: 'pnpm-workspace'; packages: string[] }

export interface RunningPort {
  port: number
  pid: number
  processName: string
  label?: string
}

export interface PortInfo {
  port: number
  pid: number
  processName: string
  cwd: string | null
  projectId: string | null  // matched project, if any
}

export interface Config {
  sitesPath: string
  editor: 'claude' | 'cursor' | 'zed'
  launchOnLogin: boolean
  pollIntervalMs: number
  favorites: string[]
  labels: Record<string, string>
  displayNames: Record<string, string>
  hiddenProjects: string[]
}
```

### Store (src/store.ts)

```typescript
import { create } from 'zustand'
import { subscribeWithSelector } from 'zustand/middleware'

interface NoodlesStore {
  // State
  projects: Project[]
  ports: PortInfo[]
  config: Config
  filter: string
  isScanning: boolean
  scanError: string | null

  // Actions
  setProjects: (projects: Project[]) => void
  setPorts: (ports: PortInfo[]) => void
  setConfig: (config: Config) => void
  setFilter: (filter: string) => void
  setScanning: (scanning: boolean) => void
  setScanError: (error: string | null) => void

  updateProjectStatus: (id: string, status: ProjectStatus, error?: string) => void
  toggleFavorite: (id: string) => void
  toggleHidden: (id: string) => void
  setLabel: (projectId: string, port: number, label: string) => void

  // Computed (as getters)
  getRunningProjects: () => Project[]
  getStoppedProjects: () => Project[]
  getFilteredProjects: () => Project[]
  getOrphanPorts: () => PortInfo[]  // ports not matched to any project
}

export const useStore = create<NoodlesStore>()(
  subscribeWithSelector((set, get) => ({
    // ... implementation
  }))
)
```

---

## Phase 4: Frontend Components

### Component Tree

```
App.tsx
├── Header.tsx                 # Title, settings gear, scan button
├── SearchFilter.tsx           # Filter input with clear button
├── ProjectList.tsx            # Virtualized list container
│   ├── SectionHeader.tsx      # "RUNNING (3)" / "AVAILABLE (47)"
│   └── ProjectCard.tsx        # Individual project row
│       ├── StatusIndicator.tsx    # Dot + pulse animation
│       ├── ProjectInfo.tsx        # Name, path, type badge
│       ├── PortBadges.tsx         # Port pills with labels
│       └── ActionButtons.tsx      # Browser, editor, restart, stop/start
├── OrphanPorts.tsx            # Unmatched ports section
│   └── OrphanPortCard.tsx     # Port with kill button
└── SettingsModal.tsx          # Editor, path, preferences
    ├── EditorPicker.tsx
    ├── PathPicker.tsx
    └── ToggleRow.tsx
```

### ProjectCard States

```
STOPPED:
┌─────────────────────────────────────────────────────────┐
│  ○ obliq                                     turborepo  │
│  ~/Sites/obliq                                          │
│  Expected: 9000                                    [▶]  │
└─────────────────────────────────────────────────────────┘

RUNNING:
┌─────────────────────────────────────────────────────────┐
│  ● obliq                                     turborepo  │
│  ~/Sites/obliq                                          │
│  ┌──────┐                              [🌐] [📝] [⟳] [⏹] │
│  │ 9000 │                                               │
│  └──────┘                                               │
└─────────────────────────────────────────────────────────┘

STARTING:
┌─────────────────────────────────────────────────────────┐
│  ◐ obliq                                     turborepo  │
│  ~/Sites/obliq                              Starting... │
└─────────────────────────────────────────────────────────┘

ERROR:
┌─────────────────────────────────────────────────────────┐
│  ✕ obliq                                     turborepo  │
│  Port 9000 already in use                    [Retry ▶]  │
└─────────────────────────────────────────────────────────┘
```

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd+R` | Restart selected project |
| `Cmd+S` | Stop selected project |
| `Cmd+O` | Open in browser |
| `Cmd+E` | Open in editor |
| `Cmd+F` | Focus filter |
| `Cmd+,` | Open settings |
| `↑/↓` | Navigate projects |
| `Enter` | Toggle start/stop |

---

## Phase 5: Port Parsing Logic

### Enhanced Port Extraction

```typescript
const PORT_PATTERNS = [
  // Explicit port flags
  /--port[=\s]+(\d+)/g,
  /-p[=\s]+(\d+)/g,
  /-H\s+\S+\s+--port[=\s]+(\d+)/g,  // next dev -H 0.0.0.0 --port 3000

  // Environment variables with defaults
  /\$\{(\w+):-(\d+)\}/g,           // ${PORT:-3000} -> capture default
  /\$\{?PORT\}?[=:]?(\d+)?/g,      // $PORT or ${PORT}

  // Direct port references
  /localhost:(\d+)/g,
  /127\.0\.0\.1:(\d+)/g,
  /0\.0\.0\.0:(\d+)/g,
]

// Framework defaults when no port found
const FRAMEWORK_DEFAULTS: Record<string, number> = {
  'next dev': 3000,
  'vite': 5173,
  'nuxt dev': 3000,
  'astro dev': 4321,
  'remix dev': 3000,
  'webpack serve': 8080,
  'react-scripts start': 3000,
  'vue-cli-service serve': 8080,
}

function extractPorts(devScript: string): number[] {
  const ports = new Set<number>()

  // Try explicit patterns
  for (const pattern of PORT_PATTERNS) {
    const matches = devScript.matchAll(pattern)
    for (const match of matches) {
      const port = parseInt(match[1] || match[2])
      if (port && port > 0 && port < 65536) {
        ports.add(port)
      }
    }
  }

  // Framework defaults if no explicit port
  if (ports.size === 0) {
    for (const [framework, defaultPort] of Object.entries(FRAMEWORK_DEFAULTS)) {
      if (devScript.includes(framework)) {
        ports.add(defaultPort)
        break
      }
    }
  }

  return Array.from(ports)
}
```

### Monorepo Detection

```typescript
interface MonorepoInfo {
  type: 'turborepo' | 'pnpm-workspace' | 'nx' | null
  apps: string[]
}

async function detectMonorepo(projectPath: string): Promise<MonorepoInfo> {
  // Check for turbo.json
  const turboPath = join(projectPath, 'turbo.json')
  if (await exists(turboPath)) {
    const apps = await findWorkspaceApps(projectPath)
    return { type: 'turborepo', apps }
  }

  // Check for pnpm-workspace.yaml
  const pnpmWorkspacePath = join(projectPath, 'pnpm-workspace.yaml')
  if (await exists(pnpmWorkspacePath)) {
    const apps = await parsePnpmWorkspace(pnpmWorkspacePath)
    return { type: 'pnpm-workspace', apps }
  }

  // Check for nx.json
  const nxPath = join(projectPath, 'nx.json')
  if (await exists(nxPath)) {
    const apps = await findNxProjects(projectPath)
    return { type: 'nx', apps }
  }

  return { type: null, apps: [] }
}

async function findWorkspaceApps(projectPath: string): Promise<string[]> {
  const apps: string[] = []

  // Check apps/ directory
  const appsDir = join(projectPath, 'apps')
  if (await exists(appsDir)) {
    const entries = await readDir(appsDir)
    for (const entry of entries) {
      if (entry.isDirectory) {
        const pkgPath = join(appsDir, entry.name, 'package.json')
        if (await exists(pkgPath)) {
          apps.push(`apps/${entry.name}`)
        }
      }
    }
  }

  // Check packages/ directory for apps (some monorepos use this)
  const packagesDir = join(projectPath, 'packages')
  if (await exists(packagesDir)) {
    const entries = await readDir(packagesDir)
    for (const entry of entries) {
      if (entry.isDirectory) {
        const pkgPath = join(packagesDir, entry.name, 'package.json')
        if (await exists(pkgPath)) {
          const pkg = await readPackageJson(pkgPath)
          // Only include if it has a dev script (likely an app, not a lib)
          if (pkg.scripts?.dev) {
            apps.push(`packages/${entry.name}`)
          }
        }
      }
    }
  }

  return apps
}
```

---

## Phase 6: Hooks & Integration

### useProjects.ts

```typescript
export function useProjects() {
  const { setProjects, setScanning, setScanError, config } = useStore()

  const scan = useCallback(async () => {
    setScanning(true)
    setScanError(null)

    try {
      const projectInfos = await invoke<ProjectInfo[]>('scan_sites', {
        sitesPath: config.sitesPath
      })

      const projects: Project[] = projectInfos
        .filter(p => p.has_dev_script)
        .map(p => ({
          id: p.id,
          name: p.name,
          path: p.path,
          devCommand: p.dev_command,
          expectedPorts: p.expected_ports,
          packageManager: p.package_manager.toLowerCase(),
          projectType: p.project_type,
          favorite: config.favorites.includes(p.id),
          hidden: config.hiddenProjects.includes(p.id),
          status: 'stopped',
          runningPorts: [],
        }))

      setProjects(projects)
    } catch (err) {
      setScanError(err instanceof Error ? err.message : 'Scan failed')
    } finally {
      setScanning(false)
    }
  }, [config.sitesPath])

  // Scan on mount and window focus
  useEffect(() => {
    scan()

    const unlisten = listen('tauri://focus', scan)
    return () => { unlisten.then(fn => fn()) }
  }, [scan])

  return { scan }
}
```

### usePorts.ts

```typescript
export function usePorts() {
  const { projects, setPorts, setProjects, config } = useStore()

  const refresh = useCallback(async () => {
    try {
      const ports = await invoke<PortInfo[]>('get_listening_ports')

      // Match ports to projects by cwd
      const enrichedPorts = ports.map(port => {
        const project = projects.find(p =>
          port.cwd?.startsWith(p.path)
        )
        return { ...port, projectId: project?.id ?? null }
      })

      setPorts(enrichedPorts)

      // Update project statuses based on ports
      const updatedProjects = projects.map(project => {
        const projectPorts = enrichedPorts.filter(p => p.projectId === project.id)

        if (projectPorts.length > 0) {
          return {
            ...project,
            status: 'running' as const,
            runningPorts: projectPorts.map(p => ({
              port: p.port,
              pid: p.pid,
              processName: p.processName,
              label: config.labels[`${project.id}:${p.port}`],
            })),
          }
        } else if (project.status === 'running') {
          // Was running, now stopped (process ended)
          return { ...project, status: 'stopped' as const, runningPorts: [] }
        }
        return project
      })

      setProjects(updatedProjects)
    } catch (err) {
      console.error('Port refresh failed:', err)
    }
  }, [projects, config.labels])

  // Poll every N ms
  useEffect(() => {
    refresh()
    const interval = setInterval(refresh, config.pollIntervalMs)
    return () => clearInterval(interval)
  }, [refresh, config.pollIntervalMs])

  return { refresh }
}
```

### useProcessControl.ts

```typescript
export function useProcessControl() {
  const { updateProjectStatus, projects } = useStore()

  const startProject = useCallback(async (projectId: string) => {
    const project = projects.find(p => p.id === projectId)
    if (!project) return

    updateProjectStatus(projectId, 'starting')

    try {
      await invoke('start_dev_server', {
        path: project.path,
        pkgManager: project.packageManager,
      })
      // Status will update to 'running' via port polling
    } catch (err) {
      updateProjectStatus(projectId, 'error',
        err instanceof Error ? err.message : 'Failed to start'
      )
    }
  }, [projects])

  const stopProject = useCallback(async (projectId: string) => {
    const project = projects.find(p => p.id === projectId)
    if (!project) return

    updateProjectStatus(projectId, 'stopping')

    try {
      const killed = await invoke<number>('stop_project_processes', {
        projectPath: project.path,
      })

      if (killed === 0) {
        // No processes found, just mark as stopped
        updateProjectStatus(projectId, 'stopped')
      }
      // Status will update to 'stopped' via port polling
    } catch (err) {
      updateProjectStatus(projectId, 'error',
        err instanceof Error ? err.message : 'Failed to stop'
      )
    }
  }, [projects])

  const restartProject = useCallback(async (projectId: string) => {
    await stopProject(projectId)
    // Small delay to ensure port is released
    await new Promise(resolve => setTimeout(resolve, 500))
    await startProject(projectId)
  }, [stopProject, startProject])

  const openInBrowser = useCallback(async (port: number) => {
    await invoke('open_in_browser', { url: `http://localhost:${port}` })
  }, [])

  const openInEditor = useCallback(async (path: string, editor: string) => {
    await invoke('open_in_editor', { path, editor })
  }, [])

  return {
    startProject,
    stopProject,
    restartProject,
    openInBrowser,
    openInEditor,
  }
}
```

---

## Phase 7: Config & Persistence

### Config Location

`~/.config/noodles/config.json`

### Default Config

```json
{
  "sitesPath": "~/Sites",
  "editor": "cursor",
  "launchOnLogin": true,
  "pollIntervalMs": 2000,
  "favorites": [],
  "labels": {},
  "displayNames": {},
  "hiddenProjects": []
}
```

### Config Validation

```typescript
const ConfigSchema = z.object({
  sitesPath: z.string().min(1),
  editor: z.enum(['claude', 'cursor', 'zed']),
  launchOnLogin: z.boolean(),
  pollIntervalMs: z.number().min(500).max(10000),
  favorites: z.array(z.string()),
  labels: z.record(z.string()),
  displayNames: z.record(z.string()),
  hiddenProjects: z.array(z.string()),
})

function loadConfig(): Config {
  try {
    const raw = await invoke<string>('read_config')
    const parsed = JSON.parse(raw)
    return ConfigSchema.parse(parsed)
  } catch {
    return DEFAULT_CONFIG
  }
}
```

### Autostart Setup

```rust
// main.rs
use tauri_plugin_autostart::MacosLauncher;

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_autostart::init(
            MacosLauncher::LaunchAgent,
            Some(vec!["--minimized"]),
        ))
        // ... other plugins
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
```

---

## Phase 8: Error Handling

### Error Types

```typescript
type NoodlesError =
  | { type: 'port_in_use'; port: number; pid: number }
  | { type: 'process_not_found'; pid: number }
  | { type: 'permission_denied'; path: string }
  | { type: 'invalid_project'; path: string; reason: string }
  | { type: 'spawn_failed'; command: string; stderr: string }
  | { type: 'kill_failed'; pid: number; reason: string }
```

### Error Recovery

```typescript
// In useProcessControl.ts
const startProject = async (projectId: string) => {
  // ... existing code ...

  try {
    await invoke('start_dev_server', { path, pkgManager })
  } catch (err) {
    const error = parseError(err)

    if (error.type === 'port_in_use') {
      // Offer to kill the blocking process
      updateProjectStatus(projectId, 'error',
        `Port ${error.port} in use by PID ${error.pid}`
      )
    } else if (error.type === 'spawn_failed') {
      updateProjectStatus(projectId, 'error', error.stderr)
    } else {
      updateProjectStatus(projectId, 'error', 'Unknown error')
    }
  }
}
```

---

## Phase 9: Polish & Ship

### Visual Polish
- [ ] App icon (noodle/node hybrid)
- [ ] Menu bar tray icon option
- [ ] System theme detection (light/dark)
- [ ] Smooth animations for status changes
- [ ] Loading skeletons during scan

### Performance
- [ ] Virtualized list for 100+ projects (react-window)
- [ ] Debounced filter input
- [ ] Memoized project cards
- [ ] Lazy port info fetching

### Distribution
- [ ] Code signing certificate
- [ ] Notarization for macOS
- [ ] DMG installer with background
- [ ] Auto-update via Tauri updater
- [ ] GitHub releases workflow

### Future Features (v2)
- [ ] Per-app monorepo control
- [ ] Process output/logs viewer
- [ ] Port conflict resolution UI
- [ ] Multiple Sites directories
- [ ] Project groups/tags

---

## File Structure

```
noodles/
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
│   │   ├── ActionButtons.tsx
│   │   ├── StatusIndicator.tsx
│   │   ├── OrphanPorts.tsx
│   │   └── SettingsModal.tsx
│   ├── hooks/
│   │   ├── useProjects.ts
│   │   ├── usePorts.ts
│   │   ├── useProcessControl.ts
│   │   ├── useConfig.ts
│   │   └── useKeyboard.ts
│   └── lib/
│       ├── tauri.ts
│       ├── portParser.ts
│       ├── errors.ts
│       └── constants.ts
├── src-tauri/
│   ├── src/
│   │   ├── main.rs
│   │   ├── lib.rs
│   │   ├── commands/
│   │   │   ├── mod.rs
│   │   │   ├── scanner.rs
│   │   │   ├── ports.rs
│   │   │   ├── process.rs
│   │   │   └── config.rs
│   │   └── utils/
│   │       ├── mod.rs
│   │       └── package_manager.rs
│   ├── Cargo.toml
│   ├── tauri.conf.json
│   ├── capabilities/
│   │   └── default.json
│   └── icons/
├── package.json
├── tailwind.config.ts
├── tsconfig.json
├── vite.config.ts
└── PLAN.md
```

---

## Implementation Order

| Phase | Focus | Deliverable |
|-------|-------|-------------|
| 1 | Scaffolding | Empty Tauri app with window |
| 2 | Rust commands | All backend commands working |
| 3 | Types & store | TypeScript foundation |
| 4 | Components | UI renders with mock data |
| 5 | Integration | Hooks connect UI to Rust |
| 6 | Port parsing | Smart detection working |
| 7 | Config | Settings persist |
| 8 | Error handling | Graceful failures |
| 9 | Polish | Ship-ready |

---

Ready to build.
