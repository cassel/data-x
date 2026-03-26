//! Directory walker implementation using walkdir and rayon for parallel scanning.

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::mpsc::SyncSender;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use rayon::prelude::*;
use walkdir::WalkDir;

use crate::tree::{FileNode, FileTree, NodeId};

use super::progress::ScanProgress;
use super::ScanError;

/// Configuration options for directory scanning.
#[derive(Debug, Clone)]
pub struct ScanOptions {
    /// The root path to start scanning from
    pub root_path: PathBuf,
    /// Maximum depth to traverse (None for unlimited)
    pub max_depth: Option<usize>,
    /// Glob patterns to exclude from scanning
    pub exclude_patterns: Vec<String>,
    /// Whether to cross filesystem mount points
    pub cross_mount: bool,
    /// If true, use apparent size (metadata.len()); if false, use disk blocks
    pub apparent_size: bool,
}

#[allow(dead_code)]
impl ScanOptions {
    /// Create new scan options with default values
    pub fn new(root_path: PathBuf) -> Self {
        Self {
            root_path,
            max_depth: None,
            exclude_patterns: Vec::new(),
            cross_mount: false,
            apparent_size: true,
        }
    }

    /// Set maximum depth
    pub fn with_max_depth(mut self, depth: Option<usize>) -> Self {
        self.max_depth = depth;
        self
    }

    /// Set exclude patterns
    pub fn with_exclude_patterns(mut self, patterns: Vec<String>) -> Self {
        self.exclude_patterns = patterns;
        self
    }

    /// Set cross mount option
    pub fn with_cross_mount(mut self, cross: bool) -> Self {
        self.cross_mount = cross;
        self
    }

    /// Set apparent size option
    pub fn with_apparent_size(mut self, apparent: bool) -> Self {
        self.apparent_size = apparent;
        self
    }
}

/// Directory scanner that walks the filesystem and builds a FileTree.
pub struct Scanner {
    options: ScanOptions,
    progress_tx: SyncSender<ScanProgress>,
}

impl Scanner {
    /// Create a new scanner with the given options and progress sender.
    pub fn new(options: ScanOptions, progress_tx: SyncSender<ScanProgress>) -> Self {
        Self {
            options,
            progress_tx,
        }
    }

