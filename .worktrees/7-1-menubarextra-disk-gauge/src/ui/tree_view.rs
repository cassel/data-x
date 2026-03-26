//! Tree view widget for the Data-X TUI disk analyzer.
//!
//! This module provides the tree view component that displays the file system
//! tree with size visualization bars, icons, and navigation state.

use std::collections::HashSet;

use ratatui::{
    layout::Rect,
    style::{Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, List, ListItem},
    Frame,
};

use crate::tree::{FileNode, FileTree, NodeId};
use crate::ui::colors::ColorScheme;

/// Safely truncate a string respecting Unicode character boundaries.
fn truncate_unicode(s: &str, max_chars: usize) -> String {
    if max_chars == 0 {
        return String::new();
    }

    let char_count = s.chars().count();
    if char_count <= max_chars {
        s.to_string()
    } else if max_chars <= 3 {
        s.chars().take(max_chars).collect()
    } else {
        let truncated: String = s.chars().take(max_chars - 3).collect();
        format!("{}...", truncated)
    }
}

/// State for the tree view widget.
#[derive(Debug, Clone)]
pub struct TreeViewState {
    /// Index of the currently selected item in the visible node list.
    pub selected_index: usize,
    /// Scroll offset for the view (first visible row).
    pub scroll_offset: usize,
    /// Set of node IDs that are currently expanded.
    pub expanded_nodes: HashSet<NodeId>,
    /// Optional search query for filtering nodes.
    pub search_query: Option<String>,
}

#[allow(dead_code)]
impl TreeViewState {
    /// Create a new TreeViewState with the root node expanded.
    ///
    /// # Arguments
    /// * `root_id` - The NodeId of the root node to expand initially
    pub fn new(root_id: Option<NodeId>) -> Self {
        let mut expanded_nodes = HashSet::new();
        if let Some(root) = root_id {
            expanded_nodes.insert(root);
        }

        Self {
            selected_index: 0,
            scroll_offset: 0,
            expanded_nodes,
            search_query: None,
        }
    }

    /// Toggle the expansion state of a node.
    #[allow(dead_code)]
    pub fn toggle_expand(&mut self, node_id: NodeId) {
        if self.expanded_nodes.contains(&node_id) {
            self.expanded_nodes.remove(&node_id);
        } else {
            self.expanded_nodes.insert(node_id);
        }
    }

    /// Expand a node.
    #[allow(dead_code)]
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

    /// Set the search query.
    #[allow(dead_code)]
    pub fn set_search(&mut self, query: Option<String>) {
        self.search_query = query;
        // Reset selection when search changes
        self.selected_index = 0;
        self.scroll_offset = 0;
    }

    /// Clear the search query.
    #[allow(dead_code)]
    pub fn clear_search(&mut self) {
        self.search_query = None;
    }

    /// Move selection up.
    #[allow(dead_code)]
    pub fn select_previous(&mut self) {
        if self.selected_index > 0 {
            self.selected_index -= 1;
        }
    }

    /// Move selection down.
    #[allow(dead_code)]
    pub fn select_next(&mut self, max_index: usize) {
        if self.selected_index < max_index {
            self.selected_index += 1;
        }
    }

    /// Jump to the first item.
    #[allow(dead_code)]
    pub fn select_first(&mut self) {
        self.selected_index = 0;
        self.scroll_offset = 0;
    }

    /// Jump to the last item.
    #[allow(dead_code)]
    pub fn select_last(&mut self, max_index: usize) {
        self.selected_index = max_index;
    }

    /// Ensure the selected item is visible by adjusting scroll offset.
    #[allow(dead_code)]
    pub fn ensure_visible(&mut self, visible_height: usize) {
        if visible_height == 0 {
            return;
        }

        if self.selected_index < self.scroll_offset {
            self.scroll_offset = self.selected_index;
        } else if self.selected_index >= self.scroll_offset + visible_height {
            self.scroll_offset = self.selected_index - visible_height + 1;
        }
    }
}

// Note: get_visible_nodes() removed - sorting now handled by App.collect_visible_nodes()
// VisibleNode struct kept for test compatibility but no longer used in main render path

/// Format a byte size into a human-readable string.
///
/// # Arguments
/// * `bytes` - The size in bytes
///
/// # Returns
/// A formatted string like "1.5 GB", "256 KB", etc.
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
///
/// # Arguments
/// * `node` - The file node
/// * `is_expanded` - Whether the node is expanded (for directories)
///
/// # Returns
/// A string containing the appropriate icon character
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

