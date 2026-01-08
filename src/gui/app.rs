//! Main GUI application - Professional Data-X disk analyzer

use std::collections::HashSet;
use std::path::PathBuf;
use std::sync::mpsc::{self, Receiver, TryRecvError};
use std::thread;
use std::time::Instant;

use eframe::egui::{self, Color32, Pos2, Rect, RichText, Rounding, Stroke, Vec2};
use indextree::NodeId;

use crate::scanner::{get_disk_space, DiskSpaceInfo, ScanOptions, ScanProgress, Scanner};
use crate::tree::{FileNode, FileTree};

// ============================================================================
// Color Scheme - Dark theme inspired by modern disk analyzers
// ============================================================================

struct Theme {
    bg_dark: Color32,
    bg_medium: Color32,
    bg_light: Color32,
    text_primary: Color32,
    text_secondary: Color32,
    accent: Color32,
    // File type colors
    dir_color: Color32,
    audio_color: Color32,
    video_color: Color32,
    image_color: Color32,
    doc_color: Color32,
    code_color: Color32,
    archive_color: Color32,
    other_color: Color32,
}

impl Default for Theme {
    fn default() -> Self {
        Self {
            bg_dark: Color32::from_rgb(18, 18, 24),
            bg_medium: Color32::from_rgb(28, 28, 36),
            bg_light: Color32::from_rgb(38, 38, 48),
            text_primary: Color32::from_rgb(240, 240, 245),
            text_secondary: Color32::from_rgb(140, 140, 160),
            accent: Color32::from_rgb(100, 140, 255),
            dir_color: Color32::from_rgb(90, 130, 180),
            audio_color: Color32::from_rgb(180, 100, 200),
            video_color: Color32::from_rgb(220, 80, 80),
            image_color: Color32::from_rgb(80, 180, 100),
            doc_color: Color32::from_rgb(80, 140, 220),
            code_color: Color32::from_rgb(220, 180, 60),
            archive_color: Color32::from_rgb(220, 140, 60),
            other_color: Color32::from_rgb(120, 120, 140),
        }
    }
}

// ============================================================================
// Main Application State
// ============================================================================

pub struct DataXApp {
    // Core data
    tree: Option<FileTree>,
    root_path: PathBuf,

    // Selection
    selected_node: Option<NodeId>,
    expanded_nodes: HashSet<NodeId>,
    hovered_node: Option<NodeId>,

    // View state
    view_mode: ViewMode,
    show_hidden: bool,
    search_query: String,

    // Disk info
    disk_info: Option<DiskSpaceInfo>,

    // Scan state
    scan_state: ScanState,
    scan_progress: ScanProgressInfo,
    progress_receiver: Option<Receiver<ScanProgress>>,

    // Treemap cache
    treemap_rects: Vec<TreemapRect>,
    treemap_root: Option<NodeId>,

    // Theme
    theme: Theme,

    // Auto-start flag
    scan_started: bool,
}

#[derive(Clone, Copy, PartialEq, Eq, Default)]
pub enum ViewMode {
    #[default]
    Treemap,
    Tree,
    Split,
}

#[derive(Clone, PartialEq)]
pub enum ScanState {
    Idle,
    Scanning,
    Complete,
    Error(String),
}

#[derive(Clone, Default)]
pub struct ScanProgressInfo {
    pub files_found: u64,
    pub current_path: String,
    pub total_files: u64,
    pub total_size: u64,
    pub bytes_processed: u64,
    pub start_time: Option<Instant>,
}

#[derive(Clone)]
struct TreemapRect {
    node_id: NodeId,
    rect: Rect,
    name: String,
    size: u64,
    is_dir: bool,
    color: Color32,
    depth: usize,
}

