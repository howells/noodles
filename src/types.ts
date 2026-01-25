export type ProjectStatus =
  | "stopped"
  | "starting"
  | "running"
  | "stopping"
  | "error";

export type PackageManager = "pnpm" | "npm" | "yarn" | "bun";

export type ProjectType =
  | { type: "standard" }
  | { type: "turborepo"; apps: string[] }
  | { type: "pnpm-workspace"; packages: string[] };

export interface Project {
  id: string;
  name: string;
  displayName?: string;
  path: string;
  devCommand: string | null;
  expectedPorts: number[];
  packageManager: PackageManager;
  projectType: ProjectType;
  favorite: boolean;
  hidden: boolean;
  status: ProjectStatus;
  runningPorts: RunningPort[];
  error?: string;
  lastStarted?: number;
}

export interface RunningPort {
  port: number;
  pid: number;
  processName: string;
  label?: string;
}

export interface PortInfo {
  port: number;
  pid: number;
  processName: string;
  cwd: string | null;
  projectId: string | null;
}

export interface Config {
  sitesPath: string;
  editor: "claude" | "cursor" | "zed";
  launchOnLogin: boolean;
  pollIntervalMs: number;
  favorites: string[];
  labels: Record<string, string>;
  displayNames: Record<string, string>;
  hiddenProjects: string[];
}
