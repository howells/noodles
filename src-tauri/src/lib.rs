mod commands;

use tauri_plugin_autostart::MacosLauncher;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_process::init())
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_autostart::init(
            MacosLauncher::LaunchAgent,
            Some(vec!["--minimized"]),
        ))
        .invoke_handler(tauri::generate_handler![
            commands::scan_sites,
            commands::get_listening_ports,
            commands::get_process_cwd,
            commands::start_dev_server,
            commands::stop_process,
            commands::stop_project_processes,
            commands::open_in_browser,
            commands::open_in_editor,
            commands::read_config,
            commands::write_config,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
