//! Tauri commands for IPC

use std::path::Path;
use std::time::Instant;
use tauri::{command, AppHandle};

use crate::scanner;
use crate::types::{DiskInfo, FileNode, ScanResult};

/// Scan a directory and return the file tree (with progress events)
#[command]
pub async fn scan_directory(
    app: AppHandle,
    path: String,
    max_depth: Option<usize>,
) -> Result<ScanResult, String> {
    let path_clone = path.clone();

    // Run scan in a blocking task to not freeze the UI
    let result = tokio::task::spawn_blocking(move || {
        let path = Path::new(&path_clone);
        let start = Instant::now();

        let root = scanner::scan_directory_with_progress(path, max_depth, Some(&app), None)?;

        let total_files = count_files(&root);
        let total_size = root.size;
        let scan_time_ms = start.elapsed().as_millis() as u64;

        Ok::<ScanResult, String>(ScanResult {
            root,
            total_files,
            total_size,
            scan_time_ms,
        })
    })
    .await
    .map_err(|e| e.to_string())??;

    Ok(result)
}

fn count_files(node: &FileNode) -> u64 {
    if node.is_dir {
        node.children.iter().map(count_files).sum()
    } else {
        1
    }
}

/// Get disk space information
#[command]
pub fn get_disk_info(path: String) -> Result<DiskInfo, String> {
    let path = Path::new(&path);
    scanner::get_disk_space(path).ok_or_else(|| "Failed to get disk info".to_string())
}

/// Open path in Finder/Explorer
#[command]
pub async fn open_in_finder(path: String) -> Result<(), String> {
    #[cfg(target_os = "macos")]
    {
        std::process::Command::new("open")
            .arg("-R")
            .arg(&path)
            .spawn()
            .map_err(|e| e.to_string())?;
    }

    #[cfg(target_os = "windows")]
    {
        std::process::Command::new("explorer")
            .arg("/select,")
            .arg(&path)
            .spawn()
            .map_err(|e| e.to_string())?;
    }

    #[cfg(target_os = "linux")]
    {
        std::process::Command::new("xdg-open")
            .arg(Path::new(&path).parent().unwrap_or(Path::new(&path)))
            .spawn()
            .map_err(|e| e.to_string())?;
    }

    Ok(())
}

/// Move file/folder to trash
#[command]
pub async fn move_to_trash(path: String) -> Result<(), String> {
    trash::delete(&path).map_err(|e| e.to_string())
}

/// Permanently delete file/folder
#[command]
pub async fn delete_file(path: String) -> Result<(), String> {
    let path = Path::new(&path);

    if path.is_dir() {
        std::fs::remove_dir_all(path).map_err(|e| e.to_string())
    } else {
        std::fs::remove_file(path).map_err(|e| e.to_string())
    }
}

/// Open Terminal with data-x TUI mode
#[command]
pub async fn open_in_terminal(path: Option<String>) -> Result<(), String> {
    // Get the path to the TUI binary bundled in Resources
    let exe_path = std::env::current_exe()
        .map_err(|e| e.to_string())?;

    // The TUI binary is in Contents/Resources/bin/data-x-tui
    // Current exe is in Contents/MacOS/data-x
    let tui_path = exe_path
        .parent() // MacOS
        .and_then(|p| p.parent()) // Contents
        .map(|p| p.join("Resources").join("bin").join("data-x-tui"))
        .ok_or("Could not find TUI binary")?;

    let tui_str = tui_path.to_string_lossy();

    #[cfg(target_os = "macos")]
    {
        let cmd_args = if let Some(ref p) = path {
            format!("'{}' --tui '{}'", tui_str.replace("'", "'\\''"), p.replace("'", "'\\''"))
        } else {
            format!("'{}' --help", tui_str.replace("'", "'\\''"))
        };

        // Check if iTerm2 is installed
        let iterm_exists = Path::new("/Applications/iTerm.app").exists();

        if iterm_exists {
            // Use iTerm2
            let script = format!(
                r#"tell application "iTerm"
                    activate
                    try
                        set newWindow to (create window with default profile)
                        tell current session of newWindow
                            write text "{}"
                        end tell
                    on error
                        tell current window
                            create tab with default profile
                            tell current session
                                write text "{}"
                            end tell
                        end tell
                    end try
                end tell"#,
                cmd_args, cmd_args
            );

            std::process::Command::new("osascript")
                .arg("-e")
                .arg(&script)
                .spawn()
                .map_err(|e| e.to_string())?;
        } else {
            // Fall back to Terminal.app
            let script = format!(
                r#"tell application "Terminal"
                    activate
                    do script "{}"
                end tell"#,
                cmd_args
            );

            std::process::Command::new("osascript")
                .arg("-e")
                .arg(&script)
                .spawn()
                .map_err(|e| e.to_string())?;
        }
    }

    #[cfg(target_os = "windows")]
    {
        let cmd = if let Some(p) = path {
            format!("\"{}\" --tui \"{}\"", tui_str, p)
        } else {
            format!("\"{}\" --help", tui_str)
        };

        std::process::Command::new("cmd")
            .args(["/c", "start", "cmd", "/k", &cmd])
            .spawn()
            .map_err(|e| e.to_string())?;
    }

    #[cfg(target_os = "linux")]
    {
        let cmd = if let Some(p) = path {
            format!("'{}' --tui '{}'", tui_str, p)
        } else {
            format!("'{}' --help", tui_str)
        };

        // Try common terminal emulators
        let terminals = ["gnome-terminal", "konsole", "xfce4-terminal", "xterm"];
        for term in terminals {
            let result = match term {
                "gnome-terminal" => std::process::Command::new(term)
                    .args(["--", "sh", "-c", &cmd])
                    .spawn(),
                "konsole" => std::process::Command::new(term)
                    .args(["-e", "sh", "-c", &cmd])
                    .spawn(),
                _ => std::process::Command::new(term)
                    .args(["-e", &cmd])
                    .spawn(),
            };
            if result.is_ok() {
                return Ok(());
            }
        }
        return Err("No terminal emulator found".to_string());
    }

    Ok(())
}