impl DataXApp {
    pub fn new(cc: &eframe::CreationContext<'_>, root_path: PathBuf) -> Self {
        // Configure dark theme
        let mut visuals = egui::Visuals::dark();
        visuals.window_fill = Color32::from_rgb(18, 18, 24);
        visuals.panel_fill = Color32::from_rgb(22, 22, 30);
        visuals.faint_bg_color = Color32::from_rgb(28, 28, 36);
        visuals.extreme_bg_color = Color32::from_rgb(12, 12, 16);
        visuals.widgets.noninteractive.bg_fill = Color32::from_rgb(32, 32, 42);
        visuals.widgets.inactive.bg_fill = Color32::from_rgb(38, 38, 50);
        visuals.widgets.hovered.bg_fill = Color32::from_rgb(50, 50, 65);
        visuals.widgets.active.bg_fill = Color32::from_rgb(60, 60, 80);
        visuals.selection.bg_fill = Color32::from_rgb(60, 100, 180);
        cc.egui_ctx.set_visuals(visuals);

        // Set default fonts
        let mut style = (*cc.egui_ctx.style()).clone();
        style.spacing.item_spacing = Vec2::new(8.0, 6.0);
        style.spacing.button_padding = Vec2::new(8.0, 4.0);
        cc.egui_ctx.set_style(style);

        Self {
            tree: None,
            root_path: root_path.clone(),
            selected_node: None,
            expanded_nodes: HashSet::new(),
            hovered_node: None,
            view_mode: ViewMode::Treemap,
            show_hidden: false,
            search_query: String::new(),
            disk_info: None,
            scan_state: ScanState::Idle,
            scan_progress: ScanProgressInfo::default(),
            progress_receiver: None,
            treemap_rects: Vec::new(),
            treemap_root: None,
            theme: Theme::default(),
            scan_started: false,
        }
    }

    fn start_scan(&mut self) {
        let options = ScanOptions {
            root_path: self.root_path.clone(),
            max_depth: None,
            exclude_patterns: vec![],
            cross_mount: true,
            apparent_size: false,
        };

        self.scan_state = ScanState::Scanning;
        self.scan_progress = ScanProgressInfo::default();
        self.scan_progress.start_time = Some(Instant::now());

        let (tx, rx) = mpsc::sync_channel(1000);
        self.progress_receiver = Some(rx);

        thread::spawn(move || {
            let scanner = Scanner::new(options, tx);
            let _result = scanner.scan();
        });
    }

    fn poll_progress(&mut self) {
        let mut messages = Vec::new();

        if let Some(ref receiver) = self.progress_receiver {
            loop {
                match receiver.try_recv() {
                    Ok(progress) => messages.push(progress),
                    Err(TryRecvError::Empty) => break,
                    Err(TryRecvError::Disconnected) => {
                        self.progress_receiver = None;
                        break;
                    }
                }
            }
        }

        for progress in messages {
            match progress {
                ScanProgress::Started => {
                    self.scan_state = ScanState::Scanning;
                }
                ScanProgress::Scanning { path, files_found, bytes_processed, .. } => {
                    self.scan_progress.files_found = files_found;
                    self.scan_progress.bytes_processed = bytes_processed;
                    self.scan_progress.current_path = path.to_string_lossy().into_owned();
                }
                ScanProgress::Completed { total_files, total_size, tree } => {
                    self.scan_progress.total_files = total_files;
                    self.scan_progress.total_size = total_size;
                    self.tree = Some(tree);
                    self.scan_state = ScanState::Complete;
                    self.progress_receiver = None;
                    self.disk_info = get_disk_space(&self.root_path);

                    // Expand and select root
                    if let Some(ref tree) = self.tree {
                        if let Some(root) = tree.root {
                            self.expanded_nodes.insert(root);
                            self.selected_node = Some(root);
                            self.treemap_root = Some(root);
                            self.rebuild_treemap();
                        }
                    }
                }
                _ => {}
            }
        }
    }

    fn get_file_color(&self, node: &FileNode) -> Color32 {
        if node.is_dir {
            return self.theme.dir_color;
        }

        match node.extension.as_deref() {
            Some("mp3") | Some("wav") | Some("flac") | Some("m4a") | Some("aac") | Some("ogg") => self.theme.audio_color,
            Some("mp4") | Some("mkv") | Some("avi") | Some("mov") | Some("wmv") | Some("webm") => self.theme.video_color,
            Some("jpg") | Some("jpeg") | Some("png") | Some("gif") | Some("bmp") | Some("svg") | Some("webp") => self.theme.image_color,
            Some("pdf") | Some("doc") | Some("docx") | Some("txt") | Some("rtf") | Some("odt") => self.theme.doc_color,
            Some("rs") | Some("py") | Some("js") | Some("ts") | Some("go") | Some("c") | Some("cpp") | Some("h") | Some("java") => self.theme.code_color,
            Some("zip") | Some("tar") | Some("gz") | Some("rar") | Some("7z") | Some("bz2") | Some("xz") => self.theme.archive_color,
            _ => self.theme.other_color,
        }
    }

