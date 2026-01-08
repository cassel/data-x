//! Treemap visualization panel for egui GUI.
//!
//! Implements a squarified treemap algorithm to render disk usage as
//! proportional colored rectangles, similar to Disk Inventory X.

#![cfg(feature = "gui")]

use egui::{Color32, Pos2, Rect, Response, Sense, Stroke, Ui, Vec2};

use crate::tree::{FileTree, NodeId};

/// File type category for coloring.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FileTypeCategory {
    Audio,
    Video,
    Image,
    Document,
    Code,
    Archive,
    Directory,
    Other,
}

impl FileTypeCategory {
    /// Determine file type from extension.
    pub fn from_extension(ext: Option<&str>) -> Self {
        let ext = match ext {
            Some(e) => e.to_lowercase(),
            None => return FileTypeCategory::Other,
        };

        match ext.as_str() {
            // Audio files - Purple
            "mp3" | "wav" | "flac" | "m4a" | "ogg" | "aac" | "wma" | "aiff" | "alac" | "opus" => {
                FileTypeCategory::Audio
            }

            // Video files - Red
            "mp4" | "mkv" | "avi" | "mov" | "wmv" | "webm" | "flv" | "m4v" | "mpeg" | "mpg"
            | "3gp" | "vob" => FileTypeCategory::Video,

            // Image files - Green
            "jpg" | "jpeg" | "png" | "gif" | "webp" | "svg" | "bmp" | "ico" | "tiff" | "tif"
            | "psd" | "raw" | "heic" | "heif" | "avif" => FileTypeCategory::Image,

            // Document files - Blue
            "pdf" | "doc" | "docx" | "txt" | "md" | "rtf" | "odt" | "xls" | "xlsx" | "ppt"
            | "pptx" | "csv" | "pages" | "numbers" | "key" | "epub" | "mobi" => {
                FileTypeCategory::Document
            }

            // Code/source files - Yellow
            "rs" | "py" | "js" | "ts" | "go" | "java" | "c" | "cpp" | "h" | "rb" | "php" | "cs"
            | "swift" | "kt" | "scala" | "clj" | "ex" | "exs" | "erl" | "hs" | "ml" | "lua"
            | "r" | "jl" | "nim" | "zig" | "v" | "vue" | "svelte" | "jsx" | "tsx" | "sh"
            | "bash" | "zsh" | "fish" | "ps1" | "sql" | "graphql" | "proto" | "hpp" | "cc"
            | "cxx" | "hxx" | "fs" | "fsx" | "html" | "htm" | "css" | "scss" | "sass" | "less"
            | "json" | "xml" | "yaml" | "yml" | "toml" | "ini" | "cfg" | "conf" => {
                FileTypeCategory::Code
            }

            // Archive files - Orange
            "zip" | "tar" | "gz" | "rar" | "7z" | "bz2" | "xz" | "zst" | "lz4" | "lzma" | "cab"
            | "iso" | "dmg" | "pkg" | "deb" | "rpm" | "tgz" | "tbz2" | "txz" => {
                FileTypeCategory::Archive
            }

            // Other/unknown
            _ => FileTypeCategory::Other,
        }
    }

    /// Get the base color for this file type.
    /// Colors: audio=purple, video=red, images=green, docs=blue, code=yellow, archives=orange, dirs=gray
    pub fn base_color(&self) -> Color32 {
        match self {
            FileTypeCategory::Audio => Color32::from_rgb(138, 43, 226),    // Purple (Blue Violet)
            FileTypeCategory::Video => Color32::from_rgb(220, 20, 60),     // Red (Crimson)
            FileTypeCategory::Image => Color32::from_rgb(34, 139, 34),     // Green (Forest Green)
            FileTypeCategory::Document => Color32::from_rgb(65, 105, 225), // Blue (Royal Blue)
            FileTypeCategory::Code => Color32::from_rgb(218, 165, 32),     // Yellow (Goldenrod)
            FileTypeCategory::Archive => Color32::from_rgb(255, 140, 0),   // Orange (Dark Orange)
            FileTypeCategory::Directory => Color32::from_rgb(128, 128, 128), // Gray
            FileTypeCategory::Other => Color32::from_rgb(100, 100, 100),   // Dark Gray
        }
    }

