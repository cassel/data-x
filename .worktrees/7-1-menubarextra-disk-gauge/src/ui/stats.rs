//! File type statistics panel for the Data-X TUI disk analyzer.
//!
//! This module provides aggregated statistics by file type/extension,
//! categorizing files into groups like Audio, Video, Images, etc.

use std::collections::HashMap;

use ratatui::{
    layout::Rect,
    style::{Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Paragraph},
    Frame,
};

use crate::tree::{FileTree, NodeId};
use crate::ui::colors::ColorScheme;
use crate::ui::input::FileCategory;

/// Stats category for internal grouping (extends FileCategory with Other)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum StatsCategory {
    Audio,
    Video,
    Images,
    Documents,
    Code,
    Archives,
    Other,
}

impl StatsCategory {
    /// Get the display name for the category
    pub fn display_name(&self) -> &'static str {
        match self {
            StatsCategory::Audio => "Audio",
            StatsCategory::Video => "Video",
            StatsCategory::Images => "Images",
            StatsCategory::Documents => "Docs",
            StatsCategory::Code => "Code",
            StatsCategory::Archives => "Archives",
            StatsCategory::Other => "Other",
        }
    }

    /// Get the icon/emoji for the category
    #[allow(dead_code)]
    pub fn icon(&self) -> &'static str {
        match self {
            StatsCategory::Audio => "\u{1F4C1}",     // Folder icon (file folder)
            StatsCategory::Video => "\u{1F3AC}",     // Clapper board
            StatsCategory::Images => "\u{1F5BC}",    // Framed picture
            StatsCategory::Documents => "\u{1F4C4}", // Page facing up
            StatsCategory::Code => "\u{1F4BB}",      // Laptop
            StatsCategory::Archives => "\u{1F4E6}", // Package
            StatsCategory::Other => "\u{1F4CE}",    // Paperclip
        }
    }

    /// Convert from FileCategory (All becomes Other)
    #[allow(dead_code)]
    pub fn from_file_category(cat: FileCategory) -> StatsCategory {
        match cat {
            FileCategory::Audio => StatsCategory::Audio,
            FileCategory::Video => StatsCategory::Video,
            FileCategory::Images => StatsCategory::Images,
            FileCategory::Documents => StatsCategory::Documents,
            FileCategory::Code => StatsCategory::Code,
            FileCategory::Archives => StatsCategory::Archives,
            FileCategory::All => StatsCategory::Other,
        }
    }

    /// Categorize an extension into a stats category
    pub fn from_extension(ext: &str) -> StatsCategory {
        let file_cat = FileCategory::from_extension(ext);
        Self::from_file_category(file_cat)
    }

    /// Get all categories in display order
    pub fn all() -> [StatsCategory; 7] {
        [
            StatsCategory::Audio,
            StatsCategory::Video,
            StatsCategory::Images,
            StatsCategory::Documents,
            StatsCategory::Code,
            StatsCategory::Archives,
            StatsCategory::Other,
        ]
    }
}

/// Statistics for a single file type/category
#[derive(Debug, Clone, Default)]
pub struct FileTypeStats {
    /// File extension or category name
    #[allow(dead_code)]
    pub extension: String,
    /// Number of files with this extension
    pub count: u64,
    /// Total size of all files with this extension
    pub total_size: u64,
    /// Percentage of total disk usage
    pub percentage: f64,
}

/// Aggregated file type statistics for the entire tree
#[derive(Debug, Clone, Default)]
pub struct AggregatedStats {
    /// Stats grouped by category
    pub by_category: HashMap<StatsCategory, FileTypeStats>,
    /// Total size of all files
    pub total_size: u64,
    /// Total file count
    pub total_count: u64,
}

impl AggregatedStats {
    /// Create new empty aggregated stats
    #[allow(dead_code)]
    pub fn new() -> Self {
        Self {
            by_category: HashMap::new(),
            total_size: 0,
            total_count: 0,
        }
    }

    /// Calculate aggregated statistics from a FileTree
    pub fn from_tree(tree: &FileTree) -> Self {
        let mut stats = AggregatedStats::new();

        if let Some(root) = tree.root {
            stats.collect_stats(tree, root);
        }

        // Calculate percentages
        if stats.total_size > 0 {
            for category_stats in stats.by_category.values_mut() {
                category_stats.percentage =
                    (category_stats.total_size as f64 / stats.total_size as f64) * 100.0;
            }
        }

        stats
    }

    /// Recursively collect stats from the tree
    fn collect_stats(&mut self, tree: &FileTree, node_id: NodeId) {
        if let Some(node) = tree.get_node(node_id) {
            // Only count files, not directories
            if !node.is_dir {
                self.total_size += node.size;
                self.total_count += 1;

                let category = node
                    .extension
                    .as_ref()
                    .map(|ext| StatsCategory::from_extension(ext))
                    .unwrap_or(StatsCategory::Other);

                let entry = self.by_category.entry(category).or_insert_with(|| {
                    FileTypeStats {
                        extension: category.display_name().to_string(),
                        count: 0,
                        total_size: 0,
                        percentage: 0.0,
                    }
                });

                entry.count += 1;
                entry.total_size += node.size;
            }

            // Recurse into children
            for child_id in tree.get_children(node_id) {
                self.collect_stats(tree, child_id);
            }
        }
    }