    fn format_size(bytes: u64) -> String {
        const KB: u64 = 1024;
        const MB: u64 = KB * 1024;
        const GB: u64 = MB * 1024;
        const TB: u64 = GB * 1024;

        if bytes >= TB {
            format!("{:.1} TB", bytes as f64 / TB as f64)
        } else if bytes >= GB {
            format!("{:.1} GB", bytes as f64 / GB as f64)
        } else if bytes >= MB {
            format!("{:.1} MB", bytes as f64 / MB as f64)
        } else if bytes >= KB {
            format!("{:.1} KB", bytes as f64 / KB as f64)
        } else {
            format!("{} B", bytes)
        }
    }

    // ========================================================================
    // Treemap rendering
    // ========================================================================

    fn rebuild_treemap(&mut self) {
        self.treemap_rects.clear();

        let Some(ref tree) = self.tree else { return };
        let Some(root_id) = self.treemap_root.or(tree.root) else { return };

        // Build will happen during render when we know the rect size
    }

    fn build_treemap_rects(&mut self, rect: Rect) {
        self.treemap_rects.clear();

        let Some(ref tree) = self.tree else { return };
        let root_id = self.treemap_root.unwrap_or_else(|| tree.root.unwrap());

        let children: Vec<NodeId> = tree.get_children(root_id);
        if children.is_empty() {
            // Single file root
            if let Some(node) = tree.get_node(root_id) {
                self.treemap_rects.push(TreemapRect {
                    node_id: root_id,
                    rect,
                    name: node.name.clone(),
                    size: node.size,
                    is_dir: node.is_dir,
                    color: self.get_file_color(node),
                    depth: 0,
                });
            }
            return;
        }

        // Collect children with sizes
        let mut items: Vec<(NodeId, u64, String, bool, Color32)> = children
            .iter()
            .filter_map(|&id| {
                let node = tree.get_node(id)?;
                if !self.show_hidden && node.is_hidden {
                    return None;
                }
                Some((id, node.size, node.name.clone(), node.is_dir, self.get_file_color(node)))
            })
            .collect();

        // Sort by size descending
        items.sort_by(|a, b| b.1.cmp(&a.1));

        // Squarify layout
        self.squarify(&items, rect, 0);
    }

    fn squarify(&mut self, items: &[(NodeId, u64, String, bool, Color32)], rect: Rect, depth: usize) {
        if items.is_empty() || rect.width() < 2.0 || rect.height() < 2.0 {
            return;
        }

        let total_size: u64 = items.iter().map(|i| i.1).sum();
        if total_size == 0 {
            return;
        }

        let mut remaining_items = items.to_vec();
        let mut remaining_rect = rect;

        while !remaining_items.is_empty() {
            let is_horizontal = remaining_rect.width() >= remaining_rect.height();

            // Find best row
            let (row_items, row_size) = self.find_best_row(&remaining_items, &remaining_rect, is_horizontal);

            if row_items == 0 {
                break;
            }

            // Layout the row
            let remaining_size: u64 = remaining_items.iter().map(|i| i.1).sum();
            let row_fraction = if remaining_size > 0 { row_size as f64 / remaining_size as f64 } else { 1.0 };

            let (row_rect, new_remaining) = if is_horizontal {
                let row_width = (remaining_rect.width() as f64 * row_fraction) as f32;
                (
                    Rect::from_min_size(remaining_rect.min, Vec2::new(row_width, remaining_rect.height())),
                    Rect::from_min_size(
                        Pos2::new(remaining_rect.min.x + row_width, remaining_rect.min.y),
                        Vec2::new(remaining_rect.width() - row_width, remaining_rect.height()),
                    ),
                )
            } else {
                let row_height = (remaining_rect.height() as f64 * row_fraction) as f32;
                (
                    Rect::from_min_size(remaining_rect.min, Vec2::new(remaining_rect.width(), row_height)),
                    Rect::from_min_size(
                        Pos2::new(remaining_rect.min.x, remaining_rect.min.y + row_height),
                        Vec2::new(remaining_rect.width(), remaining_rect.height() - row_height),
                    ),
                )
            };

            // Layout items in row
            let mut pos = row_rect.min;
            for i in 0..row_items {
                let item = &remaining_items[i];
                let item_fraction = if row_size > 0 { item.1 as f64 / row_size as f64 } else { 0.0 };

                let item_rect = if is_horizontal {
                    let h = (row_rect.height() as f64 * item_fraction) as f32;
                    let r = Rect::from_min_size(pos, Vec2::new(row_rect.width(), h));
                    pos.y += h;
                    r
                } else {
                    let w = (row_rect.width() as f64 * item_fraction) as f32;
                    let r = Rect::from_min_size(pos, Vec2::new(w, row_rect.height()));
                    pos.x += w;
                    r
                };

                // Add padding
                let padded = item_rect.shrink(1.0);
                if padded.width() > 0.0 && padded.height() > 0.0 {
                    self.treemap_rects.push(TreemapRect {
                        node_id: item.0,
                        rect: padded,
                        name: item.2.clone(),
                        size: item.1,
                        is_dir: item.3,
                        color: item.4,
                        depth,
                    });
                }
            }

            remaining_items = remaining_items[row_items..].to_vec();
            remaining_rect = new_remaining;
        }
    }