    /// Get the hover/selected color for this file type (lighter version).
    pub fn hover_color(&self) -> Color32 {
        match self {
            FileTypeCategory::Audio => Color32::from_rgb(186, 85, 211),    // Medium Orchid
            FileTypeCategory::Video => Color32::from_rgb(255, 99, 71),     // Tomato
            FileTypeCategory::Image => Color32::from_rgb(50, 205, 50),     // Lime Green
            FileTypeCategory::Document => Color32::from_rgb(100, 149, 237), // Cornflower Blue
            FileTypeCategory::Code => Color32::from_rgb(255, 215, 0),      // Gold
            FileTypeCategory::Archive => Color32::from_rgb(255, 165, 0),   // Orange
            FileTypeCategory::Directory => Color32::from_rgb(169, 169, 169), // Dark Gray (lighter)
            FileTypeCategory::Other => Color32::from_rgb(128, 128, 128),   // Gray
        }
    }
}

/// Represents a rectangle in the treemap with its associated node.
#[derive(Debug, Clone)]
pub struct TreemapRect {
    pub node_id: NodeId,
    pub rect: Rect,
    pub size: u64,
    pub name: String,
    pub is_dir: bool,
    pub extension: Option<String>,
    pub path: String,
    pub percentage: f32,
}

impl TreemapRect {
    /// Check if a point is inside this rectangle.
    pub fn contains(&self, pos: Pos2) -> bool {
        self.rect.contains(pos)
    }

    /// Get the file type category for this item.
    pub fn file_type(&self) -> FileTypeCategory {
        if self.is_dir {
            FileTypeCategory::Directory
        } else {
            FileTypeCategory::from_extension(self.extension.as_deref())
        }
    }
}

/// State for the treemap panel.
#[derive(Debug, Clone, Default)]
pub struct TreemapState {
    /// Currently selected node.
    pub selected_node: Option<NodeId>,
    /// Node under the mouse cursor (for hover effects).
    pub hovered_node: Option<NodeId>,
    /// The root node for the current treemap view (for drill-down).
    pub treemap_root: Option<NodeId>,
    /// Cached rectangles from the last render.
    pub cached_rects: Vec<TreemapRect>,
    /// Last mouse position for tooltip.
    pub last_mouse_pos: Option<Pos2>,
}

impl TreemapState {
    pub fn new() -> Self {
        Self::default()
    }

    /// Set the treemap root for drill-down navigation.
    pub fn set_root(&mut self, node_id: Option<NodeId>) {
        self.treemap_root = node_id;
        self.cached_rects.clear();
    }

    /// Find the rectangle at a given position.
    pub fn rect_at_pos(&self, pos: Pos2) -> Option<&TreemapRect> {
        // Search in reverse order (later rectangles are drawn on top)
        self.cached_rects.iter().rev().find(|r| r.contains(pos))
    }
}

/// Treemap panel for egui.
pub struct TreemapPanel<'a> {
    tree: &'a FileTree,
    state: &'a mut TreemapState,
    min_rect_size: f32,
}

impl<'a> TreemapPanel<'a> {
    pub fn new(tree: &'a FileTree, state: &'a mut TreemapState) -> Self {
        Self {
            tree,
            state,
            min_rect_size: 4.0,
        }
    }

    /// Set the minimum rectangle size (rectangles smaller than this won't be rendered).
    #[allow(dead_code)]
    pub fn min_rect_size(mut self, size: f32) -> Self {
        self.min_rect_size = size;
        self
    }

