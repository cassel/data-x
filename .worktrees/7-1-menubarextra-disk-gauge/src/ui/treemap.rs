//! Treemap visualization module for Data-X.
//!
//! Implements a squarified treemap algorithm to render disk usage as
//! proportional colored blocks, similar to Disk Inventory X.

use ratatui::{
    layout::Rect,
    style::{Color, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Paragraph},
    Frame,
};

use crate::tree::{FileTree, NodeId};
use crate::ui::colors::{get_file_type_color, get_file_type_selection_color, ColorScheme};
use crate::ui::input::FileCategory;
use crate::ui::tree_view::format_size;

/// Safely truncate a name string respecting Unicode character boundaries.
fn truncate_name_unicode(s: &str, max_chars: usize) -> String {
    if max_chars == 0 {
        return String::new();
    }
    let char_count = s.chars().count();
    if char_count <= max_chars {
        s.to_string()
    } else if max_chars <= 1 {
        s.chars().take(max_chars).collect()
    } else {
        let truncated: String = s.chars().take(max_chars - 1).collect();
        format!("{}…", truncated)
    }
}

/// Represents a rectangle in the treemap with its associated node.
#[derive(Debug, Clone)]
pub struct TreemapRect {
    pub node_id: NodeId,
    pub x: u16,
    pub y: u16,
    pub width: u16,
    pub height: u16,
    #[allow(dead_code)]
    pub size: u64,
    #[allow(dead_code)]
    pub name: String,
    pub is_dir: bool,
    #[allow(dead_code)]
    pub extension: Option<String>,
    #[allow(dead_code)]
    pub percentage: u8,
}

impl TreemapRect {
    /// Check if a point (x, y) is inside this rectangle.
    pub fn contains(&self, px: u16, py: u16) -> bool {
        px >= self.x && px < self.x + self.width && py >= self.y && py < self.y + self.height
    }
}