/// Generate a size bar using unicode block characters.
///
/// # Arguments
/// * `ratio` - The ratio of size to max size (0.0 to 1.0)
/// * `width` - The maximum width of the bar in characters
///
/// # Returns
/// A string containing the bar characters
fn generate_size_bar(ratio: f64, width: usize) -> String {
    if width == 0 {
        return String::new();
    }

    let ratio = ratio.clamp(0.0, 1.0);
    let full_blocks = (ratio * width as f64).floor() as usize;
    let remainder = (ratio * width as f64).fract();

    // Unicode block characters: ▏▎▍▌▋▊▉█
    let blocks = [
        '\u{258F}', // 1/8
        '\u{258E}', // 2/8
        '\u{258D}', // 3/8
        '\u{258C}', // 4/8
        '\u{258B}', // 5/8
        '\u{258A}', // 6/8
        '\u{2589}', // 7/8
        '\u{2588}', // 8/8 (full block)
    ];

    let mut bar = String::with_capacity(width);

    // Add full blocks
    for _ in 0..full_blocks {
        bar.push(blocks[7]); // Full block
    }

    // Add partial block if there's a remainder
    if full_blocks < width && remainder > 0.0 {
        let partial_index = ((remainder * 8.0).ceil() as usize).saturating_sub(1).min(7);
        bar.push(blocks[partial_index]);
    }

    bar
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

/// Render the tree view widget.
///
/// # Arguments
/// * `frame` - The ratatui frame to render to
/// * `area` - The rectangular area to render in
/// * `tree` - The file tree to display
/// * `visible_node_ids` - Pre-sorted list of visible node IDs from App
/// * `state` - The tree view state (for selection, scroll, expansion)
/// * `color_scheme` - The color scheme to use
pub fn render_tree_view(
    frame: &mut Frame,
    area: Rect,
    tree: &FileTree,
    visible_node_ids: &[NodeId],
    state: &TreeViewState,
    color_scheme: &ColorScheme,
) {
    if visible_node_ids.is_empty() {
        // Render empty state
        let block = Block::default()
            .borders(Borders::ALL)
            .border_style(Style::default().fg(color_scheme.border))
            .title(" Tree View ");
        frame.render_widget(block, area);
        return;
    }

    // Calculate visible area (accounting for borders)
    let inner_height = area.height.saturating_sub(2) as usize; // Subtract top and bottom borders
    let inner_width = area.width.saturating_sub(2) as usize; // Subtract left and right borders

    // Calculate bar width (reserve space for icon, name, size text, percentage)
    // Approximate layout: indent + icon(2) + name(variable) + bar(10-20) + size(10) + percent(6)
    let bar_width = 12.min(inner_width.saturating_sub(30)).max(6);

    // Build list items
    let mut items: Vec<ListItem> = Vec::new();

    // Calculate the range of nodes to render
    let start_index = state.scroll_offset;
    let end_index = (start_index + inner_height).min(visible_node_ids.len());

    for visible_index in start_index..end_index {
        let node_id = visible_node_ids[visible_index];
        let node = match tree.get_node(node_id) {
            Some(n) => n,
            None => continue,
        };

        // Compute depth and expansion state
        let depth = compute_node_depth(tree, node_id);
        let _has_children = !tree.get_children(node_id).is_empty();
        let is_expanded = state.is_expanded(node_id);

        // Get parent size for percentage calculation
        let parent_size = if depth == 0 {
            node.size
        } else {
            tree.get_parent(node_id)
                .and_then(|p| tree.get_node(p))
                .map(|p| p.size)
                .unwrap_or(node.size)
        };

        let is_selected = visible_index == state.selected_index;

        // Build the line
        let line = build_tree_line(
            node,
            depth,
            is_expanded,
            parent_size,
            bar_width,
            inner_width,
            color_scheme,
            is_selected,
            state.search_query.as_deref(),
        );

        items.push(ListItem::new(line));
    }

    // Create the list widget
    let block = Block::default()
        .borders(Borders::ALL)
        .border_style(Style::default().fg(color_scheme.border))
        .title(" Tree View ");

    let list = List::new(items).block(block);

    frame.render_widget(list, area);
}

/// Build a single line for the tree view.
fn build_tree_line(
    node: &FileNode,
    depth: usize,
    is_expanded: bool,
    parent_size: u64,
    bar_width: usize,
    max_width: usize,
    color_scheme: &ColorScheme,
    is_selected: bool,
    search_query: Option<&str>,
) -> Line<'static> {
    let mut spans: Vec<Span> = Vec::new();

    // Indent (2 spaces per depth level)
    let indent = "  ".repeat(depth);
    spans.push(Span::raw(indent));

    // Icon
    let icon = get_icon(node, is_expanded);
    let icon_color = if node.is_symlink {
        color_scheme.symlink
    } else if node.is_dir {
        color_scheme.dirs
    } else if node.is_hidden {
        color_scheme.hidden
    } else if let Some(ref ext) = node.extension {
        color_scheme.extension_to_color(ext)
    } else {
        color_scheme.text
    };
    spans.push(Span::styled(
        format!("{} ", icon),
        Style::default().fg(icon_color),
    ));

    // Name (truncate if too long)
    let name_max_len = max_width
        .saturating_sub(depth * 2) // indent
        .saturating_sub(3) // icon + space
        .saturating_sub(bar_width + 1) // bar + space
        .saturating_sub(10) // size text
        .saturating_sub(7); // percentage + spaces

    let name = truncate_unicode(&node.name, name_max_len);

    let name_style = if is_selected {
        Style::default()
            .fg(color_scheme.selected)
            .add_modifier(Modifier::REVERSED)
    } else if node.is_hidden {
        Style::default().fg(color_scheme.hidden)
    } else if node.is_dir {
        Style::default().fg(color_scheme.dirs)
    } else {
        Style::default().fg(color_scheme.text)
    };

    // Highlight search matches in name
    let highlight_style = Style::default()
        .fg(color_scheme.search_fg)
        .add_modifier(Modifier::BOLD);

    // Pad name to align columns
    let padded_name = format!("{:<width$}", name, width = name_max_len);

    // If there's a search query, highlight matching portions
    if let Some(query) = search_query {
        if !query.is_empty() {
            let query_lower = query.to_lowercase();
            let name_lower = padded_name.to_lowercase();

            if let Some(match_start) = name_lower.find(&query_lower) {
                let match_end = match_start + query.len();

                // Split name into before, match, after
                let before: String = padded_name.chars().take(match_start).collect();
                let matched: String = padded_name.chars().skip(match_start).take(query.len()).collect();
                let after: String = padded_name.chars().skip(match_end).collect();

                if !before.is_empty() {
                    spans.push(Span::styled(before, name_style));
                }
                spans.push(Span::styled(matched, highlight_style));
                if !after.is_empty() {
                    spans.push(Span::styled(after, name_style));
                }
            } else {
                spans.push(Span::styled(padded_name, name_style));
            }
        } else {
            spans.push(Span::styled(padded_name, name_style));
        }
    } else {
        spans.push(Span::styled(padded_name, name_style));
    }
    spans.push(Span::raw(" "));

    // Size bar
    let size_ratio = if parent_size > 0 {
        node.size as f64 / parent_size as f64
    } else {
        0.0
    };

    let bar_str = generate_size_bar(size_ratio, bar_width);
    let bar_color = color_scheme.size_to_color(node.size, parent_size);

    // Pad bar to fixed width
    let padded_bar = format!("{:<width$}", bar_str, width = bar_width);
    spans.push(Span::styled(padded_bar, Style::default().fg(bar_color)));
    spans.push(Span::raw(" "));

    // Size text
    let size_text = format!("{:>9}", format_size(node.size));
    spans.push(Span::styled(
        size_text,
        Style::default().fg(color_scheme.text_dim),
    ));
    spans.push(Span::raw(" "));

    // Percentage
    let percentage = if parent_size > 0 {
        (node.size as f64 / parent_size as f64 * 100.0) as u32
    } else {
        0
    };
    let percent_text = format!("{:>3}%", percentage.min(100));
    spans.push(Span::styled(
        percent_text,
        Style::default().fg(color_scheme.text_dim),
    ));

    Line::from(spans)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    #[test]
    fn test_format_size_bytes() {
        assert_eq!(format_size(0), "0 B");
        assert_eq!(format_size(512), "512 B");
        assert_eq!(format_size(1023), "1023 B");
    }

    #[test]
    fn test_format_size_kilobytes() {
        assert_eq!(format_size(1024), "1.0 KB");
        assert_eq!(format_size(1536), "1.5 KB");
        assert_eq!(format_size(1024 * 512), "512.0 KB");
    }

    #[test]
    fn test_format_size_megabytes() {
        assert_eq!(format_size(1024 * 1024), "1.0 MB");
        assert_eq!(format_size(1024 * 1024 * 100), "100.0 MB");
    }

    #[test]
    fn test_format_size_gigabytes() {
        assert_eq!(format_size(1024 * 1024 * 1024), "1.0 GB");
        assert_eq!(format_size(1024 * 1024 * 1024 * 2), "2.0 GB");
    }

    #[test]
    fn test_format_size_terabytes() {
        assert_eq!(format_size(1024u64 * 1024 * 1024 * 1024), "1.0 TB");
        assert_eq!(format_size(1024u64 * 1024 * 1024 * 1024 * 5), "5.0 TB");
    }

    #[test]
    fn test_tree_view_state_new() {
        let state = TreeViewState::new(None);
        assert_eq!(state.selected_index, 0);
        assert_eq!(state.scroll_offset, 0);
        assert!(state.expanded_nodes.is_empty());
        assert!(state.search_query.is_none());
    }

    #[test]
    fn test_tree_view_state_with_root() {
        let tree = FileTree::with_root(PathBuf::from("/test"));
        let state = TreeViewState::new(tree.root);

        assert!(tree.root.is_some());
        assert!(state.is_expanded(tree.root.unwrap()));
    }

    #[test]
    fn test_toggle_expand() {
        let tree = FileTree::with_root(PathBuf::from("/test"));
        let root = tree.root.unwrap();
        let mut state = TreeViewState::new(Some(root));

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
    fn test_navigation() {
        let mut state = TreeViewState::new(None);

        // Move down
        state.select_next(10);
        assert_eq!(state.selected_index, 1);

        state.select_next(10);
        assert_eq!(state.selected_index, 2);

        // Move up
        state.select_previous();
        assert_eq!(state.selected_index, 1);

        // Don't go below 0
        state.select_previous();
        state.select_previous();
        assert_eq!(state.selected_index, 0);

        // Don't exceed max
        state.selected_index = 9;
        state.select_next(10);
        assert_eq!(state.selected_index, 10);
        state.select_next(10);
        assert_eq!(state.selected_index, 10);
    }

    #[test]
    fn test_jump_navigation() {
        let mut state = TreeViewState::new(None);
        state.selected_index = 5;

        state.select_first();
        assert_eq!(state.selected_index, 0);
        assert_eq!(state.scroll_offset, 0);

        state.select_last(100);
        assert_eq!(state.selected_index, 100);
    }

    #[test]
    fn test_ensure_visible() {
        let mut state = TreeViewState::new(None);

        // Selected below viewport
        state.selected_index = 20;
        state.scroll_offset = 0;
        state.ensure_visible(10);
        assert_eq!(state.scroll_offset, 11); // 20 - 10 + 1

        // Selected above viewport
        state.selected_index = 5;
        state.ensure_visible(10);
        assert_eq!(state.scroll_offset, 5);

        // Selected within viewport
        state.scroll_offset = 0;
        state.selected_index = 5;
        state.ensure_visible(10);
        assert_eq!(state.scroll_offset, 0);
    }

    #[test]
    fn test_search_query() {
        let mut state = TreeViewState::new(None);
        state.selected_index = 5;

        state.set_search(Some("test".to_string()));
        assert_eq!(state.search_query, Some("test".to_string()));
        assert_eq!(state.selected_index, 0); // Reset on search

        state.clear_search();
        assert!(state.search_query.is_none());
    }

    #[test]
    fn test_generate_size_bar() {
        // Empty bar
        assert_eq!(generate_size_bar(0.0, 10), "");

        // Full bar
        let full = generate_size_bar(1.0, 5);
        assert_eq!(full.chars().count(), 5);

        // Zero width
        assert_eq!(generate_size_bar(0.5, 0), "");

        // Partial bar
        let partial = generate_size_bar(0.5, 10);
        assert!(partial.chars().count() <= 10);
    }

    // Note: get_visible_nodes tests removed - functionality now in App.collect_visible_nodes()
}
