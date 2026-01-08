//! Cache system for Data-X scan results.
//!
//! Saves scan results to disk and provides background update checking
//! to avoid full rescans on startup.

use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};

use crate::tree::{FileNode, FileTree};

/// Cache entry for a scanned directory.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CacheEntry {
    /// Root path that was scanned
    pub root_path: PathBuf,
    /// When the scan was performed
    pub scan_time: u64,
    /// Version of the cache format
    pub version: u32,
    /// Serialized file tree nodes
    pub nodes: Vec<CachedNode>,
    /// Root node index
    pub root_index: Option<usize>,
    /// Total size
    pub total_size: u64,
    /// Total file count
    pub total_files: u64,
}

/// Serializable node for cache storage.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CachedNode {
    pub path: PathBuf,
    pub name: String,
    pub size: u64,
    pub is_dir: bool,
    pub is_hidden: bool,
    pub is_symlink: bool,
    pub file_count: u64,
    pub modified: Option<u64>,
    pub extension: Option<String>,
    pub parent_index: Option<usize>,
    pub children_indices: Vec<usize>,
}

/// Cache manager for loading and saving scan results.
pub struct CacheManager {
    cache_dir: PathBuf,
}

const CACHE_VERSION: u32 = 1;
const CACHE_MAX_AGE_SECS: u64 = 86400 * 7; // 7 days

impl CacheManager {
    /// Create a new cache manager.
    pub fn new() -> Self {
        let cache_dir = Self::get_cache_dir();
        Self { cache_dir }
    }

    /// Get the cache directory path.
    fn get_cache_dir() -> PathBuf {
        // Try XDG cache dir first, then fallback to ~/.cache
        if let Ok(xdg_cache) = std::env::var("XDG_CACHE_HOME") {
            PathBuf::from(xdg_cache).join("data-x")
        } else if let Ok(home) = std::env::var("HOME") {
            PathBuf::from(home).join(".cache").join("data-x")
        } else {
            PathBuf::from("/tmp").join("data-x-cache")
        }
    }

    /// Generate a cache filename for a given path.
    fn cache_filename(&self, path: &Path) -> PathBuf {
        // Create a hash of the path for the filename
        let path_str = path.to_string_lossy();
        let hash = Self::simple_hash(&path_str);
        self.cache_dir.join(format!("scan_{:016x}.json", hash))
    }

    /// Simple hash function for path strings.
    fn simple_hash(s: &str) -> u64 {
        let mut hash: u64 = 5381;
        for byte in s.bytes() {
            hash = hash.wrapping_mul(33).wrapping_add(byte as u64);
        }
        hash
    }

    /// Check if a valid cache exists for the given path.
    pub fn has_valid_cache(&self, path: &Path) -> bool {
        let cache_file = self.cache_filename(path);
        if !cache_file.exists() {
            return false;
        }

        // Check if cache is not too old
        if let Ok(metadata) = fs::metadata(&cache_file) {
            if let Ok(modified) = metadata.modified() {
                if let Ok(age) = SystemTime::now().duration_since(modified) {
                    return age.as_secs() < CACHE_MAX_AGE_SECS;
                }
            }
        }

        false
    }

    /// Load a cached scan result.
    pub fn load(&self, path: &Path) -> Option<CacheEntry> {
        let cache_file = self.cache_filename(path);

        let content = fs::read_to_string(&cache_file).ok()?;
        let entry: CacheEntry = serde_json::from_str(&content).ok()?;

        // Verify version and path match
        if entry.version != CACHE_VERSION || entry.root_path != path {
            return None;
        }

        Some(entry)
    }

    /// Save a scan result to cache.
    pub fn save(&self, tree: &FileTree, root_path: &Path) -> Result<(), std::io::Error> {
        // Ensure cache directory exists
        fs::create_dir_all(&self.cache_dir)?;

        let entry = self.tree_to_cache_entry(tree, root_path);
        let cache_file = self.cache_filename(root_path);

        let content = serde_json::to_string(&entry)?;
        fs::write(&cache_file, content)?;

        Ok(())
    }

