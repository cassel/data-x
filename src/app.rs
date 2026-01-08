use std::collections::HashSet;
use std::path::PathBuf;
use std::sync::mpsc::{self, Receiver, TryRecvError};
use std::thread;
use std::time::{Duration, Instant};

use indextree::NodeId;

use crate::remote::{RemoteScanner, SshTarget};
use crate::scanner::{get_disk_space, DiskSpaceInfo, ScanOptions, ScanProgress, Scanner};
use crate::tree::FileTree;
use crate::ui::{ColorScheme, Command, ConfirmAction, FileCategory, InputMode, SortBy, TreemapRect, ViewMode};

/// Application state
pub struct App {
    // Core data
    pub tree: Option<FileTree>,
    pub root_path: PathBuf,

    // View state
    pub selected_index: usize,
    pub scroll_offset: usize,
    pub expanded_nodes: HashSet<NodeId>,
    pub visible_node_ids: Vec<NodeId>,

    // UI state
    pub color_scheme: ColorScheme,
    pub show_hidden: bool,
    pub sort_by: SortBy,
    pub search_query: String,
    pub path_input: String,
    pub input_mode: InputMode,
    pub view_mode: ViewMode,
    pub treemap_root: Option<NodeId>,
    pub active_filter: FileCategory,

    // Treemap interaction state
    pub treemap_rects: Vec<TreemapRect>,
    #[allow(dead_code)]
    pub treemap_selected_idx: usize,
    #[allow(dead_code)]
    pub treemap_focused: bool,
    pub last_click: Option<(Instant, (u16, u16))>,
    pub breadcrumb_items: Vec<crate::ui::BreadcrumbItem>,
    pub breadcrumb_y: u16,  // Y coordinate of breadcrumb row for click detection

    // Mouse hover state
    pub mouse_pos: Option<(u16, u16)>,  // Current mouse position (x, y)
    pub hovered_node: Option<NodeId>,   // Node currently under cursor

    // Disk space info
    pub disk_info: Option<DiskSpaceInfo>,

    // File type statistics (calculated after scan)
    pub file_type_stats: Option<crate::ui::AggregatedStats>,

    // Stats panel visibility toggle
    pub show_stats: bool,

    // Scan state
    pub scan_state: ScanState,
    pub scan_progress: ScanProgressInfo,
    progress_receiver: Option<Receiver<ScanProgress>>,

    // Animation
    pub spinner_frame: usize,
    pub last_spinner_update: Instant,

    // Flags
    pub should_quit: bool,
    pub needs_refresh: bool,
}

#[derive(Clone, PartialEq)]
pub enum ScanState {
    Idle,
    Scanning,
    Complete,
    Error(String),
}

/// Scan phase for UI display
#[derive(Clone, Copy, PartialEq, Eq, Default)]
#[allow(dead_code)]
pub enum ScanPhase {
    #[default]
    Idle,
    Counting,
    Analyzing,
    Building,
    Complete,
}

#[derive(Clone, Default)]
pub struct ScanProgressInfo {
    pub phase: ScanPhase,
    pub files_found: u64,
    pub current_path: String,
    pub total_files: u64,
    pub total_size: u64,
    pub estimated_total: u64,
    pub bytes_processed: u64,
    pub start_time: Option<std::time::Instant>,
    #[allow(dead_code)]
    pub counting_start: Option<std::time::Instant>,
    pub analyzing_start: Option<std::time::Instant>,
    pub items_per_second: f64,
    pub bytes_per_second: f64,
}

impl ScanProgressInfo {
    /// Calculate estimated time remaining in seconds
    pub fn eta_seconds(&self) -> Option<f64> {
        if self.phase != ScanPhase::Analyzing || self.items_per_second <= 0.0 {
            return None;
        }

        let remaining = self.estimated_total.saturating_sub(self.files_found);
        if remaining == 0 {
            return Some(0.0);
        }

        Some(remaining as f64 / self.items_per_second)
    }

    /// Get progress percentage (0.0 to 1.0)
    pub fn progress_percent(&self) -> f64 {
        match self.phase {
            ScanPhase::Idle => 0.0,
            ScanPhase::Counting => {
                // Indeterminate during counting
                0.15
            }
            ScanPhase::Analyzing => {
                if self.estimated_total == 0 {
                    0.5
                } else {
                    // Allow going over 100% then cap - counting vs analyzing may differ slightly
                    (self.files_found as f64 / self.estimated_total as f64).min(1.0)
                }
            }
            ScanPhase::Building => 0.98,
            ScanPhase::Complete => 1.0,
        }
    }

