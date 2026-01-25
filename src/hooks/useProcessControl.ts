import { useCallback } from "react";
import { invoke } from "@tauri-apps/api/core";
import { useStore } from "../store";

export function useProcessControl() {
  const { projects, updateProjectStatus, config } = useStore();

  const startProject = useCallback(
    async (projectId: string) => {
      const project = projects.find((p) => p.id === projectId);
      if (!project) return;

      updateProjectStatus(projectId, "starting");

      try {
        await invoke("start_dev_server", {
          path: project.path,
          pkgManager: project.packageManager,
        });
        // Status will update to 'running' via port polling
      } catch (err) {
        console.error("Start failed:", err);
        updateProjectStatus(
          projectId,
          "error",
          err instanceof Error ? err.message : "Failed to start"
        );
      }
    },
    [projects, updateProjectStatus]
  );

  const stopProject = useCallback(
    async (projectId: string) => {
      const project = projects.find((p) => p.id === projectId);
      if (!project) return;

      updateProjectStatus(projectId, "stopping");

      try {
        const killed = await invoke<number>("stop_project_processes", {
          projectPath: project.path,
        });

        if (killed === 0) {
          // No processes found, just mark as stopped
          updateProjectStatus(projectId, "stopped");
        }
        // Status will update to 'stopped' via port polling
      } catch (err) {
        console.error("Stop failed:", err);
        updateProjectStatus(
          projectId,
          "error",
          err instanceof Error ? err.message : "Failed to stop"
        );
      }
    },
    [projects, updateProjectStatus]
  );

  const restartProject = useCallback(
    async (projectId: string) => {
      await stopProject(projectId);
      // Small delay to ensure port is released
      await new Promise((resolve) => setTimeout(resolve, 1000));
      await startProject(projectId);
    },
    [stopProject, startProject]
  );

  const openInBrowser = useCallback(async (port: number) => {
    try {
      await invoke("open_in_browser", { url: `http://localhost:${port}` });
    } catch (err) {
      console.error("Failed to open browser:", err);
    }
  }, []);

  const openInEditor = useCallback(
    async (path: string) => {
      try {
        await invoke("open_in_editor", { path, editor: config.editor });
      } catch (err) {
        console.error("Failed to open editor:", err);
      }
    },
    [config.editor]
  );

  const killPort = useCallback(async (pid: number) => {
    try {
      await invoke("stop_process", { pid, force: false });
    } catch (err) {
      console.error("Failed to kill process:", err);
    }
  }, []);

  return {
    startProject,
    stopProject,
    restartProject,
    openInBrowser,
    openInEditor,
    killPort,
  };
}
