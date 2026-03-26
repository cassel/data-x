mod node;

pub use indextree::NodeId;
pub use node::{FileNode, FileTree};
// Re-exported for potential future use
#[allow(unused_imports)]
pub use node::SharedFileTree;
