use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::path::Path;
use std::process::Command;

// ============================================================================
// Types
// ============================================================================

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct ProjectInfo {
    pub id: String,
    pub name: String,
    pub path: String,
    pub has_dev_script: bool,
    pub dev_command: Option<String>,
    pub expected_ports: Vec<u16>,
    pub package_manager: String,
    pub project_type: ProjectType,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
#[serde(tag = "type")]
pub enum ProjectType {
    #[serde(rename = "standard")]
    Standard,
    #[serde(rename = "turborepo")]
    Turborepo { apps: Vec<String> },
    #[serde(rename = "pnpm-workspace")]
    PnpmWorkspace { packages: Vec<String> },
}

#[derive(Debug, Serialize, Deserialize)]
pub struct PortInfo {
    pub port: u16,
    pub pid: u32,
    pub process_name: String,
    pub cwd: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SpawnedProcess {
    pub pid: u32,
    pub started_at: u64,
}

#[derive(Debug, Serialize, Deserialize, Default)]
pub struct Config {
    pub sites_path: String,
    pub editor: String,
    pub launch_on_login: bool,
    pub poll_interval_ms: u32,
    pub favorites: Vec<String>,
    pub labels: HashMap<String, String>,
    pub display_names: HashMap<String, String>,
    pub hidden_projects: Vec<String>,
}

// ============================================================================
// Project Scanning
// ============================================================================

#[tauri::command]
pub fn scan_sites(sites_path: String) -> Result<Vec<ProjectInfo>, String> {
    let expanded_path = shellexpand::tilde(&sites_path).to_string();
    let path = Path::new(&expanded_path);

    if !path.exists() {
        return Err(format!("Sites path does not exist: {}", sites_path));
    }

    let mut projects = Vec::new();

    let entries = fs::read_dir(path).map_err(|e| e.to_string())?;

    for entry in entries.flatten() {
        let entry_path = entry.path();
        if !entry_path.is_dir() {
            continue;
        }

        let package_json_path = entry_path.join("package.json");
        if !package_json_path.exists() {
            continue;
        }

        // Parse package.json
        let package_json = match fs::read_to_string(&package_json_path) {
            Ok(content) => content,
            Err(_) => continue,
        };

        let pkg: serde_json::Value = match serde_json::from_str(&package_json) {
            Ok(v) => v,
            Err(_) => continue,
        };

        let folder_name = entry_path
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("")
            .to_string();

        let name = pkg["name"]
            .as_str()
            .unwrap_or(&folder_name)
            .to_string();

        let dev_command = pkg["scripts"]["dev"].as_str().map(|s| s.to_string());
        let has_dev_script = dev_command.is_some();

        // Extract expected ports from dev command
        let expected_ports = dev_command
            .as_ref()
            .map(|cmd| extract_ports(cmd))
            .unwrap_or_default();

        // Detect package manager
        let package_manager = detect_package_manager(&entry_path);

        // Detect monorepo type
        let project_type = detect_project_type(&entry_path);

        projects.push(ProjectInfo {
            id: folder_name.clone(),
            name,
            path: entry_path.to_string_lossy().to_string(),
            has_dev_script,
            dev_command,
            expected_ports,
            package_manager,
            project_type,
        });
    }

    // Sort by name
    projects.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));

    Ok(projects)
}

fn extract_ports(dev_command: &str) -> Vec<u16> {
    use std::collections::HashSet;

    let mut ports = HashSet::new();

    // Pattern: --port 3000 or --port=3000
    let port_re = regex_lite::Regex::new(r"--port[=\s]+(\d+)").unwrap();
    for cap in port_re.captures_iter(dev_command) {
        if let Ok(port) = cap[1].parse::<u16>() {
            ports.insert(port);
        }
    }

    // Pattern: -p 3000
    let p_re = regex_lite::Regex::new(r"-p\s+(\d+)").unwrap();
    for cap in p_re.captures_iter(dev_command) {
        if let Ok(port) = cap[1].parse::<u16>() {
            ports.insert(port);
        }
    }

    // Pattern: ${VAR:-3000} (env var with default)
    let env_default_re = regex_lite::Regex::new(r"\$\{[^:]+:-(\d+)\}").unwrap();
    for cap in env_default_re.captures_iter(dev_command) {
        if let Ok(port) = cap[1].parse::<u16>() {
            ports.insert(port);
        }
    }

    // Pattern: localhost:3000
    let localhost_re = regex_lite::Regex::new(r"localhost:(\d+)").unwrap();
    for cap in localhost_re.captures_iter(dev_command) {
        if let Ok(port) = cap[1].parse::<u16>() {
            ports.insert(port);
        }
    }

    // Framework defaults if no port found
    if ports.is_empty() {
        if dev_command.contains("next dev") {
            ports.insert(3000);
        } else if dev_command.contains("vite") {
            ports.insert(5173);
        } else if dev_command.contains("astro dev") {
            ports.insert(4321);
        } else if dev_command.contains("nuxt dev") {
            ports.insert(3000);
        }
    }

    let mut result: Vec<u16> = ports.into_iter().collect();
    result.sort();
    result
}