/// Render the treemap visualization and return the rendered rectangles for hit-testing.
///
/// # Arguments
/// * `frame` - The ratatui frame to render to
/// * `area` - The rectangular area to render in
/// * `tree` - The file tree to visualize
/// * `root_node` - The node to use as treemap root (usually selected dir or tree root)
/// * `selected_node` - Currently selected node (for highlighting)
/// * `color_scheme` - Color scheme for rendering
/// * `active_filter` - File category filter to apply
///
/// # Returns
/// A vector of TreemapRect with screen positions for hit-testing and navigation.
pub fn render_treemap(
    frame: &mut Frame,
    area: Rect,
    tree: &FileTree,
    root_node: Option<NodeId>,
    selected_node: Option<NodeId>,
    color_scheme: &ColorScheme,
    active_filter: FileCategory,
) -> Vec<TreemapRect> {
    let block = Block::default()
        .title(" Treemap ")
        .borders(Borders::ALL)
        .border_style(Style::default().fg(color_scheme.border));

    let inner_area = block.inner(area);
    frame.render_widget(block, area);

    // Get root node for treemap
    let root_id = match root_node.or(tree.root) {
        Some(id) => id,
        None => return Vec::new(),
    };

    let root_data = match tree.get_node(root_id) {
        Some(n) => n,
        None => return Vec::new(),
    };

    // Skip if no size to display
    if root_data.size == 0 {
        let msg = Paragraph::new("Empty directory")
            .style(Style::default().fg(color_scheme.text));
        frame.render_widget(msg, inner_area);
        return Vec::new();
    }

    // Get children with sizes for treemap
    let children = tree.get_children(root_id);
    if children.is_empty() {
        // Single file - fill entire area
        let color = get_node_color(root_data.is_dir, &root_data.extension, color_scheme);
        let selection_color = get_node_selection_color(root_data.is_dir, &root_data.extension);
        render_single_block(frame, inner_area, &root_data.name, root_data.size, 100, color, selection_color, selected_node == Some(root_id));
        return vec![TreemapRect {
            node_id: root_id,
            x: inner_area.x,
            y: inner_area.y,
            width: inner_area.width,
            height: inner_area.height,
            size: root_data.size,
            name: root_data.name.clone(),
            is_dir: root_data.is_dir,
            extension: root_data.extension.clone(),
            percentage: 100,
        }];
    }

    // Build items for treemap layout, applying filter
    let mut items: Vec<(NodeId, u64, String, bool, Option<String>)> = children
        .iter()
        .filter_map(|&child_id| {
            tree.get_node(child_id).map(|n| {
                (child_id, n.size, n.name.clone(), n.is_dir, n.extension.clone())
            })
        })
        .filter(|(_, size, _, _, _)| *size > 0)
        .filter(|(child_id, _, _, is_dir, extension)| {
            // Apply file category filter
            if active_filter == FileCategory::All {
                return true;
            }
            if *is_dir {
                // For directories, check if they have matching descendants
                has_matching_filter_descendant_treemap(tree, *child_id, active_filter)
            } else {
                // For files, check if extension matches
                matches_filter_treemap(extension.as_deref(), active_filter)
            }
        })
        .collect();

    // Sort by size descending for better treemap layout
    items.sort_by(|a, b| b.1.cmp(&a.1));

    if items.is_empty() {
        let msg = Paragraph::new("No files with size")
            .style(Style::default().fg(color_scheme.text));
        frame.render_widget(msg, inner_area);
        return Vec::new();
    }

    // Calculate treemap layout using squarified algorithm
    let total_size: u64 = items.iter().map(|(_, s, _, _, _)| *s).sum();
    let layout_rects = squarify(
        &items,
        inner_area.x as f64,
        inner_area.y as f64,
        inner_area.width as f64,
        inner_area.height as f64,
        total_size,
    );

    let mut result_rects = Vec::new();

    // Render each rectangle
    for (node_id, size, name, is_dir, extension, lx, ly, lw, lh) in layout_rects {
        let rx = lx.round() as u16;
        let ry = ly.round() as u16;
        let rw = lw.round().max(1.0) as u16;
        let rh = lh.round().max(1.0) as u16;

        // Clamp to inner area bounds
        if rx >= inner_area.x + inner_area.width || ry >= inner_area.y + inner_area.height {
            continue;
        }

        let clamped_w = rw.min(inner_area.x + inner_area.width - rx);
        let clamped_h = rh.min(inner_area.y + inner_area.height - ry);

        if clamped_w == 0 || clamped_h == 0 {
            continue;
        }

        let percentage = if total_size > 0 {
            ((size as f64 / total_size as f64) * 100.0).round() as u8
        } else {
            0
        };

        let rect_area = Rect::new(rx, ry, clamped_w, clamped_h);
        let color = get_node_color(is_dir, &extension, color_scheme);
        let selection_color = get_node_selection_color(is_dir, &extension);
        let is_selected = selected_node == Some(node_id);

        render_treemap_block(frame, rect_area, &name, size, percentage, color, selection_color, is_selected, is_dir);

        result_rects.push(TreemapRect {
            node_id,
            x: rx,
            y: ry,
            width: clamped_w,
            height: clamped_h,
            size,
            name,
            is_dir,
            extension,
            percentage,
        });
    }

    result_rects
}

/// Squarified treemap algorithm.
/// Attempts to create rectangles with aspect ratios close to 1 (squares).
/// Returns: Vec<(NodeId, size, name, is_dir, extension, x, y, width, height)>
fn squarify(
    items: &[(NodeId, u64, String, bool, Option<String>)],
    x: f64,
    y: f64,
    width: f64,
    height: f64,
    total_size: u64,
) -> Vec<(NodeId, u64, String, bool, Option<String>, f64, f64, f64, f64)> {
    let mut result = Vec::new();

    if items.is_empty() || total_size == 0 || width <= 0.0 || height <= 0.0 {
        return result;
    }

    // Normalize sizes to area
    let area = width * height;
    let scale = area / total_size as f64;

    // Use slice-and-dice for simplicity (alternating horizontal/vertical splits)
    let mut remaining_items = items.to_vec();
    let mut curr_x = x;
    let mut curr_y = y;
    let mut curr_width = width;
    let mut curr_height = height;
    let mut horizontal = width >= height;

    while !remaining_items.is_empty() {
        let (node_id, size, name, is_dir, extension) = remaining_items.remove(0);
        let item_area = size as f64 * scale;

        let (rect_width, rect_height) = if horizontal {
            let h = curr_height;
            let w = if h > 0.0 { item_area / h } else { 0.0 };
            (w.min(curr_width), h)
        } else {
            let w = curr_width;
            let h = if w > 0.0 { item_area / w } else { 0.0 };
            (w, h.min(curr_height))
        };

        result.push((node_id, size, name, is_dir, extension, curr_x, curr_y, rect_width, rect_height));

        // Update remaining area
        if horizontal {
            curr_x += rect_width;
            curr_width -= rect_width;
            if curr_width <= 1.0 {
                // Switch to vertical
                horizontal = false;
                curr_x = x;
                curr_width = width;
            }
        } else {
            curr_y += rect_height;
            curr_height -= rect_height;
            if curr_height <= 1.0 {
                // Switch to horizontal
                horizontal = true;
                curr_y = y;
                curr_height = height;
            }
        }
    }

    result
}

