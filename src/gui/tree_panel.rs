//! Tree view panel for the Data-X egui GUI disk analyzer.
//!
//! This module provides the tree panel component that displays the file system
//! tree with size visualization bars, icons, and navigation state.

#![cfg(feature = "gui")]

use std::collections::HashSet;

use egui::{Color32, Key, Response, Sense, Ui, Vec2};

use crate::tree::{FileNode, FileTree, NodeId};

/// Size thresholds for file categorization (matching TUI colors.rs)
const SIZE_SMALL: u64 = 1_048_576; // 1 MB
const SIZE_MEDIUM: u64 = 104_857_600; // 100 MB
const SIZE_LARGE: u64 = 1_073_741_824; // 1 GB

/// State for the tree panel widget.
#[derive(Debug, Clone)]
pub struct TreePanelState {
    /// Currently selected node ID.
    pub selected_node: Option<NodeId>,
    /// Set of node IDs that are currently expanded.
    pub expanded_nodes: HashSet<NodeId>,
    /// Scroll offset for keyboard navigation tracking.
    pub scroll_to_selected: bool,
    /// Search/filter query.
    pub search_query: String,
    /// Cached list of visible nodes for keyboard navigation.
    visible_nodes: Vec<NodeId>,
}

impl Default for TreePanelState {
    fn default() -> Self {
        Self::new()
    }
}

impl TreePanelState {
    /// Create a new TreePanelState.
    pub fn new() -> Self {
        Self {
            selected_node: None,
            expanded_nodes: HashSet::new(),
            scroll_to_selected: false,
            search_query: String::new(),
            visible_nodes: Vec::new(),
        }
    }

    /// Create a new TreePanelState with the root node expanded.
    pub fn with_root_expanded(root_id: NodeId) -> Self {
        let mut state = Self::new();
        state.expanded_nodes.insert(root_id);
        state
    }

    /// Toggle the expansion state of a node.
    pub fn toggle_expand(&mut self, node_id: NodeId) {
        if self.expanded_nodes.contains(&node_id) {
            self.expanded_nodes.remove(&node_id);
        } else {
            self.expanded_nodes.insert(node_id);
        }
    }

    /// Expand a node.
    pub fn expand(&mut self, node_id: NodeId) {
        self.expanded_nodes.insert(node_id);
    }

    /// Collapse a node.
    pub fn collapse(&mut self, node_id: NodeId) {
        self.expanded_nodes.remove(&node_id);
    }

    /// Check if a node is expanded.
    pub fn is_expanded(&self, node_id: NodeId) -> bool {
        self.expanded_nodes.contains(&node_id)
    }

    /// Select a node.
    pub fn select(&mut self, node_id: NodeId) {
        self.selected_node = Some(node_id);
        self.scroll_to_selected = true;
    }

    /// Clear selection.
    pub fn clear_selection(&mut self) {
        self.selected_node = None;
    }

    /// Get the currently selected node.
    pub fn selected(&self) -> Option<NodeId> {
        self.selected_node
    }

    /// Move selection up in the visible nodes list.
    pub fn select_previous(&mut self) {
        if self.visible_nodes.is_empty() {
            return;
        }

        if let Some(current) = self.selected_node {
            if let Some(pos) = self.visible_nodes.iter().position(|&id| id == current) {
                if pos > 0 {
                    self.selected_node = Some(self.visible_nodes[pos - 1]);
                    self.scroll_to_selected = true;
                }
            }
        } else if !self.visible_nodes.is_empty() {
            self.selected_node = Some(self.visible_nodes[0]);
            self.scroll_to_selected = true;
        }
    }

    /// Move selection down in the visible nodes list.
    pub fn select_next(&mut self) {
        if self.visible_nodes.is_empty() {
            return;
        }

        if let Some(current) = self.selected_node {
            if let Some(pos) = self.visible_nodes.iter().position(|&id| id == current) {
                if pos + 1 < self.visible_nodes.len() {
                    self.selected_node = Some(self.visible_nodes[pos + 1]);
                    self.scroll_to_selected = true;
                }
            }
        } else if !self.visible_nodes.is_empty() {
            self.selected_node = Some(self.visible_nodes[0]);
            self.scroll_to_selected = true;
        }
    }

