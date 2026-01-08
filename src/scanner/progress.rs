//! Progress reporting types for the scanner module.

use std::path::PathBuf;

use crate::tree::{FileNode, FileTree};

/// Current phase of the scan operation.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[allow(dead_code)]
pub enum ScanPhase {
    /// Initial counting phase (fast enumeration)
    Counting,
    /// Main analysis phase (detailed scan with size calculation)
    Analyzing,
    /// Building final tree structure
    Building,
    /// Scan complete
    Complete,
}

/// Represents the current progress state of a directory scan.
#[derive(Debug)]
#[allow(dead_code)]
pub enum ScanProgress {
    /// Scan has started
    Started,

    /// Quick counting phase progress
    Counting {
        /// Number of items counted so far
        items_counted: u64,
        /// Current path being enumerated
        current_path: PathBuf,
    },

    /// Counting phase complete, starting analysis
    CountingComplete {
        /// Total items found during counting
        total_items: u64,
    },

    /// Currently scanning a path (analysis phase)
    Scanning {
        /// The current path being scanned
        path: PathBuf,
        /// Number of files processed so far
        files_found: u64,
        /// Estimated total files (from counting phase)
        estimated_total: u64,
        /// Bytes processed so far
        bytes_processed: u64,
    },

    /// A new node was discovered during scan (for streaming display)
    NodeDiscovered {
        /// The discovered file/directory node
        node: FileNode,
        /// Path of the parent directory
        parent_path: PathBuf,
    },

    /// Building the tree structure (after analysis)
    Building {
        /// Number of items to process
        total_items: u64,
    },

    /// Scan completed successfully
    Completed {
        /// Total number of files scanned
        total_files: u64,
        /// Total size of all files in bytes
        total_size: u64,
        /// The completed file tree (for JSON mode compatibility)
        tree: FileTree,
    },

    /// An error occurred during scanning
    Error {
        /// The path where the error occurred
        path: PathBuf,
        /// Description of the error
        error: String,
    },
}