    /// Format ETA as human-readable string
    pub fn eta_string(&self) -> String {
        match self.eta_seconds() {
            Some(secs) if secs < 1.0 => "< 1s".to_string(),
            Some(secs) if secs < 60.0 => format!("~{}s", secs as u64),
            Some(secs) if secs < 3600.0 => format!("~{}m {}s", (secs / 60.0) as u64, (secs % 60.0) as u64),
            Some(secs) => format!("~{}h {}m", (secs / 3600.0) as u64, ((secs % 3600.0) / 60.0) as u64),
            None => "calculating...".to_string(),
        }
    }

    /// Format speed as human-readable string
    pub fn speed_string(&self) -> String {
        if self.items_per_second > 0.0 {
            format!("{:.0} files/s", self.items_per_second)
        } else {
            "-- files/s".to_string()
        }
    }
}

impl App {
    pub fn new(root_path: PathBuf, color_scheme: ColorScheme) -> Self {
        Self {
            tree: None,
            root_path,
            selected_index: 0,
            scroll_offset: 0,
            expanded_nodes: HashSet::new(),
            visible_node_ids: Vec::new(),
            color_scheme,
            show_hidden: false,
            sort_by: SortBy::Size,
            search_query: String::new(),
            path_input: String::new(),
            input_mode: InputMode::Normal,
            view_mode: ViewMode::Split,
            treemap_root: None,
            active_filter: FileCategory::All,
            treemap_rects: Vec::new(),
            treemap_selected_idx: 0,
            treemap_focused: false,
            last_click: None,
            breadcrumb_items: Vec::new(),
            breadcrumb_y: 0,
            mouse_pos: None,
            hovered_node: None,
            disk_info: None,
            file_type_stats: None,
            show_stats: false,
            scan_state: ScanState::Idle,
            scan_progress: ScanProgressInfo::default(),
            progress_receiver: None,
            spinner_frame: 0,
            last_spinner_update: Instant::now(),
            should_quit: false,
            needs_refresh: true,
        }
    }

    /// Start scanning in background thread
    pub fn start_scan(&mut self, options: ScanOptions) {
        self.scan_state = ScanState::Scanning;
        self.scan_progress = ScanProgressInfo::default();

        let (tx, rx) = mpsc::sync_channel(1000);
        self.progress_receiver = Some(rx);

        let root_path = options.root_path.clone();

        thread::spawn(move || {
            let scanner = Scanner::new(options, tx);
            let result = scanner.scan();

            // Result is sent via channel as Completed or Error
            drop(result);
        });

        self.root_path = root_path;
    }

    /// Start remote scanning via SSH in background thread
    pub fn start_remote_scan(&mut self, target: SshTarget) {
        self.scan_state = ScanState::Scanning;
        self.scan_progress = ScanProgressInfo::default();
        self.scan_progress.phase = ScanPhase::Analyzing;
        self.scan_progress.start_time = Some(Instant::now());

        let (tx, rx) = mpsc::sync_channel(1000);
        self.progress_receiver = Some(rx);

        thread::spawn(move || {
            let scanner = RemoteScanner::new(target, tx);
            let result = scanner.scan();

            // Result is sent via channel as Completed or Error
            drop(result);
        });
    }