fn detect_package_manager(project_path: &Path) -> String {
    if project_path.join("bun.lockb").exists() {
        "bun".to_string()
    } else if project_path.join("pnpm-lock.yaml").exists() {
        "pnpm".to_string()
    } else if project_path.join("yarn.lock").exists() {
        "yarn".to_string()
    } else {
        "npm".to_string()
    }
}

fn detect_project_type(project_path: &Path) -> ProjectType {
    // Check for turbo.json
    if project_path.join("turbo.json").exists() {
        let apps = find_workspace_apps(project_path);
        return ProjectType::Turborepo { apps };
    }

    // Check for pnpm-workspace.yaml
    if project_path.join("pnpm-workspace.yaml").exists() {
        let packages = find_workspace_apps(project_path);
        return ProjectType::PnpmWorkspace { packages };
    }

    ProjectType::Standard
}

fn find_workspace_apps(project_path: &Path) -> Vec<String> {
    let mut apps = Vec::new();

    // Check apps/ directory
    let apps_dir = project_path.join("apps");
    if apps_dir.exists() {
        if let Ok(entries) = fs::read_dir(&apps_dir) {
            for entry in entries.flatten() {
                if entry.path().is_dir() {
                    let pkg_path = entry.path().join("package.json");
                    if pkg_path.exists() {
                        if let Some(name) = entry.file_name().to_str() {
                            apps.push(format!("apps/{}", name));
                        }
                    }
                }
            }
        }
    }

    // Check packages/ directory
    let packages_dir = project_path.join("packages");
    if packages_dir.exists() {
        if let Ok(entries) = fs::read_dir(&packages_dir) {
            for entry in entries.flatten() {
                if entry.path().is_dir() {
                    let pkg_path = entry.path().join("package.json");
                    if pkg_path.exists() {
                        // Only include if it has a dev script
                        if let Ok(content) = fs::read_to_string(&pkg_path) {
                            if let Ok(pkg) = serde_json::from_str::<serde_json::Value>(&content) {
                                if pkg["scripts"]["dev"].is_string() {
                                    if let Some(name) = entry.file_name().to_str() {
                                        apps.push(format!("packages/{}", name));
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    apps.sort();
    apps
}

// ============================================================================
// Port Monitoring
// ============================================================================

#[tauri::command]
pub fn get_listening_ports() -> Result<Vec<PortInfo>, String> {
    let output = Command::new("lsof")
        .args(["-i", "-P", "-n"])
        .output()
        .map_err(|e| e.to_string())?;

    let stdout = String::from_utf8_lossy(&output.stdout);
    let mut ports = Vec::new();

    for line in stdout.lines() {
        if !line.contains("LISTEN") {
            continue;
        }

        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.len() < 9 {
            continue;
        }

        let process_name = parts[0].to_string();
        let pid: u32 = match parts[1].parse() {
            Ok(p) => p,
            Err(_) => continue,
        };

        // Parse port from NAME column (e.g., "*:3000" or "[::1]:5173")
        let name = parts[8];
        let port: u16 = if let Some(colon_pos) = name.rfind(':') {
            let port_str = &name[colon_pos + 1..];
            // Remove "(LISTEN)" if present
            let port_str = port_str.trim_end_matches("(LISTEN)");
            match port_str.parse() {
                Ok(p) => p,
                Err(_) => continue,
            }
        } else {
            continue;
        };

        // Get cwd for this process
        let cwd = get_process_cwd_internal(pid);

        ports.push(PortInfo {
            port,
            pid,
            process_name,
            cwd,
        });
    }

    // Deduplicate by port (keep first occurrence)
    let mut seen_ports = std::collections::HashSet::new();
    ports.retain(|p| seen_ports.insert(p.port));

    // Sort by port
    ports.sort_by_key(|p| p.port);

    Ok(ports)
}

#[tauri::command]
pub fn get_process_cwd(pid: u32) -> Result<Option<String>, String> {
    Ok(get_process_cwd_internal(pid))
}

fn get_process_cwd_internal(pid: u32) -> Option<String> {
    let output = Command::new("lsof")
        .args(["-p", &pid.to_string()])
        .output()
        .ok()?;

    let stdout = String::from_utf8_lossy(&output.stdout);

    for line in stdout.lines() {
        if line.contains("cwd") {
            let parts: Vec<&str> = line.split_whitespace().collect();
            if let Some(path) = parts.last() {
                return Some(path.to_string());
            }
        }
    }

    None
}

// ============================================================================
// Process Control
// ============================================================================

#[tauri::command]
pub fn start_dev_server(path: String, pkg_manager: String) -> Result<SpawnedProcess, String> {
    let cmd = match pkg_manager.as_str() {
        "pnpm" => "pnpm",
        "yarn" => "yarn",
        "bun" => "bun",
        _ => "npm",
    };

    let args = if pkg_manager == "npm" {
        vec!["run", "dev"]
    } else {
        vec!["dev"]
    };

    // Spawn detached process
    let child = Command::new(cmd)
        .args(&args)
        .current_dir(&path)
        .spawn()
        .map_err(|e| format!("Failed to spawn process: {}", e))?;

    let pid = child.id();
    let started_at = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs();

    Ok(SpawnedProcess { pid, started_at })
}

#[tauri::command]
pub fn stop_process(pid: u32, force: bool) -> Result<(), String> {
    let signal = if force { "KILL" } else { "TERM" };

    Command::new("kill")
        .args([&format!("-{}", signal), &pid.to_string()])
        .output()
        .map_err(|e| format!("Failed to kill process: {}", e))?;

    Ok(())
}

#[tauri::command]
pub fn stop_project_processes(project_path: String) -> Result<u32, String> {
    let ports = get_listening_ports()?;
    let mut killed = 0;

    for port in ports {
        if let Some(ref cwd) = port.cwd {
            if cwd.starts_with(&project_path) {
                if stop_process(port.pid, false).is_ok() {
                    killed += 1;
                }
            }
        }
    }

    Ok(killed)
}

// ============================================================================
// Utilities
// ============================================================================

#[tauri::command]
pub fn open_in_browser(url: String) -> Result<(), String> {
    Command::new("open")
        .arg(&url)
        .spawn()
        .map_err(|e| format!("Failed to open browser: {}", e))?;
    Ok(())
}

#[tauri::command]
pub fn open_in_editor(path: String, editor: String) -> Result<(), String> {
    let cmd = match editor.as_str() {
        "claude" => "claude",
        "cursor" => "cursor",
        "zed" => "zed",
        _ => "code",
    };

    Command::new(cmd)
        .arg(&path)
        .spawn()
        .map_err(|e| format!("Failed to open editor: {}", e))?;

    Ok(())
}

// ============================================================================
// Config
// ============================================================================

fn get_config_path() -> std::path::PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
    Path::new(&home)
        .join(".config")
        .join("nodles")
        .join("config.json")
}

#[tauri::command]
pub fn read_config() -> Result<Config, String> {
    let config_path = get_config_path();

    if !config_path.exists() {
        // Return default config
        return Ok(Config {
            sites_path: "~/Sites".to_string(),
            editor: "cursor".to_string(),
            launch_on_login: true,
            poll_interval_ms: 2000,
            favorites: Vec::new(),
            labels: HashMap::new(),
            display_names: HashMap::new(),
            hidden_projects: Vec::new(),
        });
    }

    let content = fs::read_to_string(&config_path).map_err(|e| e.to_string())?;
    let config: Config = serde_json::from_str(&content).map_err(|e| e.to_string())?;

    Ok(config)
}

#[tauri::command]
pub fn write_config(config: Config) -> Result<(), String> {
    let config_path = get_config_path();

    // Ensure parent directory exists
    if let Some(parent) = config_path.parent() {
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }

    let content = serde_json::to_string_pretty(&config).map_err(|e| e.to_string())?;
    fs::write(&config_path, content).map_err(|e| e.to_string())?;

    Ok(())
}