    /// Get the parent of the currently selected node.
    pub fn get_selected_parent(&self, tree: &FileTree) -> Option<NodeId> {
        self.selected_node.and_then(|id| tree.get_parent(id))
    }
}

/// Color scheme for the tree panel (egui Color32 version).
#[derive(Debug, Clone)]
pub struct TreePanelColors {
    /// Color for directories
    pub dirs: Color32,
    /// Color for small files (< 1MB)
    pub small_files: Color32,
    /// Color for medium files (1MB - 100MB)
    pub medium_files: Color32,
    /// Color for large files (100MB - 1GB)
    pub large_files: Color32,
    /// Color for huge files (>= 1GB)
    pub huge_files: Color32,
    /// Color for media files
    pub media: Color32,
    /// Color for compressed files
    pub compressed: Color32,
    /// Color for hidden files
    pub hidden: Color32,
    /// Color for symlinks
    pub symlink: Color32,
    /// Color for selected items
    pub selected: Color32,
    /// Color for selected item background
    pub selected_bg: Color32,
    /// Normal text color
    pub text: Color32,
    /// Dimmed text color
    pub text_dim: Color32,
    /// Bar background color
    pub bar_bg: Color32,
}

impl Default for TreePanelColors {
    fn default() -> Self {
        Self::dark()
    }
}

impl TreePanelColors {
    /// Create dark theme colors.
    pub fn dark() -> Self {
        Self {
            dirs: Color32::from_rgb(100, 149, 237),       // Cornflower blue
            small_files: Color32::from_rgb(144, 238, 144), // Light green
            medium_files: Color32::from_rgb(255, 215, 0),  // Gold
            large_files: Color32::from_rgb(255, 140, 0),   // Dark orange
            huge_files: Color32::from_rgb(255, 69, 0),     // Red-orange
            media: Color32::from_rgb(218, 112, 214),       // Orchid
            compressed: Color32::from_rgb(0, 206, 209),    // Dark turquoise
            hidden: Color32::from_rgb(169, 169, 169),      // Dark gray
            symlink: Color32::from_rgb(135, 206, 250),     // Light sky blue
            selected: Color32::from_rgb(255, 215, 0),      // Gold
            selected_bg: Color32::from_rgb(60, 60, 80),    // Dark blue-gray
            text: Color32::from_rgb(248, 248, 242),        // Off-white
            text_dim: Color32::from_rgb(136, 136, 136),    // Medium gray
            bar_bg: Color32::from_rgb(40, 40, 50),         // Dark background
        }
    }

    /// Get color for a file based on its extension.
    pub fn extension_to_color(&self, ext: &str) -> Color32 {
        let ext_lower = ext.to_lowercase();
        match ext_lower.as_str() {
            // Media files
            "mp3" | "mp4" | "wav" | "flac" | "avi" | "mkv" | "mov" | "webm" | "ogg" | "m4a"
            | "aac" | "wma" | "jpg" | "jpeg" | "png" | "gif" | "bmp" | "svg" | "webp" | "ico"
            | "tiff" | "tif" | "psd" | "raw" | "heic" | "heif" => self.media,

            // Compressed/archive files
            "zip" | "tar" | "gz" | "7z" | "rar" | "bz2" | "xz" | "zst" | "lz4" | "lzma"
            | "cab" | "iso" | "dmg" | "pkg" | "deb" | "rpm" => self.compressed,

            // Source code files
            "rs" | "py" | "js" | "ts" | "go" | "c" | "cpp" | "cc" | "cxx" | "h" | "hpp"
            | "java" | "kt" | "swift" | "rb" | "php" | "cs" | "fs" | "hs" | "ml" | "scala"
            | "clj" | "ex" | "exs" | "erl" | "lua" | "r" | "jl" | "nim" | "zig" | "v"
            | "vue" | "svelte" | "jsx" | "tsx" | "sh" | "bash" | "zsh" | "fish" | "ps1"
            | "sql" | "graphql" | "proto" => Color32::from_rgb(152, 195, 121), // Soft green

            // Document files
            "pdf" | "doc" | "docx" | "txt" | "md" | "markdown" | "rtf" | "odt" | "xls"
            | "xlsx" | "ppt" | "pptx" | "csv" | "json" | "xml" | "yaml" | "yml" | "toml"
            | "ini" | "cfg" | "conf" | "html" | "htm" | "css" | "scss" | "sass" | "less" => {
                Color32::from_rgb(97, 175, 239) // Soft blue
            }

            // Default
            _ => self.text_dim,
        }
    }

