//! Scanner module for traversing directories and building file trees.
//!
//! This module provides parallel directory scanning capabilities using
//! walkdir and rayon for efficient filesystem traversal.

mod disk_space;
mod progress;
mod walker;

pub use disk_space::{get_disk_space, DiskSpaceInfo};
pub use progress::ScanProgress;
pub use walker::{ScanOptions, Scanner};

use std::path::PathBuf;
use thiserror::Error;

/// Errors that can occur during directory scanning.
#[derive(Error, Debug)]
pub enum ScanError {
    /// Permission denied when accessing a path
    #[error("permission denied: {path}")]
    PermissionDenied {
        /// The path that could not be accessed
        path: PathBuf,
    },

    /// The specified path does not exist
    #[error("path not found: {path}")]
    PathNotFound {
        /// The path that was not found
        path: PathBuf,
    },

    /// An I/O error occurred while accessing a path
    #[error("I/O error at {path}: {source}")]
    IoError {
        /// The path where the error occurred
        path: PathBuf,
        /// The underlying I/O error
        #[source]
        source: std::io::Error,
    },

    /// The specified path is not a directory
    #[error("not a directory: {path}")]
    NotADirectory {
        /// The path that was expected to be a directory
        path: PathBuf,
    },

    /// The scan was interrupted
    #[error("scan interrupted")]
    Interrupted,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_error_display() {
        let err = ScanError::PermissionDenied {
            path: PathBuf::from("/secret"),
        };
        assert_eq!(err.to_string(), "permission denied: /secret");

        let err = ScanError::PathNotFound {
            path: PathBuf::from("/missing"),
        };
        assert_eq!(err.to_string(), "path not found: /missing");

        let err = ScanError::NotADirectory {
            path: PathBuf::from("/file.txt"),
        };
        assert_eq!(err.to_string(), "not a directory: /file.txt");

        let err = ScanError::Interrupted;
        assert_eq!(err.to_string(), "scan interrupted");
    }

    #[test]
    fn test_io_error() {
        let io_err = std::io::Error::new(std::io::ErrorKind::Other, "test error");
        let err = ScanError::IoError {
            path: PathBuf::from("/some/path"),
            source: io_err,
        };

        assert!(err.to_string().contains("/some/path"));
        assert!(err.to_string().contains("test error"));
    }
}
