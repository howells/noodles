import { AlertTriangle, CircleStop, RefreshCw, Search, SlidersHorizontal, Trash2 } from "lucide-react";
import { useEffect, useMemo, useState } from "react";

type Confidence = "low" | "medium" | "high";
type SortBy = "" | "memory" | "cpu" | "port" | "age" | "project" | "process" | "source";
type GroupBy = "none" | "project" | "source" | "port-range" | "parent-app";

type Query = {
  sortBy: SortBy;
  sortDirection: "asc" | "desc";
  groupBy: GroupBy;
  search: string;
  hideSystem: boolean;
  killableOnly: boolean;
};

type Service = {
  id: string;
  snapshotId: string;
  pid: number;
  processGroupId: number;
  parentPid: number;
  command: string;
  commandLine: string;
  executablePath: string;
  cwd: string;
  projectId: string;
  projectName: string;
  projectDisplayName: string;
  projectRoot: string;
  workspaceRoot: string;
  ports: number[];
  residentMemoryBytes: number;
  memoryUnavailableReason?: string;
  cpuPercent?: number;
  cpuUnavailableReason?: string;
  startedAt: string;
  ageSeconds: number;
  sourceLabel: string;
  sourceConfidence: Confidence;
  sourceEvidence: string[];
  killable: boolean;
  warnings: string[];
};

type Project = {
  id: string;
  name: string;
  displayName: string;
  root: string;
  workspaceRoot: string;
  serviceCount: number;
  totalResidentMemoryBytes: number;
  ports: number[];
  sourceLabels: string[];
  killableServiceCount: number;
  excludedServiceCount: number;
};

type Group = {
  id: string;
  label: string;
  kind: GroupBy;
  serviceIds: string[];
  ports: number[];
  totalResidentMemoryBytes: number;
  killableServiceCount: number;
  excludedServiceCount: number;
  sourceLabels: string[];
};

type Snapshot = {
  id: string;
  services: Service[];
  projects: Project[];
  groups: Group[];
  metadata: {
    snapshotId: string;
    scanStartedAt: string;
    scanFinishedAt: string;
    scanDurationMs: number;
    lastSuccessfulScanAt: string;
    scanSkippedReason?: string;
    permissionWarnings?: string[];
    scannerWarnings?: string[];
  };
};