    /// Get color based on file size.
    pub fn size_to_color(&self, size: u64) -> Color32 {
        if size < SIZE_SMALL {
            self.small_files
        } else if size < SIZE_MEDIUM {
            self.medium_files
        } else if size < SIZE_LARGE {
            self.large_files
        } else {
            self.huge_files
        }
    }
}

/// Format a byte size into a human-readable string.
pub fn format_size(bytes: u64) -> String {
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

/// Get the appropriate icon for a file node.
fn get_icon(node: &FileNode, is_expanded: bool) -> &'static str {
    if node.is_symlink {
        return "\u{1f517}"; // Link symbol
    }

    if node.is_dir {
        if is_expanded {
            return "\u{1f4c2}"; // Open folder
        } else {
            return "\u{1f4c1}"; // Closed folder
        }
    }

    // Check extension for file type
    if let Some(ref ext) = node.extension {
        // Audio files
        if matches!(
            ext.as_str(),
            "mp3" | "wav" | "flac" | "aac" | "ogg" | "m4a" | "wma" | "aiff"
        ) {
            return "\u{1f3b5}"; // Musical note
        }

        // Video files
        if matches!(
            ext.as_str(),
            "mp4" | "mkv" | "avi" | "mov" | "wmv" | "flv" | "webm" | "m4v"
        ) {
            return "\u{1f3ac}"; // Clapper board
        }

        // Archive files
        if matches!(
            ext.as_str(),
            "zip" | "tar" | "gz" | "bz2" | "xz" | "7z" | "rar" | "tgz" | "tbz"
        ) {
            return "\u{1f4e6}"; // Package
        }
    }

    "\u{1f4c4}" // Document/file
}

/// Compute depth of a node by traversing up to root.
fn compute_node_depth(tree: &FileTree, node_id: NodeId) -> usize {
    let mut depth = 0;
    let mut current = node_id;
    while let Some(parent) = tree.get_parent(current) {
        depth += 1;
        current = parent;
    }
    depth
}

/// Render the tree panel.
///
/// # Arguments
/// * `ui` - The egui Ui to render into
/// * `tree` - The file tree to display
/// * `state` - The tree panel state (for selection, expansion)
pub fn render_tree_panel(ui: &mut Ui, tree: &FileTree, state: &mut TreePanelState) {
    render_tree_panel_with_colors(ui, tree, state, &TreePanelColors::default())
}

/// Render the tree panel with custom colors.
///
/// # Arguments
/// * `ui` - The egui Ui to render into
/// * `tree` - The file tree to display
/// * `state` - The tree panel state (for selection, expansion)
/// * `colors` - The color scheme to use
pub fn render_tree_panel_with_colors(
    ui: &mut Ui,
    tree: &FileTree,
    state: &mut TreePanelState,
    colors: &TreePanelColors,
) {
    // Handle keyboard input
    handle_keyboard_input(ui, tree, state);

    // Build visible nodes list for navigation
    state.visible_nodes.clear();

    // Get root size for percentage calculations
    let root_size = tree.total_size();

    // Render in a scroll area
    egui::ScrollArea::vertical()
        .auto_shrink([false, false])
        .show(ui, |ui| {
            if let Some(root_id) = tree.root {
                render_node_recursive(ui, tree, root_id, state, colors, root_size, 0);
            } else {
                ui.label("No files to display");
            }
        });
}