    /// Show the treemap panel and return interaction result.
    pub fn show(self, ui: &mut Ui) -> TreemapResponse {
        let available_rect = ui.available_rect_before_wrap();

        // Allocate the entire available space
        let (response, painter) = ui.allocate_painter(available_rect.size(), Sense::click_and_drag());
        let rect = response.rect;

        // Determine the root node for the treemap
        let root_id = self.state.treemap_root.or(self.tree.root);

        let mut treemap_response = TreemapResponse {
            response: response.clone(),
            clicked_node: None,
            double_clicked_node: None,
            hovered_node: None,
        };

        let root_id = match root_id {
            Some(id) => id,
            None => {
                // No root - draw empty state
                painter.rect_filled(rect, 0.0, Color32::from_gray(30));
                painter.text(
                    rect.center(),
                    egui::Align2::CENTER_CENTER,
                    "No data to display",
                    egui::FontId::proportional(16.0),
                    Color32::GRAY,
                );
                return treemap_response;
            }
        };

        let root_data = match self.tree.get_node(root_id) {
            Some(n) => n,
            None => return treemap_response,
        };

        // Empty directory
        if root_data.size == 0 {
            painter.rect_filled(rect, 0.0, Color32::from_gray(30));
            painter.text(
                rect.center(),
                egui::Align2::CENTER_CENTER,
                "Empty directory",
                egui::FontId::proportional(16.0),
                Color32::GRAY,
            );
            return treemap_response;
        }

        // Get children for treemap
        let children = self.tree.get_children(root_id);
        if children.is_empty() {
            // Single file - fill entire area
            let file_type = if root_data.is_dir {
                FileTypeCategory::Directory
            } else {
                FileTypeCategory::from_extension(root_data.extension.as_deref())
            };

            let is_selected = self.state.selected_node == Some(root_id);
            let is_hovered = self.state.hovered_node == Some(root_id);
            let color = if is_selected || is_hovered {
                file_type.hover_color()
            } else {
                file_type.base_color()
            };

            painter.rect_filled(rect, 0.0, color);
            draw_rect_label(&painter, rect, &root_data.name, root_data.size, 100.0);

            self.state.cached_rects = vec![TreemapRect {
                node_id: root_id,
                rect,
                size: root_data.size,
                name: root_data.name.clone(),
                is_dir: root_data.is_dir,
                extension: root_data.extension.clone(),
                path: root_data.path.to_string_lossy().to_string(),
                percentage: 100.0,
            }];

            return treemap_response;
        }

        // Build items for treemap layout
        let mut items: Vec<(NodeId, u64, String, bool, Option<String>, String)> = children
            .iter()
            .filter_map(|&child_id| {
                self.tree.get_node(child_id).map(|n| {
                    (
                        child_id,
                        n.size,
                        n.name.clone(),
                        n.is_dir,
                        n.extension.clone(),
                        n.path.to_string_lossy().to_string(),
                    )
                })
            })
            .filter(|(_, size, _, _, _, _)| *size > 0)
            .collect();

        // Sort by size descending
        items.sort_by(|a, b| b.1.cmp(&a.1));

        if items.is_empty() {
            painter.rect_filled(rect, 0.0, Color32::from_gray(30));
            painter.text(
                rect.center(),
                egui::Align2::CENTER_CENTER,
                "No files with size",
                egui::FontId::proportional(16.0),
                Color32::GRAY,
            );
            return treemap_response;
        }

        // Calculate treemap layout using squarified algorithm
        let total_size: u64 = items.iter().map(|(_, s, _, _, _, _)| *s).sum();
        let layout_rects = squarify(
            &items,
            rect.min.x,
            rect.min.y,
            rect.width(),
            rect.height(),
            total_size,
        );

        // Draw background
        painter.rect_filled(rect, 0.0, Color32::from_gray(20));

        // Build and cache TreemapRects
        let mut cached_rects = Vec::new();

        for (node_id, size, name, is_dir, extension, path, x, y, w, h) in layout_rects {
            // Skip very small rectangles
            if w < self.min_rect_size || h < self.min_rect_size {
                continue;
            }

            let item_rect = Rect::from_min_size(Pos2::new(x, y), Vec2::new(w, h));
            let percentage = if total_size > 0 {
                (size as f64 / total_size as f64 * 100.0) as f32
            } else {
                0.0
            };

            cached_rects.push(TreemapRect {
                node_id,
                rect: item_rect,
                size,
                name,
                is_dir,
                extension,
                path,
                percentage,
            });
        }

        // Update mouse position and detect hover
        let mouse_pos = ui.input(|i| i.pointer.hover_pos());
        self.state.last_mouse_pos = mouse_pos;

        if let Some(pos) = mouse_pos {
            if rect.contains(pos) {
                self.state.hovered_node = cached_rects
                    .iter()
                    .rev()
                    .find(|r| r.contains(pos))
                    .map(|r| r.node_id);
            } else {
                self.state.hovered_node = None;
            }
        }

        // Draw rectangles
        for treemap_rect in &cached_rects {
            let is_selected = self.state.selected_node == Some(treemap_rect.node_id);
            let is_hovered = self.state.hovered_node == Some(treemap_rect.node_id);

            let file_type = treemap_rect.file_type();
            let fill_color = if is_selected || is_hovered {
                file_type.hover_color()
            } else {
                file_type.base_color()
            };

            // Draw filled rectangle
            painter.rect_filled(treemap_rect.rect, 0.0, fill_color);

            // Draw border
            let border_color = if is_selected {
                Color32::WHITE
            } else {
                Color32::from_gray(40)
            };
            let border_width = if is_selected { 2.0 } else { 1.0 };
            painter.rect_stroke(treemap_rect.rect, 0.0, Stroke::new(border_width, border_color));

            // Draw label if rectangle is large enough
            draw_rect_label(
                &painter,
                treemap_rect.rect,
                &treemap_rect.name,
                treemap_rect.size,
                treemap_rect.percentage,
            );
        }

        // Handle clicks
        if response.clicked() {
            if let Some(pos) = response.interact_pointer_pos() {
                if let Some(treemap_rect) = cached_rects.iter().rev().find(|r| r.contains(pos)) {
                    treemap_response.clicked_node = Some(treemap_rect.node_id);
                    self.state.selected_node = Some(treemap_rect.node_id);
                }
            }
        }

        // Handle double-clicks
        if response.double_clicked() {
            if let Some(pos) = response.interact_pointer_pos() {
                if let Some(treemap_rect) = cached_rects.iter().rev().find(|r| r.contains(pos)) {
                    if treemap_rect.is_dir {
                        treemap_response.double_clicked_node = Some(treemap_rect.node_id);
                    }
                }
            }
        }

        // Set hovered node for response
        treemap_response.hovered_node = self.state.hovered_node;

        // Store cached rects
        self.state.cached_rects = cached_rects;

        // Show tooltip for hovered item
        if let Some(hovered_id) = self.state.hovered_node {
            if let Some(treemap_rect) = self.state.cached_rects.iter().find(|r| r.node_id == hovered_id) {
                egui::show_tooltip_at_pointer(
                    ui.ctx(),
                    egui::LayerId::new(egui::Order::Tooltip, egui::Id::new("treemap_tooltip_layer")),
                    egui::Id::new("treemap_tooltip"),
                    |ui: &mut Ui| {
                        ui.label(&treemap_rect.path);
                        ui.label(format_size(treemap_rect.size));
                        ui.label(format!("{:.1}%", treemap_rect.percentage));
                    },
                );
            }
        }

        treemap_response
    }
}

