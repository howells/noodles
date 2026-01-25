import { useCallback, useEffect, useRef } from "react";
import { invoke } from "@tauri-apps/api/core";
import { useStore } from "../store";
import type { PortInfo } from "../types";

interface RustPortInfo {
  port: number;
  pid: number;
  process_name: string;
  cwd: string | null;
}

export function usePorts() {
  const { projects, setPorts, config, updateProjectPorts } = useStore();
  const intervalRef = useRef<number | null>(null);

  const refresh = useCallback(async () => {
    try {
      const rustPorts = await invoke<RustPortInfo[]>("get_listening_ports");

      // Convert and match ports to projects
      const ports: PortInfo[] = rustPorts.map((p) => {
        // Find project by matching cwd to project path
        const project = projects.find(
          (proj) => p.cwd && p.cwd.startsWith(proj.path)
        );

        return {
          port: p.port,
          pid: p.pid,
          processName: p.process_name,
          cwd: p.cwd,
          projectId: project?.id ?? null,
        };
      });

      setPorts(ports);

      // Update each project's running ports
      for (const project of projects) {
        const projectPorts = ports.filter((p) => p.projectId === project.id);
        updateProjectPorts(project.id, projectPorts);
      }
    } catch (err) {
      console.error("Port refresh failed:", err);
    }
  }, [projects, setPorts, updateProjectPorts]);

  // Start polling
  useEffect(() => {
    // Initial refresh
    refresh();

    // Set up interval
    intervalRef.current = window.setInterval(refresh, config.pollIntervalMs);

    return () => {
      if (intervalRef.current) {
        clearInterval(intervalRef.current);
      }
    };
  }, [refresh, config.pollIntervalMs]);

  return { refresh };
}