/// Handle keyboard input for tree navigation.
fn handle_keyboard_input(ui: &mut Ui, tree: &FileTree, state: &mut TreePanelState) {
    // Only handle input if this widget has focus
    if !ui.memory(|mem| mem.has_focus(ui.id())) {
        // Request focus on click
        let response = ui.interact(ui.max_rect(), ui.id(), Sense::click());
        if response.clicked() {
            ui.memory_mut(|mem| mem.request_focus(ui.id()));
        }
        return;
    }

    let events = ui.input(|i| i.events.clone());
    for event in events {
        if let egui::Event::Key { key, pressed: true, .. } = event {
            match key {
                Key::ArrowUp => {
                    state.select_previous();
                }
                Key::ArrowDown => {
                    state.select_next();
                }
                Key::ArrowRight | Key::Enter => {
                    // Expand selected directory or toggle
                    if let Some(selected) = state.selected_node {
                        if let Some(node) = tree.get_node(selected) {
                            if node.is_dir {
                                state.expand(selected);
                            }
                        }
                    }
                }
                Key::ArrowLeft => {
                    // Collapse selected directory or go to parent
                    if let Some(selected) = state.selected_node {
                        if state.is_expanded(selected) {
                            state.collapse(selected);
                        } else if let Some(parent) = tree.get_parent(selected) {
                            state.select(parent);
                        }
                    }
                }
                Key::Backspace => {
                    // Go to parent
                    if let Some(selected) = state.selected_node {
                        if let Some(parent) = tree.get_parent(selected) {
                            state.select(parent);
                        }
                    }
                }
                Key::Space => {
                    // Toggle expansion
                    if let Some(selected) = state.selected_node {
                        if let Some(node) = tree.get_node(selected) {
                            if node.is_dir {
                                state.toggle_expand(selected);
                            }
                        }
                    }
                }
                Key::Home => {
                    // Select first visible node
                    if !state.visible_nodes.is_empty() {
                        state.selected_node = Some(state.visible_nodes[0]);
                        state.scroll_to_selected = true;
                    }
                }
                Key::End => {
                    // Select last visible node
                    if !state.visible_nodes.is_empty() {
                        state.selected_node = Some(state.visible_nodes[state.visible_nodes.len() - 1]);
                        state.scroll_to_selected = true;
                    }
                }
                _ => {}
            }
        }
    }
}

/// Recursively render a node and its children.
fn render_node_recursive(
    ui: &mut Ui,
    tree: &FileTree,
    node_id: NodeId,
    state: &mut TreePanelState,
    colors: &TreePanelColors,
    parent_size: u64,
    depth: usize,
) {
    let node = match tree.get_node(node_id) {
        Some(n) => n,
        None => return,
    };

    // Add to visible nodes list
    state.visible_nodes.push(node_id);

    let is_expanded = state.is_expanded(node_id);
    let is_selected = state.selected_node == Some(node_id);
    let has_children = !tree.get_children(node_id).is_empty();

    // Calculate percentage
    let percentage = if parent_size > 0 {
        (node.size as f64 / parent_size as f64 * 100.0).min(100.0)
    } else {
        0.0
    };

    // Render the node row
    let response = render_node_row(
        ui,
        node,
        depth,
        is_expanded,
        is_selected,
        has_children,
        percentage,
        parent_size,
        colors,
    );

    // Handle interactions
    if response.clicked() {
        state.select(node_id);
    }

    if response.double_clicked() && node.is_dir {
        state.toggle_expand(node_id);
    }

    // Handle scroll to selected
    if is_selected && state.scroll_to_selected {
        response.scroll_to_me(Some(egui::Align::Center));
        state.scroll_to_selected = false;
    }

    // Render children if expanded
    if is_expanded && node.is_dir {
        let children = tree.get_children(node_id);

        // Sort children: directories first, then by size descending
        let mut sorted_children: Vec<_> = children
            .into_iter()
            .filter_map(|id| tree.get_node(id).map(|n| (id, n)))
            .collect();

        sorted_children.sort_by(|(_, a), (_, b)| {
            match (a.is_dir, b.is_dir) {
                (true, false) => std::cmp::Ordering::Less,
                (false, true) => std::cmp::Ordering::Greater,
                _ => b.size.cmp(&a.size),
            }
        });

        for (child_id, _) in sorted_children {
            render_node_recursive(
                ui,
                tree,
                child_id,
                state,
                colors,
                node.size.max(1), // Use parent's size for percentage
                depth + 1,
            );
        }
    }
}