    /// Check for progress updates (non-blocking)
    pub fn update(&mut self) {
        // Update spinner animation
        if self.last_spinner_update.elapsed() >= Duration::from_millis(80) {
            self.spinner_frame = (self.spinner_frame + 1) % 10;
            self.last_spinner_update = Instant::now();
        }

        // Collect progress messages first to avoid borrow issues
        let mut messages: Vec<ScanProgress> = Vec::new();
        let mut receiver_disconnected = false;

        if let Some(ref receiver) = self.progress_receiver {
            loop {
                match receiver.try_recv() {
                    Ok(progress) => messages.push(progress),
                    Err(TryRecvError::Empty) => {
                        break;
                    }
                    Err(TryRecvError::Disconnected) => {
                        receiver_disconnected = true;
                        break;
                    }
                }
            }
        }

        // Process collected messages
        for progress in messages {
            match progress {
                ScanProgress::Started => {
                    self.scan_state = ScanState::Scanning;
                    self.scan_progress.phase = ScanPhase::Analyzing;
                    self.scan_progress.start_time = Some(Instant::now());
                    self.scan_progress.analyzing_start = Some(Instant::now());
                }
                ScanProgress::Counting { items_counted, current_path } => {
                    // Legacy - not used in single-pass mode
                    self.scan_progress.files_found = items_counted;
                    self.scan_progress.current_path = current_path.to_string_lossy().to_string();
                }
                ScanProgress::CountingComplete { total_items } => {
                    // Legacy - not used in single-pass mode
                    self.scan_progress.estimated_total = total_items;
                }
                ScanProgress::Scanning { path, files_found, estimated_total, bytes_processed } => {
                    self.scan_progress.phase = ScanPhase::Analyzing;
                    self.scan_progress.files_found = files_found;
                    self.scan_progress.estimated_total = estimated_total;
                    self.scan_progress.bytes_processed = bytes_processed;
                    self.scan_progress.current_path = path.to_string_lossy().to_string();

                    // Calculate speed
                    if let Some(start) = self.scan_progress.analyzing_start {
                        let elapsed = start.elapsed().as_secs_f64();
                        if elapsed > 0.3 {
                            let new_speed = files_found as f64 / elapsed;
                            // Smooth the speed calculation
                            if self.scan_progress.items_per_second > 0.0 {
                                self.scan_progress.items_per_second =
                                    self.scan_progress.items_per_second * 0.8 + new_speed * 0.2;
                            } else {
                                self.scan_progress.items_per_second = new_speed;
                            }
                            self.scan_progress.bytes_per_second = bytes_processed as f64 / elapsed;
                        }
                    }
                }
                ScanProgress::NodeDiscovered { node, parent_path } => {
                    // Handle incremental node discovery for streaming display
                    self.handle_node_discovered(node, parent_path);
                }
                ScanProgress::Building { .. } => {
                    // Building phase - just update the phase indicator
                    self.scan_progress.phase = ScanPhase::Building;
                }
                ScanProgress::Completed {
                    total_files,
                    total_size,
                    tree,
                } => {
                    self.scan_progress.phase = ScanPhase::Complete;
                    self.scan_progress.total_files = total_files;
                    self.scan_progress.total_size = total_size;
                    self.tree = Some(tree);
                    self.scan_state = ScanState::Complete;
                    self.progress_receiver = None;
                    self.needs_refresh = true;

                    // Get disk space info for the scanned path
                    self.disk_info = get_disk_space(&self.root_path);

                    // Calculate file type statistics
                    if let Some(ref tree) = self.tree {
                        self.file_type_stats = Some(crate::ui::AggregatedStats::from_tree(tree));
                    }

                    // Expand root node
                    if let Some(ref tree) = self.tree {
                        if let Some(root) = tree.root {
                            self.expanded_nodes.insert(root);
                        }
                    }
                    self.refresh_visible_nodes();
                }
                ScanProgress::Error { path: _, error: _ } => {
                    // Silently ignore scan errors - they're non-fatal and would corrupt TUI
                    // Common errors: permission denied, special files like /dev/fd/*
                }
            }
        }

        // Handle disconnection
        if receiver_disconnected {
            self.progress_receiver = None;
            if self.scan_state == ScanState::Scanning {
                self.scan_state = ScanState::Error("Scanner disconnected".to_string());
            }
        }
    }