    fn find_best_row(&self, items: &[(NodeId, u64, String, bool, Color32)], rect: &Rect, horizontal: bool) -> (usize, u64) {
        if items.is_empty() {
            return (0, 0);
        }

        let total_size: u64 = items.iter().map(|i| i.1).sum();
        if total_size == 0 {
            return (items.len(), 0);
        }

        let rect_area = (rect.width() * rect.height()) as f64;
        let short_side = if horizontal { rect.height() } else { rect.width() } as f64;

        let mut best_count = 1;
        let mut best_ratio = f64::MAX;
        let mut row_size: u64 = 0;

        for i in 0..items.len() {
            row_size += items[i].1;

            let row_area = rect_area * (row_size as f64 / total_size as f64);
            let row_short = row_area / short_side;

            // Calculate worst aspect ratio in this row
            let mut worst_ratio = 0.0f64;
            let mut item_size_sum: u64 = 0;

            for j in 0..=i {
                item_size_sum += items[j].1;
                let item_area = rect_area * (items[j].1 as f64 / total_size as f64);
                let item_long = item_area / row_short;
                let ratio = (item_long / row_short).max(row_short / item_long);
                worst_ratio = worst_ratio.max(ratio);
            }

            if worst_ratio < best_ratio {
                best_ratio = worst_ratio;
                best_count = i + 1;
            } else if i > 0 {
                // Ratio getting worse, stop here
                break;
            }
        }

        let final_size: u64 = items[..best_count].iter().map(|i| i.1).sum();
        (best_count, final_size)
    }

