//! Main GUI application struct and eframe::App implementation.
//!
//! This module contains the DataXApp struct which holds all application state
//! for the GUI version and implements the eframe::App trait for rendering.

use std::collections::HashSet;
use std::path::PathBuf;
use std::sync::mpsc::{self, Receiver, TryRecvError};
use std::thread;
use std::time::Instant;

use eframe::egui;
use indextree::NodeId;

use crate::scanner::{get_disk_space, DiskSpaceInfo, ScanOptions, ScanProgress, Scanner};
use crate::tree::FileTree;

/// View mode for the main display area in GUI.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum GuiViewMode {
    /// Tree view only (classic explorer style)
    #[default]
    Tree,
    /// Treemap visualization only
    Treemap,
    /// Split view: tree on left, treemap on right
    Split,
}

impl GuiViewMode {
    /// Cycle to the next view mode.
    pub fn next(self) -> Self {
        match self {
            GuiViewMode::Tree => GuiViewMode::Treemap,
            GuiViewMode::Treemap => GuiViewMode::Split,
            GuiViewMode::Split => GuiViewMode::Tree,
        }
    }

    /// Get display name for UI.
    pub fn display_name(&self) -> &'static str {
        match self {
            GuiViewMode::Tree => "Tree",
            GuiViewMode::Treemap => "Treemap",
            GuiViewMode::Split => "Split",
        }
    }
}

/// Scan state for tracking background scan progress.
#[derive(Clone, PartialEq)]
pub enum ScanState {
    /// No scan in progress.
    Idle,
    /// Scan is running.
    Scanning,
    /// Scan completed successfully.
    Complete,
    /// Scan encountered an error.
    Error(String),
}

/// Progress information during scanning.
#[derive(Clone, Default)]
pub struct ScanProgressInfo {
    /// Current phase of the scan.
    pub phase: ScanPhase,
    /// Number of files discovered so far.
    pub files_found: u64,
    /// Current path being scanned.
    pub current_path: String,
    /// Total files (after scan complete).
    pub total_files: u64,
    /// Total size in bytes.
    pub total_size: u64,
    /// Estimated total files (during scan).
    pub estimated_total: u64,
    /// Bytes processed so far.
    pub bytes_processed: u64,
    /// When the scan started.
    pub start_time: Option<Instant>,
    /// Items processed per second.
    pub items_per_second: f64,
}

/// Scan phase for progress display.
#[derive(Clone, Copy, PartialEq, Eq, Default)]
pub enum ScanPhase {
    #[default]
    Idle,
    Counting,
    Analyzing,
    Building,
    Complete,
}

impl ScanProgressInfo {
    /// Get progress percentage (0.0 to 1.0).
    pub fn progress_percent(&self) -> f32 {
        match self.phase {
            ScanPhase::Idle => 0.0,
            ScanPhase::Counting => 0.15,
            ScanPhase::Analyzing => {
                if self.estimated_total == 0 {
                    0.5
                } else {
                    (self.files_found as f32 / self.estimated_total as f32).min(1.0)
                }
            }
            ScanPhase::Building => 0.98,
            ScanPhase::Complete => 1.0,
        }
    }

    /// Format elapsed time.
    pub fn elapsed_string(&self) -> String {
        match self.start_time {
            Some(start) => {
                let elapsed = start.elapsed().as_secs();
                if elapsed < 60 {
                    format!("{}s", elapsed)
                } else {
                    format!("{}m {}s", elapsed / 60, elapsed % 60)
                }
            }
            None => "0s".to_string(),
        }
    }
}

/// Main application state for the GUI.
pub struct DataXApp {
    // Core data
    /// The file tree structure (None until scan completes).
    pub tree: Option<FileTree>,
    /// Root path being analyzed.
    pub root_path: PathBuf,

    // Selection and navigation
    /// Currently selected node in the tree.
    pub selected_node: Option<NodeId>,
    /// Set of expanded nodes in the tree view.
    pub expanded_nodes: HashSet<NodeId>,