/// Response from the treemap panel.
pub struct TreemapResponse {
    /// The underlying egui response.
    pub response: Response,
    /// Node that was clicked (single click = select).
    pub clicked_node: Option<NodeId>,
    /// Directory that was double-clicked (drill into).
    pub double_clicked_node: Option<NodeId>,
    /// Currently hovered node.
    pub hovered_node: Option<NodeId>,
}

/// Draw a label inside a rectangle if it's large enough.
fn draw_rect_label(painter: &egui::Painter, rect: Rect, name: &str, size: u64, percentage: f32) {
    const MIN_WIDTH_FOR_TEXT: f32 = 40.0;
    const MIN_HEIGHT_FOR_TEXT: f32 = 20.0;
    const MIN_HEIGHT_FOR_SIZE: f32 = 36.0;

    if rect.width() < MIN_WIDTH_FOR_TEXT || rect.height() < MIN_HEIGHT_FOR_TEXT {
        return;
    }

    let padding = 4.0;
    let text_rect = rect.shrink(padding);

    // Calculate max characters that fit
    let char_width = 7.0; // Approximate character width
    let max_chars = ((text_rect.width() / char_width) as usize).max(1);

    // Truncate name if needed
    let truncated_name = truncate_name(name, max_chars);

    // Draw name
    let name_pos = Pos2::new(text_rect.min.x, text_rect.min.y);
    painter.text(
        name_pos,
        egui::Align2::LEFT_TOP,
        &truncated_name,
        egui::FontId::proportional(12.0),
        Color32::WHITE,
    );

    // Draw size if there's enough height
    if rect.height() >= MIN_HEIGHT_FOR_SIZE {
        let size_text = format!("{} ({:.0}%)", format_size(size), percentage);
        let size_pos = Pos2::new(text_rect.min.x, text_rect.min.y + 14.0);
        painter.text(
            size_pos,
            egui::Align2::LEFT_TOP,
            &size_text,
            egui::FontId::proportional(10.0),
            Color32::from_gray(220),
        );
    }
}