const mockSnapshot: Snapshot = {
  id: "mock-snapshot",
  services: [
    {
      id: "materia-vite",
      snapshotId: "mock-snapshot",
      pid: 42117,
      processGroupId: 42117,
      parentPid: 41702,
      command: "node",
      commandLine: "node ./node_modules/vite/bin/vite.js --host 127.0.0.1",
      executablePath: "/opt/homebrew/bin/node",
      cwd: "/Users/danielhowells/Sites/materia",
      projectId: "project:materia",
      projectName: "materia",
      projectDisplayName: "materia",
      projectRoot: "/Users/danielhowells/Sites/materia",
      workspaceRoot: "/Users/danielhowells/Sites/materia",
      ports: [5173],
      residentMemoryBytes: 384 * 1024 * 1024,
      cpuPercent: 3.8,
      startedAt: new Date(Date.now() - 48 * 60 * 1000).toISOString(),
      ageSeconds: 48 * 60,
      sourceLabel: "dev-server",
      sourceConfidence: "high",
      sourceEvidence: ["listening tcp port", "node command", "cwd under ~/Sites"],
      killable: true,
      warnings: [],
    },
    {
      id: "agent-api",
      snapshotId: "mock-snapshot",
      pid: 41792,
      processGroupId: 41792,
      parentPid: 40122,
      command: "pnpm",
      commandLine: "pnpm dev",
      executablePath: "/opt/homebrew/bin/pnpm",
      cwd: "/Users/danielhowells/Sites/agent-lab",
      projectId: "project:agent-lab",
      projectName: "agent-lab",
      projectDisplayName: "agent-lab",
      projectRoot: "/Users/danielhowells/Sites/agent-lab",
      workspaceRoot: "/Users/danielhowells/Sites/agent-lab",
      ports: [3000, 3001],
      residentMemoryBytes: 612 * 1024 * 1024,
      cpuPercent: 8.1,
      startedAt: new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString(),
      ageSeconds: 2 * 60 * 60,
      sourceLabel: "agent",
      sourceConfidence: "medium",
      sourceEvidence: ["parent command: codex", "cwd under ~/Sites"],
      killable: true,
      warnings: [],
    },
    {
      id: "control-center",
      snapshotId: "mock-snapshot",
      pid: 322,
      processGroupId: 322,
      parentPid: 1,
      command: "ControlCenter",
      commandLine: "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter",
      executablePath: "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter",
      cwd: "/",
      projectId: "project:system",
      projectName: "system",
      projectDisplayName: "system",
      projectRoot: "/",
      workspaceRoot: "/",
      ports: [5000],
      residentMemoryBytes: 92 * 1024 * 1024,
      startedAt: new Date(Date.now() - 8 * 60 * 60 * 1000).toISOString(),
      ageSeconds: 8 * 60 * 60,
      sourceLabel: "system",
      sourceConfidence: "high",
      sourceEvidence: ["system executable path"],
      killable: false,
      warnings: ["excluded from one-click kill"],
    },
  ],
  projects: [
    {
      id: "project:agent-lab",
      name: "agent-lab",
      displayName: "agent-lab",
      root: "/Users/danielhowells/Sites/agent-lab",
      workspaceRoot: "/Users/danielhowells/Sites/agent-lab",
      serviceCount: 1,
      totalResidentMemoryBytes: 612 * 1024 * 1024,
      ports: [3000, 3001],
      sourceLabels: ["agent"],
      killableServiceCount: 1,
      excludedServiceCount: 0,
    },
    {
      id: "project:materia",
      name: "materia",
      displayName: "materia",
      root: "/Users/danielhowells/Sites/materia",
      workspaceRoot: "/Users/danielhowells/Sites/materia",
      serviceCount: 1,
      totalResidentMemoryBytes: 384 * 1024 * 1024,
      ports: [5173],
      sourceLabels: ["dev-server"],
      killableServiceCount: 1,
      excludedServiceCount: 0,
    },
  ],
  groups: [
    {
      id: "project:agent-lab",
      label: "agent-lab",
      kind: "project",
      serviceIds: ["agent-api"],
      ports: [3000, 3001],
      totalResidentMemoryBytes: 612 * 1024 * 1024,
      killableServiceCount: 1,
      excludedServiceCount: 0,
      sourceLabels: ["agent"],
    },
    {
      id: "project:materia",
      label: "materia",
      kind: "project",
      serviceIds: ["materia-vite"],
      ports: [5173],
      totalResidentMemoryBytes: 384 * 1024 * 1024,
      killableServiceCount: 1,
      excludedServiceCount: 0,
      sourceLabels: ["dev-server"],
    },
  ],
  metadata: {
    snapshotId: "mock-snapshot",
    scanStartedAt: new Date().toISOString(),
    scanFinishedAt: new Date().toISOString(),
    scanDurationMs: 118,
    lastSuccessfulScanAt: new Date().toISOString(),
    permissionWarnings: ["Some process command lines may be unavailable until permissions are granted."],
  },
};

