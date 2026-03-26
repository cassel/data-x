//! File system scanner with progress events

use std::fs;
use std::path::Path;
use std::sync::atomic::{AtomicU64, AtomicBool, Ordering};
use std::sync::Arc;
use rayon::prelude::*;
use walkdir::WalkDir;
use tauri::{AppHandle, Emitter};
use serde::Serialize;

use crate::types::FileNode;

static NODE_ID_COUNTER: AtomicU64 = AtomicU64::new(1);

fn next_id() -> u64 {
    NODE_ID_COUNTER.fetch_add(1, Ordering::SeqCst)
}

#[derive(Clone, Serialize)]
pub struct ScanProgress {
    pub files_scanned: u64,
    pub total_files: u64,
    pub current_path: String,
    pub bytes_scanned: u64,
}

/// Quick count of files in a directory (for progress bar)
pub fn count_files_quick(path: &Path) -> u64 {
    WalkDir::new(path)
        .into_iter()
        .filter_map(|e| e.ok())
        .count() as u64
}

/// Scan a directory with progress events
pub fn scan_directory_with_progress(
    path: &Path,
    max_depth: Option<usize>,
    app_handle: Option<&AppHandle>,
    cancel_flag: Option<Arc<AtomicBool>>,
) -> Result<FileNode, String> {
    if !path.exists() {
        return Err(format!("Path does not exist: {}", path.display()));
    }

    let metadata = fs::metadata(path).map_err(|e| e.to_string())?;

    if !metadata.is_dir() {
        // Single file
        let name = path.file_name()
            .map(|n| n.to_string_lossy().to_string())
            .unwrap_or_else(|| path.display().to_string());
        let extension = path.extension().map(|e| e.to_string_lossy().to_string());
        let is_hidden = name.starts_with('.');

        return Ok(FileNode {
            id: next_id(),
            name,
            path: path.display().to_string(),
            size: metadata.len(),
            is_dir: false,
            is_hidden,
            extension,
            children: vec![],
            file_count: 1,
        });
    }

    // Quick file count for progress
    let total_files = if app_handle.is_some() {
        count_files_quick(path)
    } else {
        0
    };

    // Progress counter
    let files_scanned = Arc::new(AtomicU64::new(0));
    let bytes_scanned = Arc::new(AtomicU64::new(0));

    // Directory - scan recursively
    scan_directory_recursive(
        path,
        0,
        max_depth,
        app_handle,
        cancel_flag,
        total_files,
        &files_scanned,
        &bytes_scanned,
    )
}

fn scan_directory_recursive(
    path: &Path,
    depth: usize,
    max_depth: Option<usize>,
    app_handle: Option<&AppHandle>,
    cancel_flag: Option<Arc<AtomicBool>>,
    total_files: u64,
    files_scanned: &Arc<AtomicU64>,
    bytes_scanned: &Arc<AtomicU64>,
) -> Result<FileNode, String> {
    // Check for cancellation
    if let Some(ref flag) = cancel_flag {
        if flag.load(Ordering::Relaxed) {
            return Err("Scan cancelled".to_string());
        }
    }

    let name = path.file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_else(|| path.display().to_string());

    let is_hidden = name.starts_with('.');

    // Check max depth
    if let Some(max) = max_depth {
        if depth >= max {
            // Return directory with estimated size
            let size = estimate_dir_size(path);
            return Ok(FileNode {
                id: next_id(),
                name,
                path: path.display().to_string(),
                size,
                is_dir: true,
                is_hidden,
                extension: None,
                children: vec![],
                file_count: 0,
            });
        }
    }

    // Read directory entries
    let entries: Vec<_> = match fs::read_dir(path) {
        Ok(entries) => entries.filter_map(|e| e.ok()).collect(),
        Err(_) => {
            // Permission denied or other error - return empty dir
            return Ok(FileNode {
                id: next_id(),
                name,
                path: path.display().to_string(),
                size: 0,
                is_dir: true,
                is_hidden,
                extension: None,
                children: vec![],
                file_count: 0,
            });
        }
    };

    // Process entries (sequentially for better progress updates, parallel for speed)
    let children: Vec<FileNode> = if depth < 2 {
        // Sequential for top levels (better progress updates)
        entries
            .iter()
            .filter_map(|entry| {
                process_entry(
                    entry,
                    depth,
                    max_depth,
                    app_handle,
                    cancel_flag.clone(),
                    total_files,
                    files_scanned,
                    bytes_scanned,
                )
            })
            .collect()
    } else {
        // Parallel for deeper levels
        entries
            .par_iter()
            .filter_map(|entry| {
                process_entry(
                    entry,
                    depth,
                    max_depth,
                    app_handle,
                    cancel_flag.clone(),
                    total_files,
                    files_scanned,
                    bytes_scanned,
                )
            })
            .collect()
    };

    // Calculate totals
    let total_size: u64 = children.iter().map(|c| c.size).sum();
    let file_count: u64 = children.iter().map(|c| c.file_count).sum();

    // Sort children: directories first, then by size descending
    let mut sorted_children = children;
    sorted_children.sort_by(|a, b| {
        match (a.is_dir, b.is_dir) {
            (true, false) => std::cmp::Ordering::Less,
            (false, true) => std::cmp::Ordering::Greater,
            _ => b.size.cmp(&a.size),
        }
    });

    Ok(FileNode {
        id: next_id(),
        name,
        path: path.display().to_string(),
        size: total_size,
        is_dir: true,
        is_hidden,
        extension: None,
        children: sorted_children,
        file_count,
    })
}

