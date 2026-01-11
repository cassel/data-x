//! Data-X Library - Tauri Backend

mod commands;
mod duplicates;
mod scanner;
mod ssh;
mod types;

#[allow(unused_imports)]
use tauri::Manager;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .invoke_handler(tauri::generate_handler![
            commands::scan_directory,
            commands::get_disk_info,
            commands::open_in_finder,
            commands::move_to_trash,
            commands::delete_file,
            commands::open_in_terminal,
            // SSH commands
            commands::get_ssh_connections,
            commands::get_ssh_connection,
            commands::save_ssh_connection,
            commands::update_ssh_connection,
            commands::delete_ssh_connection,
            commands::test_ssh_connection,
            commands::scan_remote,
            // Duplicate detection commands
            commands::find_duplicates,
            commands::delete_files,
        ])
        .setup(|_app| {
            #[cfg(debug_assertions)]
            {
                let window = _app.get_webview_window("main").unwrap();
                window.open_devtools();
            }
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
