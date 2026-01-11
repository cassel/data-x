//! Remote scanning via SSH
//!
//! Executes scans on remote servers via SSH connection.

use serde::{Deserialize, Serialize};
use std::io::{BufRead, BufReader};
use std::path::PathBuf;
use std::process::{Command, Stdio};
use tauri::{AppHandle, Emitter};

use super::connection_manager::{get_connection, mark_connection_used, AuthMethod, SSHConnection};
use super::credentials::get_credential;
use crate::types::{FileNode, ScanProgress, ScanResult};

/// Result of testing an SSH connection
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SSHTestResult {
    pub success: bool,
    pub message: String,
    /// If successful, shows server info
    pub server_info: Option<String>,
    /// Round-trip latency in milliseconds
    pub latency_ms: Option<u64>,
}

/// Build SSH command arguments for a connection
fn build_ssh_args(connection: &SSHConnection, _password: Option<&str>) -> Vec<String> {
    let mut args = Vec::new();

    // Disable pseudo-terminal allocation (prevents hangs)
    args.push("-T".to_string());

    // Disable strict host key checking for first connection
    args.push("-o".to_string());
    args.push("StrictHostKeyChecking=accept-new".to_string());

    // Set connection timeout
    args.push("-o".to_string());
    args.push(format!("ConnectTimeout={}", connection.timeout_secs));

    // Server alive interval to detect dead connections
    args.push("-o".to_string());
    args.push("ServerAliveInterval=5".to_string());
    args.push("-o".to_string());
    args.push("ServerAliveCountMax=3".to_string());

    // Batch mode - enable for non-password auth to prevent prompts
    // For password auth, sshpass handles the password
    if !matches!(connection.auth_method, AuthMethod::Password) {
        args.push("-o".to_string());
        args.push("BatchMode=yes".to_string());
        args.push("-o".to_string());
        args.push("PasswordAuthentication=no".to_string());
    }

    // Port
    if connection.port != 22 {
        args.push("-p".to_string());
        args.push(connection.port.to_string());
    }

    // Key file if specified
    if let AuthMethod::Key { key_path: Some(ref path) } = connection.auth_method {
        args.push("-i".to_string());
        args.push(path.clone());
    }

    // User@Host
    args.push(format!("{}@{}", connection.username, connection.host));

    args
}

/// Test if an SSH connection is working
pub fn test_connection(connection: &SSHConnection) -> Result<SSHTestResult, String> {
    let password = if matches!(connection.auth_method, AuthMethod::Password) {
        get_credential(&connection.id)?
    } else {
        None
    };

    let args = build_ssh_args(connection, password.as_deref());

    let start = std::time::Instant::now();

    // Build the command - use sshpass for password auth
    let mut cmd = if matches!(connection.auth_method, AuthMethod::Password) {
        let mut c = Command::new("sshpass");
        if let Some(ref pass) = password {
            c.arg("-p").arg(pass);
        }
        c.arg("ssh");
        c
    } else {
        Command::new("ssh")
    };

    cmd.args(&args);
    cmd.arg("echo 'Data-X connection test' && uname -a");
    cmd.stdout(Stdio::piped());
    cmd.stderr(Stdio::piped());

    let output = cmd
        .output()
        .map_err(|e| format!("Failed to execute SSH command: {}", e))?;

    let latency = start.elapsed().as_millis() as u64;

    if output.status.success() {
        let stdout = String::from_utf8_lossy(&output.stdout);
        let lines: Vec<&str> = stdout.lines().collect();

        Ok(SSHTestResult {
            success: true,
            message: "Connection successful".to_string(),
            server_info: lines.get(1).map(|s| s.to_string()),
            latency_ms: Some(latency),
        })
    } else {
        let stderr = String::from_utf8_lossy(&output.stderr);
        Ok(SSHTestResult {
            success: false,
            message: format!("Connection failed: {}", stderr.trim()),
            server_info: None,
            latency_ms: None,
        })
    }
}

/// Helper to build SSH command with optional sshpass
fn build_ssh_command(use_sshpass: bool, password: Option<&str>, ssh_args: &[String]) -> Command {
    if use_sshpass {
        let mut cmd = Command::new("sshpass");
        if let Some(pass) = password {
            cmd.arg("-p").arg(pass);
        }
        cmd.arg("ssh");
        cmd.args(ssh_args);
        cmd
    } else {
        let mut cmd = Command::new("ssh");
        cmd.args(ssh_args);
        cmd
    }
}