    // View state
    /// Current view mode (Tree/Treemap/Split).
    pub view_mode: GuiViewMode,
    /// Whether to show the statistics panel.
    pub show_stats: bool,
    /// Current search/filter query.
    pub search_query: String,
    /// Whether to show hidden files.
    pub show_hidden: bool,

    // Disk info
    /// Disk space information for the scanned volume.
    pub disk_info: Option<DiskSpaceInfo>,

    // Scan state
    /// Current scan state.
    pub scan_state: ScanState,
    /// Scan progress information.
    pub scan_progress: ScanProgressInfo,
    /// Channel receiver for scan progress updates.
    progress_receiver: Option<Receiver<ScanProgress>>,

    // UI state
    /// Whether the left panel (tree) is visible.
    pub show_left_panel: bool,
    /// Whether the right panel (details/stats) is visible.
    pub show_right_panel: bool,
    /// Width of the left panel in pixels.
    pub left_panel_width: f32,
    /// Width of the right panel in pixels.
    pub right_panel_width: f32,
}

impl Default for DataXApp {
    fn default() -> Self {
        Self {
            tree: None,
            root_path: PathBuf::from("."),
            selected_node: None,
            expanded_nodes: HashSet::new(),
            view_mode: GuiViewMode::default(),
            show_stats: false,
            search_query: String::new(),
            show_hidden: false,
            disk_info: None,
            scan_state: ScanState::Idle,
            scan_progress: ScanProgressInfo::default(),
            progress_receiver: None,
            show_left_panel: true,
            show_right_panel: true,
            left_panel_width: 300.0,
            right_panel_width: 250.0,
        }
    }
}

impl DataXApp {
    /// Create a new DataXApp with the given root path.
    /// This is the primary constructor that accepts the eframe creation context.
    pub fn new(cc: &eframe::CreationContext<'_>, root_path: PathBuf) -> Self {
        // Configure default fonts and style
        let mut style = (*cc.egui_ctx.style()).clone();
        style.spacing.item_spacing = egui::vec2(8.0, 4.0);
        cc.egui_ctx.set_style(style);

        Self {
            root_path,
            ..Default::default()
        }
    }

    /// Create a new DataXApp with just a root path (for testing or when no cc is available).
    #[allow(dead_code)]
    pub fn new_simple(root_path: PathBuf) -> Self {
        Self {
            root_path,
            ..Default::default()
        }
    }

    /// Start scanning in a background thread.
    pub fn start_scan(&mut self, options: ScanOptions) {
        self.scan_state = ScanState::Scanning;
        self.scan_progress = ScanProgressInfo::default();
        self.scan_progress.start_time = Some(Instant::now());

        let (tx, rx) = mpsc::sync_channel(1000);
        self.progress_receiver = Some(rx);

        let root_path = options.root_path.clone();

        thread::spawn(move || {
            let scanner = Scanner::new(options, tx);
            let _result = scanner.scan();
        });

        self.root_path = root_path;
    }