/// Render a single block filling the entire area.
fn render_single_block(frame: &mut Frame, area: Rect, name: &str, size: u64, percentage: u8, color: Color, selection_color: Color, is_selected: bool) {
    let bg_color = if is_selected { selection_color } else { color };
    let fg_color = if is_selected { Color::Black } else { Color::White };
    let style = if is_selected {
        Style::default().bg(bg_color).fg(fg_color).add_modifier(ratatui::style::Modifier::BOLD)
    } else {
        Style::default().bg(bg_color).fg(fg_color)
    };

    // Fill with spaces (background color)
    let mut lines: Vec<Line> = (0..area.height)
        .map(|_| {
            let fill: String = (0..area.width).map(|_| ' ').collect();
            Line::from(Span::styled(fill, style))
        })
        .collect();

    // Add name and size if space allows
    if area.height >= 2 && area.width > 4 {
        let max_len = area.width as usize - 2;
        let truncated_name = truncate_name_unicode(name, max_len);
        let size_str = format!("{} ({}%)", format_size(size), percentage);
        let truncated_size = truncate_name_unicode(&size_str, max_len);

        let center_row = (area.height / 2).saturating_sub(1) as usize;

        // Name line
        if center_row < lines.len() {
            let padded_name = format!(" {:<width$}", truncated_name, width = area.width as usize - 1);
            lines[center_row] = Line::from(Span::styled(padded_name, style));
        }

        // Size line
        if center_row + 1 < lines.len() {
            let padded_size = format!(" {:<width$}", truncated_size, width = area.width as usize - 1);
            lines[center_row + 1] = Line::from(Span::styled(padded_size, style));
        }
    } else if area.height >= 1 && area.width > 4 {
        // Just name if only 1 line
        let max_len = area.width as usize - 2;
        let truncated_name = truncate_name_unicode(name, max_len);
        let padded_name = format!(" {:<width$}", truncated_name, width = area.width as usize - 1);
        lines[0] = Line::from(Span::styled(padded_name, style));
    }

    let paragraph = Paragraph::new(lines);
    frame.render_widget(paragraph, area);
}

