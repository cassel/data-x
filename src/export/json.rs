use serde::{Deserialize, Serialize};
use std::io::Write;

use crate::tree::{FileTree, NodeId};

/// Represents a node in the exported tree structure
#[derive(Serialize, Deserialize)]
pub struct ExportNode {
    pub path: String,
    pub name: String,
    pub size: u64,
    pub is_dir: bool,
    #[serde(skip_serializing_if = "Vec::is_empty", default)]
    pub children: Vec<ExportNode>,
}

/// Options for customizing the JSON export
pub struct ExportOptions {
    /// If Some(n), flatten tree and return top n items by size
    /// If None, export full tree structure
    pub top_n: Option<usize>,
}

/// Recursively convert a FileTree node to an ExportNode
pub fn tree_to_export_node(tree: &FileTree, node_id: NodeId) -> ExportNode {
    let node = tree.get_node(node_id).expect("Node must exist");

    let children: Vec<ExportNode> = tree
        .get_children(node_id)
        .into_iter()
        .map(|child_id| tree_to_export_node(tree, child_id))
        .collect();

    ExportNode {
        path: node.path.to_string_lossy().to_string(),
        name: node.name.clone(),
        size: node.size,
        is_dir: node.is_dir,
        children,
    }
}

/// Flatten a tree into a vector of ExportNodes (without children)
fn flatten_tree(tree: &FileTree, node_id: NodeId, result: &mut Vec<ExportNode>) {
    let node = tree.get_node(node_id).expect("Node must exist");

    result.push(ExportNode {
        path: node.path.to_string_lossy().to_string(),
        name: node.name.clone(),
        size: node.size,
        is_dir: node.is_dir,
        children: Vec::new(),
    });

    for child_id in tree.get_children(node_id) {
        flatten_tree(tree, child_id, result);
    }
}

/// Export the FileTree to JSON format
///
/// # Arguments
/// * `tree` - The FileTree to export
/// * `options` - Export options (top_n for flattening, None for full tree)
/// * `writer` - Output writer for the JSON
///
/// # Returns
/// * `Ok(())` on success
/// * `Err(std::io::Error)` on write failure
pub fn export_json(
    tree: &FileTree,
    options: &ExportOptions,
    writer: &mut impl Write,
) -> Result<(), std::io::Error> {
    let root = match tree.root {
        Some(root) => root,
        None => {
            // Empty tree - output empty object or array based on options
            return if options.top_n.is_some() {
                serde_json::to_writer_pretty(writer, &Vec::<ExportNode>::new())
                    .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e))
            } else {
                writer.write_all(b"null")
            };
        }
    };

    match options.top_n {
        Some(n) => {
            // Flatten tree, sort by size descending, take top n
            let mut flattened = Vec::new();
            flatten_tree(tree, root, &mut flattened);

            // Sort by size descending
            flattened.sort_by(|a, b| b.size.cmp(&a.size));

            // Take top n
            let top_items: Vec<_> = flattened.into_iter().take(n).collect();

            serde_json::to_writer_pretty(writer, &top_items)
                .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e))
        }
        None => {
            // Export full tree structure
            let export_tree = tree_to_export_node(tree, root);
            serde_json::to_writer_pretty(writer, &export_tree)
                .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tree::FileNode;
    use std::path::PathBuf;

    fn create_test_tree() -> FileTree {
        let mut tree = FileTree::with_root(PathBuf::from("/test"));
        let root = tree.root.unwrap();

        let file1 = FileNode::new(PathBuf::from("/test/large.txt"), false).with_size(1000);
        let file2 = FileNode::new(PathBuf::from("/test/small.txt"), false).with_size(100);

        let subdir = FileNode::new(PathBuf::from("/test/subdir"), true);
        let subdir_id = tree.add_child(root, subdir);

        let file3 = FileNode::new(PathBuf::from("/test/subdir/medium.txt"), false).with_size(500);
        tree.add_child(subdir_id, file3);

        tree.add_child(root, file1);
        tree.add_child(root, file2);

        tree.calculate_sizes();
        tree
    }

    #[test]
    fn test_tree_to_export_node() {
        let tree = create_test_tree();
        let root = tree.root.unwrap();

        let export = tree_to_export_node(&tree, root);

        assert_eq!(export.name, "test");
        assert_eq!(export.path, "/test");
        assert!(export.is_dir);
        assert_eq!(export.children.len(), 3);
    }

    #[test]
    fn test_export_json_full_tree() {
        let tree = create_test_tree();
        let options = ExportOptions { top_n: None };

        let mut buffer = Vec::new();
        export_json(&tree, &options, &mut buffer).unwrap();

        let output = String::from_utf8(buffer).unwrap();
        assert!(output.contains("\"name\": \"test\""));
        assert!(output.contains("\"children\""));
    }

    #[test]
    fn test_export_json_top_n() {
        let tree = create_test_tree();
        let options = ExportOptions { top_n: Some(2) };

        let mut buffer = Vec::new();
        export_json(&tree, &options, &mut buffer).unwrap();

        let output = String::from_utf8(buffer).unwrap();
        // Should be an array with 2 items
        let parsed: Vec<ExportNode> = serde_json::from_str(&output).unwrap();
        assert_eq!(parsed.len(), 2);
        // First item should be largest (root with total size 1600)
        assert!(parsed[0].size >= parsed[1].size);
    }

    #[test]
    fn test_export_empty_tree() {
        let tree = FileTree::new();
        let options = ExportOptions { top_n: None };

        let mut buffer = Vec::new();
        export_json(&tree, &options, &mut buffer).unwrap();

        let output = String::from_utf8(buffer).unwrap();
        assert_eq!(output, "null");
    }

    #[test]
    fn test_export_empty_tree_top_n() {
        let tree = FileTree::new();
        let options = ExportOptions { top_n: Some(10) };

        let mut buffer = Vec::new();
        export_json(&tree, &options, &mut buffer).unwrap();

        let output = String::from_utf8(buffer).unwrap();
        assert_eq!(output, "[]");
    }
}
