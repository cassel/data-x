//! Type definitions for Tauri IPC

use serde::{Deserialize, Serialize};

/// File node for frontend consumption
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileNode {
    pub id: u64,
    pub name: String,
    pub path: String,
    pub size: u64,
    pub is_dir: bool,
    pub is_hidden: bool,
    pub extension: Option<String>,
    pub children: Vec<FileNode>,
    pub file_count: u64,
}

/// Category for file type coloring
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum FileCategory {
    Audio,
    Video,
    Image,
    Document,
    Code,
    Archive,
    Application,
    System,
    Other,
}

impl FileCategory {
    pub fn from_extension(ext: Option<&str>) -> Self {
        match ext.map(|e| e.to_lowercase()).as_deref() {
            Some("mp3") | Some("wav") | Some("flac") | Some("m4a") | Some("aac") | Some("ogg") => Self::Audio,
            Some("mp4") | Some("mkv") | Some("avi") | Some("mov") | Some("wmv") | Some("webm") => Self::Video,
            Some("jpg") | Some("jpeg") | Some("png") | Some("gif") | Some("bmp") | Some("svg") | Some("webp") | Some("heic") => Self::Image,
            Some("pdf") | Some("doc") | Some("docx") | Some("txt") | Some("rtf") | Some("xls") | Some("xlsx") | Some("ppt") => Self::Document,
            Some("rs") | Some("py") | Some("js") | Some("ts") | Some("go") | Some("c") | Some("cpp") | Some("java") | Some("swift") | Some("html") | Some("css") | Some("json") => Self::Code,
            Some("zip") | Some("tar") | Some("gz") | Some("rar") | Some("7z") | Some("dmg") | Some("iso") => Self::Archive,
            Some("app") | Some("exe") | Some("dll") | Some("so") | Some("dylib") => Self::Application,
            Some("sys") | Some("log") | Some("plist") | Some("db") => Self::System,
            _ => Self::Other,
        }
    }

    pub fn color(&self) -> &'static str {
        match self {
            Self::Audio => "#c864dc",    // Purple
            Self::Video => "#dc5050",    // Red
            Self::Image => "#64c864",    // Green
            Self::Document => "#6496dc", // Blue
            Self::Code => "#dcc850",     // Yellow
            Self::Archive => "#dc9650",  // Orange
            Self::Application => "#b4b4dc", // Light purple
            Self::System => "#969696",   // Gray
            Self::Other => "#788ca0",    // Blue-gray
        }
    }
}

/// Scan result for frontend
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScanResult {
    pub root: FileNode,
    pub total_files: u64,
    pub total_size: u64,
    pub scan_time_ms: u64,
}

/// Disk space info
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DiskInfo {
    pub total: u64,
    pub used: u64,
    pub available: u64,
    pub mount_point: String,
}

/// Scan progress event
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScanProgress {
    pub files_found: u64,
    pub current_path: String,
    pub percent: f32,
}
