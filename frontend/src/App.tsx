import { AlertTriangle, CircleStop, RefreshCw, Search, SlidersHorizontal, Trash2 } from "lucide-react";
import { useEffect, useState } from "react";

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

type KillRequest = {
  snapshotId: string;
  serviceId: string;
  pid: number;
  processGroupId: number;
  startedAt: string;
  command: string;
  executablePath: string;
  cwd: string;
  projectRoot: string;
  expectedPorts: number[];
  requestedAction: "service";
};

type KillResult = {
  planSnapshotId: string;
  targets: Array<{
    serviceId: string;
    pid: number;
    success: boolean;
    errorReason?: string;
  }>;
  exclusions: Array<{
    serviceId: string;
    pid: number;
    reason: string;
  }>;
};

type NoodlesApi = {
  scan(query: Query): Promise<Snapshot>;
  killService(request: KillRequest): Promise<KillResult>;
};

declare global {
  interface Window {
    runtime?: unknown;
  }
}

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

const defaultQuery: Query = {
  sortBy: "memory",
  sortDirection: "desc",
  groupBy: "project",
  search: "",
  hideSystem: false,
  killableOnly: false,
};

const noodlesApi = createNoodlesApi();

export default function App() {
	const [query, setQuery] = useState<Query>(defaultQuery);
	const [snapshot, setSnapshot] = useState<Snapshot>(() => buildFallbackSnapshot(mockSnapshot.services, defaultQuery));
	const [scanning, setScanning] = useState(true);
	const [stale, setStale] = useState(false);
	const [scanError, setScanError] = useState("");
	const [killing, setKilling] = useState<Record<string, boolean>>({});
	const [killFailures, setKillFailures] = useState<Record<string, string>>({});

	useEffect(() => {
		let cancelled = false;
		const timer = window.setTimeout(() => {
			setScanning(true);
			setScanError("");
			noodlesApi
				.scan(query)
				.then((nextSnapshot) => {
					if (cancelled) return;
					setSnapshot(nextSnapshot);
					setStale(false);
				})
				.catch((error: unknown) => {
					if (cancelled) return;
					setScanError(errorMessage(error));
					setStale(true);
				})
				.finally(() => {
					if (!cancelled) setScanning(false);
				});
		}, 140);
		return () => {
			cancelled = true;
			window.clearTimeout(timer);
		};
	}, [query]);

	const services = snapshot.services;
	const killableCount = services.filter((service) => service.killable).length;
	const totalMemory = services.reduce((total, service) => total + service.residentMemoryBytes, 0);

	function refresh() {
		setQuery({ ...query });
	}

	async function killService(service: Service) {
		setKilling((current) => ({ ...current, [service.id]: true }));
		setKillFailures((current) => {
			const next = { ...current };
			delete next[service.id];
			return next;
		});
		try {
			const result = await noodlesApi.killService(killRequestFromService(service));
			const target = result.targets.find((candidate) => candidate.serviceId === service.id);
			if (!target?.success) {
				const exclusion = result.exclusions.find((candidate) => candidate.serviceId === service.id);
				throw new Error(target?.errorReason || exclusion?.reason || "kill did not complete");
			}
			setSnapshot((current) => withServices(current, current.services.filter((candidate) => candidate.id !== service.id)));
			setStale(true);
			refresh();
		} catch (error) {
			setKillFailures((current) => ({ ...current, [service.id]: errorMessage(error) }));
		} finally {
			setKilling((current) => ({ ...current, [service.id]: false }));
		}
	}

	async function killGroup(group: Group) {
		const groupServices = services.filter((service) => group.serviceIds.includes(service.id) && service.killable);
		for (const service of groupServices) {
			await killService(service);
		}
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
        {stale ? <span className="stale-label">Stale</span> : null}
        {scanError ? <span className="error-label">{scanError}</span> : null}
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
              <button
                className="kill-group"
                disabled={group.killableServiceCount === 0}
                onClick={() => killGroup(group)}
                type="button"
                title={`Kill ${group.killableServiceCount} services`}
              >
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
                      disabled={!service.killable || killing[service.id]}
                      onClick={() => killService(service)}
                      title={service.killable ? "Kill service" : "Service excluded from kill"}
                      type="button"
                    >
                      {killing[service.id] ? <RefreshCw size={16} aria-hidden="true" /> : <Trash2 size={16} aria-hidden="true" />}
                    </button>
                    {killFailures[service.id] ? <div className="kill-error">{killFailures[service.id]}</div> : null}
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

function createNoodlesApi(): NoodlesApi {
  const removedServiceIds = new Set<string>();
  let bindingPromise: Promise<Partial<Record<"Scan" | "KillService", unknown>> | null> | null = null;

  async function loadBindings() {
    if (!hasWailsRuntime()) return null;
    if (!bindingPromise) {
      const dynamicImport = new Function("path", "return import(path)") as (
        path: string,
      ) => Promise<Partial<Record<"Scan" | "KillService", unknown>>>;
      bindingPromise = dynamicImport("./wailsjs/go/main/App")
        .then((module) => module as Partial<Record<"Scan" | "KillService", unknown>>)
        .catch(() => null);
    }
    return bindingPromise;
  }

  return {
    async scan(query: Query) {
      const bindings = await loadBindings();
      if (bindings && typeof bindings.Scan === "function") {
        return (bindings.Scan as (query: Query) => Promise<Snapshot>)(query);
      }
      await delay(160);
      const services = mockSnapshot.services.filter((service) => !removedServiceIds.has(service.id));
      return buildFallbackSnapshot(services, query);
    },
    async killService(request: KillRequest) {
      const bindings = await loadBindings();
      if (bindings && typeof bindings.KillService === "function") {
        return (bindings.KillService as (request: KillRequest) => Promise<KillResult>)(request);
      }
      await delay(180);
      removedServiceIds.add(request.serviceId);
      return {
        planSnapshotId: request.snapshotId,
        targets: [{ serviceId: request.serviceId, pid: request.pid, success: true }],
        exclusions: [],
      };
    },
  };
}

function hasWailsRuntime(): boolean {
  return typeof window !== "undefined" && window.runtime !== undefined;
}

function killRequestFromService(service: Service): KillRequest {
  return {
    snapshotId: service.snapshotId,
    serviceId: service.id,
    pid: service.pid,
    processGroupId: service.processGroupId,
    startedAt: service.startedAt,
    command: service.command,
    executablePath: service.executablePath,
    cwd: service.cwd,
    projectRoot: service.projectRoot,
    expectedPorts: [...service.ports],
    requestedAction: "service",
  };
}

function buildFallbackSnapshot(services: Service[], query: Query): Snapshot {
  const filtered = sortServices(filterServices(services, query), query);
  return withServices(
    {
      ...mockSnapshot,
      id: `mock-${Date.now()}`,
      metadata: {
        ...mockSnapshot.metadata,
        snapshotId: `mock-${Date.now()}`,
        scanStartedAt: new Date().toISOString(),
        scanFinishedAt: new Date().toISOString(),
        lastSuccessfulScanAt: new Date().toISOString(),
        scanDurationMs: 112,
      },
    },
    filtered,
  );
}

function withServices(snapshot: Snapshot, services: Service[]): Snapshot {
  const projectsById = new Map<string, Project>();
  for (const service of services) {
    const id = service.projectId || "unknown";
    const existing = projectsById.get(id);
    const project =
      existing ??
      ({
        id,
        name: service.projectName || id,
        displayName: service.projectDisplayName || service.projectName || id,
        root: service.projectRoot,
        workspaceRoot: service.workspaceRoot,
        serviceCount: 0,
        totalResidentMemoryBytes: 0,
        ports: [],
        sourceLabels: [],
        killableServiceCount: 0,
        excludedServiceCount: 0,
      } satisfies Project);
    project.serviceCount += 1;
    project.totalResidentMemoryBytes += service.residentMemoryBytes;
    project.ports = uniqueNumbers([...project.ports, ...service.ports]);
    project.sourceLabels = uniqueStrings([...project.sourceLabels, service.sourceLabel]);
    if (service.killable) project.killableServiceCount += 1;
    else project.excludedServiceCount += 1;
    projectsById.set(id, project);
  }

  const projects = Array.from(projectsById.values()).sort(
    (a, b) => b.totalResidentMemoryBytes - a.totalResidentMemoryBytes || a.displayName.localeCompare(b.displayName),
  );
  const groups = projects.map((project) => ({
    id: project.id,
    label: project.displayName,
    kind: "project" as GroupBy,
    serviceIds: services.filter((service) => service.projectId === project.id).map((service) => service.id).sort(),
    ports: project.ports,
    totalResidentMemoryBytes: project.totalResidentMemoryBytes,
    killableServiceCount: project.killableServiceCount,
    excludedServiceCount: project.excludedServiceCount,
    sourceLabels: project.sourceLabels,
  }));

  return {
    ...snapshot,
    services,
    projects,
    groups,
  };
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

function sortServices(services: Service[], query: Query): Service[] {
  return [...services].sort((a, b) => {
    switch (query.sortBy) {
      case "cpu":
        return applyDirection(query, (a.cpuPercent ?? -1) - (b.cpuPercent ?? -1));
      case "port":
        return applyDirection(query, lowestPort(a.ports) - lowestPort(b.ports));
      case "age":
        return applyDirection(query, a.ageSeconds - b.ageSeconds);
      case "project":
        return applyDirection(query, projectLabel(a).localeCompare(projectLabel(b)));
      case "process":
        return applyDirection(query, a.command.localeCompare(b.command));
      case "source":
        return applyDirection(query, a.sourceLabel.localeCompare(b.sourceLabel));
      case "memory":
      default:
        return applyDirection(query, a.residentMemoryBytes - b.residentMemoryBytes);
    }
  });
}

function applyDirection(query: Query, value: number): number {
  return query.sortDirection === "asc" ? value : -value;
}

function lowestPort(ports: number[]): number {
  return ports.length ? Math.min(...ports) : 0;
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

function uniqueNumbers(values: number[]): number[] {
  return Array.from(new Set(values)).sort((a, b) => a - b);
}

function uniqueStrings(values: string[]): string[] {
  return Array.from(new Set(values.filter(Boolean))).sort((a, b) => a.localeCompare(b));
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => window.setTimeout(resolve, ms));
}

function errorMessage(error: unknown): string {
  if (error instanceof Error) return error.message;
  return String(error);
}
