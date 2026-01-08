use std::path::PathBuf;
use std::sync::{Arc, RwLock};
use std::time::SystemTime;

use indextree::{Arena, NodeId};

/// Thread-safe shared file tree for concurrent read/write access during streaming scans
#[allow(dead_code)]
pub type SharedFileTree = Arc<RwLock<FileTree>>;

/// Represents a file or directory in the tree
#[derive(Debug, Clone)]
pub struct FileNode {
    pub name: String,
    pub path: PathBuf,
    pub size: u64,
    pub is_dir: bool,
    pub file_count: u64,
    pub modified: Option<SystemTime>,
    pub is_hidden: bool,
    pub is_symlink: bool,
    pub symlink_target: Option<PathBuf>,
    pub extension: Option<String>,
    pub excluded: bool,
    /// Pre-computed lowercase name for search
    pub name_lower: String,
}

impl FileNode {
    pub fn new(path: PathBuf, is_dir: bool) -> Self {
        let name = path
            .file_name()
            .map(|s| s.to_string_lossy().to_string())
            .unwrap_or_else(|| path.to_string_lossy().to_string());

        let is_hidden = name.starts_with('.');
        let extension = if is_dir {
            None
        } else {
            path.extension().map(|e| e.to_string_lossy().to_lowercase())
        };
        let name_lower = name.to_lowercase();

        Self {
            name,
            path,
            size: 0,
            is_dir,
            file_count: if is_dir { 0 } else { 1 },
            modified: None,
            is_hidden,
            is_symlink: false,
            symlink_target: None,
            extension,
            excluded: false,
            name_lower,
        }
    }

    #[allow(dead_code)]
    pub fn with_size(mut self, size: u64) -> Self {
        self.size = size;
        self
    }

    pub fn with_modified(mut self, modified: SystemTime) -> Self {
        self.modified = Some(modified);
        self
    }

    pub fn with_symlink(mut self, target: PathBuf) -> Self {
        self.is_symlink = true;
        self.symlink_target = Some(target);
        self
    }
}

/// File tree using arena allocation for performance
#[derive(Debug)]
pub struct FileTree {
    pub arena: Arena<FileNode>,
    pub root: Option<NodeId>,
}

impl Clone for FileTree {
    fn clone(&self) -> Self {
        // Deep clone the tree by rebuilding it
        let mut new_tree = FileTree::new();

        if let Some(root_id) = self.root {
            if let Some(root_node) = self.get_node(root_id) {
                new_tree = FileTree::with_root(root_node.path.clone());
                let new_root = new_tree.root.unwrap();

                // Copy root node properties
                if let Some(new_root_node) = new_tree.get_node_mut(new_root) {
                    new_root_node.size = root_node.size;
                    new_root_node.file_count = root_node.file_count;
                    new_root_node.modified = root_node.modified;
                    new_root_node.is_hidden = root_node.is_hidden;
                    new_root_node.excluded = root_node.excluded;
                }

                // Clone children recursively
                Self::clone_children(&self, root_id, new_root, &mut new_tree);
            }
        }

        new_tree
    }
}

impl FileTree {
    fn clone_children(source: &FileTree, source_parent: NodeId, dest_parent: NodeId, dest: &mut FileTree) {
        for child_id in source.get_children(source_parent) {
            if let Some(child_node) = source.get_node(child_id) {
                let mut new_node = FileNode::new(child_node.path.clone(), child_node.is_dir);
                new_node.size = child_node.size;
                new_node.file_count = child_node.file_count;
                new_node.modified = child_node.modified;
                new_node.is_hidden = child_node.is_hidden;
                new_node.is_symlink = child_node.is_symlink;
                new_node.symlink_target = child_node.symlink_target.clone();
                new_node.extension = child_node.extension.clone();
                new_node.excluded = child_node.excluded;
                new_node.name_lower = child_node.name_lower.clone();

                let new_child_id = dest.add_child(dest_parent, new_node);

                // Recursively clone grandchildren
                Self::clone_children(source, child_id, new_child_id, dest);
            }
        }
    }

    pub fn new() -> Self {
        Self {
            arena: Arena::new(),
            root: None,
        }
    }

    /// Create a new tree with a root node
    pub fn with_root(root_path: PathBuf) -> Self {
        let mut arena = Arena::new();
        let root_node = FileNode::new(root_path, true);
        let root_id = arena.new_node(root_node);

        Self {
            arena,
            root: Some(root_id),
        }
    }

    /// Add a child node under a parent
    pub fn add_child(&mut self, parent_id: NodeId, node: FileNode) -> NodeId {
        let child_id = self.arena.new_node(node);
        parent_id.append(child_id, &mut self.arena);
        child_id
    }

    /// Get a reference to a node
    pub fn get_node(&self, id: NodeId) -> Option<&FileNode> {
        self.arena.get(id).map(|n| n.get())
    }

    /// Get a mutable reference to a node
    pub fn get_node_mut(&mut self, id: NodeId) -> Option<&mut FileNode> {
        self.arena.get_mut(id).map(|n| n.get_mut())
    }

    /// Get children of a node
    pub fn get_children(&self, id: NodeId) -> Vec<NodeId> {
        id.children(&self.arena).collect()
    }

