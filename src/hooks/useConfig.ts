import { useCallback, useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";
import { useStore } from "../store";
import type { Config } from "../types";

interface RustConfig {
  sites_path: string;
  editor: string;
  launch_on_login: boolean;
  poll_interval_ms: number;
  favorites: string[];
  labels: Record<string, string>;
  display_names: Record<string, string>;
  hidden_projects: string[];
}

function convertFromRust(rust: RustConfig): Config {
  return {
    sitesPath: rust.sites_path,
    editor: rust.editor as Config["editor"],
    launchOnLogin: rust.launch_on_login,
    pollIntervalMs: rust.poll_interval_ms,
    favorites: rust.favorites,
    labels: rust.labels,
    displayNames: rust.display_names,
    hiddenProjects: rust.hidden_projects,
  };
}

function convertToRust(config: Config): RustConfig {
  return {
    sites_path: config.sitesPath,
    editor: config.editor,
    launch_on_login: config.launchOnLogin,
    poll_interval_ms: config.pollIntervalMs,
    favorites: config.favorites,
    labels: config.labels,
    display_names: config.displayNames,
    hidden_projects: config.hiddenProjects,
  };
}

export function useConfig() {
  const { config, setConfig } = useStore();

  const loadConfig = useCallback(async () => {
    try {
      const rustConfig = await invoke<RustConfig>("read_config");
      setConfig(convertFromRust(rustConfig));
    } catch (err) {
      console.error("Failed to load config:", err);
    }
  }, [setConfig]);

  const saveConfig = useCallback(async (newConfig: Config) => {
    try {
      await invoke("write_config", { config: convertToRust(newConfig) });
      setConfig(newConfig);
    } catch (err) {
      console.error("Failed to save config:", err);
    }
  }, [setConfig]);

  const updateConfig = useCallback(
    async (updates: Partial<Config>) => {
      const newConfig = { ...config, ...updates };
      await saveConfig(newConfig);
    },
    [config, saveConfig]
  );

  // Load config on mount
  useEffect(() => {
    loadConfig();
  }, [loadConfig]);

  return {
    config,
    loadConfig,
    saveConfig,
    updateConfig,
  };
}