    /// Handle a command from input
    pub fn handle_command(&mut self, cmd: Command) {
        match cmd {
            Command::Quit => {
                if matches!(self.input_mode, InputMode::Normal) {
                    self.should_quit = true;
                }
            }
            Command::MoveUp => {
                if self.selected_index > 0 {
                    self.selected_index -= 1;
                    self.ensure_visible();
                    self.sync_treemap_with_selection();
                }
            }
            Command::MoveDown => {
                if self.selected_index < self.visible_node_ids.len().saturating_sub(1) {
                    self.selected_index += 1;
                    self.ensure_visible();
                    self.sync_treemap_with_selection();
                }
            }
            Command::Enter => {
                if let Some(node_id) = self.get_selected_node_id() {
                    if let Some(ref tree) = self.tree {
                        if let Some(node) = tree.get_node(node_id) {
                            if node.is_dir {
                                if self.expanded_nodes.contains(&node_id) {
                                    self.expanded_nodes.remove(&node_id);
                                } else {
                                    self.expanded_nodes.insert(node_id);
                                }
                                self.refresh_visible_nodes();
                                self.sync_treemap_with_selection();
                            }
                        }
                    }
                }
            }
            Command::Back => {
                if let Some(node_id) = self.get_selected_node_id() {
                    if let Some(ref tree) = self.tree {
                        // If current node is expanded dir, collapse it
                        if self.expanded_nodes.contains(&node_id) {
                            self.expanded_nodes.remove(&node_id);
                            self.refresh_visible_nodes();
                            self.sync_treemap_with_selection();
                        } else if let Some(parent) = tree.get_parent(node_id) {
                            // Go to parent
                            if let Some(idx) = self
                                .visible_node_ids
                                .iter()
                                .position(|&id| id == parent)
                            {
                                self.selected_index = idx;
                                self.ensure_visible();
                                self.sync_treemap_with_selection();
                            }
                        }
                    }
                }
            }
            Command::GotoTop => {
                self.selected_index = 0;
                self.scroll_offset = 0;
                self.sync_treemap_with_selection();
            }
            Command::GotoBottom => {
                self.selected_index = self.visible_node_ids.len().saturating_sub(1);
                self.ensure_visible();
                self.sync_treemap_with_selection();
            }
            Command::ToggleHidden => {
                self.show_hidden = !self.show_hidden;
                self.refresh_visible_nodes();
            }
            Command::Sort(_new_sort) => {
                self.sort_by = match self.sort_by {
                    SortBy::Size => SortBy::Name,
                    SortBy::Name => SortBy::FileCount,
                    SortBy::FileCount => SortBy::Modified,
                    SortBy::Modified => SortBy::Size,
                };
                self.refresh_visible_nodes();
            }
            Command::StartSearch => {
                self.input_mode = InputMode::Search;
                self.search_query.clear();
            }
            Command::SearchInput(c) => {
                self.search_query.push(c);
                self.refresh_visible_nodes();
            }
            Command::SearchBackspace => {
                self.search_query.pop();
                self.refresh_visible_nodes();
            }
            Command::ConfirmSearch => {
                self.input_mode = InputMode::Normal;
            }
            Command::ExitSearch => {
                self.input_mode = InputMode::Normal;
                self.search_query.clear();
                self.refresh_visible_nodes();
            }
            Command::Delete => {
                self.input_mode = InputMode::Confirm(ConfirmAction::Delete);
            }
            Command::Confirm => {
                if let InputMode::Confirm(ref action) = self.input_mode {
                    match action {
                        ConfirmAction::Delete => {
                            self.delete_selected();
                        }
                        ConfirmAction::Quit => {
                            self.should_quit = true;
                        }
                    }
                }
                self.input_mode = InputMode::Normal;
            }
            Command::Cancel => {
                self.input_mode = InputMode::Normal;
            }
            Command::Rescan => {
                let options = ScanOptions {
                    root_path: self.root_path.clone(),
                    max_depth: None,
                    exclude_patterns: vec![],
                    cross_mount: true,
                    apparent_size: false,
                };
                self.start_scan(options);
            }
            Command::CopyPath => {
                self.copy_selected_path();
            }
            Command::OpenInFM => {
                self.open_selected_in_fm();
            }
            Command::Export => {
                self.export_json();
            }
            Command::Exclude => {
                self.exclude_selected();
            }
            Command::ToggleView => {
                self.view_mode = self.view_mode.next();
            }
            Command::SetViewMode(mode) => {
                self.view_mode = mode;
            }
            Command::PageUp => {
                let page_size = 20; // Will be adjusted by actual viewport size
                self.selected_index = self.selected_index.saturating_sub(page_size);
                self.ensure_visible();
                self.sync_treemap_with_selection();
            }
            Command::PageDown => {
                let page_size = 20;
                self.selected_index = (self.selected_index + page_size)
                    .min(self.visible_node_ids.len().saturating_sub(1));
                self.ensure_visible();
                self.sync_treemap_with_selection();
            }
            Command::DrillDown => {
                // Set selected directory as treemap root
                if let Some(node_id) = self.get_selected_node_id() {
                    if let Some(ref tree) = self.tree {
                        if let Some(node) = tree.get_node(node_id) {
                            if node.is_dir {
                                self.treemap_root = Some(node_id);
                                // Also expand the node in tree view
                                self.expanded_nodes.insert(node_id);
                                self.refresh_visible_nodes();
                            }
                        }
                    }
                }
            }
            Command::DrillUp => {
                // Go up one level in treemap root
                if let Some(current_root) = self.treemap_root {
                    if let Some(ref tree) = self.tree {
                        if let Some(parent) = tree.get_parent(current_root) {
                            self.treemap_root = Some(parent);
                        } else {
                            // At root, clear treemap_root
                            self.treemap_root = None;
                        }
                    }
                }
            }
            Command::ShowHelp => {
                self.input_mode = InputMode::Help;
            }
            Command::HideHelp => {
                self.input_mode = InputMode::Normal;
            }
            Command::StartPathInput => {
                self.input_mode = InputMode::PathInput;
                self.path_input = self.root_path.to_string_lossy().to_string();
            }
            Command::PathInput(c) => {
                if c == '\t' {
                    // Simple tab completion: expand ~ to home dir
                    if self.path_input.starts_with('~') {
                        if let Ok(home) = std::env::var("HOME") {
                            self.path_input = self.path_input.replacen('~', &home, 1);
                        }
                    }
                } else {
                    self.path_input.push(c);
                }
            }
            Command::PathBackspace => {
                self.path_input.pop();
            }
            Command::ConfirmPath => {
                let input = self.path_input.trim().to_string();

                // Check if it's a remote SSH path
                if crate::remote::is_remote_path(&input) {
                    if let Some(target) = SshTarget::parse(&input) {
                        self.input_mode = InputMode::Normal;
                        self.tree = None;
                        self.treemap_root = None;
                        self.selected_index = 0;
                        self.scroll_offset = 0;
                        self.expanded_nodes.clear();
                        self.visible_node_ids.clear();

                        // Update display path to show remote target
                        self.root_path = PathBuf::from(target.display());
                        self.start_remote_scan(target);
                    }
                    // If invalid SSH path, stay in input mode
                } else {
                    // Local path
                    let path = PathBuf::from(&input);
                    if path.exists() && path.is_dir() {
                        self.input_mode = InputMode::Normal;
                        self.tree = None;
                        self.treemap_root = None;
                        self.selected_index = 0;
                        self.scroll_offset = 0;
                        self.expanded_nodes.clear();
                        self.visible_node_ids.clear();

                        let options = ScanOptions {
                            root_path: path,
                            max_depth: None,
                            exclude_patterns: vec![],
                            cross_mount: true,
                            apparent_size: false,
                        };
                        self.start_scan(options);
                    }
                    // If path doesn't exist, stay in input mode
                }
            }
            Command::CancelPath => {
                self.input_mode = InputMode::Normal;
                self.path_input.clear();
            }
            Command::ToggleFilter(category) => {
                self.active_filter = category;
                self.refresh_visible_nodes();
            }
            Command::ToggleStats => {
                self.show_stats = !self.show_stats;
            }
            Command::ShowDetails | Command::Noop => {}
        }
    }