fn process_entry(
    entry: &fs::DirEntry,
    depth: usize,
    max_depth: Option<usize>,
    app_handle: Option<&AppHandle>,
    cancel_flag: Option<Arc<AtomicBool>>,
    total_files: u64,
    files_scanned: &Arc<AtomicU64>,
    bytes_scanned: &Arc<AtomicU64>,
) -> Option<FileNode> {
    let entry_path = entry.path();
    let entry_name = entry.file_name().to_string_lossy().to_string();
    let entry_hidden = entry_name.starts_with('.');

    let metadata = entry.metadata().ok()?;
    let size = metadata.len();

    // Update progress
    let scanned = files_scanned.fetch_add(1, Ordering::Relaxed) + 1;
    bytes_scanned.fetch_add(size, Ordering::Relaxed);

    // Emit progress event every 100 files
    if scanned % 100 == 0 {
        if let Some(app) = app_handle {
            let _ = app.emit("scan-progress", ScanProgress {
                files_scanned: scanned,
                total_files,
                current_path: entry_path.display().to_string(),
                bytes_scanned: bytes_scanned.load(Ordering::Relaxed),
            });
        }
    }

    if metadata.is_dir() {
        // Recursively scan subdirectory
        scan_directory_recursive(
            &entry_path,
            depth + 1,
            max_depth,
            app_handle,
            cancel_flag,
            total_files,
            files_scanned,
            bytes_scanned,
        ).ok()
    } else {
        // File
        let extension = entry_path.extension().map(|e| e.to_string_lossy().to_string());
        Some(FileNode {
            id: next_id(),
            name: entry_name,
            path: entry_path.display().to_string(),
            size,
            is_dir: false,
            is_hidden: entry_hidden,
            extension,
            children: vec![],
            file_count: 1,
        })
    }
}

/// Quick size estimation for max_depth exceeded directories
fn estimate_dir_size(path: &Path) -> u64 {
    WalkDir::new(path)
        .into_iter()
        .filter_map(|e| e.ok())
        .filter_map(|e| e.metadata().ok())
        .filter(|m| m.is_file())
        .map(|m| m.len())
        .sum()
}

/// Get disk space information
pub fn get_disk_space(path: &Path) -> Option<crate::types::DiskInfo> {
    use fs2::available_space;
    use fs2::total_space;

    let total = total_space(path).ok()?;
    let available = available_space(path).ok()?;
    let used = total.saturating_sub(available);

    // Get mount point (simplified - just use root)
    let mount_point = if cfg!(target_os = "macos") {
        "/".to_string()
    } else {
        path.display().to_string()
    };

    Some(crate::types::DiskInfo {
        total,
        used,
        available,
        mount_point,
    })
}