    /// Check for progress updates from the scanner (non-blocking).
    pub fn poll_scan_progress(&mut self) {
        let mut messages: Vec<ScanProgress> = Vec::new();
        let mut receiver_disconnected = false;

        if let Some(ref receiver) = self.progress_receiver {
            loop {
                match receiver.try_recv() {
                    Ok(progress) => messages.push(progress),
                    Err(TryRecvError::Empty) => break,
                    Err(TryRecvError::Disconnected) => {
                        receiver_disconnected = true;
                        break;
                    }
                }
            }
        }

        // Process messages
        for progress in messages {
            match progress {
                ScanProgress::Started => {
                    self.scan_state = ScanState::Scanning;
                    self.scan_progress.phase = ScanPhase::Analyzing;
                    if self.scan_progress.start_time.is_none() {
                        self.scan_progress.start_time = Some(Instant::now());
                    }
                }
                ScanProgress::Counting { items_counted, current_path } => {
                    self.scan_progress.phase = ScanPhase::Counting;
                    self.scan_progress.files_found = items_counted;
                    self.scan_progress.current_path = current_path.to_string_lossy().to_string();
                }
                ScanProgress::CountingComplete { total_items } => {
                    self.scan_progress.estimated_total = total_items;
                }
                ScanProgress::Scanning {
                    path,
                    files_found,
                    estimated_total,
                    bytes_processed,
                } => {
                    self.scan_progress.phase = ScanPhase::Analyzing;
                    self.scan_progress.files_found = files_found;
                    self.scan_progress.estimated_total = estimated_total;
                    self.scan_progress.bytes_processed = bytes_processed;
                    self.scan_progress.current_path = path.to_string_lossy().to_string();

                    // Calculate speed
                    if let Some(start) = self.scan_progress.start_time {
                        let elapsed = start.elapsed().as_secs_f64();
                        if elapsed > 0.3 {
                            self.scan_progress.items_per_second = files_found as f64 / elapsed;
                        }
                    }
                }
                ScanProgress::NodeDiscovered { node: _, parent_path: _ } => {
                    // Handle streaming node discovery (for future incremental display)
                }
                ScanProgress::Building { .. } => {
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

                    // Get disk space info
                    self.disk_info = get_disk_space(&self.root_path);

                    // Expand root node
                    if let Some(ref tree) = self.tree {
                        if let Some(root) = tree.root {
                            self.expanded_nodes.insert(root);
                            self.selected_node = Some(root);
                        }
                    }
                }
                ScanProgress::Error { path: _, error: _ } => {
                    // Silently ignore individual file errors
                }
            }
        }

        if receiver_disconnected {
            self.progress_receiver = None;
            if self.scan_state == ScanState::Scanning {
                self.scan_state = ScanState::Error("Scanner disconnected".to_string());
            }
        }
    }

    /// Toggle expansion of a node.
    pub fn toggle_node(&mut self, node_id: NodeId) {
        if self.expanded_nodes.contains(&node_id) {
            self.expanded_nodes.remove(&node_id);
        } else {
            self.expanded_nodes.insert(node_id);
        }
    }

    /// Select a node.
    pub fn select_node(&mut self, node_id: NodeId) {
        self.selected_node = Some(node_id);
    }

    /// Get the currently selected node's data.
    pub fn get_selected_node_data(&self) -> Option<&crate::tree::FileNode> {
        self.selected_node
            .and_then(|id| self.tree.as_ref()?.get_node(id))
    }

    /// Format a size in bytes to human-readable string.
    pub fn format_size(bytes: u64) -> String {
        const KB: u64 = 1024;
        const MB: u64 = KB * 1024;
        const GB: u64 = MB * 1024;
        const TB: u64 = GB * 1024;

        if bytes >= TB {
            format!("{:.2} TB", bytes as f64 / TB as f64)
        } else if bytes >= GB {
            format!("{:.2} GB", bytes as f64 / GB as f64)
        } else if bytes >= MB {
            format!("{:.2} MB", bytes as f64 / MB as f64)
        } else if bytes >= KB {
            format!("{:.2} KB", bytes as f64 / KB as f64)
        } else {
            format!("{} B", bytes)
        }
    }
}