    /// Convert a FileTree to a CacheEntry.
    fn tree_to_cache_entry(&self, tree: &FileTree, root_path: &Path) -> CacheEntry {
        let mut nodes = Vec::new();
        let mut path_to_index: HashMap<PathBuf, usize> = HashMap::new();

        // First pass: collect all nodes
        if let Some(root_id) = tree.root {
            self.collect_nodes_recursive(tree, root_id, &mut nodes, &mut path_to_index, None);
        }

        // Second pass: set children indices
        for i in 0..nodes.len() {
            let path = nodes[i].path.clone();
            if let Some(node_id) = tree.find_by_path(&path) {
                let children_paths: Vec<PathBuf> = tree
                    .get_children(node_id)
                    .iter()
                    .filter_map(|&child_id| tree.get_node(child_id).map(|n| n.path.clone()))
                    .collect();

                nodes[i].children_indices = children_paths
                    .iter()
                    .filter_map(|p| path_to_index.get(p).copied())
                    .collect();
            }
        }

        let root_index = tree.root.and_then(|r| {
            tree.get_node(r)
                .and_then(|n| path_to_index.get(&n.path).copied())
        });

        let total_size = tree.root
            .and_then(|r| tree.get_node(r))
            .map(|n| n.size)
            .unwrap_or(0);

        let total_files = tree.root
            .and_then(|r| tree.get_node(r))
            .map(|n| n.file_count)
            .unwrap_or(0);

        CacheEntry {
            root_path: root_path.to_path_buf(),
            scan_time: SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs(),
            version: CACHE_VERSION,
            nodes,
            root_index,
            total_size,
            total_files,
        }
    }

    /// Recursively collect nodes into the cache structure.
    fn collect_nodes_recursive(
        &self,
        tree: &FileTree,
        node_id: indextree::NodeId,
        nodes: &mut Vec<CachedNode>,
        path_to_index: &mut HashMap<PathBuf, usize>,
        parent_index: Option<usize>,
    ) {
        if let Some(node) = tree.get_node(node_id) {
            let index = nodes.len();
            path_to_index.insert(node.path.clone(), index);

            let modified = node.modified.and_then(|t| {
                t.duration_since(UNIX_EPOCH).ok().map(|d| d.as_secs())
            });

            nodes.push(CachedNode {
                path: node.path.clone(),
                name: node.name.clone(),
                size: node.size,
                is_dir: node.is_dir,
                is_hidden: node.is_hidden,
                is_symlink: node.is_symlink,
                file_count: node.file_count,
                modified,
                extension: node.extension.clone(),
                parent_index,
                children_indices: Vec::new(), // Filled in second pass
            });

            // Recurse for children
            for child_id in tree.get_children(node_id) {
                self.collect_nodes_recursive(tree, child_id, nodes, path_to_index, Some(index));
            }
        }
    }

