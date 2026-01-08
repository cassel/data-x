//! Data-X GUI - Disk Inventory X inspired design

use std::collections::{HashMap, HashSet};
use std::path::PathBuf;
use std::sync::mpsc::{self, Receiver, TryRecvError};
use std::thread;
use std::time::Instant;

use eframe::egui::{self, Color32, Pos2, Rect, RichText, Rounding, Stroke, Vec2};
use indextree::NodeId;

use crate::scanner::{get_disk_space, DiskSpaceInfo, ScanOptions, ScanProgress, Scanner};
use crate::tree::{FileNode, FileTree};

// ============================================================================
// File Type Categories & Colors (Disk Inventory X style)
// ============================================================================

#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub enum FileCategory {
    Audio,
    Video,
    Images,
    Documents,
    Code,
    Archives,
    Applications,
    System,
    Other,
}

impl FileCategory {
    fn from_extension(ext: Option<&str>) -> Self {
        match ext.map(|e| e.to_lowercase()).as_deref() {
            Some("mp3") | Some("wav") | Some("flac") | Some("m4a") | Some("aac") | Some("ogg") | Some("wma") | Some("aiff") => Self::Audio,
            Some("mp4") | Some("mkv") | Some("avi") | Some("mov") | Some("wmv") | Some("webm") | Some("m4v") | Some("flv") => Self::Video,
            Some("jpg") | Some("jpeg") | Some("png") | Some("gif") | Some("bmp") | Some("svg") | Some("webp") | Some("tiff") | Some("ico") | Some("heic") => Self::Images,
            Some("pdf") | Some("doc") | Some("docx") | Some("txt") | Some("rtf") | Some("odt") | Some("xls") | Some("xlsx") | Some("ppt") | Some("pptx") | Some("pages") | Some("numbers") => Self::Documents,
            Some("rs") | Some("py") | Some("js") | Some("ts") | Some("go") | Some("c") | Some("cpp") | Some("h") | Some("java") | Some("swift") | Some("kt") | Some("rb") | Some("php") | Some("html") | Some("css") | Some("json") | Some("xml") | Some("yaml") | Some("toml") | Some("md") | Some("sh") => Self::Code,
            Some("zip") | Some("tar") | Some("gz") | Some("rar") | Some("7z") | Some("bz2") | Some("xz") | Some("dmg") | Some("iso") => Self::Archives,
            Some("app") | Some("exe") | Some("dll") | Some("so") | Some("dylib") => Self::Applications,
            Some("sys") | Some("log") | Some("plist") | Some("db") | Some("sqlite") => Self::System,
            _ => Self::Other,
        }
    }

    fn color(&self) -> Color32 {
        match self {
            Self::Audio => Color32::from_rgb(200, 100, 220),      // Purple
            Self::Video => Color32::from_rgb(220, 80, 80),        // Red
            Self::Images => Color32::from_rgb(100, 200, 100),     // Green
            Self::Documents => Color32::from_rgb(100, 150, 220),  // Blue
            Self::Code => Color32::from_rgb(220, 200, 80),        // Yellow
            Self::Archives => Color32::from_rgb(220, 150, 80),    // Orange
            Self::Applications => Color32::from_rgb(180, 180, 220), // Light purple
            Self::System => Color32::from_rgb(150, 150, 150),     // Gray
            Self::Other => Color32::from_rgb(120, 140, 160),      // Blue-gray
        }
    }

    fn name(&self) -> &'static str {
        match self {
            Self::Audio => "Audio",
            Self::Video => "Video",
            Self::Images => "Images",
            Self::Documents => "Documents",
            Self::Code => "Code",
            Self::Archives => "Archives",
            Self::Applications => "Apps",
            Self::System => "System",
            Self::Other => "Other",
        }
    }

    fn icon(&self) -> &'static str {
        match self {
            Self::Audio => "🎵",
            Self::Video => "🎬",
            Self::Images => "🖼",
            Self::Documents => "📄",
            Self::Code => "💻",
            Self::Archives => "📦",
            Self::Applications => "⚙",
            Self::System => "🔧",
            Self::Other => "📁",
        }
    }
}