    fn render_treemap(&mut self, ui: &mut egui::Ui) {
        let rect = ui.available_rect_before_wrap();

        // Rebuild treemap if needed
        if self.treemap_rects.is_empty() || self.tree.is_some() {
            self.build_treemap_rects(rect.shrink(4.0));
        }

        let painter = ui.painter();

        // Background
        painter.rect_filled(rect, Rounding::ZERO, self.theme.bg_dark);

        // Draw rects
        let mouse_pos = ui.input(|i| i.pointer.hover_pos());
        let mut new_hovered = None;
        let mut clicked_node = None;
        let mut double_clicked = false;

        for tr in &self.treemap_rects {
            let is_hovered = mouse_pos.map(|p| tr.rect.contains(p)).unwrap_or(false);
            let is_selected = self.selected_node == Some(tr.node_id);

            if is_hovered {
                new_hovered = Some(tr.node_id);
            }

            // Darken color for depth effect
            let base_color = tr.color;
            let color = if is_selected {
                Color32::from_rgb(
                    (base_color.r() as u16 + 60).min(255) as u8,
                    (base_color.g() as u16 + 60).min(255) as u8,
                    (base_color.b() as u16 + 60).min(255) as u8,
                )
            } else if is_hovered {
                Color32::from_rgb(
                    (base_color.r() as u16 + 30).min(255) as u8,
                    (base_color.g() as u16 + 30).min(255) as u8,
                    (base_color.b() as u16 + 30).min(255) as u8,
                )
            } else {
                base_color
            };

            // Draw rect
            painter.rect_filled(tr.rect, Rounding::same(2.0), color);

            // Border
            let stroke_color = if is_selected {
                Color32::WHITE
            } else {
                Color32::from_rgba_unmultiplied(0, 0, 0, 100)
            };
            painter.rect_stroke(tr.rect, Rounding::same(2.0), Stroke::new(if is_selected { 2.0 } else { 1.0 }, stroke_color));

            // Label if rect is big enough
            if tr.rect.width() > 40.0 && tr.rect.height() > 20.0 {
                let text = if tr.rect.width() > 100.0 {
                    format!("{}\n{}", truncate(&tr.name, 15), Self::format_size(tr.size))
                } else {
                    truncate(&tr.name, 8)
                };

                painter.text(
                    tr.rect.center(),
                    egui::Align2::CENTER_CENTER,
                    text,
                    egui::FontId::proportional(11.0),
                    Color32::WHITE,
                );
            }
        }

        self.hovered_node = new_hovered;

        // Handle clicks
        let response = ui.allocate_rect(rect, egui::Sense::click());
        if response.clicked() {
            if let Some(pos) = mouse_pos {
                for tr in &self.treemap_rects {
                    if tr.rect.contains(pos) {
                        clicked_node = Some(tr.node_id);
                        break;
                    }
                }
            }
        }
        if response.double_clicked() {
            double_clicked = true;
        }

        if let Some(node_id) = clicked_node {
            self.selected_node = Some(node_id);

            if double_clicked {
                // Drill down into directory
                if let Some(ref tree) = self.tree {
                    if let Some(node) = tree.get_node(node_id) {
                        if node.is_dir && !tree.get_children(node_id).is_empty() {
                            self.treemap_root = Some(node_id);
                            self.treemap_rects.clear();
                        }
                    }
                }
            }
        }

        // Show tooltip for hovered item
        if let Some(hovered_id) = self.hovered_node {
            if let Some(ref tree) = self.tree {
                if let Some(node) = tree.get_node(hovered_id) {
                    egui::show_tooltip(ui.ctx(), ui.layer_id(), egui::Id::new("treemap_tooltip"), |ui| {
                        ui.label(RichText::new(&node.name).strong());
                        ui.label(format!("Size: {}", Self::format_size(node.size)));
                        ui.label(format!("Path: {}", node.path.display()));
                        if node.is_dir {
                            ui.label(format!("Files: {}", node.file_count));
                        }
                    });
                }
            }
        }
    }

    // ========================================================================
    // Tree view rendering
    // ========================================================================

    fn render_tree(&mut self, ui: &mut egui::Ui) {
        let Some(tree) = self.tree.clone() else {
            ui.centered_and_justified(|ui| {
                ui.label("No data");
            });
            return;
        };

        let Some(root) = tree.root else { return };

        egui::ScrollArea::vertical()
            .auto_shrink([false, false])
            .show(ui, |ui| {
                self.render_tree_node(ui, &tree, root, 0);
            });
    }

