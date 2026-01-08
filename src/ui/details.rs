//! Details panel for the Data-X TUI disk analyzer.
//!
//! This module renders a details panel showing comprehensive information
//! about the currently selected file or directory node.

use chrono::{DateTime, Local};
use ratatui::{
    layout::Rect,
    style::Style,
    text::{Line, Span},
    widgets::{Block, Borders, Paragraph},
    Frame,
};
use std::time::SystemTime;

use crate::tree::{FileTree, NodeId};
use crate::ui::colors::ColorScheme;

/// Render the details panel showing information about the selected node.
///
/// # Arguments
///
/// * `frame` - The ratatui frame to render into
/// * `area` - The rectangular area to render the panel in
/// * `tree` - The file tree containing all nodes
/// * `selected_node_id` - The currently selected node, if any
/// * `color_scheme` - The color scheme for styling
///
/// # Display Fields
///
/// When a node is selected, the following fields are displayed:
/// - Full path
/// - Name
/// - Type (Directory / File / Symlink)
/// - Size (formatted, e.g., "1.5 GB")
/// - Size (raw bytes)
/// - File count (for directories)
/// - Modified date (formatted)
/// - Extension (for files)
/// - Hidden: Yes/No
/// - Symlink target (if symlink)
/// - Percentage of parent
/// - Percentage of total
pub fn render_details_panel(
    frame: &mut Frame,
    area: Rect,
    tree: &FileTree,
    selected_node_id: Option<NodeId>,
    color_scheme: &ColorScheme,
) {
    let block = Block::default()
        .title("Details")
        .borders(Borders::ALL)
        .border_type(ratatui::widgets::BorderType::Rounded)
        .border_style(Style::default().fg(color_scheme.border));

    match selected_node_id.and_then(|id| tree.get_node(id).map(|node| (id, node))) {
        Some((node_id, node)) => {
            let lines = build_detail_lines(tree, node_id, node, color_scheme);
            let paragraph = Paragraph::new(lines).block(block);
            frame.render_widget(paragraph, area);
        }
        None => {
            let text = vec![Line::from(Span::styled(
                "No item selected",
                Style::default().fg(color_scheme.text_dim),
            ))];
            let paragraph = Paragraph::new(text).block(block);
            frame.render_widget(paragraph, area);
        }
    }
}

/// Build the detail lines for a selected node.
fn build_detail_lines<'a>(
    tree: &FileTree,
    node_id: NodeId,
    node: &crate::tree::FileNode,
    color_scheme: &ColorScheme,
) -> Vec<Line<'a>> {
    let label_style = Style::default().fg(color_scheme.text_dim);
    let value_style = Style::default().fg(color_scheme.text);

    let mut lines = Vec::new();

    // Full path
    lines.push(create_detail_line(
        "Path",
        &node.path.to_string_lossy(),
        label_style,
        value_style,
    ));

    // Name
    lines.push(create_detail_line("Name", &node.name, label_style, value_style));

    // Type
    let type_str = if node.is_symlink {
        "Symlink"
    } else if node.is_dir {
        "Directory"
    } else {
        "File"
    };
    lines.push(create_detail_line("Type", type_str, label_style, value_style));

    // Size (formatted)
    let formatted_size = format_size(node.size);
    lines.push(create_detail_line(
        "Size",
        &formatted_size,
        label_style,
        value_style,
    ));

    // Size (raw bytes)
    let raw_size = format!("{} bytes", format_number_with_commas(node.size));
    lines.push(create_detail_line(
        "Size (bytes)",
        &raw_size,
        label_style,
        value_style,
    ));

    // File count (for directories)
    if node.is_dir {
        let count_str = format_number_with_commas(node.file_count);
        lines.push(create_detail_line(
            "File count",
            &count_str,
            label_style,
            value_style,
        ));
    }

    // Modified date
    let modified_str = match node.modified {
        Some(time) => format_system_time(time),
        None => "Unknown".to_string(),
    };
    lines.push(create_detail_line(
        "Modified",
        &modified_str,
        label_style,
        value_style,
    ));

    // Extension (for files)
    if !node.is_dir {
        let ext_str = node.extension.as_deref().unwrap_or("None");
        lines.push(create_detail_line(
            "Extension",
            ext_str,
            label_style,
            value_style,
        ));
    }

    // Hidden
    let hidden_str = if node.is_hidden { "Yes" } else { "No" };
    lines.push(create_detail_line(
        "Hidden",
        hidden_str,
        label_style,
        value_style,
    ));

    // Symlink target (if symlink)
    if node.is_symlink {
        let target_str = match &node.symlink_target {
            Some(target) => target.to_string_lossy().to_string(),
            None => "(broken)".to_string(),
        };
        lines.push(create_detail_line(
            "Target",
            &target_str,
            label_style,
            value_style,
        ));
    }

    // Percentage of parent
    let parent_percentage = calculate_parent_percentage(tree, node_id, node);
    lines.push(create_detail_line(
        "% of parent",
        &parent_percentage,
        label_style,
        value_style,
    ));

    // Percentage of total
    let total_percentage = calculate_total_percentage(tree, node);
    lines.push(create_detail_line(
        "% of total",
        &total_percentage,
        label_style,
        value_style,
    ));

    lines
}

