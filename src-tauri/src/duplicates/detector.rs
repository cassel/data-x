use crate::duplicates::hasher::{full_hash, partial_hash};
use rayon::prelude::*;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use tauri::{AppHandle, Emitter};
use walkdir::WalkDir;

/// Configuration for duplicate scan
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DuplicateScanConfig {
    pub min_size: u64,          // Minimum file size to consider (default 1KB)
    pub include_hidden: bool,    // Include hidden files
}

impl Default for DuplicateScanConfig {
    fn default() -> Self {
        Self {
            min_size: 1024, // 1KB
            include_hidden: false,
        }
    }
}

/// Progress update for duplicate scan
#[derive(Debug, Clone, Serialize)]
pub struct DuplicateScanProgress {
    pub phase: String,
    pub files_processed: u64,
    pub total_files: u64,
    pub current_file: String,
}

/// A single file entry
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DuplicateFile {
    pub path: String,
    pub size: u64,
    pub modified: i64,
}

/// A group of duplicate files
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DuplicateGroup {
    pub hash: String,
    pub size: u64,
    pub files: Vec<DuplicateFile>,
}

/// Result of duplicate scan
#[derive(Debug, Clone, Serialize)]
pub struct DuplicateScanResult {
    pub groups: Vec<DuplicateGroup>,
    pub total_duplicates: u64,
    pub wasted_space: u64,
}