    /// Check if a file matches the active filter based on its extension.
    /// Directories are checked using has_matching_filter_descendant.
    pub fn matches_filter(&self, extension: Option<&str>) -> bool {
        if self.active_filter == FileCategory::All {
            return true;
        }

        match extension {
            Some(ext) => FileCategory::from_extension(ext) == self.active_filter,
            None => false, // Files without extension don't match specific filters
        }
    }

    /// Check if a directory contains any files matching the active filter.
    fn has_matching_filter_descendant(&self, tree: &FileTree, node_id: NodeId) -> bool {
        if self.active_filter == FileCategory::All {
            return true;
        }

        for child_id in tree.get_children(node_id) {
            if let Some(child) = tree.get_node(child_id) {
                if child.is_dir {
                    // Recursively check directories
                    if self.has_matching_filter_descendant(tree, child_id) {
                        return true;
                    }
                } else {
                    // Check file extension
                    if self.matches_filter(child.extension.as_deref()) {
                        return true;
                    }
                }
            }
        }
        false
    }

    /// Get currently selected node ID
    pub fn get_selected_node_id(&self) -> Option<NodeId> {
        self.visible_node_ids.get(self.selected_index).copied()
    }

    /// Refresh the list of visible nodes based on current state
    pub fn refresh_visible_nodes(&mut self) {
        self.visible_node_ids.clear();

        // Take the tree temporarily to avoid borrow conflicts
        if let Some(tree) = self.tree.take() {
            if let Some(root) = tree.root {
                self.collect_visible_nodes(&tree, root, 0);
            }
            self.tree = Some(tree);
        }

        // Clamp selected index
        if self.selected_index >= self.visible_node_ids.len() {
            self.selected_index = self.visible_node_ids.len().saturating_sub(1);
        }

        self.needs_refresh = false;
    }