impl eframe::App for DataXApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        // Poll for scan progress
        self.poll_scan_progress();

        // Request repaint if scanning (for progress updates)
        if self.scan_state == ScanState::Scanning {
            ctx.request_repaint();
        }

        // Top menu bar
        egui::TopBottomPanel::top("menu_bar").show(ctx, |ui| {
            egui::menu::bar(ui, |ui| {
                ui.menu_button("File", |ui| {
                    if ui.button("Open folder...").clicked() {
                        // TODO: Open folder dialog
                        ui.close_menu();
                    }
                    if ui.button("Rescan").clicked() {
                        let options = ScanOptions {
                            root_path: self.root_path.clone(),
                            max_depth: None,
                            exclude_patterns: vec![],
                            cross_mount: true,
                            apparent_size: false,
                        };
                        self.start_scan(options);
                        ui.close_menu();
                    }
                    ui.separator();
                    if ui.button("Quit").clicked() {
                        ctx.send_viewport_cmd(egui::ViewportCommand::Close);
                    }
                });

                ui.menu_button("View", |ui| {
                    if ui
                        .selectable_label(self.view_mode == GuiViewMode::Tree, "Tree")
                        .clicked()
                    {
                        self.view_mode = GuiViewMode::Tree;
                        ui.close_menu();
                    }
                    if ui
                        .selectable_label(self.view_mode == GuiViewMode::Treemap, "Treemap")
                        .clicked()
                    {
                        self.view_mode = GuiViewMode::Treemap;
                        ui.close_menu();
                    }
                    if ui
                        .selectable_label(self.view_mode == GuiViewMode::Split, "Split")
                        .clicked()
                    {
                        self.view_mode = GuiViewMode::Split;
                        ui.close_menu();
                    }
                    ui.separator();
                    if ui.checkbox(&mut self.show_hidden, "Show hidden files").clicked() {
                        ui.close_menu();
                    }
                    if ui.checkbox(&mut self.show_stats, "Show statistics").clicked() {
                        ui.close_menu();
                    }
                });

                ui.menu_button("Help", |ui| {
                    if ui.button("About").clicked() {
                        // TODO: Show about dialog
                        ui.close_menu();
                    }
                });

                // Right-aligned path and view mode
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    ui.label(format!("View: {}", self.view_mode.display_name()));
                    ui.separator();
                    ui.label(format!("Path: {}", self.root_path.display()));
                });
            });
        });

        // Bottom status bar
        egui::TopBottomPanel::bottom("status_bar").show(ctx, |ui| {
            ui.horizontal(|ui| {
                match &self.scan_state {
                    ScanState::Idle => {
                        ui.label("Ready");
                    }
                    ScanState::Scanning => {
                        ui.spinner();
                        ui.label(format!(
                            "Scanning... {} files found ({})",
                            self.scan_progress.files_found,
                            self.scan_progress.elapsed_string()
                        ));

                        // Progress bar
                        let progress = self.scan_progress.progress_percent();
                        ui.add(
                            egui::ProgressBar::new(progress)
                                .show_percentage()
                                .animate(true),
                        );

                        // Current path being scanned (truncated)
                        let current_path = &self.scan_progress.current_path;
                        if current_path.len() > 50 {
                            ui.label(format!("...{}", &current_path[current_path.len() - 47..]));
                        } else {
                            ui.label(current_path);
                        }
                    }
                    ScanState::Complete => {
                        ui.label(format!(
                            "Complete: {} files, {}",
                            self.scan_progress.total_files,
                            Self::format_size(self.scan_progress.total_size)
                        ));

                        // Show disk usage if available
                        if let Some(ref disk_info) = self.disk_info {
                            ui.separator();
                            let used_percent =
                                (disk_info.used as f64 / disk_info.total as f64 * 100.0) as u64;
                            ui.label(format!(
                                "Disk: {} / {} ({}% used)",
                                Self::format_size(disk_info.used),
                                Self::format_size(disk_info.total),
                                used_percent
                            ));
                        }
                    }
                    ScanState::Error(err) => {
                        ui.colored_label(egui::Color32::RED, format!("Error: {}", err));
                    }
                }

                // Right-aligned selection info
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    if let Some(node) = self.get_selected_node_data() {
                        ui.label(format!("{} - {}", node.name, Self::format_size(node.size)));
                    }
                });
            });
        });

        // Left panel - Tree view
        if self.show_left_panel && (self.view_mode == GuiViewMode::Tree || self.view_mode == GuiViewMode::Split) {
            egui::SidePanel::left("tree_panel")
                .default_width(self.left_panel_width)
                .resizable(true)
                .show(ctx, |ui| {
                    ui.heading("File Tree");
                    ui.separator();

                    // Search box
                    ui.horizontal(|ui| {
                        ui.label("Search:");
                        ui.text_edit_singleline(&mut self.search_query);
                    });
                    ui.separator();

                    // Tree view
                    egui::ScrollArea::vertical()
                        .auto_shrink([false, false])
                        .show(ui, |ui| {
                            self.render_tree_view(ui);
                        });
                });
        }

        // Right panel - Details or Statistics
        if self.show_right_panel && self.show_stats {
            egui::SidePanel::right("stats_panel")
                .default_width(self.right_panel_width)
                .resizable(true)
                .show(ctx, |ui| {
                    ui.heading("Statistics");
                    ui.separator();

                    if let Some(ref _tree) = self.tree {
                        // TODO: Render file type statistics
                        ui.label("File type statistics will appear here");
                    } else {
                        ui.label("No data available");
                    }
                });
        } else if self.show_right_panel {
            egui::SidePanel::right("details_panel")
                .default_width(self.right_panel_width)
                .resizable(true)
                .show(ctx, |ui| {
                    ui.heading("Details");
                    ui.separator();

                    if let Some(node) = self.get_selected_node_data() {
                        egui::Grid::new("details_grid")
                            .num_columns(2)
                            .spacing([20.0, 4.0])
                            .show(ui, |ui| {
                                ui.label("Name:");
                                ui.label(&node.name);
                                ui.end_row();

                                ui.label("Path:");
                                ui.label(node.path.display().to_string());
                                ui.end_row();

                                ui.label("Size:");
                                ui.label(Self::format_size(node.size));
                                ui.end_row();

                                ui.label("Type:");
                                ui.label(if node.is_dir { "Directory" } else { "File" });
                                ui.end_row();

                                if node.is_dir {
                                    ui.label("Files:");
                                    ui.label(format!("{}", node.file_count));
                                    ui.end_row();
                                }

                                if let Some(ref ext) = node.extension {
                                    ui.label("Extension:");
                                    ui.label(ext);
                                    ui.end_row();
                                }

                                if let Some(modified) = node.modified {
                                    ui.label("Modified:");
                                    if let Ok(duration) = modified.duration_since(std::time::UNIX_EPOCH) {
                                        let datetime = chrono::DateTime::from_timestamp(
                                            duration.as_secs() as i64,
                                            0,
                                        );
                                        if let Some(dt) = datetime {
                                            ui.label(dt.format("%Y-%m-%d %H:%M:%S").to_string());
                                        } else {
                                            ui.label("Unknown");
                                        }
                                    } else {
                                        ui.label("Unknown");
                                    }
                                    ui.end_row();
                                }

                                if node.is_hidden {
                                    ui.label("Hidden:");
                                    ui.label("Yes");
                                    ui.end_row();
                                }

                                if node.is_symlink {
                                    ui.label("Symlink:");
                                    if let Some(ref target) = node.symlink_target {
                                        ui.label(target.display().to_string());
                                    } else {
                                        ui.label("Yes");
                                    }
                                    ui.end_row();
                                }
                            });
                    } else {
                        ui.label("Select a file or directory to see details");
                    }
                });
        }

        // Central panel - Main content area
        egui::CentralPanel::default().show(ctx, |ui| {
            match self.view_mode {
                GuiViewMode::Tree => {
                    // Tree is in left panel, show details here if no right panel
                    if !self.show_right_panel {
                        self.render_details_panel(ui);
                    } else {
                        ui.centered_and_justified(|ui| {
                            ui.label("Select items in the tree view");
                        });
                    }
                }
                GuiViewMode::Treemap => {
                    // Treemap visualization
                    self.render_treemap(ui);
                }
                GuiViewMode::Split => {
                    // Tree is in left panel, treemap in center
                    self.render_treemap(ui);
                }
            }
        });
    }
}

