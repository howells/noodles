import { create } from "zustand";
import type { Project, PortInfo, Config, ProjectStatus } from "./types";

interface NodlesStore {
  // State
  projects: Project[];
  ports: PortInfo[];
  config: Config;
  filter: string;
  isScanning: boolean;
  scanError: string | null;
  selectedProjectId: string | null;

  // Actions
  setProjects: (projects: Project[]) => void;
  setPorts: (ports: PortInfo[]) => void;
  setConfig: (config: Config) => void;
  setFilter: (filter: string) => void;
  setScanning: (scanning: boolean) => void;
  setScanError: (error: string | null) => void;
  setSelectedProjectId: (id: string | null) => void;

  updateProjectStatus: (
    id: string,
    status: ProjectStatus,
    error?: string
  ) => void;
  updateProjectPorts: (id: string, ports: PortInfo[]) => void;

  // Computed helpers
  getRunningProjects: () => Project[];
  getStoppedProjects: () => Project[];
  getFilteredProjects: () => Project[];
  getOrphanPorts: () => PortInfo[];
}

const DEFAULT_CONFIG: Config = {
  sitesPath: "~/Sites",
  editor: "cursor",
  launchOnLogin: true,
  pollIntervalMs: 2000,
  favorites: [],
  labels: {},
  displayNames: {},
  hiddenProjects: [],
};

export const useStore = create<NodlesStore>((set, get) => ({
  // Initial state
  projects: [],
  ports: [],
  config: DEFAULT_CONFIG,
  filter: "",
  isScanning: false,
  scanError: null,
  selectedProjectId: null,

  // Actions
  setProjects: (projects) => set({ projects }),
  setPorts: (ports) => set({ ports }),
  setConfig: (config) => set({ config }),
  setFilter: (filter) => set({ filter }),
  setScanning: (isScanning) => set({ isScanning }),
  setScanError: (scanError) => set({ scanError }),
  setSelectedProjectId: (selectedProjectId) => set({ selectedProjectId }),

  updateProjectStatus: (id, status, error) =>
    set((state) => ({
      projects: state.projects.map((p) =>
        p.id === id ? { ...p, status, error } : p
      ),
    })),

  updateProjectPorts: (id, ports) =>
    set((state) => ({
      projects: state.projects.map((p) =>
        p.id === id
          ? {
              ...p,
              runningPorts: ports.map((port) => ({
                port: port.port,
                pid: port.pid,
                processName: port.processName,
                label: state.config.labels[`${id}:${port.port}`],
              })),
              status: ports.length > 0 ? "running" : "stopped",
            }
          : p
      ),
    })),

  // Computed helpers
  getRunningProjects: () => {
    const { projects, filter, config } = get();
    return projects
      .filter((p) => p.status === "running")
      .filter((p) => !config.hiddenProjects.includes(p.id))
      .filter(
        (p) =>
          !filter ||
          p.name.toLowerCase().includes(filter.toLowerCase()) ||
          p.id.toLowerCase().includes(filter.toLowerCase())
      );
  },

  getStoppedProjects: () => {
    const { projects, filter, config } = get();
    return projects
      .filter((p) => p.status !== "running")
      .filter((p) => !config.hiddenProjects.includes(p.id))
      .filter(
        (p) =>
          !filter ||
          p.name.toLowerCase().includes(filter.toLowerCase()) ||
          p.id.toLowerCase().includes(filter.toLowerCase())
      );
  },

  getFilteredProjects: () => {
    const { projects, filter, config } = get();
    return projects
      .filter((p) => !config.hiddenProjects.includes(p.id))
      .filter(
        (p) =>
          !filter ||
          p.name.toLowerCase().includes(filter.toLowerCase()) ||
          p.id.toLowerCase().includes(filter.toLowerCase())
      );
  },

  getOrphanPorts: () => {
    const { ports } = get();
    return ports.filter((p) => !p.projectId);
  },
}));