/// Scan a remote directory via SSH
pub fn scan_remote_directory(
    connection_id: &str,
    path: Option<&str>,
    app: &AppHandle,
) -> Result<ScanResult, String> {
    let connection =
        get_connection(connection_id)?.ok_or_else(|| "Connection not found".to_string())?;

    let scan_path = path
        .map(|s| s.to_string())
        .or(connection.default_path.clone())
        .unwrap_or_else(|| "/".to_string());

    let use_sshpass = matches!(connection.auth_method, AuthMethod::Password);
    let password = if use_sshpass {
        get_credential(connection_id)?
    } else {
        None
    };

    let args = build_ssh_args(&connection, password.as_deref());

    // Emit scan start event
    let _ = app.emit(
        "scan-progress",
        ScanProgress {
            files_found: 0,
            current_path: format!("Connecting to {}...", connection.host),
            percent: 0.0,
        },
    );

    // First check if data-x is available on remote
    let has_datax = check_remote_datax(use_sshpass, password.as_deref(), &args)?;

    let result = if has_datax {
        scan_with_datax(use_sshpass, password.as_deref(), &args, &scan_path, app)?
    } else {
        scan_with_find(use_sshpass, password.as_deref(), &args, &scan_path, app)?
    };

    // Update last used timestamp
    let _ = mark_connection_used(connection_id);

    Ok(result)
}

/// Check if data-x is installed on the remote server
fn check_remote_datax(use_sshpass: bool, password: Option<&str>, ssh_args: &[String]) -> Result<bool, String> {
    let mut cmd = build_ssh_command(use_sshpass, password, ssh_args);
    cmd.arg("which data-x 2>/dev/null || echo ''");
    cmd.stdout(Stdio::piped());
    cmd.stderr(Stdio::null());

    let output = cmd
        .output()
        .map_err(|e| format!("Failed to check for remote data-x: {}", e))?;

    let stdout = String::from_utf8_lossy(&output.stdout);
    Ok(!stdout.trim().is_empty())
}

/// Scan using remote data-x installation (preferred, faster)
fn scan_with_datax(use_sshpass: bool, password: Option<&str>, ssh_args: &[String], path: &str, _app: &AppHandle) -> Result<ScanResult, String> {
    let mut cmd = build_ssh_command(use_sshpass, password, ssh_args);
    cmd.arg(format!("data-x --json '{}'", path));
    cmd.stdout(Stdio::piped());
    cmd.stderr(Stdio::null());

    let start = std::time::Instant::now();

    let output = cmd
        .output()
        .map_err(|e| format!("Failed to run remote data-x: {}", e))?;

    if !output.status.success() {
        return Err("Remote data-x scan failed".to_string());
    }

    let json = String::from_utf8_lossy(&output.stdout);

    // Parse JSON into FileNode
    let root: FileNode =
        serde_json::from_str(&json).map_err(|e| format!("Failed to parse remote scan: {}", e))?;

    let total_files = count_files(&root);
    let total_size = root.size;
    let scan_time_ms = start.elapsed().as_millis() as u64;

    Ok(ScanResult {
        root,
        total_files,
        total_size,
        scan_time_ms,
    })
}

/// Scan using find/stat commands (fallback)
fn scan_with_find(use_sshpass: bool, password: Option<&str>, ssh_args: &[String], path: &str, app: &AppHandle) -> Result<ScanResult, String> {
    let mut cmd = build_ssh_command(use_sshpass, password, ssh_args);

    // Use a portable approach that works on both Linux and BSD/macOS:
    // - Try GNU find -printf first (Linux)
    // - Fall back to find with a shell script that works on BSD/macOS
    // Format: path|type|size
    // Limit depth to 4 levels for remote scans to avoid timeouts
    // User can drill down to go deeper
    let max_depth = 4;
    let find_cmd = format!(
        r#"if find '{}' -maxdepth 0 -printf '' 2>/dev/null; then
            find '{}' -maxdepth {} -printf '%p|%y|%s\n' 2>/dev/null
        else
            find '{}' -maxdepth {} -exec sh -c 'for f; do
                if [ -d "$f" ]; then t=d; else t=f; fi
                s=$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null || echo 0)
                printf "%s|%s|%s\n" "$f" "$t" "$s"
            done' _ {{}} +
        fi"#,
        path, path, max_depth, path, max_depth
    );
    cmd.arg(find_cmd);
    cmd.stdout(Stdio::piped());
    cmd.stderr(Stdio::piped());

    let start = std::time::Instant::now();

    let mut child = cmd
        .spawn()
        .map_err(|e| format!("Failed to start remote scan: {}", e))?;

    let stdout = child
        .stdout
        .take()
        .ok_or_else(|| "Failed to capture stdout".to_string())?;
    let reader = BufReader::new(stdout);

    let mut files: Vec<(String, bool, u64)> = Vec::new();
    let mut total_size = 0u64;
    let mut files_found = 0u64;


    for line in reader.lines() {
        let line = match line {
            Ok(l) => l,
            Err(_) => continue,
        };

        let parts: Vec<&str> = line.split('|').collect();
        if parts.len() < 3 {
            continue;
        }

        let file_path = parts[0].to_string();
        let file_type = parts[1];
        let size: u64 = parts[2].parse().unwrap_or(0);

        let is_dir = file_type == "d" || file_type == "Directory";
        files.push((file_path.clone(), is_dir, size));
        total_size += size;
        files_found += 1;

        // Emit progress every 100 files
        if files_found % 100 == 0 {
            let _ = app.emit(
                "scan-progress",
                ScanProgress {
                    files_found,
                    current_path: file_path,
                    percent: 0.0, // Can't know total for remote
                },
            );
        }
    }

    let output = child.wait_with_output().map_err(|e| e.to_string())?;

    // Check if scan produced any results
    if files.is_empty() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        if !stderr.is_empty() {
            return Err(format!("Remote scan failed: {}", stderr.trim()));
        }
        return Err(format!(
            "Remote scan failed: no files found at '{}'. Check that the path exists and you have permission to read it.",
            path
        ));
    }

    // Build tree from flat list
    let root = build_tree_from_files(&files, path)?;
    let scan_time_ms = start.elapsed().as_millis() as u64;

    Ok(ScanResult {
        root,
        total_files: files_found,
        total_size,
        scan_time_ms,
    })
}