impl DataXApp {
    /// Render the file tree view.
    fn render_tree_view(&mut self, ui: &mut egui::Ui) {
        if let Some(tree) = self.tree.clone() {
            if let Some(root) = tree.root {
                self.render_tree_node(ui, &tree, root, 0);
            }
        } else if self.scan_state == ScanState::Scanning {
            ui.label("Scanning...");
        } else {
            ui.label("No data. Start a scan to analyze disk usage.");
        }
    }

    /// Render a single tree node and its children recursively.
    fn render_tree_node(&mut self, ui: &mut egui::Ui, tree: &FileTree, node_id: NodeId, depth: usize) {
        let Some(node) = tree.get_node(node_id) else {
            return;
        };

        // Filter hidden files
        if !self.show_hidden && node.is_hidden {
            return;
        }

        // Filter by search query
        if !self.search_query.is_empty() {
            let query_lower = self.search_query.to_lowercase();
            if !node.name_lower.contains(&query_lower) {
                // Check if any child matches
                let has_matching_child = tree
                    .get_children(node_id)
                    .iter()
                    .any(|&child_id| {
                        tree.get_node(child_id)
                            .map(|c| c.name_lower.contains(&query_lower))
                            .unwrap_or(false)
                    });
                if !has_matching_child && depth > 0 {
                    return;
                }
            }
        }

        let is_selected = self.selected_node == Some(node_id);
        let is_expanded = self.expanded_nodes.contains(&node_id);
        let has_children = !tree.get_children(node_id).is_empty();

        // Indentation
        let indent = depth as f32 * 16.0;

        ui.horizontal(|ui| {
            ui.add_space(indent);

            // Expand/collapse button or spacer
            if node.is_dir && has_children {
                let icon = if is_expanded { "\u{25BC}" } else { "\u{25B6}" }; // Down/Right triangles
                if ui.small_button(icon).clicked() {
                    self.toggle_node(node_id);
                }
            } else {
                ui.add_space(20.0);
            }

            // Icon
            let icon = if node.is_dir {
                if is_expanded {
                    "\u{1F4C2}" // Open folder
                } else {
                    "\u{1F4C1}" // Closed folder
                }
            } else {
                "\u{1F4C4}" // File
            };
            ui.label(icon);

            // Name and size
            let label_text = format!("{} ({})", node.name, Self::format_size(node.size));
            let response = ui.selectable_label(is_selected, label_text);

            if response.clicked() {
                self.select_node(node_id);
                if node.is_dir {
                    self.toggle_node(node_id);
                }
            }

            if response.double_clicked() && node.is_dir {
                // Double-click to drill down
                self.expanded_nodes.insert(node_id);
            }
        });

        // Render children if expanded
        if is_expanded && node.is_dir {
            let mut children: Vec<NodeId> = tree.get_children(node_id);

            // Sort children by size (largest first)
            children.sort_by(|&a, &b| {
                let size_a = tree.get_node(a).map(|n| n.size).unwrap_or(0);
                let size_b = tree.get_node(b).map(|n| n.size).unwrap_or(0);
                size_b.cmp(&size_a)
            });

            for child_id in children {
                self.render_tree_node(ui, tree, child_id, depth + 1);
            }
        }
    }