    fn render_tree_node(&mut self, ui: &mut egui::Ui, tree: &FileTree, node_id: NodeId, depth: usize) {
        let Some(node) = tree.get_node(node_id) else { return };

        if !self.show_hidden && node.is_hidden {
            return;
        }

        let is_selected = self.selected_node == Some(node_id);
        let is_expanded = self.expanded_nodes.contains(&node_id);
        let has_children = node.is_dir && !tree.get_children(node_id).is_empty();

        let indent = depth as f32 * 20.0;
        let color = self.get_file_color(node);

        // Calculate percentage of parent
        let parent_size = if depth == 0 {
            node.size
        } else {
            node_id.ancestors(&tree.arena)
                .nth(1)
                .and_then(|p| tree.get_node(p))
                .map(|p| p.size)
                .unwrap_or(node.size)
        };
        let percent = if parent_size > 0 {
            (node.size as f64 / parent_size as f64 * 100.0) as u8
        } else {
            0
        };

        ui.horizontal(|ui| {
            ui.add_space(indent);

            // Expand button
            if has_children {
                let icon = if is_expanded { "▼" } else { "▶" };
                if ui.small_button(RichText::new(icon).size(10.0)).clicked() {
                    if is_expanded {
                        self.expanded_nodes.remove(&node_id);
                    } else {
                        self.expanded_nodes.insert(node_id);
                    }
                }
            } else {
                ui.add_space(18.0);
            }

            // Color indicator
            let (rect, _) = ui.allocate_exact_size(Vec2::new(12.0, 12.0), egui::Sense::hover());
            ui.painter().rect_filled(rect, Rounding::same(2.0), color);

            // Icon
            let icon = if node.is_dir {
                if is_expanded { "📂" } else { "📁" }
            } else {
                match node.extension.as_deref() {
                    Some("mp3") | Some("wav") | Some("flac") => "🎵",
                    Some("mp4") | Some("mkv") | Some("avi") => "🎬",
                    Some("jpg") | Some("png") | Some("gif") => "🖼",
                    Some("zip") | Some("tar") | Some("gz") => "📦",
                    Some("pdf") | Some("doc") | Some("txt") => "📄",
                    _ => "📄",
                }
            };
            ui.label(icon);

            // Name
            let name_text = RichText::new(&node.name).color(if is_selected {
                Color32::WHITE
            } else {
                self.theme.text_primary
            });

            let response = ui.selectable_label(is_selected, name_text);
            if response.clicked() {
                self.selected_node = Some(node_id);
                if has_children {
                    if is_expanded {
                        self.expanded_nodes.remove(&node_id);
                    } else {
                        self.expanded_nodes.insert(node_id);
                    }
                }
            }

            // Size bar
            let bar_width = 60.0;
            let bar_height = 8.0;
            let (bar_rect, _) = ui.allocate_exact_size(Vec2::new(bar_width, bar_height), egui::Sense::hover());

            // Background
            ui.painter().rect_filled(bar_rect, Rounding::same(2.0), self.theme.bg_light);

            // Fill
            let fill_width = bar_width * (percent as f32 / 100.0);
            let fill_rect = Rect::from_min_size(bar_rect.min, Vec2::new(fill_width, bar_height));
            ui.painter().rect_filled(fill_rect, Rounding::same(2.0), color);

            // Size text
            ui.label(RichText::new(Self::format_size(node.size)).color(self.theme.text_secondary).size(11.0));
            ui.label(RichText::new(format!("{}%", percent)).color(self.theme.text_secondary).size(11.0));
        });

        // Children
        if is_expanded && has_children {
            let mut children: Vec<NodeId> = tree.get_children(node_id);
            children.sort_by(|&a, &b| {
                let sa = tree.get_node(a).map(|n| n.size).unwrap_or(0);
                let sb = tree.get_node(b).map(|n| n.size).unwrap_or(0);
                sb.cmp(&sa)
            });

            for child_id in children {
                self.render_tree_node(ui, tree, child_id, depth + 1);
            }
        }
    }
}