    /// Perform the directory scan and return a FileTree.
    pub fn scan(&self) -> Result<FileTree, ScanError> {
        // Validate the root path
        let root_path = &self.options.root_path;

        if !root_path.exists() {
            return Err(ScanError::PathNotFound {
                path: root_path.clone(),
            });
        }

        let metadata = std::fs::metadata(root_path).map_err(|e| {
            if e.kind() == std::io::ErrorKind::PermissionDenied {
                ScanError::PermissionDenied {
                    path: root_path.clone(),
                }
            } else {
                ScanError::IoError {
                    path: root_path.clone(),
                    source: e,
                }
            }
        })?;

        if !metadata.is_dir() {
            return Err(ScanError::NotADirectory {
                path: root_path.clone(),
            });
        }

        // Send started progress
        let _ = self.progress_tx.send(ScanProgress::Started);

        // Single-pass scan - walk directory once
        let mut walker = WalkDir::new(root_path)
            .follow_links(false)
            .same_file_system(!self.options.cross_mount);

        if let Some(max_depth) = self.options.max_depth {
            walker = walker.max_depth(max_depth);
        }

        // Collect all entries first (walkdir is not thread-safe for parallel iteration)
        let entries: Vec<_> = walker
            .into_iter()
            .filter_entry(|e| !self.should_exclude(e.path()))
            .collect();

        // Thread-safe counters for progress reporting
        let files_found = Arc::new(AtomicU64::new(0));
        let bytes_processed = Arc::new(AtomicU64::new(0));
        let last_progress_time = Arc::new(Mutex::new(Instant::now()));
        let last_progress_count = Arc::new(AtomicU64::new(0));
        let interrupted = Arc::new(AtomicBool::new(false));
        let total_entries = entries.len() as u64;

        // Process entries in parallel to calculate sizes
        let processed_entries: Vec<_> = entries
            .par_iter()
            .filter_map(|entry_result| {
                if interrupted.load(Ordering::Relaxed) {
                    return None;
                }

                match entry_result {
                    Ok(entry) => {
                        let path = entry.path().to_path_buf();
                        let is_dir = entry.file_type().is_dir();
                        let is_symlink = entry.file_type().is_symlink();

                        // Get file size
                        let size = if is_dir || is_symlink {
                            0
                        } else {
                            self.get_file_size(&path)
                        };

                        // Get modification time
                        let modified = entry.metadata().ok().and_then(|m| m.modified().ok());

                        // Get symlink target if applicable
                        let symlink_target = if is_symlink {
                            std::fs::read_link(&path).ok()
                        } else {
                            None
                        };

                        // Update progress counters
                        let count = files_found.fetch_add(1, Ordering::Relaxed) + 1;
                        let total_bytes = bytes_processed.fetch_add(size, Ordering::Relaxed) + size;

                        // Throttle progress updates: every 100 files or 50ms
                        let should_send = {
                            let mut last_time = last_progress_time.lock().unwrap();
                            let last_count = last_progress_count.load(Ordering::Relaxed);

                            if count - last_count >= 100
                                || last_time.elapsed() >= Duration::from_millis(50)
                            {
                                *last_time = Instant::now();
                                last_progress_count.store(count, Ordering::Relaxed);
                                true
                            } else {
                                false
                            }
                        };

                        if should_send {
                            let _ = self.progress_tx.send(ScanProgress::Scanning {
                                path: path.clone(),
                                files_found: count,
                                estimated_total: total_entries,
                                bytes_processed: total_bytes,
                            });
                        }

                        Some((path, is_dir, is_symlink, size, modified, symlink_target))
                    }
                    Err(err) => {
                        // Handle permission errors gracefully - skip and continue
                        if let Some(path) = err.path() {
                            let _ = self.progress_tx.send(ScanProgress::Error {
                                path: path.to_path_buf(),
                                error: err.to_string(),
                            });
                        }
                        None
                    }
                }
            })
            .collect();

        // Check for interruption
        if interrupted.load(Ordering::Relaxed) {
            return Err(ScanError::Interrupted);
        }

        // Build the file tree from processed entries
        let mut tree = FileTree::with_root(root_path.clone());
        let root_id = tree.root.unwrap();

        // Create a map from path to NodeId for efficient parent lookup
        let mut path_to_node: HashMap<PathBuf, NodeId> = HashMap::new();
        path_to_node.insert(root_path.clone(), root_id);

        // Send root node for streaming display
        if let Some(root_node) = tree.get_node(root_id) {
            let _ = self.progress_tx.send(ScanProgress::NodeDiscovered {
                node: root_node.clone(),
                parent_path: root_path.clone(),
            });
        }

        // Sort entries by path depth to ensure parents are processed before children
        let mut sorted_entries = processed_entries;
        sorted_entries.sort_by(|a, b| {
            let depth_a = a.0.components().count();
            let depth_b = b.0.components().count();
            depth_a.cmp(&depth_b)
        });

        let mut total_size = 0u64;
        let mut total_files = 0u64;
        let mut nodes_sent = 0u64;

        for (path, is_dir, is_symlink, size, modified, symlink_target) in sorted_entries {
            // Skip the root path as it's already added
            if path == *root_path {
                continue;
            }

            // Find parent path
            let parent_path = path.parent().unwrap_or(root_path).to_path_buf();

            // Get parent node ID
            if let Some(&parent_id) = path_to_node.get(&parent_path) {
                let mut node = FileNode::new(path.clone(), is_dir);
                node.size = size;

                if let Some(mod_time) = modified {
                    node = node.with_modified(mod_time);
                }

                if is_symlink {
                    if let Some(target) = symlink_target {
                        node = node.with_symlink(target);
                    } else {
                        node.is_symlink = true;
                    }
                }

                // Stream node discovery (throttled to avoid channel overflow)
                nodes_sent += 1;
                if nodes_sent % 50 == 0 || nodes_sent < 100 {
                    let _ = self.progress_tx.send(ScanProgress::NodeDiscovered {
                        node: node.clone(),
                        parent_path: parent_path.clone(),
                    });
                }

                let node_id = tree.add_child(parent_id, node);
                path_to_node.insert(path.clone(), node_id);

                if !is_dir {
                    total_size += size;
                    total_files += 1;
                }
            }
        }

        // Calculate aggregated sizes for directories
        tree.calculate_sizes();

        // Send completion progress with the tree
        let _ = self.progress_tx.send(ScanProgress::Completed {
            total_files,
            total_size,
            tree: tree.clone(),
        });

        Ok(tree)
    }

