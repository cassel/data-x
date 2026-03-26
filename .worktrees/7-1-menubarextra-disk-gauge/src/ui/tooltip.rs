//! Tooltip rendering for treemap hover functionality.
//!
//! Displays detailed information about a file or directory when the user
//! hovers their mouse over a treemap block.

use ratatui::{
    layout::Rect,
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Clear, Paragraph},
    Frame,
};

use crate::tree::{FileTree, NodeId};
use crate::ui::colors::ColorScheme;
use crate::ui::layout::format_size;

/// Render a tooltip overlay for a hovered treemap node.
///
/// The tooltip displays:
/// - Icon and name (folder/file)
/// - Size with percentage of parent
/// - File count (for directories)
/// - Full path
///
/// The tooltip is positioned near the mouse cursor but adjusted to stay on-screen.
pub fn render_tooltip(
    frame: &mut Frame,
    mouse_pos: (u16, u16),
    node_id: NodeId,
    tree: &FileTree,
    color_scheme: &ColorScheme,
    parent_size: u64,
) {
    let node = match tree.get_node(node_id) {
        Some(n) => n,
        None => return,
    };

    let screen_size = frame.area();

    // Build tooltip content lines
    let mut lines: Vec<Line> = Vec::new();

    // Line 1: Icon and name
    let icon = if node.is_dir { "folder" } else { "file" };
    let name = truncate_name(&node.name, 28);
    lines.push(Line::from(vec![
        Span::styled(
            format!(" {} ", icon),
            Style::default()
                .fg(if node.is_dir { color_scheme.dirs } else { color_scheme.text })
                .add_modifier(Modifier::BOLD),
        ),
        Span::styled(
            name,
            Style::default()
                .fg(color_scheme.text)
                .add_modifier(Modifier::BOLD),
        ),
    ]));

    // Line 2: Size and percentage
    let percentage = if parent_size > 0 {
        ((node.size as f64 / parent_size as f64) * 100.0).round() as u64
    } else {
        100
    };
    let size_str = format!(" Size: {} ({:.1}%)", format_size(node.size), percentage);
    lines.push(Line::from(Span::styled(
        size_str,
        Style::default().fg(color_scheme.size_fg),
    )));

    // Line 3: File count (for directories)
    if node.is_dir && node.file_count > 0 {
        let files_str = format!(" Files: {}", format_file_count(node.file_count));
        lines.push(Line::from(Span::styled(
            files_str,
            Style::default().fg(color_scheme.hint_fg),
        )));
    }

    // Line 4: Path (truncated)
    let path_str = node.path.to_string_lossy();
    let truncated_path = truncate_path(&path_str, 30);
    lines.push(Line::from(Span::styled(
        format!(" Path: {}", truncated_path),
        Style::default().fg(color_scheme.path_fg),
    )));

    // Calculate tooltip dimensions
    let content_width = lines.iter()
        .map(|line| line.spans.iter().map(|s| s.content.chars().count()).sum::<usize>())
        .max()
        .unwrap_or(20);
    let tooltip_width = (content_width + 4).min(40) as u16; // +4 for borders and padding
    let tooltip_height = (lines.len() + 2) as u16; // +2 for top/bottom borders

    // Position tooltip near mouse, but keep on screen
    let (x, y) = calculate_tooltip_position(
        mouse_pos,
        tooltip_width,
        tooltip_height,
        screen_size,
    );

    let tooltip_area = Rect::new(x, y, tooltip_width, tooltip_height);

    // Use a solid dark background for contrast
    let bg_color = Color::Rgb(25, 25, 35);
    let border_color = color_scheme.accent;

    // Clear the area first
    frame.render_widget(Clear, tooltip_area);

    let block = Block::default()
        .borders(Borders::ALL)
        .border_style(Style::default().fg(border_color))
        .style(Style::default().bg(bg_color));

    let paragraph = Paragraph::new(lines)
        .block(block)
        .style(Style::default().bg(bg_color));

    frame.render_widget(paragraph, tooltip_area);
}

/// Calculate tooltip position to keep it visible on screen.
/// Prefers positioning below and to the right of the cursor.
fn calculate_tooltip_position(
    mouse_pos: (u16, u16),
    width: u16,
    height: u16,
    screen: Rect,
) -> (u16, u16) {
    let (mx, my) = mouse_pos;

    // Offset from cursor to avoid overlapping
    let offset_x: u16 = 2;
    let offset_y: u16 = 1;

    // Try positioning to the right and below cursor
    let mut x = mx.saturating_add(offset_x);
    let mut y = my.saturating_add(offset_y);

    // Adjust if tooltip would go off right edge
    if x + width > screen.width {
        // Position to the left of cursor instead
        x = mx.saturating_sub(width).saturating_sub(1);
    }

    // Adjust if tooltip would go off bottom edge
    if y + height > screen.height {
        // Position above cursor instead
        y = my.saturating_sub(height);
    }

    // Final bounds check (ensure we stay in screen)
    x = x.min(screen.width.saturating_sub(width));
    y = y.min(screen.height.saturating_sub(height));

    (x, y)
}

/// Truncate a name string to fit in the tooltip, respecting Unicode.
fn truncate_name(s: &str, max_chars: usize) -> String {
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

/// Truncate a path to show the end portion with ellipsis at start.
fn truncate_path(s: &str, max_chars: usize) -> String {
    let char_count = s.chars().count();
    if char_count <= max_chars {
        s.to_string()
    } else if max_chars <= 3 {
        s.chars().skip(char_count - max_chars).collect()
    } else {
        let skip = char_count - (max_chars - 3);
        let suffix: String = s.chars().skip(skip).collect();
        format!("...{}", suffix)
    }
}

/// Format file count with thousands separators.
fn format_file_count(count: u64) -> String {
    let count_str = count.to_string();
    let mut result = String::new();
    for (i, c) in count_str.chars().rev().enumerate() {
        if i > 0 && i % 3 == 0 {
            result.insert(0, ',');
        }
        result.insert(0, c);
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_truncate_name() {
        assert_eq!(truncate_name("hello", 10), "hello");
        assert_eq!(truncate_name("hello world test", 10), "hello w...");
        assert_eq!(truncate_name("hi", 2), "hi");
    }

    #[test]
    fn test_truncate_path() {
        assert_eq!(truncate_path("/short", 10), "/short");
        // Input: "/very/long/path/to/file" (22 chars), max 15 -> skip 10 chars, keep "path/to/file" (12) + "..." (3) = 15
        assert_eq!(truncate_path("/very/long/path/to/file", 15), "...path/to/file");
    }

    #[test]
    fn test_format_file_count() {
        assert_eq!(format_file_count(0), "0");
        assert_eq!(format_file_count(999), "999");
        assert_eq!(format_file_count(1000), "1,000");
        assert_eq!(format_file_count(1234567), "1,234,567");
    }

    #[test]
    fn test_tooltip_position() {
        let screen = Rect::new(0, 0, 100, 50);

        // Normal case: position below and right of cursor
        let (x, y) = calculate_tooltip_position((10, 10), 20, 5, screen);
        assert_eq!(x, 12); // 10 + 2 offset
        assert_eq!(y, 11); // 10 + 1 offset

        // Near right edge: should flip to left
        let (x, _y) = calculate_tooltip_position((90, 10), 20, 5, screen);
        assert!(x < 90);

        // Near bottom edge: should flip to above
        let (_x, y) = calculate_tooltip_position((10, 48), 20, 5, screen);
        assert!(y < 48);
    }
}