    fn collect_visible_nodes(&mut self, tree: &FileTree, node_id: NodeId, _depth: usize) {
        if let Some(node) = tree.get_node(node_id) {
            // Filter hidden files
            if !self.show_hidden && node.is_hidden {
                return;
            }

            // Filter by search query
            if !self.search_query.is_empty() {
                let query_lower = self.search_query.to_lowercase();
                if !node.name_lower.contains(&query_lower) {
                    // Check if any descendant matches
                    let has_matching_descendant = self.has_matching_descendant(tree, node_id, &query_lower);
                    if !has_matching_descendant {
                        return;
                    }
                }
            }

            // Filter by file category
            if self.active_filter != FileCategory::All {
                if node.is_dir {
                    // Only show directory if it has matching descendants
                    if !self.has_matching_filter_descendant(tree, node_id) {
                        return;
                    }
                } else {
                    // Only show file if it matches the filter
                    if !self.matches_filter(node.extension.as_deref()) {
                        return;
                    }
                }
            }

            self.visible_node_ids.push(node_id);

            // If expanded, add children
            if self.expanded_nodes.contains(&node_id) {
                let mut children: Vec<NodeId> = tree.get_children(node_id);

                // Sort children
                children.sort_by(|&a, &b| {
                    let node_a = tree.get_node(a);
                    let node_b = tree.get_node(b);

                    match (node_a, node_b) {
                        (Some(na), Some(nb)) => match self.sort_by {
                            SortBy::Size => nb.size.cmp(&na.size),
                            SortBy::Name => na.name.to_lowercase().cmp(&nb.name.to_lowercase()),
                            SortBy::FileCount => nb.file_count.cmp(&na.file_count),
                            SortBy::Modified => nb.modified.cmp(&na.modified),
                        },
                        _ => std::cmp::Ordering::Equal,
                    }
                });

                for child_id in children {
                    self.collect_visible_nodes(tree, child_id, _depth + 1);
                }
            }
        }
    }

    fn has_matching_descendant(&self, tree: &FileTree, node_id: NodeId, query: &str) -> bool {
        for child_id in tree.get_children(node_id) {
            if let Some(child) = tree.get_node(child_id) {
                if child.name_lower.contains(query) {
                    return true;
                }
                if self.has_matching_descendant(tree, child_id, query) {
                    return true;
                }
            }
        }
        false
    }

    /// Ensure selected item is visible (scroll if needed)
    fn ensure_visible(&mut self) {
        let visible_height = 20; // Will be set properly during render
        if self.selected_index < self.scroll_offset {
            self.scroll_offset = self.selected_index;
        } else if self.selected_index >= self.scroll_offset + visible_height {
            self.scroll_offset = self.selected_index - visible_height + 1;
        }
    }

    /// Delete selected file/directory
    fn delete_selected(&mut self) {
        if let Some(node_id) = self.get_selected_node_id() {
            if let Some(ref tree) = self.tree {
                if let Some(node) = tree.get_node(node_id) {
                    let path = node.path.clone();
                    let is_dir = node.is_dir;

                    let result = if is_dir {
                        std::fs::remove_dir_all(&path)
                    } else {
                        std::fs::remove_file(&path)
                    };

                    match result {
                        Ok(_) => {
                            // Trigger rescan of parent
                            self.needs_refresh = true;
                            // For now, just rescan entirely
                            self.handle_command(Command::Rescan);
                        }
                        Err(e) => {
                            eprintln!("Delete failed: {}", e);
                        }
                    }
                }
            }
        }
    }

    /// Copy selected path to clipboard
    fn copy_selected_path(&self) {
        if let Some(node_id) = self.get_selected_node_id() {
            if let Some(ref tree) = self.tree {
                if let Some(node) = tree.get_node(node_id) {
                    let path_str = node.path.to_string_lossy().to_string();

                    match arboard::Clipboard::new() {
                        Ok(mut clipboard) => {
                            if clipboard.set_text(&path_str).is_err() {
                                eprintln!("Clipboard: {}", path_str);
                            }
                        }
                        Err(_) => {
                            eprintln!("Clipboard unavailable. Path: {}", path_str);
                        }
                    }
                }
            }
        }
    }

    /// Open selected item in file manager
    fn open_selected_in_fm(&self) {
        if let Some(node_id) = self.get_selected_node_id() {
            if let Some(ref tree) = self.tree {
                if let Some(node) = tree.get_node(node_id) {
                    let path = if node.is_dir {
                        &node.path
                    } else {
                        node.path.parent().unwrap_or(&node.path)
                    };

                    if let Err(e) = open::that(path) {
                        eprintln!("Failed to open: {}", e);
                    }
                }
            }
        }
    }