/// Create a single detail line with a label and value.
fn create_detail_line<'a>(
    label: &str,
    value: &str,
    label_style: Style,
    value_style: Style,
) -> Line<'a> {
    Line::from(vec![
        Span::styled(format!("{}: ", label), label_style),
        Span::styled(value.to_string(), value_style),
    ])
}

/// Format a size in bytes to a human-readable string.
///
/// Examples:
/// - 1024 -> "1.0 KB"
/// - 1048576 -> "1.0 MB"
/// - 1073741824 -> "1.0 GB"
fn format_size(bytes: u64) -> String {
    const KB: u64 = 1024;
    const MB: u64 = 1024 * KB;
    const GB: u64 = 1024 * MB;
    const TB: u64 = 1024 * GB;

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

/// Format a number with comma separators for readability.
///
/// Example: 1234567 -> "1,234,567"
fn format_number_with_commas(n: u64) -> String {
    let s = n.to_string();
    let mut result = String::new();
    let chars: Vec<char> = s.chars().collect();
    let len = chars.len();

    for (i, c) in chars.iter().enumerate() {
        if i > 0 && (len - i) % 3 == 0 {
            result.push(',');
        }
        result.push(*c);
    }

    result
}

/// Format a SystemTime as a human-readable date string.
fn format_system_time(time: SystemTime) -> String {
    let datetime: DateTime<Local> = time.into();
    datetime.format("%Y-%m-%d %H:%M:%S").to_string()
}

/// Calculate the percentage of the node's size relative to its parent.
fn calculate_parent_percentage(tree: &FileTree, node_id: NodeId, node: &crate::tree::FileNode) -> String {
    if let Some(parent_id) = tree.get_parent(node_id) {
        if let Some(parent) = tree.get_node(parent_id) {
            if parent.size > 0 {
                let percentage = (node.size as f64 / parent.size as f64) * 100.0;
                return format!("{:.1}%", percentage);
            }
        }
    }
    // Root node or parent has zero size
    "100.0%".to_string()
}

/// Calculate the percentage of the node's size relative to the total tree size.
fn calculate_total_percentage(tree: &FileTree, node: &crate::tree::FileNode) -> String {
    let total_size = tree.total_size();
    if total_size > 0 {
        let percentage = (node.size as f64 / total_size as f64) * 100.0;
        format!("{:.1}%", percentage)
    } else {
        "0.0%".to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_format_size() {
        assert_eq!(format_size(0), "0 B");
        assert_eq!(format_size(512), "512 B");
        assert_eq!(format_size(1024), "1.0 KB");
        assert_eq!(format_size(1536), "1.5 KB");
        assert_eq!(format_size(1024 * 1024), "1.0 MB");
        assert_eq!(format_size(1024 * 1024 * 1024), "1.0 GB");
        assert_eq!(format_size(1024 * 1024 * 1024 * 1024), "1.0 TB");
        assert_eq!(format_size(1536 * 1024 * 1024), "1.5 GB");
    }

    #[test]
    fn test_format_number_with_commas() {
        assert_eq!(format_number_with_commas(0), "0");
        assert_eq!(format_number_with_commas(999), "999");
        assert_eq!(format_number_with_commas(1000), "1,000");
        assert_eq!(format_number_with_commas(1234567), "1,234,567");
        assert_eq!(format_number_with_commas(1234567890), "1,234,567,890");
    }

    #[test]
    fn test_create_detail_line() {
        use ratatui::style::Color;

        let label_style = Style::default().fg(Color::Gray);
        let value_style = Style::default().fg(Color::White);

        let line = create_detail_line("Test Label", "Test Value", label_style, value_style);

        assert_eq!(line.spans.len(), 2);
    }
}