/// Render a treemap block with color fill and optional label.
fn render_treemap_block(frame: &mut Frame, area: Rect, name: &str, size: u64, percentage: u8, color: Color, selection_color: Color, is_selected: bool, is_dir: bool) {
    if area.width == 0 || area.height == 0 {
        return;
    }

    let bg_color = if is_selected {
        selection_color
    } else {
        color
    };

    let fg_color = if is_selected {
        Color::Black
    } else {
        Color::White
    };

    let style = Style::default().bg(bg_color).fg(fg_color);

    // For very small blocks, just fill with color
    if area.width < 3 || area.height < 1 {
        let fill: String = (0..area.width).map(|_| ' ').collect();
        let lines: Vec<Line> = (0..area.height)
            .map(|_| Line::from(Span::styled(fill.clone(), style)))
            .collect();
        let paragraph = Paragraph::new(lines);
        frame.render_widget(paragraph, area);
        return;
    }

    // Create filled block with border effect
    let mut lines = Vec::new();

    for row in 0..area.height {
        let mut line_spans = Vec::new();

        if row == 0 || row == area.height - 1 {
            // Top/bottom border (lighter shade)
            let border_style = Style::default()
                .bg(lighten_color(bg_color))
                .fg(fg_color);
            let border_content: String = (0..area.width).map(|_| ' ').collect();
            line_spans.push(Span::styled(border_content, border_style));
        } else {
            // Left border
            line_spans.push(Span::styled(" ", Style::default().bg(lighten_color(bg_color))));

            // Inner content
            let inner_width = area.width.saturating_sub(2);
            let inner_content: String = (0..inner_width).map(|_| ' ').collect();
            line_spans.push(Span::styled(inner_content, style));

            // Right border
            line_spans.push(Span::styled(" ", Style::default().bg(darken_color(bg_color))));
        }

        lines.push(Line::from(line_spans));
    }

    // Add labels if there's enough space
    let max_label_len = (area.width.saturating_sub(2)) as usize;
    if max_label_len < 3 {
        let paragraph = Paragraph::new(lines);
        frame.render_widget(paragraph, area);
        return;
    }

    let border_left = Style::default().bg(lighten_color(bg_color));
    let border_right = Style::default().bg(darken_color(bg_color));

    // Icon + Name on first content row
    if area.height >= 3 {
        let icon = if is_dir { "📁" } else { "📄" };
        let icon_and_name = format!("{} {}", icon, name);
        let label = truncate_name_unicode(&icon_and_name, max_label_len);
        let padded = format!("{:<width$}", label, width = max_label_len);

        lines[1] = Line::from(vec![
            Span::styled(" ", border_left),
            Span::styled(padded, style),
            Span::styled(" ", border_right),
        ]);
    }

    // Size and percentage on second content row
    if area.height >= 4 {
        let size_str = format!("{} ({}%)", format_size(size), percentage);
        let size_label = truncate_name_unicode(&size_str, max_label_len);
        let padded = format!("{:<width$}", size_label, width = max_label_len);

        lines[2] = Line::from(vec![
            Span::styled(" ", border_left),
            Span::styled(padded, style),
            Span::styled(" ", border_right),
        ]);
    } else if area.height >= 3 {
        // If only 3 rows, show just size on row 1 without icon
        let label = truncate_name_unicode(name, max_label_len);
        let padded = format!("{:<width$}", label, width = max_label_len);
        lines[1] = Line::from(vec![
            Span::styled(" ", border_left),
            Span::styled(padded, style),
            Span::styled(" ", border_right),
        ]);
    } else if area.height >= 2 {
        // Just name if only 2 rows (no borders taking space)
        let label = truncate_name_unicode(name, max_label_len);
        let padded = format!("{:<width$}", label, width = max_label_len);
        lines[0] = Line::from(vec![
            Span::styled(" ", border_left),
            Span::styled(padded, style),
            Span::styled(" ", border_right),
        ]);
    }

    let paragraph = Paragraph::new(lines);
    frame.render_widget(paragraph, area);
}

/// Get color for a node based on type and extension.
/// Uses the new file type color system for extension-based coloring:
/// - Audio (mp3, wav, flac, m4a, ogg, aac) -> Blue shades
/// - Video (mp4, mkv, avi, mov, wmv, webm) -> Purple shades
/// - Images (jpg, jpeg, png, gif, webp, svg, bmp, ico) -> Green shades
/// - Documents (pdf, doc, docx, txt, md, rtf, odt) -> Orange/Yellow shades
/// - Code (rs, py, js, ts, go, java, c, cpp, h, rb, php) -> Cyan shades
/// - Archives (zip, tar, gz, rar, 7z, bz2) -> Red shades
/// - Directories -> Cornflower blue
/// - Other -> Gray shades
fn get_node_color(is_dir: bool, extension: &Option<String>, _color_scheme: &ColorScheme) -> Color {
    get_file_type_color(extension.as_deref(), is_dir)
}

/// Get selection color for a node based on type and extension.
/// Returns a brighter/lighter version of the file type color for selected items.
fn get_node_selection_color(is_dir: bool, extension: &Option<String>) -> Color {
    get_file_type_selection_color(extension.as_deref(), is_dir)
}

/// Check if a file matches the active filter based on its extension (for treemap).
fn matches_filter_treemap(extension: Option<&str>, active_filter: FileCategory) -> bool {
    if active_filter == FileCategory::All {
        return true;
    }

    match extension {
        Some(ext) => FileCategory::from_extension(ext) == active_filter,
        None => false,
    }
}

/// Check if a directory contains any files matching the active filter (for treemap).
fn has_matching_filter_descendant_treemap(tree: &FileTree, node_id: NodeId, active_filter: FileCategory) -> bool {
    if active_filter == FileCategory::All {
        return true;
    }

    for child_id in tree.get_children(node_id) {
        if let Some(child) = tree.get_node(child_id) {
            if child.is_dir {
                if has_matching_filter_descendant_treemap(tree, child_id, active_filter) {
                    return true;
                }
            } else if matches_filter_treemap(child.extension.as_deref(), active_filter) {
                return true;
            }
        }
    }
    false
}