    /// Export tree to JSON
    fn export_json(&self) {
        if let Some(ref tree) = self.tree {
            use crate::export::{export_json, ExportOptions};

            let options = ExportOptions { top_n: None };
            let mut stdout = std::io::stdout();

            if let Err(e) = export_json(tree, &options, &mut stdout) {
                eprintln!("Export failed: {}", e);
            }
        }
    }

    /// Exclude selected node from calculations
    fn exclude_selected(&mut self) {
        if let Some(node_id) = self.get_selected_node_id() {
            if let Some(ref mut tree) = self.tree {
                if let Some(node) = tree.get_node_mut(node_id) {
                    node.excluded = !node.excluded;
                }
                tree.calculate_sizes();
                self.needs_refresh = true;
            }
        }
    }

    /// Get depth of a node in the tree
    #[allow(dead_code)]
    pub fn get_node_depth(&self, node_id: NodeId) -> usize {
        if let Some(ref tree) = self.tree {
            let mut depth = 0;
            let mut current = node_id;

            while let Some(parent) = tree.get_parent(current) {
                depth += 1;
                current = parent;
            }
            depth
        } else {
            0
        }
    }

    /// Find treemap rect at the given screen position.
    #[allow(dead_code)]
    pub fn find_treemap_rect_at(&self, x: u16, y: u16) -> Option<&TreemapRect> {
        self.treemap_rects.iter().find(|rect| rect.contains(x, y))
    }

    /// Update mouse position and detect which treemap block is being hovered.
    pub fn update_mouse_pos(&mut self, x: u16, y: u16) {
        self.mouse_pos = Some((x, y));
        self.update_hovered_node();
    }

    /// Update the hovered_node based on current mouse position.
    /// Uses treemap_rects to find which block the mouse is over.
    pub fn update_hovered_node(&mut self) {
        if let Some((x, y)) = self.mouse_pos {
            // Check if mouse is over any treemap block
            self.hovered_node = self.treemap_rects
                .iter()
                .find(|rect| rect.contains(x, y))
                .map(|rect| rect.node_id);
        } else {
            self.hovered_node = None;
        }
    }

    /// Clear mouse position when mouse leaves window or is irrelevant.
    #[allow(dead_code)]
    pub fn clear_mouse_pos(&mut self) {
        self.mouse_pos = None;
        self.hovered_node = None;
    }

    /// Handle single click on treemap - select the block at position.
    /// Returns true if a block was found and selected.
    pub fn handle_treemap_click(&mut self, x: u16, y: u16) -> bool {
        // Find which rect was clicked
        let node_id = self.treemap_rects
            .iter()
            .find(|rect| rect.contains(x, y))
            .map(|rect| rect.node_id);

        if let Some(node_id) = node_id {
            // Find the index of this node in visible_node_ids and select it
            if let Some(idx) = self.visible_node_ids.iter().position(|&id| id == node_id) {
                self.selected_index = idx;
                self.ensure_visible();
                return true;
            }

            // If not in visible nodes, expand path to it
            self.expand_to_node(node_id);
            if let Some(idx) = self.visible_node_ids.iter().position(|&id| id == node_id) {
                self.selected_index = idx;
                self.ensure_visible();
                return true;
            }
        }
        false
    }

    /// Handle double-click on treemap - enter directory if clicked on a directory.
    /// Returns true if entered a directory.
    pub fn handle_treemap_double_click(&mut self, x: u16, y: u16) -> bool {
        let rect_info = self.treemap_rects
            .iter()
            .find(|rect| rect.contains(x, y))
            .map(|rect| (rect.node_id, rect.is_dir));

        if let Some((node_id, is_dir)) = rect_info {
            if is_dir {
                // Set as treemap root and expand
                self.treemap_root = Some(node_id);
                self.expanded_nodes.insert(node_id);
                self.refresh_visible_nodes();

                // Select this node in tree view
                if let Some(idx) = self.visible_node_ids.iter().position(|&id| id == node_id) {
                    self.selected_index = idx;
                    self.ensure_visible();
                }
                return true;
            }
        }
        false
    }

    /// Sync treemap view with current tree selection.
    /// When a directory is selected, show its contents in treemap.
    /// When a file is selected, show its parent directory contents.
    pub fn sync_treemap_with_selection(&mut self) {
        if let Some(node_id) = self.get_selected_node_id() {
            if let Some(ref tree) = self.tree {
                if let Some(node) = tree.get_node(node_id) {
                    if node.is_dir {
                        // Directory selected - show its contents
                        self.treemap_root = Some(node_id);
                    } else {
                        // File selected - show parent directory contents
                        if let Some(parent_id) = tree.get_parent(node_id) {
                            self.treemap_root = Some(parent_id);
                        }
                    }
                }
            }
        }
    }