/// Render a single node row.
fn render_node_row(
    ui: &mut Ui,
    node: &FileNode,
    depth: usize,
    is_expanded: bool,
    is_selected: bool,
    has_children: bool,
    percentage: f64,
    _parent_size: u64,
    colors: &TreePanelColors,
) -> Response {
    let indent = depth as f32 * 20.0;
    let row_height = 22.0;
    let bar_width = 80.0;
    let size_width = 70.0;
    let percent_width = 45.0;

    // Allocate space for the row
    let available_width = ui.available_width();
    let (rect, response) = ui.allocate_exact_size(
        Vec2::new(available_width, row_height),
        Sense::click(),
    );

    if ui.is_rect_visible(rect) {
        let painter = ui.painter();

        // Draw selection background
        if is_selected {
            painter.rect_filled(rect, 2.0, colors.selected_bg);
        } else if response.hovered() {
            painter.rect_filled(
                rect,
                2.0,
                Color32::from_rgba_unmultiplied(100, 100, 100, 30),
            );
        }

        // Calculate positions
        let mut x = rect.left() + indent + 4.0;
        let y_center = rect.center().y;

        // Draw expand/collapse arrow for directories
        if node.is_dir && has_children {
            let arrow = if is_expanded { "\u{25BC}" } else { "\u{25B6}" }; // Down or right arrow
            let arrow_color = colors.text_dim;
            painter.text(
                egui::pos2(x, y_center),
                egui::Align2::LEFT_CENTER,
                arrow,
                egui::FontId::proportional(10.0),
                arrow_color,
            );
        }
        x += 14.0;

        // Draw icon
        let icon = get_icon(node, is_expanded);
        let icon_color = get_node_color(node, is_expanded, colors);
        painter.text(
            egui::pos2(x, y_center),
            egui::Align2::LEFT_CENTER,
            icon,
            egui::FontId::proportional(14.0),
            icon_color,
        );
        x += 20.0;

        // Draw name
        let name_color = if is_selected {
            colors.selected
        } else if node.is_hidden {
            colors.hidden
        } else if node.is_dir {
            colors.dirs
        } else {
            colors.text
        };

        let max_name_width = available_width - indent - 14.0 - 20.0 - bar_width - size_width - percent_width - 20.0;
        let name = truncate_name(&node.name, max_name_width, ui);

        painter.text(
            egui::pos2(x, y_center),
            egui::Align2::LEFT_CENTER,
            &name,
            egui::FontId::proportional(13.0),
            name_color,
        );

        // Draw size bar (from right side)
        let bar_x = rect.right() - bar_width - size_width - percent_width - 8.0;
        let bar_rect = egui::Rect::from_min_size(
            egui::pos2(bar_x, rect.top() + 4.0),
            Vec2::new(bar_width, row_height - 8.0),
        );

        // Bar background
        painter.rect_filled(bar_rect, 2.0, colors.bar_bg);

        // Bar fill
        if percentage > 0.0 {
            let fill_width = (bar_width * percentage as f32 / 100.0).max(1.0);
            let fill_rect = egui::Rect::from_min_size(
                bar_rect.min,
                Vec2::new(fill_width, bar_rect.height()),
            );
            let bar_color = colors.size_to_color(node.size);
            painter.rect_filled(fill_rect, 2.0, bar_color);
        }

        // Draw size text
        let size_text = format_size(node.size);
        let size_x = rect.right() - size_width - percent_width - 4.0;
        painter.text(
            egui::pos2(size_x, y_center),
            egui::Align2::LEFT_CENTER,
            &size_text,
            egui::FontId::proportional(12.0),
            colors.text_dim,
        );

        // Draw percentage
        let percent_text = format!("{:.0}%", percentage);
        let percent_x = rect.right() - percent_width;
        painter.text(
            egui::pos2(percent_x, y_center),
            egui::Align2::LEFT_CENTER,
            &percent_text,
            egui::FontId::proportional(12.0),
            colors.text_dim,
        );
    }

    response
}

