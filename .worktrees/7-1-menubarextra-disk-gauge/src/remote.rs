//! Remote scanning via SSH for Data-X.
//!
//! Enables scanning remote servers by connecting via SSH and
//! executing commands to gather file system information.

use std::io::{BufRead, BufReader};
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::mpsc::SyncSender;

use anyhow::{anyhow, Result};

use crate::scanner::ScanProgress;
use crate::tree::{FileNode, FileTree};

/// Parsed SSH connection info.
#[derive(Debug, Clone)]
pub struct SshTarget {
    pub user: Option<String>,
    pub host: String,
    pub port: Option<u16>,
    pub path: PathBuf,
}

impl SshTarget {
    /// Parse a remote path string into SSH target.
    /// Supports formats:
    /// - user@host:/path
    /// - host:/path
    /// - ssh://user@host/path
    /// - ssh://user@host:port/path
    pub fn parse(s: &str) -> Option<Self> {
        // Try ssh:// URL format first
        if s.starts_with("ssh://") {
            return Self::parse_ssh_url(&s[6..]);
        }

        // Try user@host:/path or host:/path format
        if s.contains(':') && !s.starts_with('/') {
            return Self::parse_scp_format(s);
        }

        None
    }

    fn parse_ssh_url(s: &str) -> Option<Self> {
        // Format: user@host:port/path or user@host/path or host/path
        let (auth_host, path) = s.split_once('/')?;
        let path = PathBuf::from(format!("/{}", path));

        let (user, host_port) = if auth_host.contains('@') {
            let (u, h) = auth_host.split_once('@')?;
            (Some(u.to_string()), h)
        } else {
            (None, auth_host)
        };

        let (host, port) = if host_port.contains(':') {
            let (h, p) = host_port.split_once(':')?;
            (h.to_string(), p.parse().ok())
        } else {
            (host_port.to_string(), None)
        };

        Some(SshTarget { user, host, port, path })
    }

    fn parse_scp_format(s: &str) -> Option<Self> {
        // Format: user@host:/path or host:/path
        let (host_part, path) = s.split_once(':')?;
        let path = PathBuf::from(path);

        let (user, host) = if host_part.contains('@') {
            let (u, h) = host_part.split_once('@')?;
            (Some(u.to_string()), h.to_string())
        } else {
            (None, host_part.to_string())
        };

        Some(SshTarget { user, host, port: None, path })
    }

    /// Build SSH command arguments.
    pub fn ssh_args(&self) -> Vec<String> {
        let mut args = Vec::new();

        if let Some(port) = self.port {
            args.push("-p".to_string());
            args.push(port.to_string());
        }

        let target = if let Some(ref user) = self.user {
            format!("{}@{}", user, self.host)
        } else {
            self.host.clone()
        };
        args.push(target);

        args
    }

    /// Get display string for the target.
    pub fn display(&self) -> String {
        let user_part = self.user.as_ref().map(|u| format!("{}@", u)).unwrap_or_default();
        let port_part = self.port.map(|p| format!(":{}", p)).unwrap_or_default();
        format!("{}{}{}:{}", user_part, self.host, port_part, self.path.display())
    }
}

/// Check if a path string represents a remote target.
pub fn is_remote_path(s: &str) -> bool {
    SshTarget::parse(s).is_some()
}

/// Remote scanner that uses SSH to scan a remote filesystem.
pub struct RemoteScanner {
    target: SshTarget,
    progress_tx: SyncSender<ScanProgress>,
}

impl RemoteScanner {
    pub fn new(target: SshTarget, progress_tx: SyncSender<ScanProgress>) -> Self {
        Self { target, progress_tx }
    }

    /// Scan the remote filesystem.
    pub fn scan(&self) -> Result<FileTree> {
        // Send started signal
        let _ = self.progress_tx.send(ScanProgress::Started);

        // First, check if data-x is available on remote
        let has_datax = self.check_remote_datax()?;

        if has_datax {
            self.scan_with_datax()
        } else {
            self.scan_with_find()
        }
    }