    /// Get parent of a node
    pub fn get_parent(&self, id: NodeId) -> Option<NodeId> {
        self.arena.get(id).and_then(|n| n.parent())
    }

    /// Calculate sizes bottom-up (call after tree is built)
    pub fn calculate_sizes(&mut self) {
        if let Some(root) = self.root {
            self.calculate_sizes_recursive(root);
        }
    }

    fn calculate_sizes_recursive(&mut self, node_id: NodeId) -> (u64, u64) {
        let children: Vec<NodeId> = node_id.children(&self.arena).collect();

        if children.is_empty() {
            // Leaf node - return its own size and count
            let node = self.arena.get(node_id).unwrap().get();
            let size = if node.excluded { 0 } else { node.size };
            let count = if node.excluded { 0 } else { node.file_count };
            return (size, count);
        }

        // Aggregate children
        let mut total_size = 0u64;
        let mut total_count = 0u64;

        for child_id in children {
            let (child_size, child_count) = self.calculate_sizes_recursive(child_id);
            total_size += child_size;
            total_count += child_count;
        }

        // Update this node
        if let Some(node) = self.arena.get_mut(node_id) {
            let node = node.get_mut();
            if !node.excluded {
                node.size = total_size;
                node.file_count = total_count;
            }
        }

        let node = self.arena.get(node_id).unwrap().get();
        let size = if node.excluded { 0 } else { node.size };
        let count = if node.excluded { 0 } else { node.file_count };
        (size, count)
    }

    /// Get total size of the tree
    pub fn total_size(&self) -> u64 {
        self.root
            .and_then(|r| self.get_node(r))
            .map(|n| n.size)
            .unwrap_or(0)
    }

    /// Get total file count
    #[allow(dead_code)]
    pub fn total_file_count(&self) -> u64 {
        self.root
            .and_then(|r| self.get_node(r))
            .map(|n| n.file_count)
            .unwrap_or(0)
    }

    /// Incrementally add size to a node and all its ancestors.
    /// Used during streaming scans to update sizes as nodes are discovered.
    /// O(depth) complexity instead of O(n) for full tree recalculation.
    pub fn add_size_to_ancestors(&mut self, node_id: NodeId, size: u64, file_count: u64) {
        let mut current = Some(node_id);

        while let Some(id) = current {
            if let Some(node) = self.arena.get_mut(id) {
                let node = node.get_mut();
                if !node.excluded {
                    node.size = node.size.saturating_add(size);
                    node.file_count = node.file_count.saturating_add(file_count);
                }
            }
            current = self.get_parent(id);
        }
    }

    /// Remove a node and its subtree
    #[allow(dead_code)]
    pub fn remove_node(&mut self, node_id: NodeId) {
        node_id.remove_subtree(&mut self.arena);
    }

    /// Find a node by path
    pub fn find_by_path(&self, path: &PathBuf) -> Option<NodeId> {
        self.root.and_then(|root| {
            for node_id in root.descendants(&self.arena) {
                if let Some(node) = self.get_node(node_id) {
                    if &node.path == path {
                        return Some(node_id);
                    }
                }
            }
            None
        })
    }

    /// Count total nodes in tree
    #[allow(dead_code)]
    pub fn node_count(&self) -> usize {
        self.arena.count()
    }
}

impl Default for FileTree {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_tree_creation() {
        let tree = FileTree::with_root(PathBuf::from("/test"));
        assert!(tree.root.is_some());
        assert_eq!(tree.node_count(), 1);
    }

    #[test]
    fn test_add_children() {
        let mut tree = FileTree::with_root(PathBuf::from("/test"));
        let root = tree.root.unwrap();

        let child1 = FileNode::new(PathBuf::from("/test/file1.txt"), false).with_size(100);
        let child2 = FileNode::new(PathBuf::from("/test/file2.txt"), false).with_size(200);

        tree.add_child(root, child1);
        tree.add_child(root, child2);

        assert_eq!(tree.node_count(), 3);
        assert_eq!(tree.get_children(root).len(), 2);
    }

    #[test]
    fn test_size_calculation() {
        let mut tree = FileTree::with_root(PathBuf::from("/test"));
        let root = tree.root.unwrap();

        let child1 = FileNode::new(PathBuf::from("/test/file1.txt"), false).with_size(100);
        let child2 = FileNode::new(PathBuf::from("/test/file2.txt"), false).with_size(200);

        tree.add_child(root, child1);
        tree.add_child(root, child2);

        tree.calculate_sizes();

        assert_eq!(tree.total_size(), 300);
        assert_eq!(tree.total_file_count(), 2);
    }

    #[test]
    fn test_hidden_file_detection() {
        let node = FileNode::new(PathBuf::from("/test/.hidden"), false);
        assert!(node.is_hidden);

        let node = FileNode::new(PathBuf::from("/test/visible"), false);
        assert!(!node.is_hidden);
    }

    #[test]
    fn test_extension_extraction() {
        let node = FileNode::new(PathBuf::from("/test/file.TXT"), false);
        assert_eq!(node.extension, Some("txt".to_string()));

        let dir = FileNode::new(PathBuf::from("/test/dir"), true);
        assert_eq!(dir.extension, None);
    }
}