/// Build a FileNode tree from a flat list of files
fn build_tree_from_files(files: &[(String, bool, u64)], root_path: &str) -> Result<FileNode, String> {
    use std::collections::HashMap;

    if files.is_empty() {
        return Ok(FileNode {
            id: 0,
            name: PathBuf::from(root_path)
                .file_name()
                .map(|s| s.to_string_lossy().to_string())
                .unwrap_or_else(|| root_path.to_string()),
            path: root_path.to_string(),
            size: 0,
            is_dir: true,
            is_hidden: false,
            extension: None,
            children: Vec::new(),
            file_count: 0,
        });
    }

    // Create nodes for all files
    let mut nodes: HashMap<String, FileNode> = HashMap::new();
    let mut next_id = 0u64;

    for (path, is_dir, size) in files {
        let name = PathBuf::from(path)
            .file_name()
            .map(|s| s.to_string_lossy().to_string())
            .unwrap_or_else(|| path.clone());

        let extension = if !is_dir {
            PathBuf::from(path)
                .extension()
                .map(|s| s.to_string_lossy().to_string())
        } else {
            None
        };

        let is_hidden = name.starts_with('.');

        nodes.insert(
            path.clone(),
            FileNode {
                id: next_id,
                name,
                path: path.clone(),
                size: *size,
                is_dir: *is_dir,
                is_hidden,
                extension,
                children: Vec::new(),
                file_count: if *is_dir { 0 } else { 1 },
            },
        );
        next_id += 1;
    }

    // Build parent-child relationships
    // Sort paths by depth (deepest first) so children are processed before parents
    let mut paths: Vec<String> = files.iter().map(|(p, _, _)| p.clone()).collect();
    paths.sort_by(|a, b| {
        let depth_a = a.matches('/').count();
        let depth_b = b.matches('/').count();
        depth_b.cmp(&depth_a) // Deepest first
    });

    for path in &paths {
        if let Some(parent_path) = PathBuf::from(path).parent() {
            let parent_str = parent_path.to_string_lossy().to_string();
            if parent_str != *path && nodes.contains_key(&parent_str) {
                if let Some(node) = nodes.remove(path) {
                    if let Some(parent) = nodes.get_mut(&parent_str) {
                        parent.children.push(node);
                    }
                }
            }
        }
    }

    // Find root - should be the only remaining node (or the one matching root_path)
    let root = nodes
        .remove(root_path)
        .or_else(|| nodes.into_values().next())
        .ok_or_else(|| "Failed to build file tree".to_string())?;

    // Calculate sizes and file counts
    fn calculate_size(node: &mut FileNode) -> (u64, u64) {
        if node.is_dir {
            let mut total_size = 0u64;
            let mut file_count = 0u64;
            for child in &mut node.children {
                let (size, count) = calculate_size(child);
                total_size += size;
                file_count += count;
            }
            node.size = total_size;
            node.file_count = file_count;
            (total_size, file_count)
        } else {
            (node.size, 1)
        }
    }

    let mut root = root;
    calculate_size(&mut root);

    Ok(root)
}

fn count_files(node: &FileNode) -> u64 {
    if node.is_dir {
        node.children.iter().map(count_files).sum()
    } else {
        1
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_build_tree_from_files() {
        let files = vec![
            ("/home".to_string(), true, 0),
            ("/home/user".to_string(), true, 0),
            ("/home/user/file.txt".to_string(), false, 100),
        ];

        let tree = build_tree_from_files(&files, "/home").unwrap();
        assert_eq!(tree.path, "/home");
        assert!(tree.is_dir);
    }
}