/// Lighten a color for border effects.
fn lighten_color(color: Color) -> Color {
    match color {
        Color::Rgb(r, g, b) => Color::Rgb(
            r.saturating_add(40),
            g.saturating_add(40),
            b.saturating_add(40),
        ),
        Color::Blue => Color::LightBlue,
        Color::Green => Color::LightGreen,
        Color::Red => Color::LightRed,
        Color::Yellow => Color::LightYellow,
        Color::Magenta => Color::LightMagenta,
        Color::Cyan => Color::LightCyan,
        _ => Color::White,
    }
}

/// Darken a color for border effects.
fn darken_color(color: Color) -> Color {
    match color {
        Color::Rgb(r, g, b) => Color::Rgb(
            r.saturating_sub(40),
            g.saturating_sub(40),
            b.saturating_sub(40),
        ),
        Color::LightBlue => Color::Blue,
        Color::LightGreen => Color::Green,
        Color::LightRed => Color::Red,
        Color::LightYellow => Color::Yellow,
        Color::LightMagenta => Color::Magenta,
        Color::LightCyan => Color::Cyan,
        _ => Color::DarkGray,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ui::colors::FileTypeColors;

    #[test]
    fn test_lighten_color() {
        assert_eq!(lighten_color(Color::Blue), Color::LightBlue);
        assert_eq!(lighten_color(Color::Rgb(100, 100, 100)), Color::Rgb(140, 140, 140));
    }

    #[test]
    fn test_darken_color() {
        assert_eq!(darken_color(Color::LightBlue), Color::Blue);
        assert_eq!(darken_color(Color::Rgb(100, 100, 100)), Color::Rgb(60, 60, 60));
    }

    #[test]
    fn test_get_node_color_directory() {
        let scheme = ColorScheme::dark();
        let colors = FileTypeColors::dark();
        let color = get_node_color(true, &Some("rs".to_string()), &scheme);
        assert_eq!(color, colors.directory_base);
    }

    #[test]
    fn test_get_node_color_audio() {
        let scheme = ColorScheme::dark();
        let colors = FileTypeColors::dark();
        let color = get_node_color(false, &Some("mp3".to_string()), &scheme);
        assert_eq!(color, colors.audio_base);
    }

    #[test]
    fn test_get_node_color_video() {
        let scheme = ColorScheme::dark();
        let colors = FileTypeColors::dark();
        let color = get_node_color(false, &Some("mp4".to_string()), &scheme);
        assert_eq!(color, colors.video_base);
    }

    #[test]
    fn test_get_node_color_image() {
        let scheme = ColorScheme::dark();
        let colors = FileTypeColors::dark();
        let color = get_node_color(false, &Some("png".to_string()), &scheme);
        assert_eq!(color, colors.image_base);
    }

    #[test]
    fn test_get_node_color_document() {
        let scheme = ColorScheme::dark();
        let colors = FileTypeColors::dark();
        let color = get_node_color(false, &Some("pdf".to_string()), &scheme);
        assert_eq!(color, colors.document_base);
    }

    #[test]
    fn test_get_node_color_code() {
        let scheme = ColorScheme::dark();
        let colors = FileTypeColors::dark();
        let color = get_node_color(false, &Some("rs".to_string()), &scheme);
        assert_eq!(color, colors.code_base);
    }

    #[test]
    fn test_get_node_color_archive() {
        let scheme = ColorScheme::dark();
        let colors = FileTypeColors::dark();
        let color = get_node_color(false, &Some("zip".to_string()), &scheme);
        assert_eq!(color, colors.archive_base);
    }

    #[test]
    fn test_get_node_selection_color_directory() {
        let colors = FileTypeColors::dark();
        let color = get_node_selection_color(true, &Some("rs".to_string()));
        assert_eq!(color, colors.directory_light);
    }

    #[test]
    fn test_get_node_selection_color_audio() {
        let colors = FileTypeColors::dark();
        let color = get_node_selection_color(false, &Some("mp3".to_string()));
        assert_eq!(color, colors.audio_light);
    }

    #[test]
    fn test_truncate_name_unicode() {
        assert_eq!(truncate_name_unicode("hello", 10), "hello");
        assert_eq!(truncate_name_unicode("hello world", 5), "hell…");
        assert_eq!(truncate_name_unicode("hello", 0), "");
        assert_eq!(truncate_name_unicode("hello", 1), "h");
    }
}