    /// Handle click on breadcrumb item - navigate to that level.
    /// Returns true if navigation occurred.
    pub fn handle_breadcrumb_click(&mut self, x: u16, y: u16) -> bool {
        // Check if click is within breadcrumb area (y within breadcrumb row range)
        // Breadcrumb bar is 3 rows tall with border, text is on the middle row
        if y < self.breadcrumb_y || y > self.breadcrumb_y + 2 {
            return false;
        }

        // Breadcrumb items store their x position and width
        for item in &self.breadcrumb_items {
            if x >= item.x && x < item.x + item.width {
                // Navigate to this node
                if let Some(node_id) = item.node_id {
                    // If clicking on current root, do nothing
                    if self.treemap_root == Some(node_id) {
                        return false;
                    }

                    // Check if this is the tree root
                    if self.tree.as_ref().and_then(|t| t.root) == Some(node_id) {
                        self.treemap_root = None;
                    } else {
                        self.treemap_root = Some(node_id);
                    }

                    // Expand and select this node
                    self.expanded_nodes.insert(node_id);
                    self.refresh_visible_nodes();

                    if let Some(idx) = self.visible_node_ids.iter().position(|&id| id == node_id) {
                        self.selected_index = idx;
                        self.ensure_visible();
                    }
                    return true;
                }
            }
        }
        false
    }

    /// Expand the tree view path to make a node visible.
    fn expand_to_node(&mut self, target_node_id: NodeId) {
        if let Some(ref tree) = self.tree {
            // Collect ancestors
            let mut ancestors = Vec::new();
            let mut current = target_node_id;
            while let Some(parent) = tree.get_parent(current) {
                ancestors.push(parent);
                current = parent;
            }

            // Expand all ancestors from root to parent
            for ancestor in ancestors.into_iter().rev() {
                self.expanded_nodes.insert(ancestor);
            }

            self.refresh_visible_nodes();
        }
    }

    /// Get spinner character for current frame
    pub fn spinner_char(&self) -> char {
        const SPINNER: &[char] = &['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];
        SPINNER[self.spinner_frame % SPINNER.len()]
    }

    /// Handle a newly discovered node during streaming scan.
    /// Adds the node to the tree and updates sizes incrementally.
    fn handle_node_discovered(&mut self, node: crate::tree::FileNode, parent_path: std::path::PathBuf) {
        // Initialize tree with root if this is the first node
        if self.tree.is_none() {
            // First node should be the root
            let mut tree = crate::tree::FileTree::with_root(node.path.clone());
            if let Some(root) = tree.root {
                // Update root node with the discovered node's properties
                if let Some(root_node) = tree.get_node_mut(root) {
                    root_node.size = node.size;
                    root_node.file_count = node.file_count;
                    root_node.modified = node.modified;
                    root_node.is_hidden = node.is_hidden;
                    root_node.is_symlink = node.is_symlink;
                    root_node.symlink_target = node.symlink_target;
                }
                self.expanded_nodes.insert(root);
            }
            self.tree = Some(tree);
            self.needs_refresh = true;
            self.refresh_visible_nodes();
            return;
        }

        // Add node as child of parent
        if let Some(ref mut tree) = self.tree {
            // Find parent node
            let parent_id = tree.find_by_path(&parent_path);

            if let Some(parent_id) = parent_id {
                // Add the new node as a child
                let size = node.size;
                let file_count = node.file_count;
                let _new_node_id = tree.add_child(parent_id, node);

                // Update sizes incrementally up the tree
                tree.add_size_to_ancestors(parent_id, size, file_count);

                // Update progress counters
                self.scan_progress.files_found += 1;
                self.scan_progress.total_size += size;

                self.needs_refresh = true;
            }
        }

        // Periodically refresh visible nodes (not every single node to avoid perf issues)
        if self.scan_progress.files_found % 100 == 0 {
            self.refresh_visible_nodes();
        }
    }

    /// Start a background refresh to check for filesystem changes.
    /// This runs a lightweight scan in the background while showing cached data.
    #[allow(dead_code)]
    pub fn start_background_refresh(&mut self, options: ScanOptions) {
        // Mark that we're doing a background refresh (not a full rescan)
        // For now, we just start a normal scan in the background
        // The UI will continue showing cached data until the new scan completes

        // Don't start background refresh if already scanning
        if self.scan_state == ScanState::Scanning {
            return;
        }

        // Start the scan - it will update the tree when complete
        self.start_scan(options);
    }
}