    /// Render the treemap visualization.
    fn render_treemap(&self, ui: &mut egui::Ui) {
        let available_rect = ui.available_rect_before_wrap();

        if self.tree.is_none() {
            ui.centered_and_justified(|ui| {
                if self.scan_state == ScanState::Scanning {
                    ui.spinner();
                    ui.label("Scanning...");
                } else {
                    ui.label("No data. Start a scan to analyze disk usage.");
                }
            });
            return;
        }

        // Placeholder treemap - draw colored rectangles
        ui.painter().rect_filled(
            available_rect,
            0.0,
            egui::Color32::from_rgb(40, 40, 50),
        );

        ui.centered_and_justified(|ui| {
            ui.label("Treemap visualization will be rendered here");
        });

        // TODO: Implement actual treemap rendering with squarified algorithm
    }

    /// Render the details panel in the central area.
    fn render_details_panel(&self, ui: &mut egui::Ui) {
        if let Some(node) = self.get_selected_node_data() {
            ui.heading(&node.name);
            ui.separator();

            egui::Grid::new("central_details_grid")
                .num_columns(2)
                .spacing([20.0, 8.0])
                .show(ui, |ui| {
                    ui.label("Path:");
                    ui.label(node.path.display().to_string());
                    ui.end_row();

                    ui.label("Size:");
                    ui.label(Self::format_size(node.size));
                    ui.end_row();

                    ui.label("Type:");
                    ui.label(if node.is_dir { "Directory" } else { "File" });
                    ui.end_row();

                    if node.is_dir {
                        ui.label("File count:");
                        ui.label(format!("{}", node.file_count));
                        ui.end_row();
                    }
                });
        } else {
            ui.centered_and_justified(|ui| {
                ui.label("Select a file or directory to see details");
            });
        }
    }
}