    /// Get the size of a file based on the apparent_size option.
    fn get_file_size(&self, path: &PathBuf) -> u64 {
        match std::fs::metadata(path) {
            Ok(metadata) => {
                if self.options.apparent_size {
                    metadata.len()
                } else {
                    // Use disk blocks if available (Unix-specific)
                    #[cfg(unix)]
                    {
                        use std::os::unix::fs::MetadataExt;
                        // blocks() returns 512-byte blocks
                        metadata.blocks() * 512
                    }
                    #[cfg(not(unix))]
                    {
                        // Fallback to apparent size on non-Unix systems
                        metadata.len()
                    }
                }
            }
            Err(_) => 0,
        }
    }

    /// Check if a path should be excluded based on exclude patterns.
    fn should_exclude(&self, path: &std::path::Path) -> bool {
        if self.options.exclude_patterns.is_empty() {
            return false;
        }

        let path_str = path.to_string_lossy();

        for pattern in &self.options.exclude_patterns {
            // Simple glob matching: support * as wildcard
            if pattern.contains('*') {
                // Convert glob to a simple regex-like pattern
                let regex_pattern = pattern.replace('.', r"\.").replace('*', ".*");
                if let Ok(re) = regex_simple_match(&regex_pattern, &path_str) {
                    if re {
                        return true;
                    }
                }
            } else {
                // Exact match or contains
                if path_str.contains(pattern) {
                    return true;
                }
            }
        }

        false
    }
}