impl eframe::App for DataXApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        // Auto-start scan on first frame
        if !self.scan_started {
            self.scan_started = true;
            self.start_scan();
        }

        // Poll progress
        self.poll_progress();

        if self.scan_state == ScanState::Scanning {
            ctx.request_repaint();
        }

        // Top panel with controls
        egui::TopBottomPanel::top("top_panel").show(ctx, |ui| {
            ui.horizontal(|ui| {
                ui.heading(RichText::new("Data-X").strong());
                ui.separator();

                // View mode buttons
                if ui.selectable_label(self.view_mode == ViewMode::Treemap, "🗺 Treemap").clicked() {
                    self.view_mode = ViewMode::Treemap;
                    self.treemap_rects.clear();
                }
                if ui.selectable_label(self.view_mode == ViewMode::Tree, "🌳 Tree").clicked() {
                    self.view_mode = ViewMode::Tree;
                }
                if ui.selectable_label(self.view_mode == ViewMode::Split, "⊞ Split").clicked() {
                    self.view_mode = ViewMode::Split;
                    self.treemap_rects.clear();
                }

                ui.separator();

                // Navigation for treemap
                if self.treemap_root.is_some() && self.treemap_root != self.tree.as_ref().and_then(|t| t.root) {
                    if ui.button("⬆ Up").clicked() {
                        if let Some(ref tree) = self.tree {
                            if let Some(current_root) = self.treemap_root {
                                let parent = current_root.ancestors(&tree.arena).nth(1);
                                self.treemap_root = parent.or(tree.root);
                                self.treemap_rects.clear();
                            }
                        }
                    }
                }

                ui.separator();

                ui.checkbox(&mut self.show_hidden, "Hidden");

                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    // Path display
                    let path_str = self.root_path.display().to_string();
                    ui.label(RichText::new(&path_str).color(self.theme.text_secondary));
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
                        ui.label(format!("Scanning... {} files", self.scan_progress.files_found));

                        // Truncated current path
                        let path = &self.scan_progress.current_path;
                        if path.len() > 60 {
                            ui.label(RichText::new(format!("...{}", &path[path.len()-57..])).color(self.theme.text_secondary));
                        }
                    }
                    ScanState::Complete => {
                        ui.label(format!(
                            "✓ {} files  •  {}",
                            self.scan_progress.total_files,
                            Self::format_size(self.scan_progress.total_size)
                        ));

                        if let Some(ref disk) = self.disk_info {
                            ui.separator();
                            let used_pct = (disk.used as f64 / disk.total as f64 * 100.0) as u32;
                            ui.label(format!(
                                "Disk: {} / {} ({}%)",
                                Self::format_size(disk.used),
                                Self::format_size(disk.total),
                                used_pct
                            ));
                        }
                    }
                    ScanState::Error(e) => {
                        ui.label(RichText::new(format!("Error: {}", e)).color(Color32::RED));
                    }
                }

                // Selected item info
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    if let Some(node_id) = self.selected_node {
                        if let Some(ref tree) = self.tree {
                            if let Some(node) = tree.get_node(node_id) {
                                ui.label(format!("{} • {}", node.name, Self::format_size(node.size)));
                            }
                        }
                    }
                });
            });
        });

        // Main content
        egui::CentralPanel::default().show(ctx, |ui| {
            if self.tree.is_none() {
                ui.centered_and_justified(|ui| {
                    if self.scan_state == ScanState::Scanning {
                        ui.vertical_centered(|ui| {
                            ui.spinner();
                            ui.add_space(10.0);
                            ui.label(RichText::new("Scanning...").size(18.0));
                            ui.label(format!("{} files found", self.scan_progress.files_found));
                        });
                    } else {
                        ui.label("No data");
                    }
                });
                return;
            }

            match self.view_mode {
                ViewMode::Treemap => {
                    self.render_treemap(ui);
                }
                ViewMode::Tree => {
                    self.render_tree(ui);
                }
                ViewMode::Split => {
                    ui.columns(2, |cols| {
                        // Tree on left
                        cols[0].push_id("tree_col", |ui| {
                            let mut app = std::mem::take(self);
                            app.render_tree(ui);
                            *self = app;
                        });

                        // Treemap on right
                        cols[1].push_id("treemap_col", |ui| {
                            let mut app = std::mem::take(self);
                            app.render_treemap(ui);
                            *self = app;
                        });
                    });
                }
            }
        });
    }
}

impl Default for DataXApp {
    fn default() -> Self {
        Self {
            tree: None,
            root_path: PathBuf::from("."),
            selected_node: None,
            expanded_nodes: HashSet::new(),
            hovered_node: None,
            view_mode: ViewMode::Treemap,
            show_hidden: false,
            search_query: String::new(),
            disk_info: None,
            scan_state: ScanState::Idle,
            scan_progress: ScanProgressInfo::default(),
            progress_receiver: None,
            treemap_rects: Vec::new(),
            treemap_root: None,
            theme: Theme::default(),
            scan_started: false,
        }
    }
}

fn truncate(s: &str, max: usize) -> String {
    if s.len() <= max {
        s.to_string()
    } else {
        format!("{}…", &s[..max-1])
    }
}