// ============================================================================
// Category Statistics
// ============================================================================

#[derive(Clone, Default)]
struct CategoryStats {
    size: u64,
    count: u64,
}

// ============================================================================
// Treemap Rectangle
// ============================================================================

#[derive(Clone)]
struct TreemapRect {
    node_id: NodeId,
    rect: Rect,
    name: String,
    size: u64,
    is_dir: bool,
    category: FileCategory,
}

// ============================================================================
// Main Application
// ============================================================================

pub struct DataXApp {
    // Data
    tree: Option<FileTree>,
    root_path: PathBuf,

    // Selection (synchronized across views)
    selected_node: Option<NodeId>,
    expanded_nodes: HashSet<NodeId>,
    hovered_node: Option<NodeId>,

    // Category stats
    category_stats: HashMap<FileCategory, CategoryStats>,

    // View state
    show_hidden: bool,

    // Scan
    scan_state: ScanState,
    scan_progress: ScanProgressInfo,
    progress_receiver: Option<Receiver<ScanProgress>>,
    scan_started: bool,

    // Disk info
    disk_info: Option<DiskSpaceInfo>,

    // Treemap
    treemap_rects: Vec<TreemapRect>,
    treemap_root: Option<NodeId>,
    needs_rebuild: bool,
    last_treemap_size: Vec2,
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
    pub start_time: Option<Instant>,
}

impl DataXApp {
    pub fn new(cc: &eframe::CreationContext<'_>, root_path: PathBuf) -> Self {
        // Dark theme
        let mut visuals = egui::Visuals::dark();
        visuals.window_fill = Color32::from_rgb(30, 30, 35);
        visuals.panel_fill = Color32::from_rgb(35, 35, 42);
        visuals.faint_bg_color = Color32::from_rgb(40, 40, 48);
        visuals.extreme_bg_color = Color32::from_rgb(20, 20, 25);
        visuals.widgets.noninteractive.bg_fill = Color32::from_rgb(45, 45, 55);
        visuals.widgets.inactive.bg_fill = Color32::from_rgb(50, 50, 60);
        visuals.widgets.hovered.bg_fill = Color32::from_rgb(65, 65, 80);
        visuals.widgets.active.bg_fill = Color32::from_rgb(80, 80, 100);
        visuals.selection.bg_fill = Color32::from_rgb(70, 120, 200);
        visuals.selection.stroke = Stroke::new(1.0, Color32::WHITE);
        cc.egui_ctx.set_visuals(visuals);

        Self {
            tree: None,
            root_path,
            selected_node: None,
            expanded_nodes: HashSet::new(),
            hovered_node: None,
            category_stats: HashMap::new(),
            show_hidden: false,
            scan_state: ScanState::Idle,
            scan_progress: ScanProgressInfo::default(),
            progress_receiver: None,
            scan_started: false,
            disk_info: None,
            treemap_rects: Vec::new(),
            treemap_root: None,
            needs_rebuild: true,
            last_treemap_size: Vec2::ZERO,
        }
    }

    fn start_scan(&mut self) {
        self.scan_state = ScanState::Scanning;
        self.scan_progress = ScanProgressInfo {
            start_time: Some(Instant::now()),
            ..Default::default()
        };

        let (tx, rx) = mpsc::sync_channel(1000);
        self.progress_receiver = Some(rx);

        let options = ScanOptions {
            root_path: self.root_path.clone(),
            max_depth: None,
            exclude_patterns: vec![],
            cross_mount: true,
            apparent_size: false,
        };

        thread::spawn(move || {
            let scanner = Scanner::new(options, tx);
            let _ = scanner.scan();
        });
    }