    /// Convert a CacheEntry back to a FileTree.
    pub fn cache_entry_to_tree(&self, entry: &CacheEntry) -> Option<FileTree> {
        if entry.nodes.is_empty() {
            return None;
        }

        let root_index = entry.root_index?;
        let root_cached = entry.nodes.get(root_index)?;

        let mut tree = FileTree::with_root(root_cached.path.clone());
        let tree_root_id = tree.root?;

        // Update root node
        if let Some(root_node) = tree.get_node_mut(tree_root_id) {
            root_node.size = root_cached.size;
            root_node.file_count = root_cached.file_count;
            root_node.is_hidden = root_cached.is_hidden;
            if let Some(mod_secs) = root_cached.modified {
                root_node.modified = Some(UNIX_EPOCH + Duration::from_secs(mod_secs));
            }
        }

        // Build a map of cache index to tree NodeId
        let mut index_to_node_id: HashMap<usize, indextree::NodeId> = HashMap::new();
        index_to_node_id.insert(root_index, tree_root_id);

        // Track visited indices to prevent cycles from corrupted cache
        let mut visited: std::collections::HashSet<usize> = std::collections::HashSet::new();
        visited.insert(root_index);

        // Add all other nodes (breadth-first to ensure parents exist)
        let mut queue: Vec<(usize, indextree::NodeId)> = vec![(root_index, tree_root_id)];

        while let Some((cache_idx, parent_node_id)) = queue.pop() {
            let cached = &entry.nodes[cache_idx];

            for &child_idx in &cached.children_indices {
                // Skip if already visited (prevents cycles)
                if visited.contains(&child_idx) {
                    continue;
                }
                visited.insert(child_idx);

                if let Some(child_cached) = entry.nodes.get(child_idx) {
                    let mut child_node = FileNode::new(child_cached.path.clone(), child_cached.is_dir);
                    child_node.size = child_cached.size;
                    child_node.file_count = child_cached.file_count;
                    child_node.is_hidden = child_cached.is_hidden;
                    child_node.is_symlink = child_cached.is_symlink;
                    child_node.extension = child_cached.extension.clone();

                    if let Some(mod_secs) = child_cached.modified {
                        child_node.modified = Some(UNIX_EPOCH + Duration::from_secs(mod_secs));
                    }

                    let child_node_id = tree.add_child(parent_node_id, child_node);
                    index_to_node_id.insert(child_idx, child_node_id);
                    queue.push((child_idx, child_node_id));
                }
            }
        }

        Some(tree)
    }

    /// Clear all cached data.
    #[allow(dead_code)]
    pub fn clear_all(&self) -> Result<(), std::io::Error> {
        if self.cache_dir.exists() {
            fs::remove_dir_all(&self.cache_dir)?;
        }
        Ok(())
    }

    /// Clear cache for a specific path.
    #[allow(dead_code)]
    pub fn clear(&self, path: &Path) -> Result<(), std::io::Error> {
        let cache_file = self.cache_filename(path);
        if cache_file.exists() {
            fs::remove_file(&cache_file)?;
        }
        Ok(())
    }

    /// Get cache info for display.
    #[allow(dead_code)]
    pub fn get_cache_info(&self, path: &Path) -> Option<CacheInfo> {
        let cache_file = self.cache_filename(path);
        let metadata = fs::metadata(&cache_file).ok()?;
        let modified = metadata.modified().ok()?;
        let size = metadata.len();
        let age = SystemTime::now().duration_since(modified).ok()?;

        Some(CacheInfo {
            file_path: cache_file,
            size,
            age_secs: age.as_secs(),
        })
    }
}

/// Information about a cache entry.
#[derive(Debug)]
#[allow(dead_code)]
pub struct CacheInfo {
    pub file_path: PathBuf,
    pub size: u64,
    pub age_secs: u64,
}

#[allow(dead_code)]
impl CacheInfo {
    /// Format the age as a human-readable string.
    pub fn age_string(&self) -> String {
        let secs = self.age_secs;
        if secs < 60 {
            format!("{}s ago", secs)
        } else if secs < 3600 {
            format!("{}m ago", secs / 60)
        } else if secs < 86400 {
            format!("{}h ago", secs / 3600)
        } else {
            format!("{}d ago", secs / 86400)
        }
    }
}

impl Default for CacheManager {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[allow(unused_imports)]
    use tempfile::TempDir;

    #[test]
    fn test_cache_filename_hash() {
        let manager = CacheManager::new();
        let path1 = PathBuf::from("/home/user/test");
        let path2 = PathBuf::from("/home/user/test2");

        let file1 = manager.cache_filename(&path1);
        let file2 = manager.cache_filename(&path2);

        assert_ne!(file1, file2);
    }

    #[test]
    fn test_simple_hash() {
        let hash1 = CacheManager::simple_hash("/test/path");
        let hash2 = CacheManager::simple_hash("/test/path");
        let hash3 = CacheManager::simple_hash("/test/other");

        assert_eq!(hash1, hash2);
        assert_ne!(hash1, hash3);
    }
}