/// Detect duplicate files in a directory
pub fn find_duplicates(
    app: &AppHandle,
    path: &Path,
    config: DuplicateScanConfig,
    cancel_flag: Arc<AtomicBool>,
) -> Result<DuplicateScanResult, String> {
    let files_processed = Arc::new(AtomicU64::new(0));

    // Phase 1: Collect all files and group by size
    emit_progress(app, "Scanning files...", 0, 0, "");

    let mut size_groups: HashMap<u64, Vec<PathBuf>> = HashMap::new();
    let mut total_files = 0u64;

    for entry in WalkDir::new(path)
        .follow_links(false)
        .into_iter()
        .filter_entry(|e| {
            // Skip hidden files if not included
            if !config.include_hidden {
                if let Some(name) = e.file_name().to_str() {
                    if name.starts_with('.') {
                        return false;
                    }
                }
            }
            true
        })
    {
        if cancel_flag.load(Ordering::Relaxed) {
            return Err("Scan cancelled".to_string());
        }

        let entry = match entry {
            Ok(e) => e,
            Err(_) => continue,
        };

        // Skip directories and symlinks
        let file_type = entry.file_type();
        if file_type.is_dir() || file_type.is_symlink() {
            continue;
        }

        let metadata = match entry.metadata() {
            Ok(m) => m,
            Err(_) => continue,
        };

        let size = metadata.len();

        // Skip files smaller than min_size
        if size < config.min_size {
            continue;
        }

        total_files += 1;
        size_groups
            .entry(size)
            .or_default()
            .push(entry.path().to_path_buf());

        // Emit progress every 1000 files
        if total_files % 1000 == 0 {
            emit_progress(
                app,
                "Scanning files...",
                total_files,
                total_files,
                entry.path().to_string_lossy().as_ref(),
            );
        }
    }

    // Remove size groups with only one file (no possible duplicates)
    size_groups.retain(|_, files| files.len() > 1);

    let potential_duplicates: u64 = size_groups.values().map(|v| v.len() as u64).sum();
    emit_progress(
        app,
        "Computing partial hashes...",
        0,
        potential_duplicates,
        "",
    );

    // Phase 2: Compute partial hashes for size groups
    files_processed.store(0, Ordering::Relaxed);
    let mut partial_hash_groups: HashMap<(u64, String), Vec<PathBuf>> = HashMap::new();

    for (size, files) in size_groups.iter() {
        if cancel_flag.load(Ordering::Relaxed) {
            return Err("Scan cancelled".to_string());
        }

        for file_path in files {
            let processed = files_processed.fetch_add(1, Ordering::Relaxed);

            if processed % 100 == 0 {
                emit_progress(
                    app,
                    "Computing partial hashes...",
                    processed,
                    potential_duplicates,
                    file_path.to_string_lossy().as_ref(),
                );
            }

            let hash = match partial_hash(file_path) {
                Ok(h) => h,
                Err(_) => continue,
            };

            partial_hash_groups
                .entry((*size, hash))
                .or_default()
                .push(file_path.clone());
        }
    }

    // Remove partial hash groups with only one file
    partial_hash_groups.retain(|_, files| files.len() > 1);

    let candidates: u64 = partial_hash_groups.values().map(|v| v.len() as u64).sum();
    emit_progress(app, "Computing full hashes...", 0, candidates, "");

    // Phase 3: Compute full hashes for candidates
    files_processed.store(0, Ordering::Relaxed);

    // Use parallel processing for full hashes
    let full_hash_results: Vec<_> = partial_hash_groups
        .par_iter()
        .flat_map(|((size, _), files)| {
            if cancel_flag.load(Ordering::Relaxed) {
                return vec![];
            }

            files
                .par_iter()
                .filter_map(|file_path| {
                    let processed = files_processed.fetch_add(1, Ordering::Relaxed);

                    if processed % 50 == 0 {
                        // Can't emit from parallel context easily, skip progress updates here
                    }

                    let hash = match full_hash(file_path) {
                        Ok(h) => h,
                        Err(_) => return None,
                    };

                    let modified = fs::metadata(file_path)
                        .ok()
                        .and_then(|m| m.modified().ok())
                        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                        .map(|d| d.as_secs() as i64)
                        .unwrap_or(0);

                    Some((hash, *size, file_path.clone(), modified))
                })
                .collect::<Vec<_>>()
        })
        .collect();

    // Group by full hash
    let mut full_hash_groups: HashMap<String, Vec<(PathBuf, u64, i64)>> = HashMap::new();
    for (hash, size, path, modified) in full_hash_results {
        full_hash_groups
            .entry(hash)
            .or_default()
            .push((path, size, modified));
    }

    // Remove groups with only one file and build result
    full_hash_groups.retain(|_, files| files.len() > 1);

    let mut groups: Vec<DuplicateGroup> = full_hash_groups
        .into_iter()
        .map(|(hash, files)| {
            let size = files.first().map(|(_, s, _)| *s).unwrap_or(0);
            let file_entries: Vec<DuplicateFile> = files
                .into_iter()
                .map(|(path, size, modified)| DuplicateFile {
                    path: path.to_string_lossy().to_string(),
                    size,
                    modified,
                })
                .collect();

            DuplicateGroup {
                hash,
                size,
                files: file_entries,
            }
        })
        .collect();

    // Sort groups by wasted space (largest first)
    groups.sort_by(|a, b| {
        let waste_a = a.size * (a.files.len() as u64 - 1);
        let waste_b = b.size * (b.files.len() as u64 - 1);
        waste_b.cmp(&waste_a)
    });

    // Sort files within each group by modified time (oldest first = suggested original)
    for group in &mut groups {
        group.files.sort_by(|a, b| a.modified.cmp(&b.modified));
    }

    // Calculate totals
    let total_duplicates: u64 = groups.iter().map(|g| g.files.len() as u64 - 1).sum();
    let wasted_space: u64 = groups
        .iter()
        .map(|g| g.size * (g.files.len() as u64 - 1))
        .sum();

    emit_progress(app, "Complete", total_files, total_files, "");

    Ok(DuplicateScanResult {
        groups,
        total_duplicates,
        wasted_space,
    })
}

fn emit_progress(app: &AppHandle, phase: &str, processed: u64, total: u64, current: &str) {
    let progress = DuplicateScanProgress {
        phase: phase.to_string(),
        files_processed: processed,
        total_files: total,
        current_file: current.to_string(),
    };
    let _ = app.emit("duplicate-scan-progress", progress);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_config() {
        let config = DuplicateScanConfig::default();
        assert_eq!(config.min_size, 1024);
        assert!(!config.include_hidden);
    }
}