    fn poll_progress(&mut self) {
        let Some(ref receiver) = self.progress_receiver else { return };

        loop {
            match receiver.try_recv() {
                Ok(ScanProgress::Scanning { files_found, path, .. }) => {
                    self.scan_progress.files_found = files_found;
                    self.scan_progress.current_path = path.to_string_lossy().into_owned();
                }
                Ok(ScanProgress::Completed { total_files, total_size, tree }) => {
                    self.scan_progress.total_files = total_files;
                    self.scan_progress.total_size = total_size;
                    self.tree = Some(tree);
                    self.scan_state = ScanState::Complete;
                    self.progress_receiver = None;
                    self.disk_info = get_disk_space(&self.root_path);

                    // Initialize view
                    if let Some(ref tree) = self.tree {
                        if let Some(root) = tree.root {
                            self.expanded_nodes.insert(root);
                            self.selected_node = Some(root);
                            self.treemap_root = Some(root);
                            self.needs_rebuild = true;
                            self.compute_category_stats();
                        }
                    }
                    break;
                }
                Ok(_) => {}
                Err(TryRecvError::Empty) => break,
                Err(TryRecvError::Disconnected) => {
                    self.progress_receiver = None;
                    break;
                }
            }
        }
    }

    fn compute_category_stats(&mut self) {
        self.category_stats.clear();

        let Some(tree) = self.tree.clone() else { return };
        let Some(root) = tree.root else { return };

        Self::compute_stats_recursive_impl(&tree, root, &mut self.category_stats);
    }

    fn compute_stats_recursive_impl(tree: &FileTree, node_id: NodeId, stats: &mut HashMap<FileCategory, CategoryStats>) {
        let Some(node) = tree.get_node(node_id) else { return };

        if !node.is_dir {
            let cat = FileCategory::from_extension(node.extension.as_deref());
            let entry = stats.entry(cat).or_default();
            entry.size += node.size;
            entry.count += 1;
        }

        for child in tree.get_children(node_id) {
            Self::compute_stats_recursive_impl(tree, child, stats);
        }
    }

    fn format_size(bytes: u64) -> String {
        const KB: u64 = 1024;
        const MB: u64 = KB * 1024;
        const GB: u64 = MB * 1024;
        const TB: u64 = GB * 1024;

        if bytes >= TB { format!("{:.1} TB", bytes as f64 / TB as f64) }
        else if bytes >= GB { format!("{:.1} GB", bytes as f64 / GB as f64) }
        else if bytes >= MB { format!("{:.1} MB", bytes as f64 / MB as f64) }
        else if bytes >= KB { format!("{:.1} KB", bytes as f64 / KB as f64) }
        else { format!("{} B", bytes) }
    }

    // ========================================================================
    // LEFT PANEL: File Tree
    // ========================================================================

    fn render_tree_panel(&mut self, ui: &mut egui::Ui) {
        let tree = match self.tree.clone() {
            Some(t) => t,
            None => {
                ui.centered_and_justified(|ui| {
                    ui.label("No data");
                });
                return;
            }
        };

        let Some(root) = tree.root else { return };

        // Collect state needed for rendering
        let selected = self.selected_node;
        let expanded = self.expanded_nodes.clone();
        let show_hidden = self.show_hidden;

        egui::ScrollArea::both()
            .auto_shrink([false, false])
            .show(ui, |ui| {
                self.render_tree_node_impl(ui, &tree, root, 0, selected, &expanded, show_hidden);
            });
    }

