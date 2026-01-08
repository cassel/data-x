//! Disk space information module.
//!
//! Provides cross-platform disk space retrieval using the fs2 crate.

use std::path::Path;
use fs2::statvfs;

/// Information about disk space for a mount point.
#[derive(Debug, Clone, Copy, Default)]
pub struct DiskSpaceInfo {
    /// Total disk capacity in bytes
    pub total: u64,
    /// Used space in bytes
    pub used: u64,
    /// Free/available space in bytes
    #[allow(dead_code)]
    pub free: u64,
}

impl DiskSpaceInfo {
    /// Returns the usage percentage (0.0 to 100.0)
    #[allow(dead_code)]
    pub fn usage_percent(&self) -> f64 {
        if self.total == 0 {
            0.0
        } else {
            (self.used as f64 / self.total as f64) * 100.0
        }
    }
}

/// Get disk space information for the mount point containing the given path.
///
/// This uses the fs2 crate which works on Unix (via statvfs) and Windows.
///
/// # Arguments
/// * `path` - Any path on the filesystem. The function will get info for the
///            mount point containing this path.
///
/// # Returns
/// * `Some(DiskSpaceInfo)` - Disk space information if successful
/// * `None` - If the path doesn't exist or disk info couldn't be retrieved
pub fn get_disk_space<P: AsRef<Path>>(path: P) -> Option<DiskSpaceInfo> {
    let path = path.as_ref();

    // Ensure path exists
    if !path.exists() {
        return None;
    }

    // Use fs2::statvfs to get filesystem stats
    // This works on the mount point containing the given path
    match statvfs(path) {
        Ok(stats) => {
            let total = stats.total_space();
            let free = stats.available_space();
            let used = total.saturating_sub(free);

            Some(DiskSpaceInfo {
                total,
                used,
                free,
            })
        }
        Err(_) => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::env;

    #[test]
    fn test_get_disk_space_current_dir() {
        let current_dir = env::current_dir().expect("Failed to get current directory");
        let info = get_disk_space(&current_dir);

        assert!(info.is_some(), "Should be able to get disk space for current directory");

        let info = info.unwrap();
        assert!(info.total > 0, "Total space should be greater than 0");
        assert!(info.free <= info.total, "Free space should be <= total space");
        assert!(info.used <= info.total, "Used space should be <= total space");
    }

    #[test]
    fn test_get_disk_space_nonexistent() {
        let info = get_disk_space("/this/path/definitely/does/not/exist/xyz123");
        assert!(info.is_none(), "Should return None for nonexistent path");
    }

    #[test]
    fn test_usage_percent() {
        let info = DiskSpaceInfo {
            total: 1000,
            used: 750,
            free: 250,
        };
        assert!((info.usage_percent() - 75.0).abs() < 0.01);

        let empty_info = DiskSpaceInfo::default();
        assert_eq!(empty_info.usage_percent(), 0.0);
    }
}