/// Get the color for a node.
fn get_node_color(node: &FileNode, _is_expanded: bool, colors: &TreePanelColors) -> Color32 {
    if node.is_symlink {
        colors.symlink
    } else if node.is_dir {
        colors.dirs
    } else if node.is_hidden {
        colors.hidden
    } else if let Some(ref ext) = node.extension {
        colors.extension_to_color(ext)
    } else {
        colors.text
    }
}

/// Truncate a name to fit within a given width.
fn truncate_name(name: &str, max_width: f32, ui: &Ui) -> String {
    let font_id = egui::FontId::proportional(13.0);
    let full_width = ui.fonts(|f| f.glyph_width(&font_id, 'M')) * name.chars().count() as f32;

    if full_width <= max_width {
        name.to_string()
    } else {
        let char_width = ui.fonts(|f| f.glyph_width(&font_id, 'M'));
        let max_chars = ((max_width / char_width) as usize).saturating_sub(3);

        if max_chars == 0 {
            String::new()
        } else {
            let truncated: String = name.chars().take(max_chars).collect();
            format!("{}...", truncated)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    #[test]
    fn test_tree_panel_state_new() {
        let state = TreePanelState::new();
        assert!(state.selected_node.is_none());
        assert!(state.expanded_nodes.is_empty());
    }

    #[test]
    fn test_tree_panel_state_with_root() {
        let tree = FileTree::with_root(PathBuf::from("/test"));
        let root = tree.root.unwrap();
        let state = TreePanelState::with_root_expanded(root);
        assert!(state.is_expanded(root));
    }

    #[test]
    fn test_toggle_expand() {
        let tree = FileTree::with_root(PathBuf::from("/test"));
        let root = tree.root.unwrap();
        let mut state = TreePanelState::with_root_expanded(root);

        // Initially expanded
        assert!(state.is_expanded(root));

        // Toggle to collapse
        state.toggle_expand(root);
        assert!(!state.is_expanded(root));

        // Toggle to expand
        state.toggle_expand(root);
        assert!(state.is_expanded(root));
    }

    #[test]
    fn test_format_size() {
        assert_eq!(format_size(0), "0 B");
        assert_eq!(format_size(512), "512 B");
        assert_eq!(format_size(1024), "1.0 KB");
        assert_eq!(format_size(1024 * 1024), "1.0 MB");
        assert_eq!(format_size(1024 * 1024 * 1024), "1.0 GB");
        assert_eq!(format_size(1024u64 * 1024 * 1024 * 1024), "1.0 TB");
    }

    #[test]
    fn test_colors_default() {
        let colors = TreePanelColors::default();
        assert_eq!(colors.dirs, Color32::from_rgb(100, 149, 237));
    }

    #[test]
    fn test_extension_to_color() {
        let colors = TreePanelColors::default();

        // Media files should use media color
        assert_eq!(colors.extension_to_color("mp3"), colors.media);
        assert_eq!(colors.extension_to_color("MP4"), colors.media);

        // Archives should use compressed color
        assert_eq!(colors.extension_to_color("zip"), colors.compressed);
    }

    #[test]
    fn test_selection() {
        let tree = FileTree::with_root(PathBuf::from("/test"));
        let root = tree.root.unwrap();
        let mut state = TreePanelState::new();

        assert!(state.selected().is_none());

        state.select(root);
        assert_eq!(state.selected(), Some(root));

        state.clear_selection();
        assert!(state.selected().is_none());
    }
}