    /// Get stats for a specific category
    #[allow(dead_code)]
    pub fn get_category(&self, category: StatsCategory) -> Option<&FileTypeStats> {
        self.by_category.get(&category)
    }

    /// Get stats sorted by size (descending)
    #[allow(dead_code)]
    pub fn sorted_by_size(&self) -> Vec<(StatsCategory, &FileTypeStats)> {
        let mut sorted: Vec<_> = self.by_category.iter().map(|(&k, v)| (k, v)).collect();
        sorted.sort_by(|a, b| b.1.total_size.cmp(&a.1.total_size));
        sorted
    }
}

/// Render the file type statistics panel.
///
/// # Arguments
///
/// * `frame` - The ratatui frame to render into
/// * `area` - The rectangular area to render the panel in
/// * `stats` - The aggregated file type statistics
/// * `color_scheme` - The color scheme for styling
pub fn render_stats_panel(
    frame: &mut Frame,
    area: Rect,
    stats: &AggregatedStats,
    color_scheme: &ColorScheme,
) {
    let block = Block::default()
        .title(" File Types ")
        .borders(Borders::ALL)
        .border_type(ratatui::widgets::BorderType::Rounded)
        .border_style(Style::default().fg(color_scheme.border));

    let inner_area = block.inner(area);

    // Build lines for each category
    let mut lines: Vec<Line> = Vec::new();

    // Header line
    lines.push(Line::from(vec![
        Span::styled(
            "Category",
            Style::default()
                .fg(color_scheme.accent)
                .add_modifier(Modifier::BOLD),
        ),
    ]));
    lines.push(Line::from("")); // Empty line after header

    // Display categories in fixed order
    for category in StatsCategory::all() {
        let stats_entry = stats.by_category.get(&category);

        let (size_str, count, percentage) = match stats_entry {
            Some(entry) => (
                format_size(entry.total_size),
                entry.count,
                entry.percentage,
            ),
            None => ("0 B".to_string(), 0, 0.0),
        };

        // Format: icon category_name  size  percentage
        let icon = category.icon();
        let name = format!("{} {:<9}", icon, category.display_name());
        let size_display = format!("{:>8}", size_str);
        let percent_display = format!("{:>5.1}%", percentage);
        let count_display = format!("({} files)", format_count(count));

        // Calculate bar width based on percentage
        let max_bar_width = inner_area.width.saturating_sub(35) as usize;
        let bar_width = ((percentage / 100.0) * max_bar_width as f64).round() as usize;
        let bar: String = "\u{2588}".repeat(bar_width);

        let category_color = get_category_color(category, color_scheme);

        lines.push(Line::from(vec![
            Span::styled(name, Style::default().fg(color_scheme.text)),
            Span::styled(size_display, Style::default().fg(color_scheme.size_fg)),
            Span::raw("  "),
            Span::styled(
                percent_display,
                Style::default()
                    .fg(color_scheme.accent)
                    .add_modifier(Modifier::BOLD),
            ),
        ]));

        // Progress bar on next line if there's space
        if inner_area.height > 16 && bar_width > 0 {
            lines.push(Line::from(vec![
                Span::raw("  "),
                Span::styled(bar, Style::default().fg(category_color)),
                Span::raw(" "),
                Span::styled(count_display, Style::default().fg(color_scheme.text_dim)),
            ]));
        }
    }

    // Add total line
    lines.push(Line::from("")); // Separator
    lines.push(Line::from(vec![
        Span::styled(
            "Total:",
            Style::default()
                .fg(color_scheme.accent)
                .add_modifier(Modifier::BOLD),
        ),
        Span::raw(" "),
        Span::styled(
            format_size(stats.total_size),
            Style::default().fg(color_scheme.size_fg),
        ),
        Span::raw("  "),
        Span::styled(
            format!("({} files)", format_count(stats.total_count)),
            Style::default().fg(color_scheme.text_dim),
        ),
    ]));

    let paragraph = Paragraph::new(lines).block(block);
    frame.render_widget(paragraph, area);
}

/// Get color for a stats category
fn get_category_color(category: StatsCategory, color_scheme: &ColorScheme) -> ratatui::style::Color {
    match category {
        StatsCategory::Audio => color_scheme.audio,
        StatsCategory::Video => color_scheme.video,
        StatsCategory::Images => color_scheme.images,
        StatsCategory::Documents => color_scheme.documents,
        StatsCategory::Code => color_scheme.code,
        StatsCategory::Archives => color_scheme.archives,
        StatsCategory::Other => color_scheme.text_dim,
    }
}

/// Format a size in bytes to a human-readable string.
fn format_size(bytes: u64) -> String {
    const KB: u64 = 1024;
    const MB: u64 = 1024 * KB;
    const GB: u64 = 1024 * MB;
    const TB: u64 = 1024 * GB;

    if bytes >= TB {
        format!("{:.1}TB", bytes as f64 / TB as f64)
    } else if bytes >= GB {
        format!("{:.1}GB", bytes as f64 / GB as f64)
    } else if bytes >= MB {
        format!("{:.1}MB", bytes as f64 / MB as f64)
    } else if bytes >= KB {
        format!("{:.1}KB", bytes as f64 / KB as f64)
    } else {
        format!("{}B", bytes)
    }
}