    fn render_tree_node_impl(
        &mut self,
        ui: &mut egui::Ui,
        tree: &FileTree,
        node_id: NodeId,
        depth: usize,
        selected: Option<NodeId>,
        expanded: &HashSet<NodeId>,
        show_hidden: bool,
    ) {
        let Some(node) = tree.get_node(node_id) else { return };

        // Always show root (depth 0), filter hidden for others
        if depth > 0 && !show_hidden && node.is_hidden {
            return;
        }

        let is_selected = self.selected_node == Some(node_id);
        let is_expanded = self.expanded_nodes.contains(&node_id);
        let has_children = node.is_dir && !tree.get_children(node_id).is_empty();

        let indent = depth as f32 * 16.0;
        let cat = FileCategory::from_extension(node.extension.as_deref());
        let color = if node.is_dir { Color32::from_rgb(130, 170, 220) } else { cat.color() };

        // Row
        let row_response = ui.horizontal(|ui| {
            ui.add_space(indent);

            // Expand arrow
            if has_children {
                let arrow = if is_expanded { "▼" } else { "▶" };
                if ui.small_button(RichText::new(arrow).size(9.0).color(Color32::from_rgb(150, 150, 160))).clicked() {
                    if is_expanded {
                        self.expanded_nodes.remove(&node_id);
                    } else {
                        self.expanded_nodes.insert(node_id);
                    }
                }
            } else {
                ui.add_space(16.0);
            }

            // Color box
            let (color_rect, _) = ui.allocate_exact_size(Vec2::new(10.0, 10.0), egui::Sense::hover());
            ui.painter().rect_filled(color_rect, Rounding::same(2.0), color);

            // Icon
            let icon = if node.is_dir { "📁" } else { cat.icon() };
            ui.label(RichText::new(icon).size(12.0));

            // Name - selectable
            let text_color = if is_selected { Color32::WHITE } else { Color32::from_rgb(220, 220, 230) };
            let response = ui.selectable_label(is_selected, RichText::new(&node.name).color(text_color).size(12.0));

            if response.clicked() {
                self.selected_node = Some(node_id);
                self.needs_rebuild = true;
                if has_children {
                    if is_expanded {
                        self.expanded_nodes.remove(&node_id);
                    } else {
                        self.expanded_nodes.insert(node_id);
                    }
                }
            }

            if response.double_clicked() && node.is_dir {
                self.treemap_root = Some(node_id);
                self.needs_rebuild = true;
            }

            // Size
            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                ui.label(RichText::new(Self::format_size(node.size)).size(11.0).color(Color32::from_rgb(140, 140, 150)));
            });
        });

        // Children
        if is_expanded && has_children {
            let mut children: Vec<NodeId> = tree.get_children(node_id);
            // Sort: directories first, then by size
            children.sort_by(|&a, &b| {
                let na = tree.get_node(a);
                let nb = tree.get_node(b);
                match (na.map(|n| n.is_dir), nb.map(|n| n.is_dir)) {
                    (Some(true), Some(false)) => std::cmp::Ordering::Less,
                    (Some(false), Some(true)) => std::cmp::Ordering::Greater,
                    _ => {
                        let sa = na.map(|n| n.size).unwrap_or(0);
                        let sb = nb.map(|n| n.size).unwrap_or(0);
                        sb.cmp(&sa)
                    }
                }
            });

            for child in children {
                self.render_tree_node_impl(ui, tree, child, depth + 1, selected, expanded, show_hidden);
            }
        }
    }

    // ========================================================================
    // CENTER: Treemap (Cushion Shading)
    // ========================================================================

    fn build_treemap(&mut self, rect: Rect) {
        self.treemap_rects.clear();

        let Some(ref tree) = self.tree else { return };
        let root_id = self.treemap_root.unwrap_or_else(|| tree.root.unwrap());

        let children: Vec<NodeId> = tree.get_children(root_id);
        if children.is_empty() {
            if let Some(node) = tree.get_node(root_id) {
                let cat = FileCategory::from_extension(node.extension.as_deref());
                self.treemap_rects.push(TreemapRect {
                    node_id: root_id,
                    rect,
                    name: node.name.clone(),
                    size: node.size,
                    is_dir: node.is_dir,
                    category: cat,
                });
            }
            return;
        }

        // Collect items
        let mut items: Vec<(NodeId, u64, String, bool, FileCategory)> = children
            .iter()
            .filter_map(|&id| {
                let node = tree.get_node(id)?;
                if !self.show_hidden && node.is_hidden { return None; }
                let cat = if node.is_dir {
                    FileCategory::Other
                } else {
                    FileCategory::from_extension(node.extension.as_deref())
                };
                Some((id, node.size.max(1), node.name.clone(), node.is_dir, cat))
            })
            .collect();

        items.sort_by(|a, b| b.1.cmp(&a.1));
        self.squarify(&items, rect);
    }

    fn squarify(&mut self, items: &[(NodeId, u64, String, bool, FileCategory)], rect: Rect) {
        if items.is_empty() || rect.width() < 1.0 || rect.height() < 1.0 {
            return;
        }

        let total: u64 = items.iter().map(|i| i.1).sum();
        if total == 0 { return; }

        let mut remaining = items.to_vec();
        let mut r = rect;

        while !remaining.is_empty() && r.width() > 1.0 && r.height() > 1.0 {
            let horizontal = r.width() >= r.height();
            let (row_count, row_size) = self.best_row(&remaining, &r, horizontal, total);

            if row_count == 0 { break; }

            let rem_total: u64 = remaining.iter().map(|i| i.1).sum();
            let fraction = row_size as f32 / rem_total as f32;

            let (row_rect, new_r) = if horizontal {
                let w = r.width() * fraction;
                (
                    Rect::from_min_size(r.min, Vec2::new(w, r.height())),
                    Rect::from_min_size(Pos2::new(r.min.x + w, r.min.y), Vec2::new(r.width() - w, r.height()))
                )
            } else {
                let h = r.height() * fraction;
                (
                    Rect::from_min_size(r.min, Vec2::new(r.width(), h)),
                    Rect::from_min_size(Pos2::new(r.min.x, r.min.y + h), Vec2::new(r.width(), r.height() - h))
                )
            };

            // Layout row items
            let mut pos = row_rect.min;
            for i in 0..row_count {
                let item = &remaining[i];
                let item_frac = item.1 as f32 / row_size as f32;

                let item_rect = if horizontal {
                    let h = row_rect.height() * item_frac;
                    let ir = Rect::from_min_size(pos, Vec2::new(row_rect.width(), h));
                    pos.y += h;
                    ir
                } else {
                    let w = row_rect.width() * item_frac;
                    let ir = Rect::from_min_size(pos, Vec2::new(w, row_rect.height()));
                    pos.x += w;
                    ir
                };

                let padded = item_rect.shrink(1.0);
                if padded.width() > 1.0 && padded.height() > 1.0 {
                    self.treemap_rects.push(TreemapRect {
                        node_id: item.0,
                        rect: padded,
                        name: item.2.clone(),
                        size: item.1,
                        is_dir: item.3,
                        category: item.4,
                    });
                }
            }

            remaining = remaining[row_count..].to_vec();
            r = new_r;
        }
    }

    fn best_row(&self, items: &[(NodeId, u64, String, bool, FileCategory)], rect: &Rect, horiz: bool, total: u64) -> (usize, u64) {
        if items.is_empty() { return (0, 0); }

        let area = (rect.width() * rect.height()) as f64;
        let short = if horiz { rect.height() } else { rect.width() } as f64;

        let mut best_n = 1;
        let mut best_ratio = f64::MAX;
        let mut sum: u64 = 0;

        for i in 0..items.len() {
            sum += items[i].1;
            let row_area = area * (sum as f64 / total as f64);
            let row_short = row_area / short;
            if row_short <= 0.0 { continue; }

            let mut worst = 0.0f64;
            let mut s2: u64 = 0;
            for j in 0..=i {
                s2 += items[j].1;
                let ia = area * (items[j].1 as f64 / total as f64);
                let il = ia / row_short;
                let ratio = (il / row_short).max(row_short / il);
                worst = worst.max(ratio);
            }

            if worst < best_ratio {
                best_ratio = worst;
                best_n = i + 1;
            } else if i > 0 {
                break;
            }
        }

        (best_n, items[..best_n].iter().map(|i| i.1).sum())
    }

    fn render_treemap(&mut self, ui: &mut egui::Ui) {
        let rect = ui.available_rect_before_wrap();

        // Rebuild if needed or size changed
        let size = rect.size();
        if self.needs_rebuild || (size - self.last_treemap_size).length() > 5.0 {
            self.build_treemap(rect.shrink(2.0));
            self.last_treemap_size = size;
            self.needs_rebuild = false;
        }

        let painter = ui.painter();

        // Background
        painter.rect_filled(rect, Rounding::ZERO, Color32::from_rgb(25, 25, 30));

        let mouse_pos = ui.input(|i| i.pointer.hover_pos());
        let mut hovered: Option<NodeId> = None;

        // Draw rectangles with cushion shading
        for tr in &self.treemap_rects {
            let is_hovered = mouse_pos.map(|p| tr.rect.contains(p)).unwrap_or(false);
            let is_selected = self.selected_node == Some(tr.node_id);

            if is_hovered {
                hovered = Some(tr.node_id);
            }

            // Base color
            let base = if tr.is_dir {
                Color32::from_rgb(80, 100, 130)
            } else {
                tr.category.color()
            };

            // Cushion shading effect
            self.draw_cushion_rect(painter, tr.rect, base, is_selected, is_hovered);

            // Label
            if tr.rect.width() > 50.0 && tr.rect.height() > 25.0 {
                let max_chars = (tr.rect.width() / 7.0) as usize;
                let name = if tr.name.len() > max_chars && max_chars > 3 {
                    format!("{}…", &tr.name[..max_chars-1])
                } else {
                    tr.name.clone()
                };

                let text = if tr.rect.height() > 40.0 {
                    format!("{}\n{}", name, Self::format_size(tr.size))
                } else {
                    name
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

        self.hovered_node = hovered;

        // Handle interaction
        let response = ui.allocate_rect(rect, egui::Sense::click());

        if response.clicked() {
            if let Some(pos) = mouse_pos {
                for tr in &self.treemap_rects {
                    if tr.rect.contains(pos) {
                        self.selected_node = Some(tr.node_id);

                        // Ensure visible in tree
                        if let Some(ref tree) = self.tree {
                            for ancestor in tr.node_id.ancestors(&tree.arena) {
                                self.expanded_nodes.insert(ancestor);
                            }
                        }
                        break;
                    }
                }
            }
        }

        if response.double_clicked() {
            if let Some(pos) = mouse_pos {
                for tr in &self.treemap_rects {
                    if tr.rect.contains(pos) && tr.is_dir {
                        self.treemap_root = Some(tr.node_id);
                        self.needs_rebuild = true;
                        break;
                    }
                }
            }
        }

        // Tooltip
        if let Some(hid) = self.hovered_node {
            if let Some(ref tree) = self.tree {
                if let Some(node) = tree.get_node(hid) {
                    egui::show_tooltip(ui.ctx(), ui.layer_id(), egui::Id::new("tm_tip"), |ui| {
                        ui.label(RichText::new(&node.name).strong().size(13.0));
                        ui.label(format!("Size: {}", Self::format_size(node.size)));
                        if node.is_dir {
                            ui.label(format!("Files: {}", node.file_count));
                        } else if let Some(ref ext) = node.extension {
                            ui.label(format!("Type: .{}", ext));
                        }
                    });
                }
            }
        }
    }

    fn draw_cushion_rect(&self, painter: &egui::Painter, rect: Rect, base: Color32, selected: bool, hovered: bool) {
        // Main fill with gradient effect
        let (r, g, b) = (base.r(), base.g(), base.b());

        // Brighten for hover/selection
        let (r, g, b) = if selected {
            ((r as u16 + 50).min(255) as u8, (g as u16 + 50).min(255) as u8, (b as u16 + 50).min(255) as u8)
        } else if hovered {
            ((r as u16 + 25).min(255) as u8, (g as u16 + 25).min(255) as u8, (b as u16 + 25).min(255) as u8)
        } else {
            (r, g, b)
        };

        // Draw base
        painter.rect_filled(rect, Rounding::same(3.0), Color32::from_rgb(r, g, b));

        // Top highlight (cushion effect)
        let highlight_rect = Rect::from_min_size(
            rect.min,
            Vec2::new(rect.width(), rect.height() * 0.4)
        );
        let highlight_color = Color32::from_rgba_unmultiplied(255, 255, 255, 30);
        painter.rect_filled(highlight_rect, Rounding::same(3.0), highlight_color);

        // Bottom shadow
        let shadow_rect = Rect::from_min_size(
            Pos2::new(rect.min.x, rect.min.y + rect.height() * 0.6),
            Vec2::new(rect.width(), rect.height() * 0.4)
        );
        let shadow_color = Color32::from_rgba_unmultiplied(0, 0, 0, 40);
        painter.rect_filled(shadow_rect, Rounding::same(3.0), shadow_color);

        // Border
        let stroke = if selected {
            Stroke::new(2.0, Color32::WHITE)
        } else {
            Stroke::new(1.0, Color32::from_rgba_unmultiplied(0, 0, 0, 80))
        };
        painter.rect_stroke(rect, Rounding::same(3.0), stroke);
    }

    // ========================================================================
    // RIGHT PANEL: File Types
    // ========================================================================

    fn render_types_panel(&mut self, ui: &mut egui::Ui) {
        ui.heading(RichText::new("File Types").size(14.0));
        ui.separator();

        let total_size = self.scan_progress.total_size;
        if total_size == 0 {
            ui.label("No data");
            return;
        }

        // Sort categories by size
        let mut cats: Vec<_> = self.category_stats.iter().collect();
        cats.sort_by(|a, b| b.1.size.cmp(&a.1.size));

        egui::ScrollArea::vertical().show(ui, |ui| {
            for (cat, stats) in cats {
                let pct = (stats.size as f64 / total_size as f64 * 100.0) as u32;

                ui.horizontal(|ui| {
                    // Color box
                    let (cr, _) = ui.allocate_exact_size(Vec2::new(14.0, 14.0), egui::Sense::hover());
                    ui.painter().rect_filled(cr, Rounding::same(3.0), cat.color());

                    // Icon and name
                    ui.label(RichText::new(cat.icon()).size(12.0));
                    ui.label(RichText::new(cat.name()).size(12.0));
                });

                // Progress bar
                let bar_height = 8.0;
                let (bar_rect, _) = ui.allocate_exact_size(Vec2::new(ui.available_width(), bar_height), egui::Sense::hover());
                ui.painter().rect_filled(bar_rect, Rounding::same(2.0), Color32::from_rgb(45, 45, 55));

                let fill_w = bar_rect.width() * (pct as f32 / 100.0).min(1.0);
                let fill_rect = Rect::from_min_size(bar_rect.min, Vec2::new(fill_w, bar_height));
                ui.painter().rect_filled(fill_rect, Rounding::same(2.0), cat.color());

                // Stats text
                ui.horizontal(|ui| {
                    ui.label(RichText::new(Self::format_size(stats.size)).size(11.0).color(Color32::from_rgb(180, 180, 190)));
                    ui.label(RichText::new(format!("{}%", pct)).size(11.0).color(Color32::from_rgb(140, 140, 150)));
                    ui.label(RichText::new(format!("{} files", stats.count)).size(10.0).color(Color32::from_rgb(120, 120, 130)));
                });

                ui.add_space(6.0);
            }
        });
    }
}

// ============================================================================
// App Implementation
// ============================================================================

impl eframe::App for DataXApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        // Auto-start scan
        if !self.scan_started {
            self.scan_started = true;
            self.start_scan();
        }

        self.poll_progress();

        if self.scan_state == ScanState::Scanning {
            ctx.request_repaint();
        }

        // Top bar
        egui::TopBottomPanel::top("top").min_height(32.0).show(ctx, |ui| {
            ui.horizontal_centered(|ui| {
                ui.heading(RichText::new("Data-X").strong().size(16.0));
                ui.separator();

                // Up button
                if self.treemap_root.is_some() && self.treemap_root != self.tree.as_ref().and_then(|t| t.root) {
                    if ui.button("⬆ Up").clicked() {
                        if let Some(ref tree) = self.tree {
                            if let Some(root) = self.treemap_root {
                                self.treemap_root = root.ancestors(&tree.arena).nth(1).or(tree.root);
                                self.needs_rebuild = true;
                            }
                        }
                    }
                    ui.separator();
                }

                ui.checkbox(&mut self.show_hidden, "Show Hidden");

                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    ui.label(RichText::new(self.root_path.display().to_string()).size(12.0).color(Color32::from_rgb(150, 150, 160)));
                });
            });
        });

        // Bottom status
        egui::TopBottomPanel::bottom("bottom").min_height(24.0).show(ctx, |ui| {
            ui.horizontal_centered(|ui| {
                match &self.scan_state {
                    ScanState::Scanning => {
                        ui.spinner();
                        ui.label(format!("Scanning... {} files", self.scan_progress.files_found));
                    }
                    ScanState::Complete => {
                        ui.label(format!("✓ {} files • {}", self.scan_progress.total_files, Self::format_size(self.scan_progress.total_size)));
                        if let Some(ref d) = self.disk_info {
                            ui.separator();
                            ui.label(format!("Disk: {} / {}", Self::format_size(d.used), Self::format_size(d.total)));
                        }
                    }
                    _ => { ui.label("Ready"); }
                }

                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    if let Some(nid) = self.selected_node {
                        if let Some(ref tree) = self.tree {
                            if let Some(node) = tree.get_node(nid) {
                                ui.label(RichText::new(format!("{} • {}", node.name, Self::format_size(node.size))).size(12.0));
                            }
                        }
                    }
                });
            });
        });

        // Main content
        if self.tree.is_none() {
            egui::CentralPanel::default().show(ctx, |ui| {
                ui.centered_and_justified(|ui| {
                    ui.vertical_centered(|ui| {
                        ui.spinner();
                        ui.add_space(10.0);
                        ui.label(RichText::new("Scanning...").size(18.0));
                        ui.label(format!("{} files found", self.scan_progress.files_found));
                        if !self.scan_progress.current_path.is_empty() {
                            let p = &self.scan_progress.current_path;
                            let display = if p.len() > 50 { format!("...{}", &p[p.len()-47..]) } else { p.clone() };
                            ui.label(RichText::new(display).size(11.0).color(Color32::from_rgb(130, 130, 140)));
                        }
                    });
                });
            });
            return;
        }

        // Three-panel layout
        egui::SidePanel::left("tree_panel")
            .default_width(250.0)
            .min_width(150.0)
            .resizable(true)
            .show(ctx, |ui| {
                self.render_tree_panel(ui);
            });

        egui::SidePanel::right("types_panel")
            .default_width(180.0)
            .min_width(120.0)
            .resizable(true)
            .show(ctx, |ui| {
                self.render_types_panel(ui);
            });

        egui::CentralPanel::default().show(ctx, |ui| {
            self.render_treemap(ui);
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
            category_stats: HashMap::new(),
            show_hidden: false,
            scan_state: ScanState::Idle,
            scan_progress: ScanProgressInfo::default(),
            progress_receiver: None,
            scan_started: false,
            disk_info: None,
            treemap_rects: Vec::new(),
            treemap_root: None,
            needs_rebuild: true,
            last_treemap_size: Vec2::ZERO,
        }
    }
}