    /// Check if data-x is installed on the remote server.
    fn check_remote_datax(&self) -> Result<bool> {
        let mut args = self.target.ssh_args();
        args.push("which data-x 2>/dev/null || echo ''".to_string());

        let output = Command::new("ssh")
            .args(&args)
            .output()?;

        let stdout = String::from_utf8_lossy(&output.stdout);
        Ok(!stdout.trim().is_empty())
    }

    /// Scan using remote data-x installation (preferred, faster).
    fn scan_with_datax(&self) -> Result<FileTree> {
        let mut args = self.target.ssh_args();
        args.push(format!("data-x --json '{}'", self.target.path.display()));

        let mut child = Command::new("ssh")
            .args(&args)
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()?;

        let stdout = child.stdout.take().ok_or_else(|| anyhow!("Failed to capture stdout"))?;
        let mut json_output = String::new();

        let reader = BufReader::new(stdout);
        for line in reader.lines() {
            if let Ok(line) = line {
                json_output.push_str(&line);
            }
        }

        child.wait()?;

        // Parse JSON and build tree
        self.parse_json_to_tree(&json_output)
    }

    /// Scan using find/stat commands (fallback when data-x not installed).
    fn scan_with_find(&self) -> Result<FileTree> {
        let mut args = self.target.ssh_args();

        // Use find with stat to get file info
        // Format: path|type|size|mtime
        let find_cmd = format!(
            r#"find '{}' -printf '%p|%y|%s|%T@\n' 2>/dev/null || find '{}' -exec stat -f '%N|%HT|%z|%m' {{}} \; 2>/dev/null"#,
            self.target.path.display(),
            self.target.path.display()
        );
        args.push(find_cmd);

        let mut child = Command::new("ssh")
            .args(&args)
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()?;

        let stdout = child.stdout.take().ok_or_else(|| anyhow!("Failed to capture stdout"))?;
        let reader = BufReader::new(stdout);

        let mut tree = FileTree::new();
        let mut files_found = 0u64;
        let mut total_size = 0u64;
        let mut path_to_id = std::collections::HashMap::new();

        for line in reader.lines() {
            let line = match line {
                Ok(l) => l,
                Err(_) => continue,
            };

            let parts: Vec<&str> = line.split('|').collect();
            if parts.len() < 3 {
                continue;
            }

            let path = PathBuf::from(parts[0]);
            let file_type = parts[1];
            let size: u64 = parts[2].parse().unwrap_or(0);

            let is_dir = file_type == "d" || file_type == "Directory";

            // Create or update tree
            if tree.root.is_none() {
                // First entry should be root
                tree = FileTree::with_root(path.clone());
                if let Some(root_id) = tree.root {
                    path_to_id.insert(path.clone(), root_id);
                    if let Some(node) = tree.get_node_mut(root_id) {
                        node.size = size;
                    }
                }
            } else {
                // Add as child of parent
                let parent_path = path.parent().map(|p| p.to_path_buf());

                if let Some(parent_path) = parent_path {
                    if let Some(&parent_id) = path_to_id.get(&parent_path) {
                        let mut node = FileNode::new(path.clone(), is_dir);
                        node.size = size;
                        let node_id = tree.add_child(parent_id, node);
                        path_to_id.insert(path, node_id);
                    }
                }
            }

            files_found += 1;
            total_size += size;

            // Send progress every 100 files
            if files_found % 100 == 0 {
                let _ = self.progress_tx.send(ScanProgress::Scanning {
                    path: PathBuf::from(parts[0]),
                    files_found,
                    estimated_total: files_found + 1000, // Estimate
                    bytes_processed: total_size,
                });
            }
        }

        child.wait()?;

        // Calculate sizes
        tree.calculate_sizes();

        // Send completed
        let _ = self.progress_tx.send(ScanProgress::Completed {
            total_files: files_found,
            total_size,
            tree: tree.clone(),
        });

        Ok(tree)
    }