/// Truncate a name to fit within max_chars, adding ellipsis if needed.
fn truncate_name(s: &str, max_chars: usize) -> String {
    if max_chars == 0 {
        return String::new();
    }

    let char_count = s.chars().count();
    if char_count <= max_chars {
        s.to_string()
    } else if max_chars <= 3 {
        s.chars().take(max_chars).collect()
    } else {
        let truncated: String = s.chars().take(max_chars - 1).collect();
        format!("{}...", truncated)
    }
}

/// Format a byte size into a human-readable string.
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

/// Squarified treemap algorithm.
/// Returns: Vec<(NodeId, size, name, is_dir, extension, path, x, y, width, height)>
fn squarify(
    items: &[(NodeId, u64, String, bool, Option<String>, String)],
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    total_size: u64,
) -> Vec<(NodeId, u64, String, bool, Option<String>, String, f32, f32, f32, f32)> {
    let mut result = Vec::new();

    if items.is_empty() || total_size == 0 || width <= 0.0 || height <= 0.0 {
        return result;
    }

    // Normalize sizes to area
    let area = (width * height) as f64;
    let scale = area / total_size as f64;

    // Use squarified algorithm with row-based layout
    let mut remaining: Vec<_> = items.to_vec();
    let mut current_x = x;
    let mut current_y = y;
    let mut current_width = width;
    let mut current_height = height;

    while !remaining.is_empty() {
        // Determine layout direction (lay out along the shorter side)
        let horizontal = current_width >= current_height;
        let side = if horizontal { current_height } else { current_width };

        // Find the best row
        let (row, rest) = find_best_row(&remaining, side as f64, scale);

        if row.is_empty() {
            break;
        }

        // Calculate total area for this row
        let row_area: f64 = row.iter().map(|(_, size, _, _, _, _)| *size as f64 * scale).sum();
        let row_size = if side > 0.0 { (row_area / side as f64) as f32 } else { 0.0 };

        // Layout items in the row
        let mut offset = 0.0f32;
        for (node_id, size, name, is_dir, extension, path) in &row {
            let item_area = *size as f64 * scale;
            let item_size = if row_size > 0.0 { (item_area / row_size as f64) as f32 } else { 0.0 };

            let (rx, ry, rw, rh) = if horizontal {
                (current_x, current_y + offset, row_size, item_size)
            } else {
                (current_x + offset, current_y, item_size, row_size)
            };

            result.push((
                *node_id,
                *size,
                name.clone(),
                *is_dir,
                extension.clone(),
                path.clone(),
                rx,
                ry,
                rw,
                rh,
            ));

            offset += item_size;
        }

        // Update remaining area
        if horizontal {
            current_x += row_size;
            current_width -= row_size;
        } else {
            current_y += row_size;
            current_height -= row_size;
        }

        remaining = rest;
    }

    result
}

/// Find the best row of items to lay out along a side.
/// Returns (items in row, remaining items).
fn find_best_row(
    items: &[(NodeId, u64, String, bool, Option<String>, String)],
    side: f64,
    scale: f64,
) -> (Vec<(NodeId, u64, String, bool, Option<String>, String)>, Vec<(NodeId, u64, String, bool, Option<String>, String)>) {
    if items.is_empty() {
        return (vec![], vec![]);
    }

    let mut row: Vec<(NodeId, u64, String, bool, Option<String>, String)> = Vec::new();
    let mut row_area = 0.0f64;
    let mut best_ratio = f64::MAX;

    for (i, item) in items.iter().enumerate() {
        let item_area = item.1 as f64 * scale;
        let new_row_area = row_area + item_area;

        // Calculate worst aspect ratio if we add this item
        let row_size = new_row_area / side;
        let mut worst_ratio = 0.0f64;

        // Check existing items in row
        for existing in &row {
            let existing_area = existing.1 as f64 * scale;
            let item_size = existing_area / row_size;
            let ratio = if item_size > row_size {
                item_size / row_size
            } else {
                row_size / item_size
            };
            worst_ratio = worst_ratio.max(ratio);
        }

        // Check new item
        let new_item_size = item_area / row_size;
        let new_ratio = if new_item_size > row_size {
            new_item_size / row_size
        } else {
            row_size / new_item_size
        };
        worst_ratio = worst_ratio.max(new_ratio);

        if worst_ratio <= best_ratio || row.is_empty() {
            // Adding this item improves or maintains the aspect ratio
            row.push(item.clone());
            row_area = new_row_area;
            best_ratio = worst_ratio;
        } else {
            // Adding this item makes it worse, stop here
            return (row, items[i..].to_vec());
        }
    }

    (row, vec![])
}