/// Simple regex-like matching for basic glob patterns.
fn regex_simple_match(pattern: &str, text: &str) -> Result<bool, ()> {
    // Very basic pattern matching - handles .* patterns
    let parts: Vec<&str> = pattern.split(".*").collect();

    if parts.is_empty() {
        return Ok(true);
    }

    let mut remaining = text;

    for (i, part) in parts.iter().enumerate() {
        if part.is_empty() {
            continue;
        }

        if i == 0 {
            // First part must match at the start
            if !remaining.starts_with(part) {
                if let Some(pos) = remaining.find(part) {
                    remaining = &remaining[pos + part.len()..];
                } else {
                    return Ok(false);
                }
            } else {
                remaining = &remaining[part.len()..];
            }
        } else {
            // Other parts can match anywhere
            if let Some(pos) = remaining.find(part) {
                remaining = &remaining[pos + part.len()..];
            } else {
                return Ok(false);
            }
        }
    }

    Ok(true)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::mpsc::sync_channel;
    use tempfile::TempDir;

    #[test]
    fn test_scan_options_builder() {
        let opts = ScanOptions::new(PathBuf::from("/test"))
            .with_max_depth(Some(5))
            .with_cross_mount(true)
            .with_apparent_size(false)
            .with_exclude_patterns(vec!["*.tmp".to_string()]);

        assert_eq!(opts.root_path, PathBuf::from("/test"));
        assert_eq!(opts.max_depth, Some(5));
        assert!(opts.cross_mount);
        assert!(!opts.apparent_size);
        assert_eq!(opts.exclude_patterns.len(), 1);
    }

    #[test]
    fn test_scan_nonexistent_path() {
        let (tx, _rx) = sync_channel(1000);
        let opts = ScanOptions::new(PathBuf::from("/nonexistent/path/that/does/not/exist"));
        let scanner = Scanner::new(opts, tx);

        let result = scanner.scan();
        assert!(matches!(result, Err(ScanError::PathNotFound { .. })));
    }

    #[test]
    fn test_scan_file_not_directory() {
        let temp_dir = TempDir::new().unwrap();
        let file_path = temp_dir.path().join("test.txt");
        std::fs::write(&file_path, "test content").unwrap();

        let (tx, _rx) = sync_channel(1000);
        let opts = ScanOptions::new(file_path);
        let scanner = Scanner::new(opts, tx);

        let result = scanner.scan();
        assert!(matches!(result, Err(ScanError::NotADirectory { .. })));
    }

    #[test]
    fn test_scan_empty_directory() {
        let temp_dir = TempDir::new().unwrap();

        let (tx, rx) = sync_channel(1000);
        let opts = ScanOptions::new(temp_dir.path().to_path_buf());
        let scanner = Scanner::new(opts, tx);

        let result = scanner.scan();
        assert!(result.is_ok());

        let tree = result.unwrap();
        assert!(tree.root.is_some());

        // Check that we received progress updates
        let mut received_started = false;
        let mut received_completed = false;

        while let Ok(progress) = rx.try_recv() {
            match progress {
                ScanProgress::Started => received_started = true,
                ScanProgress::Completed { .. } => received_completed = true,
                _ => {}
            }
        }

        assert!(received_started);
        assert!(received_completed);
    }

    #[test]
    fn test_scan_with_files() {
        let temp_dir = TempDir::new().unwrap();

        // Create some test files
        std::fs::write(temp_dir.path().join("file1.txt"), "hello").unwrap();
        std::fs::write(temp_dir.path().join("file2.txt"), "world").unwrap();
        std::fs::create_dir(temp_dir.path().join("subdir")).unwrap();
        std::fs::write(temp_dir.path().join("subdir/file3.txt"), "nested").unwrap();

        let (tx, rx) = sync_channel(1000);
        let opts = ScanOptions::new(temp_dir.path().to_path_buf());
        let scanner = Scanner::new(opts, tx);

        let result = scanner.scan();
        assert!(result.is_ok());

        let tree = result.unwrap();

        // We should have: root, file1.txt, file2.txt, subdir, subdir/file3.txt = 5 nodes
        assert_eq!(tree.node_count(), 5);

        // Check completion progress
        let mut completion_files = 0;
        while let Ok(progress) = rx.try_recv() {
            if let ScanProgress::Completed { total_files, .. } = progress {
                completion_files = total_files;
            }
        }

        assert_eq!(completion_files, 3);
    }

    #[test]
    fn test_exclude_patterns() {
        let temp_dir = TempDir::new().unwrap();

        std::fs::write(temp_dir.path().join("keep.txt"), "keep").unwrap();
        std::fs::write(temp_dir.path().join("exclude.tmp"), "exclude").unwrap();
        std::fs::create_dir(temp_dir.path().join("node_modules")).unwrap();
        std::fs::write(
            temp_dir.path().join("node_modules/package.json"),
            "{}",
        )
        .unwrap();

        let (tx, _rx) = sync_channel(1000);
        let opts = ScanOptions::new(temp_dir.path().to_path_buf())
            .with_exclude_patterns(vec!["*.tmp".to_string(), "node_modules".to_string()]);
        let scanner = Scanner::new(opts, tx);

        let result = scanner.scan();
        assert!(result.is_ok());

        let tree = result.unwrap();

        // Should have: root, keep.txt = 2 nodes minimum
        // (exclude.tmp and node_modules are excluded via filter_entry)
        // Note: actual count depends on walkdir filter_entry behavior
        assert!(tree.node_count() >= 2);
        assert!(tree.node_count() <= 3); // At most root + keep.txt + node_modules dir entry
    }
}