    /// Parse JSON output from remote data-x into a FileTree.
    fn parse_json_to_tree(&self, json: &str) -> Result<FileTree> {
        // Parse the JSON structure
        let value: serde_json::Value = serde_json::from_str(json)?;

        let mut tree = FileTree::new();

        if let Some(obj) = value.as_object() {
            let path = obj.get("path")
                .and_then(|v| v.as_str())
                .map(PathBuf::from)
                .unwrap_or_else(|| self.target.path.clone());

            let size = obj.get("size")
                .and_then(|v| v.as_u64())
                .unwrap_or(0);

            let file_count = obj.get("file_count")
                .and_then(|v| v.as_u64())
                .unwrap_or(0);

            tree = FileTree::with_root(path);

            if let Some(root_id) = tree.root {
                if let Some(node) = tree.get_node_mut(root_id) {
                    node.size = size;
                    node.file_count = file_count;
                }

                // Parse children recursively
                if let Some(children) = obj.get("children").and_then(|v| v.as_array()) {
                    self.parse_children(&mut tree, root_id, children);
                }
            }

            // Send completed
            let _ = self.progress_tx.send(ScanProgress::Completed {
                total_files: file_count,
                total_size: size,
                tree: tree.clone(),
            });
        }

        Ok(tree)
    }

    fn parse_children(&self, tree: &mut FileTree, parent_id: indextree::NodeId, children: &[serde_json::Value]) {
        for child_val in children {
            if let Some(obj) = child_val.as_object() {
                let path = obj.get("path")
                    .and_then(|v| v.as_str())
                    .map(PathBuf::from);

                let path = match path {
                    Some(p) => p,
                    None => continue,
                };

                let is_dir = obj.get("is_dir")
                    .and_then(|v| v.as_bool())
                    .unwrap_or(false);

                let size = obj.get("size")
                    .and_then(|v| v.as_u64())
                    .unwrap_or(0);

                let file_count = obj.get("file_count")
                    .and_then(|v| v.as_u64())
                    .unwrap_or(0);

                let mut node = FileNode::new(path, is_dir);
                node.size = size;
                node.file_count = file_count;

                let node_id = tree.add_child(parent_id, node);

                // Recurse for children
                if let Some(grandchildren) = obj.get("children").and_then(|v| v.as_array()) {
                    self.parse_children(tree, node_id, grandchildren);
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_scp_format() {
        let target = SshTarget::parse("user@host:/path/to/dir").unwrap();
        assert_eq!(target.user, Some("user".to_string()));
        assert_eq!(target.host, "host");
        assert_eq!(target.path, PathBuf::from("/path/to/dir"));
        assert_eq!(target.port, None);
    }

    #[test]
    fn test_parse_scp_format_no_user() {
        let target = SshTarget::parse("host:/path").unwrap();
        assert_eq!(target.user, None);
        assert_eq!(target.host, "host");
        assert_eq!(target.path, PathBuf::from("/path"));
    }

    #[test]
    fn test_parse_ssh_url() {
        let target = SshTarget::parse("ssh://user@host/path/to/dir").unwrap();
        assert_eq!(target.user, Some("user".to_string()));
        assert_eq!(target.host, "host");
        assert_eq!(target.path, PathBuf::from("/path/to/dir"));
    }

    #[test]
    fn test_parse_ssh_url_with_port() {
        let target = SshTarget::parse("ssh://user@host:2222/path").unwrap();
        assert_eq!(target.user, Some("user".to_string()));
        assert_eq!(target.host, "host");
        assert_eq!(target.port, Some(2222));
        assert_eq!(target.path, PathBuf::from("/path"));
    }

    #[test]
    fn test_is_remote_path() {
        assert!(is_remote_path("user@host:/path"));
        assert!(is_remote_path("ssh://user@host/path"));
        assert!(!is_remote_path("/local/path"));
        assert!(!is_remote_path("./relative"));
    }

    #[test]
    fn test_ssh_args() {
        let target = SshTarget {
            user: Some("admin".to_string()),
            host: "server.com".to_string(),
            port: Some(2222),
            path: PathBuf::from("/data"),
        };

        let args = target.ssh_args();
        assert_eq!(args, vec!["-p", "2222", "admin@server.com"]);
    }
}