/// Format a count with K/M suffixes for large numbers
fn format_count(count: u64) -> String {
    if count >= 1_000_000 {
        format!("{:.1}M", count as f64 / 1_000_000.0)
    } else if count >= 1_000 {
        format!("{:.1}K", count as f64 / 1_000.0)
    } else {
        count.to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    #[test]
    fn test_stats_category_from_extension() {
        assert_eq!(StatsCategory::from_extension("mp3"), StatsCategory::Audio);
        assert_eq!(StatsCategory::from_extension("MP3"), StatsCategory::Audio);
        assert_eq!(StatsCategory::from_extension("wav"), StatsCategory::Audio);

        assert_eq!(StatsCategory::from_extension("mp4"), StatsCategory::Video);
        assert_eq!(StatsCategory::from_extension("mkv"), StatsCategory::Video);

        assert_eq!(StatsCategory::from_extension("jpg"), StatsCategory::Images);
        assert_eq!(StatsCategory::from_extension("PNG"), StatsCategory::Images);

        assert_eq!(StatsCategory::from_extension("pdf"), StatsCategory::Documents);
        assert_eq!(StatsCategory::from_extension("txt"), StatsCategory::Documents);

        assert_eq!(StatsCategory::from_extension("rs"), StatsCategory::Code);
        assert_eq!(StatsCategory::from_extension("py"), StatsCategory::Code);
        assert_eq!(StatsCategory::from_extension("js"), StatsCategory::Code);

        assert_eq!(StatsCategory::from_extension("zip"), StatsCategory::Archives);
        assert_eq!(StatsCategory::from_extension("tar"), StatsCategory::Archives);

        assert_eq!(StatsCategory::from_extension("xyz"), StatsCategory::Other);
        assert_eq!(StatsCategory::from_extension(""), StatsCategory::Other);
    }

    #[test]
    fn test_format_size() {
        assert_eq!(format_size(0), "0B");
        assert_eq!(format_size(512), "512B");
        assert_eq!(format_size(1024), "1.0KB");
        assert_eq!(format_size(1024 * 1024), "1.0MB");
        assert_eq!(format_size(1024 * 1024 * 1024), "1.0GB");
        assert_eq!(format_size(1024 * 1024 * 1024 * 1024), "1.0TB");
    }

    #[test]
    fn test_format_count() {
        assert_eq!(format_count(0), "0");
        assert_eq!(format_count(999), "999");
        assert_eq!(format_count(1000), "1.0K");
        assert_eq!(format_count(1500), "1.5K");
        assert_eq!(format_count(1000000), "1.0M");
    }

    #[test]
    fn test_aggregated_stats_empty_tree() {
        let tree = crate::tree::FileTree::new();
        let stats = AggregatedStats::from_tree(&tree);
        assert_eq!(stats.total_size, 0);
        assert_eq!(stats.total_count, 0);
    }

    #[test]
    fn test_aggregated_stats_with_files() {
        use crate::tree::{FileNode, FileTree};

        let mut tree = FileTree::with_root(PathBuf::from("/test"));
        let root = tree.root.unwrap();

        // Add some test files
        let mp3_file = FileNode::new(PathBuf::from("/test/song.mp3"), false).with_size(1000);
        let jpg_file = FileNode::new(PathBuf::from("/test/photo.jpg"), false).with_size(2000);
        let rs_file = FileNode::new(PathBuf::from("/test/main.rs"), false).with_size(500);

        tree.add_child(root, mp3_file);
        tree.add_child(root, jpg_file);
        tree.add_child(root, rs_file);

        let stats = AggregatedStats::from_tree(&tree);

        assert_eq!(stats.total_size, 3500);
        assert_eq!(stats.total_count, 3);

        let audio_stats = stats.get_category(StatsCategory::Audio).unwrap();
        assert_eq!(audio_stats.count, 1);
        assert_eq!(audio_stats.total_size, 1000);

        let image_stats = stats.get_category(StatsCategory::Images).unwrap();
        assert_eq!(image_stats.count, 1);
        assert_eq!(image_stats.total_size, 2000);

        let code_stats = stats.get_category(StatsCategory::Code).unwrap();
        assert_eq!(code_stats.count, 1);
        assert_eq!(code_stats.total_size, 500);
    }

    #[test]
    fn test_category_display_name() {
        assert_eq!(StatsCategory::Audio.display_name(), "Audio");
        assert_eq!(StatsCategory::Video.display_name(), "Video");
        assert_eq!(StatsCategory::Images.display_name(), "Images");
        assert_eq!(StatsCategory::Documents.display_name(), "Docs");
        assert_eq!(StatsCategory::Code.display_name(), "Code");
        assert_eq!(StatsCategory::Archives.display_name(), "Archives");
        assert_eq!(StatsCategory::Other.display_name(), "Other");
    }
}