export default function App() {
  const [query, setQuery] = useState<Query>({
    sortBy: "memory",
    sortDirection: "desc",
    groupBy: "project",
    search: "",
    hideSystem: false,
    killableOnly: false,
  });
  const [snapshot, setSnapshot] = useState<Snapshot>(mockSnapshot);
  const [scanning, setScanning] = useState(true);

  useEffect(() => {
    const timer = window.setTimeout(() => setScanning(false), 260);
    return () => window.clearTimeout(timer);
  }, []);

  const services = useMemo(() => filterServices(snapshot.services, query), [snapshot.services, query]);
  const killableCount = services.filter((service) => service.killable).length;
  const totalMemory = services.reduce((total, service) => total + service.residentMemoryBytes, 0);

  function refresh() {
    setScanning(true);
    window.setTimeout(() => setScanning(false), 320);
  }

  function removeService(serviceId: string) {
    setSnapshot((current) => ({
      ...current,
      services: current.services.filter((service) => service.id !== serviceId),
    }));
  }

  return (
    <main className="app-shell">
      <header className="topbar">
        <div>
          <h1>Noodles</h1>
          <div className="meta-line">
            {services.length} services · {killableCount} killable · {formatBytes(totalMemory)} resident
          </div>
        </div>
        <div className="toolbar">
          <label className="search-field">
            <Search size={16} aria-hidden="true" />
            <input
              value={query.search}
              onChange={(event) => setQuery({ ...query, search: event.target.value })}
              placeholder="Search project, command, port"
            />
          </label>
          <label className="select-field">
            <SlidersHorizontal size={16} aria-hidden="true" />
            <select
              value={query.sortBy}
              onChange={(event) => setQuery({ ...query, sortBy: event.target.value as SortBy })}
            >
              <option value="memory">Memory</option>
              <option value="cpu">CPU</option>
              <option value="port">Port</option>
              <option value="age">Age</option>
              <option value="project">Project</option>
              <option value="process">Process</option>
              <option value="source">Source</option>
            </select>
          </label>
          <label className="check-field">
            <input
              type="checkbox"
              checked={query.hideSystem}
              onChange={(event) => setQuery({ ...query, hideSystem: event.target.checked })}
            />
            Hide system
          </label>
          <button className="icon-button" onClick={refresh} title="Refresh services" type="button">
            <RefreshCw size={17} aria-hidden="true" />
          </button>
        </div>
      </header>

      {snapshot.metadata.permissionWarnings?.length ? (
        <section className="warning-band" aria-label="Permission warnings">
          <AlertTriangle size={18} aria-hidden="true" />
          <div>
            {snapshot.metadata.permissionWarnings.map((warning) => (
              <div key={warning}>{warning}</div>
            ))}
          </div>
        </section>
      ) : null}

      <section className="status-strip" aria-label="Scan status">
        <span className={scanning ? "dot dot-active" : "dot"} />
        <span>{scanning ? "Scanning" : `Last scan ${formatTime(snapshot.metadata.lastSuccessfulScanAt)}`}</span>
        <span>{snapshot.metadata.scanDurationMs} ms</span>
        {snapshot.metadata.scanSkippedReason ? <span>{snapshot.metadata.scanSkippedReason}</span> : null}
      </section>

      {query.groupBy === "project" && services.length ? (
        <section className="group-strip" aria-label="Project groups">
          {snapshot.groups.map((group) => (
            <div className="group-row" key={group.id}>
              <div>
                <strong>{group.label}</strong>
                <span>{formatBytes(group.totalResidentMemoryBytes)}</span>
                <span>{group.ports.join(", ")}</span>
                <span>{group.sourceLabels.join(", ")}</span>
              </div>
              <button className="kill-group" type="button" title={`Kill ${group.killableServiceCount} services`}>
                <CircleStop size={16} aria-hidden="true" />
                Kill {group.killableServiceCount}
              </button>
            </div>
          ))}
        </section>
      ) : null}

      <section className="table-region" aria-label="Running services">
        {services.length === 0 ? (
          <div className="empty-state">No matching services</div>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Project</th>
                <th>Command</th>
                <th>Ports</th>
                <th>Memory</th>
                <th>CPU</th>
                <th>Age</th>
                <th>Source</th>
                <th aria-label="Actions" />
              </tr>
            </thead>
            <tbody>
              {services.map((service) => (
                <tr key={service.id} className={service.killable ? undefined : "muted-row"}>
                  <td>
                    <div className="primary-text">{projectLabel(service)}</div>
                    <div className="secondary-text">{service.cwd}</div>
                  </td>
                  <td>
                    <div className="primary-text">{service.command}</div>
                    <div className="secondary-text">{service.commandLine}</div>
                  </td>
                  <td>{service.ports.join(", ")}</td>
                  <td>{formatBytes(service.residentMemoryBytes)}</td>
                  <td>{service.cpuPercent === undefined ? "sample pending" : `${service.cpuPercent.toFixed(1)}%`}</td>
                  <td>{formatAge(service.ageSeconds)}</td>
                  <td>
                    <span className={`source-pill confidence-${service.sourceConfidence}`}>{service.sourceLabel}</span>
                  </td>
                  <td className="action-cell">
                    <button
                      className="kill-button"
                      disabled={!service.killable}
                      onClick={() => removeService(service.id)}
                      title={service.killable ? "Kill service" : "Service excluded from kill"}
                      type="button"
                    >
                      <Trash2 size={16} aria-hidden="true" />
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </section>
    </main>
  );
}

function filterServices(services: Service[], query: Query): Service[] {
  const search = query.search.trim().toLowerCase();
  return services.filter((service) => {
    if (query.hideSystem && service.sourceLabel === "system") return false;
    if (query.killableOnly && !service.killable) return false;
    if (!search) return true;
    return [
      service.projectDisplayName,
      service.projectName,
      service.cwd,
      service.command,
      service.commandLine,
      service.sourceLabel,
      service.ports.join(" "),
    ]
      .join(" ")
      .toLowerCase()
      .includes(search);
  });
}

function projectLabel(service: Service): string {
  return service.projectDisplayName || service.projectName || service.cwd || "unknown";
}

function formatBytes(bytes: number): string {
  if (bytes >= 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} GB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

function formatAge(seconds: number): string {
  if (seconds >= 3600) return `${Math.floor(seconds / 3600)}h ${Math.floor((seconds % 3600) / 60)}m`;
  if (seconds >= 60) return `${Math.floor(seconds / 60)}m`;
  return `${seconds}s`;
}

function formatTime(value: string): string {
  return new Intl.DateTimeFormat(undefined, {
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  }).format(new Date(value));
}