#[cfg(all(test, feature = "gui"))]
mod tests {
    use super::*;

    #[test]
    fn test_file_type_from_extension_audio() {
        assert_eq!(FileTypeCategory::from_extension(Some("mp3")), FileTypeCategory::Audio);
        assert_eq!(FileTypeCategory::from_extension(Some("MP3")), FileTypeCategory::Audio);
        assert_eq!(FileTypeCategory::from_extension(Some("wav")), FileTypeCategory::Audio);
    }

    #[test]
    fn test_file_type_from_extension_video() {
        assert_eq!(FileTypeCategory::from_extension(Some("mp4")), FileTypeCategory::Video);
        assert_eq!(FileTypeCategory::from_extension(Some("mkv")), FileTypeCategory::Video);
    }

    #[test]
    fn test_file_type_from_extension_image() {
        assert_eq!(FileTypeCategory::from_extension(Some("png")), FileTypeCategory::Image);
        assert_eq!(FileTypeCategory::from_extension(Some("jpg")), FileTypeCategory::Image);
    }

    #[test]
    fn test_file_type_from_extension_document() {
        assert_eq!(FileTypeCategory::from_extension(Some("pdf")), FileTypeCategory::Document);
        assert_eq!(FileTypeCategory::from_extension(Some("txt")), FileTypeCategory::Document);
    }

    #[test]
    fn test_file_type_from_extension_code() {
        assert_eq!(FileTypeCategory::from_extension(Some("rs")), FileTypeCategory::Code);
        assert_eq!(FileTypeCategory::from_extension(Some("py")), FileTypeCategory::Code);
    }

    #[test]
    fn test_file_type_from_extension_archive() {
        assert_eq!(FileTypeCategory::from_extension(Some("zip")), FileTypeCategory::Archive);
        assert_eq!(FileTypeCategory::from_extension(Some("tar")), FileTypeCategory::Archive);
    }

    #[test]
    fn test_file_type_from_extension_other() {
        assert_eq!(FileTypeCategory::from_extension(Some("xyz")), FileTypeCategory::Other);
        assert_eq!(FileTypeCategory::from_extension(None), FileTypeCategory::Other);
    }

    #[test]
    fn test_truncate_name() {
        assert_eq!(truncate_name("hello", 10), "hello");
        assert_eq!(truncate_name("hello world test", 8), "hello w...");
        assert_eq!(truncate_name("hello", 0), "");
        assert_eq!(truncate_name("hello", 2), "he");
    }

    #[test]
    fn test_format_size() {
        assert_eq!(format_size(0), "0 B");
        assert_eq!(format_size(512), "512 B");
        assert_eq!(format_size(1024), "1.0 KB");
        assert_eq!(format_size(1024 * 1024), "1.0 MB");
        assert_eq!(format_size(1024 * 1024 * 1024), "1.0 GB");
    }

    #[test]
    fn test_base_colors_distinct() {
        let categories = [
            FileTypeCategory::Audio,
            FileTypeCategory::Video,
            FileTypeCategory::Image,
            FileTypeCategory::Document,
            FileTypeCategory::Code,
            FileTypeCategory::Archive,
            FileTypeCategory::Directory,
            FileTypeCategory::Other,
        ];

        // Verify all colors are different
        for i in 0..categories.len() {
            for j in (i + 1)..categories.len() {
                assert_ne!(
                    categories[i].base_color(),
                    categories[j].base_color(),
                    "Colors for {:?} and {:?} should be different",
                    categories[i],
                    categories[j]
                );
            }
        }
    }
}
