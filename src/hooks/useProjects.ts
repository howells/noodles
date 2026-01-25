import { useCallback, useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { useStore } from "../store";
import type { Project, ProjectType } from "../types";

interface ProjectInfo {
  id: string;
  name: string;
  path: string;
  has_dev_script: boolean;
  dev_command: string | null;
  expected_ports: number[];
  package_manager: string;
  project_type: RustProjectType;
}

type RustProjectType =
  | { type: "standard" }
  | { type: "turborepo"; apps: string[] }
  | { type: "pnpm-workspace"; packages: string[] };

function convertProjectType(rustType: RustProjectType): ProjectType {
  if (rustType.type === "turborepo") {
    return { type: "turborepo", apps: rustType.apps };
  }
  if (rustType.type === "pnpm-workspace") {
    return { type: "pnpm-workspace", packages: rustType.packages };
  }
  return { type: "standard" };
}

export function useProjects() {
  const {
    setProjects,
    setScanning,
    setScanError,
    config,
  } = useStore();

  const scan = useCallback(async () => {
    setScanning(true);
    setScanError(null);

    try {
      const projectInfos = await invoke<ProjectInfo[]>("scan_sites", {
        sitesPath: config.sitesPath,
      });

      const projects: Project[] = projectInfos
        .filter((p) => p.has_dev_script)
        .map((p) => ({
          id: p.id,
          name: p.name,
          displayName: config.displayNames[p.id],
          path: p.path,
          devCommand: p.dev_command,
          expectedPorts: p.expected_ports,
          packageManager: p.package_manager.toLowerCase() as Project["packageManager"],
          projectType: convertProjectType(p.project_type),
          favorite: config.favorites.includes(p.id),
          hidden: config.hiddenProjects.includes(p.id),
          status: "stopped" as const,
          runningPorts: [],
        }));

      // Sort: favorites first, then alphabetically
      projects.sort((a, b) => {
        if (a.favorite && !b.favorite) return -1;
        if (!a.favorite && b.favorite) return 1;
        return a.name.localeCompare(b.name);
      });

      setProjects(projects);
    } catch (err) {
      console.error("Scan failed:", err);
      setScanError(err instanceof Error ? err.message : String(err));
    } finally {
      setScanning(false);
    }
  }, [config.sitesPath, config.displayNames, config.favorites, config.hiddenProjects, setProjects, setScanning, setScanError]);

  // Scan on mount
  useEffect(() => {
    scan();
  }, [scan]);

  // Re-scan when window gains focus
  useEffect(() => {
    let unlisten: (() => void) | undefined;

    listen("tauri://focus", () => {
      scan();
    }).then((fn) => {
      unlisten = fn;
    });

    return () => {
      unlisten?.();
    };
  }, [scan]);

  return { scan };
}
