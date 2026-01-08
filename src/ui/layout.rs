//! Main UI layout and rendering for the Data-X TUI disk analyzer.
//!
//! This module provides the main render function and layout components
//! for the application's terminal user interface.

use ratatui::{
    layout::{Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Clear, Paragraph},
    Frame,
};

use crate::app::{App, ScanPhase, ScanState};
use crate::scanner::DiskSpaceInfo;
use crate::tree::{FileTree, NodeId};
use crate::ui::colors::ColorScheme;
use crate::ui::details::render_details_panel;
use crate::ui::input::{ConfirmAction, FileCategory, InputMode, ViewMode};
use crate::ui::stats::render_stats_panel;
use crate::ui::tooltip::render_tooltip;
use crate::ui::tree_view::{render_tree_view, TreeViewState};
use crate::ui::treemap::render_treemap;

/// Application version string.
const VERSION: &str = env!("CARGO_PKG_VERSION");

/// Application name.
const APP_NAME: &str = "Data-X";

/// Main render function that draws the entire UI.
///
/// This function creates the main layout with header, main area, and status bar,
/// then delegates rendering to specialized functions for each section.
pub fn render_ui(frame: &mut Frame, app: &mut App) {
    let size = frame.area();

    // Create main vertical layout: header (3 lines), disk usage (3 lines), filter bar (3 lines), main area, status (3 lines)
    let main_layout = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3), // Header
            Constraint::Length(3), // Disk usage bar
            Constraint::Length(3), // Filter bar
            Constraint::Min(1),    // Main content area
            Constraint::Length(3), // Status bar
        ])
        .split(size);

    // Render header
    render_header(frame, main_layout[0], app);

    // Render disk usage bar
    render_disk_usage_bar(frame, main_layout[1], app);

    // Render filter bar
    render_filter_bar(frame, main_layout[2], app);

    // Render main content based on view mode
    // Store render results to assign after tree borrow ends
    let mut treemap_result: Option<TreemapRenderResult> = None;
    let mut clear_treemap = false;

    // Copy active_filter before borrowing tree
    let active_filter = app.active_filter;

    if let Some(ref tree) = app.tree {
        let tree_state = TreeViewState {
            selected_index: app.selected_index,
            scroll_offset: app.scroll_offset,
            expanded_nodes: app.expanded_nodes.clone(),
            search_query: if app.search_query.is_empty() {
                None
            } else {
                Some(app.search_query.clone())
            },
        };

        let selected_node_id = app.get_selected_node_id();
        let treemap_root = app.treemap_root.or(app.tree.as_ref().and_then(|t| t.root));

        // Get file type stats if available
        let file_type_stats = app.file_type_stats.as_ref();

        match app.view_mode {
            ViewMode::Split => {
                // Split view: tree (50%) | treemap (35%) | details/stats (15%)
                let main_area = Layout::default()
                    .direction(Direction::Horizontal)
                    .constraints([
                        Constraint::Percentage(50), // Tree view
                        Constraint::Percentage(35), // Treemap
                        Constraint::Percentage(15), // Details or Stats panel
                    ])
                    .split(main_layout[3]);

                render_tree_view(
                    frame,
                    main_area[0],
                    tree,
                    &app.visible_node_ids,
                    &tree_state,
                    &app.color_scheme,
                );

                treemap_result = Some(render_treemap_with_breadcrumb(
                    frame,
                    main_area[1],
                    tree,
                    treemap_root,
                    selected_node_id,
                    &app.color_scheme,
                    active_filter,
                ));

                // Render stats panel or details panel based on toggle
                if app.show_stats {
                    if let Some(stats) = file_type_stats {
                        render_stats_panel(frame, main_area[2], stats, &app.color_scheme);
                    } else {
                        render_empty_stats(frame, main_area[2], &app.color_scheme);
                    }
                } else {
                    render_details_panel(
                        frame,
                        main_area[2],
                        tree,
                        selected_node_id,
                        &app.color_scheme,
                    );
                }
            }
            ViewMode::TreeOnly => {
                // Tree view only with details/stats panel
                let main_area = Layout::default()
                    .direction(Direction::Horizontal)
                    .constraints([
                        Constraint::Percentage(70), // Tree view
                        Constraint::Percentage(30), // Details or Stats panel
                    ])
                    .split(main_layout[3]);

                // Mark treemap rects for clearing
                clear_treemap = true;

                render_tree_view(
                    frame,
                    main_area[0],
                    tree,
                    &app.visible_node_ids,
                    &tree_state,
                    &app.color_scheme,
                );

                // Render stats panel or details panel based on toggle
                if app.show_stats {
                    if let Some(stats) = file_type_stats {
                        render_stats_panel(frame, main_area[1], stats, &app.color_scheme);
                    } else {
                        render_empty_stats(frame, main_area[1], &app.color_scheme);
                    }
                } else {
                    render_details_panel(
                        frame,
                        main_area[1],
                        tree,
                        selected_node_id,
                        &app.color_scheme,
                    );
                }
            }
            ViewMode::TreemapOnly => {
                // Treemap view with details/stats panel
                let main_area = Layout::default()
                    .direction(Direction::Horizontal)
                    .constraints([
                        Constraint::Percentage(80), // Treemap
                        Constraint::Percentage(20), // Details or Stats panel
                    ])
                    .split(main_layout[3]);

                treemap_result = Some(render_treemap_with_breadcrumb(
                    frame,
                    main_area[0],
                    tree,
                    treemap_root,
                    selected_node_id,
                    &app.color_scheme,
                    active_filter,
                ));

                // Render stats panel or details panel based on toggle
                if app.show_stats {
                    if let Some(stats) = file_type_stats {
                        render_stats_panel(frame, main_area[1], stats, &app.color_scheme);
                    } else {
                        render_empty_stats(frame, main_area[1], &app.color_scheme);
                    }
                } else {
                    render_details_panel(
                        frame,
                        main_area[1],
                        tree,
                        selected_node_id,
                        &app.color_scheme,
                    );
                }
            }
        }
    } else {
        // No tree - show empty views based on mode
        let main_area = Layout::default()
            .direction(Direction::Horizontal)
            .constraints([
                Constraint::Percentage(70),
                Constraint::Percentage(30),
            ])
            .split(main_layout[3]);

        render_empty_tree(frame, main_area[0], &app.color_scheme);
        render_empty_details(frame, main_area[1], &app.color_scheme);
    }

    // Apply treemap results now that tree borrow has ended
    if let Some(result) = treemap_result {
        app.treemap_rects = result.treemap_rects;
        app.breadcrumb_items = result.breadcrumb_items;
        app.breadcrumb_y = result.breadcrumb_y;
    } else if clear_treemap {
        app.treemap_rects.clear();
        app.breadcrumb_items.clear();
    }

    render_status_bar(frame, main_layout[4], app);

    // Render overlays last (on top)
    if matches!(app.input_mode, InputMode::Help) {
        render_help_overlay(frame, size, &app.color_scheme);
    }

    if matches!(app.input_mode, InputMode::PathInput) {
        render_path_input_overlay(frame, size, app);
    }

    // Render hover tooltip over treemap (only in normal mode, not during overlays)
    if matches!(app.input_mode, InputMode::Normal) {
        if let (Some(mouse_pos), Some(hovered_node)) = (app.mouse_pos, app.hovered_node) {
            // Only show tooltip when treemap is visible
            if !matches!(app.view_mode, ViewMode::TreeOnly) {
                if let Some(ref tree) = app.tree {
                    // Get parent size for percentage calculation
                    let parent_size = app.treemap_root
                        .or(tree.root)
                        .and_then(|root_id| tree.get_node(root_id))
                        .map(|n| n.size)
                        .unwrap_or(0);

                    render_tooltip(
                        frame,
                        mouse_pos,
                        hovered_node,
                        tree,
                        &app.color_scheme,
                        parent_size,
                    );
                }
            }
        }
    }
}

/// Breadcrumb item for click navigation
#[derive(Debug, Clone)]
pub struct BreadcrumbItem {
    pub node_id: Option<NodeId>,
    pub x: u16,
    pub width: u16,
}

/// Render breadcrumb navigation for treemap.
/// Returns Vec of BreadcrumbItem for click handling.
fn render_breadcrumb(
    frame: &mut Frame,
    area: Rect,
    tree: &FileTree,
    treemap_root: Option<NodeId>,
    color_scheme: &ColorScheme,
) -> Vec<BreadcrumbItem> {
    let mut breadcrumbs: Vec<BreadcrumbItem> = Vec::new();

    // Build path from root to treemap_root
    let mut path_nodes: Vec<(Option<NodeId>, String)> = Vec::new();

    if let Some(root_id) = treemap_root {
        // Collect ancestors from treemap_root back to tree root
        let mut current = Some(root_id);
        while let Some(node_id) = current {
            if let Some(node) = tree.get_node(node_id) {
                let name = node.path.file_name()
                    .map(|n| n.to_string_lossy().to_string())
                    .unwrap_or_else(|| "/".to_string());
                path_nodes.push((Some(node_id), name));
            }
            current = tree.get_parent(node_id);
        }
        path_nodes.reverse();
    } else if let Some(root_id) = tree.root {
        // Just show the root
        if let Some(node) = tree.get_node(root_id) {
            let name = node.path.file_name()
                .map(|n| n.to_string_lossy().to_string())
                .unwrap_or_else(|| "/".to_string());
            path_nodes.push((Some(root_id), name));
        }
    }

    // Build spans for breadcrumb
    let mut spans = Vec::new();
    let sep_style = Style::default().fg(color_scheme.hint_fg);
    let item_style = Style::default().fg(color_scheme.accent);
    let current_style = Style::default()
        .fg(color_scheme.accent)
        .add_modifier(Modifier::BOLD);

    let mut x_pos: u16 = area.x + 1; // Start after border

    for (i, (node_id, name)) in path_nodes.iter().enumerate() {
        let is_last = i == path_nodes.len() - 1;

        // Add separator
        if i > 0 {
            spans.push(Span::styled(" → ", sep_style));
            x_pos += 3;
        }

        // Truncate name if needed
        let display_name = if name.chars().count() > 15 {
            let truncated: String = name.chars().take(12).collect();
            format!("{}...", truncated)
        } else {
            name.clone()
        };

        let name_width = display_name.chars().count() as u16;

        // Store position for click handling
        breadcrumbs.push(BreadcrumbItem {
            node_id: *node_id,
            x: x_pos,
            width: name_width,
        });

        // Style differently for current item
        let style = if is_last { current_style } else { item_style };
        spans.push(Span::styled(display_name, style));
        x_pos += name_width;
    }

    let line = Line::from(spans);

    let block = Block::default()
        .borders(Borders::ALL)
        .border_style(Style::default().fg(color_scheme.border))
        .title(" Path ")
        .title_style(Style::default().fg(color_scheme.hint_fg));

    let paragraph = Paragraph::new(line).block(block);
    frame.render_widget(paragraph, area);

    breadcrumbs
}

/// Treemap with breadcrumb render result.
pub struct TreemapRenderResult {
    pub treemap_rects: Vec<crate::ui::treemap::TreemapRect>,
    pub breadcrumb_items: Vec<BreadcrumbItem>,
    pub breadcrumb_y: u16,
}

/// Render treemap area with breadcrumb bar on top.
/// Returns the treemap rects and breadcrumb items for click handling.
fn render_treemap_with_breadcrumb(
    frame: &mut Frame,
    area: Rect,
    tree: &FileTree,
    treemap_root: Option<NodeId>,
    selected_node_id: Option<NodeId>,
    color_scheme: &ColorScheme,
    active_filter: FileCategory,
) -> TreemapRenderResult {
    // Split area: breadcrumb (3 lines) + treemap (rest)
    let layout = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3), // Breadcrumb bar
            Constraint::Min(1),    // Treemap
        ])
        .split(area);

    // Remember breadcrumb y position for click detection
    let breadcrumb_y = layout[0].y;

    // Render breadcrumb
    let breadcrumb_items = render_breadcrumb(frame, layout[0], tree, treemap_root, color_scheme);

    // Render treemap
    let treemap_rects = render_treemap(
        frame,
        layout[1],
        tree,
        treemap_root,
        selected_node_id,
        color_scheme,
        active_filter,
    );

    TreemapRenderResult {
        treemap_rects,
        breadcrumb_items,
        breadcrumb_y,
    }
}

/// Render empty tree view placeholder
fn render_empty_tree(frame: &mut Frame, area: Rect, color_scheme: &ColorScheme) {
    let block = Block::default()
        .title(" Tree View ")
        .borders(Borders::ALL)
        .border_style(Style::default().fg(color_scheme.border));

    let content = Paragraph::new("Scanning...")
        .block(block)
        .style(Style::default().fg(color_scheme.hint_fg));

    frame.render_widget(content, area);
}

/// Render empty details panel placeholder
fn render_empty_details(frame: &mut Frame, area: Rect, color_scheme: &ColorScheme) {
    let block = Block::default()
        .title(" Details ")
        .borders(Borders::ALL)
        .border_style(Style::default().fg(color_scheme.border));

    let content = Paragraph::new("No item selected")
        .block(block)
        .style(Style::default().fg(color_scheme.hint_fg));

    frame.render_widget(content, area);
}

/// Render empty stats panel placeholder (shown while scanning)
fn render_empty_stats(frame: &mut Frame, area: Rect, color_scheme: &ColorScheme) {
    let block = Block::default()
        .title(" File Types ")
        .borders(Borders::ALL)
        .border_style(Style::default().fg(color_scheme.border));

    let content = Paragraph::new("Calculating statistics...")
        .block(block)
        .style(Style::default().fg(color_scheme.hint_fg));

    frame.render_widget(content, area);
}

/// Render the header bar at the top of the screen.
fn render_header(frame: &mut Frame, area: Rect, app: &App) {
    let header_style = Style::default()
        .fg(app.color_scheme.header_fg)
        .bg(app.color_scheme.header_bg);

    let title_style = Style::default()
        .fg(app.color_scheme.accent)
        .add_modifier(Modifier::BOLD);

    let path_style = Style::default().fg(app.color_scheme.path_fg);

    let hint_style = Style::default()
        .fg(app.color_scheme.hint_fg)
        .add_modifier(Modifier::DIM);

    // Format the path, truncating if necessary (Unicode-safe)
    let path_str = app.root_path.to_string_lossy();
    let max_path_len = area.width.saturating_sub(40) as usize;
    let char_count = path_str.chars().count();
    let display_path = if char_count > max_path_len && max_path_len > 3 {
        // Take last (max_path_len - 3) characters, prepend "..."
        let skip_count = char_count.saturating_sub(max_path_len - 3);
        let suffix: String = path_str.chars().skip(skip_count).collect();
        format!("...{}", suffix)
    } else {
        path_str.to_string()
    };

    let header_line = Line::from(vec![
        Span::raw(" "),
        Span::styled(format!("{} v{}", APP_NAME, VERSION), title_style),
        Span::raw(" "),
        Span::styled("\u{2502}", header_style), // Vertical separator
        Span::raw(" "),
        Span::styled(display_path, path_style),
        Span::raw(" "),
        Span::styled("\u{2502}", header_style), // Vertical separator
        Span::raw(" "),
        Span::styled("Press ? for help", hint_style),
    ]);

    let header_block = Block::default()
        .borders(Borders::ALL)
        .border_style(Style::default().fg(app.color_scheme.border))
        .style(header_style);

    let header = Paragraph::new(header_line)
        .block(header_block)
        .style(header_style);

    frame.render_widget(header, area);
}

/// Render the disk usage bar showing used/free space.
///
/// Displays a visual bar with color gradient:
/// - Green (0-60%): Healthy disk usage
/// - Yellow (60-80%): Getting full
/// - Red (80-100%): Critical, disk nearly full
fn render_disk_usage_bar(frame: &mut Frame, area: Rect, app: &App) {
    let color_scheme = &app.color_scheme;

    // Get disk info, or show placeholder if not available
    let disk_info = app.disk_info.unwrap_or(DiskSpaceInfo {
        total: 0,
        used: 0,
        free: 0,
    });

    // Also get the scanned folder size
    let scanned_size = app.scan_progress.total_size;

    // Calculate usage percentage
    let usage_percent = if disk_info.total > 0 {
        (disk_info.used as f64 / disk_info.total as f64) * 100.0
    } else {
        0.0
    };

    // Calculate scanned folder percentage of disk
    let scanned_percent = if disk_info.total > 0 {
        (scanned_size as f64 / disk_info.total as f64) * 100.0
    } else {
        0.0
    };

    // Choose color based on usage percentage
    let bar_color = if usage_percent >= 80.0 {
        Color::Rgb(255, 80, 80)   // Red for critical
    } else if usage_percent >= 60.0 {
        Color::Rgb(255, 200, 80)  // Yellow/orange for warning
    } else {
        Color::Rgb(80, 200, 120)  // Green for healthy
    };

    // Calculate bar widths
    // Reserve space for: border (2) + label + sizes text
    let inner_width = area.width.saturating_sub(2) as usize;
    let label_and_stats = format!(
        " Disk Usage {} / {} ({:.1}%) | Scanned: {} ({:.1}%) ",
        format_size(disk_info.used),
        format_size(disk_info.total),
        usage_percent,
        format_size(scanned_size),
        scanned_percent
    );
    let label_len = label_and_stats.chars().count();

    // Remaining width for the progress bar
    let bar_width = inner_width.saturating_sub(label_len + 2); // +2 for spacing

    let filled_width = if disk_info.total > 0 && bar_width > 0 {
        ((usage_percent / 100.0) * bar_width as f64).round() as usize
    } else {
        0
    };
    let empty_width = bar_width.saturating_sub(filled_width);

    // Build the bar characters
    let filled_bar: String = "\u{2588}".repeat(filled_width);  // Full block
    let empty_bar: String = "\u{2591}".repeat(empty_width);    // Light shade

    // Build the line with bar and stats
    let mut spans = Vec::new();
    spans.push(Span::raw(" "));

    // Add the filled portion of the bar
    spans.push(Span::styled(filled_bar, Style::default().fg(bar_color)));

    // Add the empty portion of the bar
    spans.push(Span::styled(empty_bar, Style::default().fg(color_scheme.hint_fg)));

    spans.push(Span::raw(" "));

    // Add stats text
    if disk_info.total > 0 {
        spans.push(Span::styled(
            format!("{} / {}", format_size(disk_info.used), format_size(disk_info.total)),
            Style::default().fg(color_scheme.size_fg).add_modifier(Modifier::BOLD),
        ));
        spans.push(Span::styled(
            format!(" ({:.0}%)", usage_percent),
            Style::default().fg(bar_color).add_modifier(Modifier::BOLD),
        ));
        spans.push(Span::styled(" | ", Style::default().fg(color_scheme.hint_fg)));
        spans.push(Span::styled("Scanned: ", Style::default().fg(color_scheme.hint_fg)));
        spans.push(Span::styled(
            format_size(scanned_size),
            Style::default().fg(color_scheme.accent).add_modifier(Modifier::BOLD),
        ));
        spans.push(Span::styled(
            format!(" ({:.1}%)", scanned_percent),
            Style::default().fg(color_scheme.hint_fg),
        ));
    } else {
        // No disk info available
        spans.push(Span::styled(
            "Disk info not available",
            Style::default().fg(color_scheme.hint_fg),
        ));
    }

    let line = Line::from(spans);

    let block = Block::default()
        .borders(Borders::ALL)
        .border_style(Style::default().fg(color_scheme.border))
        .title(" Disk Usage ")
        .title_style(Style::default().fg(color_scheme.hint_fg));

    let paragraph = Paragraph::new(line).block(block);
    frame.render_widget(paragraph, area);
}

/// Render the file category filter bar.
///
/// Displays clickable filter chips for filtering files by category:
/// - All: Show all files (1)
/// - Audio: mp3, wav, flac, etc. (2)
/// - Video: mp4, mkv, avi, etc. (3)
/// - Images: jpg, png, gif, etc. (4)
/// - Docs: pdf, doc, txt, etc. (5)
/// - Code: rs, py, js, etc. (6)
/// - Archives: zip, tar, gz, etc. (7)
fn render_filter_bar(frame: &mut Frame, area: Rect, app: &App) {
    let color_scheme = &app.color_scheme;
    let active_filter = app.active_filter;

    let mut spans = Vec::new();
    spans.push(Span::styled(" Filter: ", Style::default().fg(color_scheme.hint_fg)));

    // Render each category as a chip
    for category in FileCategory::all_categories() {
        let is_active = *category == active_filter;
        let key = category.key_binding();
        let name = category.display_name();

        // Add spacing between chips
        if *category != FileCategory::All {
            spans.push(Span::raw(" "));
        }

        if is_active {
            // Active chip: highlighted background
            spans.push(Span::styled(
                format!("[{}:{}]", key, name),
                Style::default()
                    .fg(Color::Black)
                    .bg(color_scheme.accent)
                    .add_modifier(Modifier::BOLD),
            ));
        } else {
            // Inactive chip: dim appearance
            spans.push(Span::styled(
                format!("[{}:{}]", key, name),
                Style::default().fg(color_scheme.hint_fg),
            ));
        }
    }

    // Add filter hint on the right
    let hint_text = " | Press 1-7 to filter";
    spans.push(Span::styled(hint_text, Style::default().fg(color_scheme.text_dim)));

    let line = Line::from(spans);

    let block = Block::default()
        .borders(Borders::ALL)
        .border_style(Style::default().fg(color_scheme.border))
        .title(" File Types ")
        .title_style(Style::default().fg(color_scheme.hint_fg));

    let paragraph = Paragraph::new(line).block(block);
    frame.render_widget(paragraph, area);
}

/// Render the status bar at the bottom of the screen.
fn render_status_bar(frame: &mut Frame, area: Rect, app: &App) {
    let status_style = Style::default()
        .fg(app.color_scheme.status_fg)
        .bg(app.color_scheme.status_bg);

    let count_style = Style::default()
        .fg(app.color_scheme.size_fg)
        .add_modifier(Modifier::BOLD);

    let scanning_style = Style::default()
        .fg(app.color_scheme.scanning_fg)
        .add_modifier(Modifier::BOLD);

    let key_style = Style::default()
        .fg(app.color_scheme.key_fg)
        .add_modifier(Modifier::BOLD);

    let hint_style = Style::default().fg(app.color_scheme.hint_fg);

    let search_style = Style::default()
        .fg(app.color_scheme.search_fg)
        .add_modifier(Modifier::BOLD);

    // Build status line components
    let mut spans = vec![Span::raw(" ")];

    // File count
    let total_files = app.scan_progress.total_files;
    spans.push(Span::styled(format_file_count(total_files), count_style));
    spans.push(Span::raw(" "));
    spans.push(Span::styled("\u{2502}", status_style)); // Separator
    spans.push(Span::raw(" "));

    // Total size
    let total_size = app.scan_progress.total_size;
    spans.push(Span::styled(format_size(total_size), count_style));
    spans.push(Span::raw(" "));
    spans.push(Span::styled("\u{2502}", status_style)); // Separator
    spans.push(Span::raw(" "));

    // Scan status with progress bar
    match &app.scan_state {
        ScanState::Scanning => {
            let spinner = app.spinner_char();

            match app.scan_progress.phase {
                ScanPhase::Counting => {
                    // Counting phase (legacy, not used in single-pass mode)
                    let status_text = format!(
                        "{} Scanning... {} items",
                        spinner, app.scan_progress.files_found
                    );
                    spans.push(Span::styled(status_text, scanning_style));
                }
                ScanPhase::Analyzing | ScanPhase::Building => {
                    // Analysis phase - show progress bar with ETA
                    let progress = app.scan_progress.progress_percent();
                    let bar_width: usize = 15;
                    let filled = (progress * bar_width as f64).round() as usize;
                    let empty = bar_width.saturating_sub(filled);

                    // Progress bar characters
                    let bar: String = format!(
                        "{}{}",
                        "█".repeat(filled),
                        "░".repeat(empty)
                    );

                    let percent_str = format!("{:>3.0}%", progress * 100.0);

                    spans.push(Span::styled(
                        format!("{} ", spinner),
                        scanning_style,
                    ));
                    spans.push(Span::styled(
                        bar,
                        Style::default().fg(app.color_scheme.size_fg),
                    ));
                    spans.push(Span::styled(
                        format!(" {} ", percent_str),
                        count_style,
                    ));

                    // Files processed
                    spans.push(Span::styled(
                        format!(
                            "{}/{}",
                            format_compact_number(app.scan_progress.files_found),
                            format_compact_number(app.scan_progress.estimated_total)
                        ),
                        hint_style,
                    ));

                    // Speed and ETA
                    if app.scan_progress.items_per_second > 0.0 {
                        spans.push(Span::styled(" │ ", status_style));
                        spans.push(Span::styled(
                            app.scan_progress.speed_string(),
                            hint_style,
                        ));
                        if app.scan_progress.phase == ScanPhase::Analyzing {
                            spans.push(Span::styled(" │ ", status_style));
                            spans.push(Span::styled(
                                format!("ETA: {}", app.scan_progress.eta_string()),
                                scanning_style,
                            ));
                        }
                    }
                }
                ScanPhase::Complete | ScanPhase::Idle => {
                    spans.push(Span::styled("Ready", count_style));
                }
            }
        }
        ScanState::Complete => {
            spans.push(Span::styled("✓ Ready", count_style));
        }
        ScanState::Error(msg) => {
            spans.push(Span::styled(
                format!("✗ Error: {}", truncate_str(msg, 20)),
                Style::default().fg(app.color_scheme.error_fg),
            ));
        }
        ScanState::Idle => {
            spans.push(Span::styled("Idle", hint_style));
        }
    }

    spans.push(Span::raw(" "));
    spans.push(Span::styled("\u{2502}", status_style)); // Separator
    spans.push(Span::raw(" "));

    // Key shortcuts or search query
    match &app.input_mode {
        InputMode::Search => {
            spans.push(Span::styled("/", search_style));
            spans.push(Span::styled(&app.search_query, search_style));
            spans.push(Span::styled("_", search_style)); // Cursor
            spans.push(Span::raw(" "));
            spans.push(Span::styled("(ESC to cancel)", hint_style));
        }
        InputMode::Confirm(action) => {
            let action_text = match action {
                ConfirmAction::Delete => "Delete? (y/n)",
                ConfirmAction::Quit => "Quit? (y/n)",
            };
            spans.push(Span::styled(
                action_text,
                Style::default()
                    .fg(app.color_scheme.warning_fg)
                    .add_modifier(Modifier::BOLD),
            ));
        }
        InputMode::Normal => {
            // Key shortcuts
            spans.push(Span::styled("?", key_style));
            spans.push(Span::styled(":help ", hint_style));
            spans.push(Span::styled("p", key_style));
            spans.push(Span::styled(":path ", hint_style));
            spans.push(Span::styled("v", key_style));
            spans.push(Span::styled(":view ", hint_style));
            spans.push(Span::styled("T", key_style));
            spans.push(Span::styled(":stats ", hint_style));
            spans.push(Span::styled("s", key_style));
            spans.push(Span::styled(":sort ", hint_style));
            spans.push(Span::styled("q", key_style));
            spans.push(Span::styled(":quit ", hint_style));
            // Show current view mode and stats indicator
            let view_mode_str = match app.view_mode {
                ViewMode::Split => "[Split]",
                ViewMode::TreeOnly => "[Tree]",
                ViewMode::TreemapOnly => "[Map]",
            };
            spans.push(Span::styled(view_mode_str, count_style));
            if app.show_stats {
                spans.push(Span::styled(" [Stats]", Style::default().fg(app.color_scheme.accent)));
            }
        }
        InputMode::PathInput | InputMode::Help => {
            // Don't show shortcuts in overlay modes
        }
    }

    // Calculate padding for right-aligned credit
    let credit_text = "powered by C. Cassel - c@cassel.us";
    let current_len: usize = spans.iter().map(|s| s.content.len()).sum();
    let available_width = area.width.saturating_sub(4) as usize; // Account for borders and margins
    let padding_needed = available_width.saturating_sub(current_len + credit_text.len());

    if padding_needed > 0 {
        spans.push(Span::raw(" ".repeat(padding_needed)));
    }
    spans.push(Span::styled(credit_text, hint_style));

    let status_line = Line::from(spans);

    let status_block = Block::default()
        .borders(Borders::ALL)
        .border_style(Style::default().fg(app.color_scheme.border))
        .style(status_style);

    let status = Paragraph::new(status_line)
        .block(status_block)
        .style(status_style);

    frame.render_widget(status, area);
}

/// Format a file count with thousands separators.
fn format_file_count(count: u64) -> String {
    let count_str = count.to_string();
    let mut result = String::new();
    for (i, c) in count_str.chars().rev().enumerate() {
        if i > 0 && i % 3 == 0 {
            result.insert(0, ',');
        }
        result.insert(0, c);
    }
    format!("{} files", result)
}

/// Format a number in compact form (e.g., 1.2K, 3.4M).
fn format_compact_number(n: u64) -> String {
    if n >= 1_000_000 {
        format!("{:.1}M", n as f64 / 1_000_000.0)
    } else if n >= 1_000 {
        format!("{:.1}K", n as f64 / 1_000.0)
    } else {
        n.to_string()
    }
}

/// Format a byte size into human-readable format.
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

/// Truncate a string to a maximum length, adding ellipsis if needed.
/// Respects Unicode character boundaries.
fn truncate_str(s: &str, max_chars: usize) -> String {
    let char_count = s.chars().count();
    if char_count <= max_chars {
        s.to_string()
    } else if max_chars > 3 {
        let truncated: String = s.chars().take(max_chars - 3).collect();
        format!("{}...", truncated)
    } else {
        s.chars().take(max_chars).collect()
    }
}

/// Render help overlay with all keyboard shortcuts.
fn render_help_overlay(frame: &mut Frame, area: Rect, color_scheme: &ColorScheme) {
    // Calculate centered overlay dimensions
    let overlay_width = 60.min(area.width.saturating_sub(4));
    let overlay_height = 29.min(area.height.saturating_sub(2));
    let overlay_x = (area.width.saturating_sub(overlay_width)) / 2;
    let overlay_y = (area.height.saturating_sub(overlay_height)) / 2;

    let overlay_area = Rect::new(overlay_x, overlay_y, overlay_width, overlay_height);

    // Use a solid dark background color for the overlay
    let bg_color = Color::Rgb(30, 30, 40);

    // First clear the area completely
    frame.render_widget(Clear, overlay_area);

    let block = Block::default()
        .title(" Data-X Help ")
        .title_style(Style::default().fg(color_scheme.accent).add_modifier(Modifier::BOLD))
        .borders(Borders::ALL)
        .border_style(Style::default().fg(color_scheme.accent))
        .style(Style::default().bg(bg_color));

    let help_text = vec![
        Line::from(vec![
            Span::styled("Navigation", Style::default().fg(color_scheme.accent).add_modifier(Modifier::BOLD)),
        ]),
        Line::from(vec![
            Span::styled("  j/↓      ", Style::default().fg(color_scheme.key_fg)),
            Span::styled("Move down", Style::default().fg(color_scheme.text)),
        ]),
        Line::from(vec![
            Span::styled("  k/↑      ", Style::default().fg(color_scheme.key_fg)),
            Span::styled("Move up", Style::default().fg(color_scheme.text)),
        ]),
        Line::from(vec![
            Span::styled("  l/→/Enter", Style::default().fg(color_scheme.key_fg)),
            Span::styled("Expand/Enter directory", Style::default().fg(color_scheme.text)),
        ]),
        Line::from(vec![
            Span::styled("  h/←/Bksp ", Style::default().fg(color_scheme.key_fg)),
            Span::styled("Collapse/Go back", Style::default().fg(color_scheme.text)),
        ]),
        Line::from(vec![
            Span::styled("  g/G      ", Style::default().fg(color_scheme.key_fg)),
            Span::styled("Go to top/bottom", Style::default().fg(color_scheme.text)),
        ]),
        Line::from(vec![
            Span::styled("  PgUp/PgDn", Style::default().fg(color_scheme.key_fg)),
            Span::styled("Page up/down", Style::default().fg(color_scheme.text)),
        ]),
        Line::from(""),
        Line::from(vec![
            Span::styled("View", Style::default().fg(color_scheme.accent).add_modifier(Modifier::BOLD)),
        ]),
        Line::from(vec![
            Span::styled("  v/Tab    ", Style::default().fg(color_scheme.key_fg)),
            Span::styled("Toggle view mode (Split/Tree/Map)", Style::default().fg(color_scheme.text)),
        ]),
        Line::from(vec![
            Span::styled("  T        ", Style::default().fg(color_scheme.key_fg)),
            Span::styled("Toggle file type statistics panel", Style::default().fg(color_scheme.text)),
        ]),
        Line::from(vec![
            Span::styled("  z/Z      ", Style::default().fg(color_scheme.key_fg)),
            Span::styled("Drill down/up in treemap", Style::default().fg(color_scheme.text)),
        ]),
        Line::from(vec![
            Span::styled("  .        ", Style::default().fg(color_scheme.key_fg)),
            Span::styled("Toggle hidden files", Style::default().fg(color_scheme.text)),
        ]),
        Line::from(vec![
            Span::styled("  s        ", Style::default().fg(color_scheme.key_fg)),
            Span::styled("Cycle sort (size/name/count/date)", Style::default().fg(color_scheme.text)),
        ]),
        Line::from(vec![
            Span::styled("  1-7      ", Style::default().fg(color_scheme.key_fg)),
            Span::styled("Filter: All/Audio/Video/Images/Docs/Code/Archives", Style::default().fg(color_scheme.text)),
        ]),
        Line::from(""),
        Line::from(vec![
            Span::styled("Actions", Style::default().fg(color_scheme.accent).add_modifier(Modifier::BOLD)),
        ]),
        Line::from(vec![
            Span::styled("  /        ", Style::default().fg(color_scheme.key_fg)),
            Span::styled("Search/filter", Style::default().fg(color_scheme.text)),
        ]),
        Line::from(vec![
            Span::styled("  p        ", Style::default().fg(color_scheme.key_fg)),
            Span::styled("Change path (scan new directory)", Style::default().fg(color_scheme.text)),
        ]),
        Line::from(vec![
            Span::styled("  r        ", Style::default().fg(color_scheme.key_fg)),
            Span::styled("Rescan current directory", Style::default().fg(color_scheme.text)),
        ]),
        Line::from(vec![
            Span::styled("  d        ", Style::default().fg(color_scheme.key_fg)),
            Span::styled("Delete selected item", Style::default().fg(color_scheme.text)),
        ]),
        Line::from(vec![
            Span::styled("  c        ", Style::default().fg(color_scheme.key_fg)),
            Span::styled("Copy path to clipboard", Style::default().fg(color_scheme.text)),
        ]),
        Line::from(vec![
            Span::styled("  o        ", Style::default().fg(color_scheme.key_fg)),
            Span::styled("Open in file manager", Style::default().fg(color_scheme.text)),
        ]),
        Line::from(vec![
            Span::styled("  x        ", Style::default().fg(color_scheme.key_fg)),
            Span::styled("Exclude from analysis", Style::default().fg(color_scheme.text)),
        ]),
        Line::from(""),
        Line::from(vec![
            Span::styled("  q        ", Style::default().fg(color_scheme.key_fg)),
            Span::styled("Quit", Style::default().fg(color_scheme.text)),
        ]),
        Line::from(""),
        Line::from(vec![
            Span::styled("Press any key to close", Style::default().fg(color_scheme.hint_fg)),
        ]),
    ];

    let paragraph = Paragraph::new(help_text)
        .block(block)
        .style(Style::default().bg(bg_color));

    frame.render_widget(paragraph, overlay_area);
}

/// Render path input overlay.
fn render_path_input_overlay(frame: &mut Frame, area: Rect, app: &App) {
    let color_scheme = &app.color_scheme;

    // Calculate centered overlay dimensions
    let overlay_width = 75.min(area.width.saturating_sub(4));
    let overlay_height = 7;
    let overlay_x = (area.width.saturating_sub(overlay_width)) / 2;
    let overlay_y = (area.height.saturating_sub(overlay_height)) / 2;

    let overlay_area = Rect::new(overlay_x, overlay_y, overlay_width, overlay_height);

    // Use a solid dark background color for the overlay
    let bg_color = Color::Rgb(30, 30, 40);

    // First clear the area completely
    frame.render_widget(Clear, overlay_area);

    let block = Block::default()
        .title(" Change Path (Local or Remote) ")
        .title_style(Style::default().fg(color_scheme.accent).add_modifier(Modifier::BOLD))
        .borders(Borders::ALL)
        .border_style(Style::default().fg(color_scheme.accent))
        .style(Style::default().bg(bg_color));

    let inner = block.inner(overlay_area);
    frame.render_widget(block, overlay_area);

    // Path input line
    let path_line = Line::from(vec![
        Span::styled("Path: ", Style::default().fg(color_scheme.hint_fg)),
        Span::styled(&app.path_input, Style::default().fg(color_scheme.path_fg)),
        Span::styled("█", Style::default().fg(color_scheme.accent)), // Cursor
    ]);

    let hint_line = Line::from(vec![
        Span::styled("Enter: confirm | Esc: cancel", Style::default().fg(color_scheme.hint_fg)),
    ]);

    let example_line = Line::from(vec![
        Span::styled("Local: /path  Remote: user@host:/path", Style::default().fg(color_scheme.text_dim)),
    ]);

    let text = vec![path_line, Line::from(""), hint_line, example_line];
    let paragraph = Paragraph::new(text).style(Style::default().bg(bg_color));
    frame.render_widget(paragraph, inner);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_format_file_count() {
        assert_eq!(format_file_count(0), "0 files");
        assert_eq!(format_file_count(1), "1 files");
        assert_eq!(format_file_count(999), "999 files");
        assert_eq!(format_file_count(1000), "1,000 files");
        assert_eq!(format_file_count(1234567), "1,234,567 files");
    }

    #[test]
    fn test_format_size() {
        assert_eq!(format_size(0), "0 B");
        assert_eq!(format_size(512), "512 B");
        assert_eq!(format_size(1024), "1.0 KB");
        assert_eq!(format_size(1536), "1.5 KB");
        assert_eq!(format_size(1048576), "1.0 MB");
        assert_eq!(format_size(1073741824), "1.0 GB");
        assert_eq!(format_size(1099511627776), "1.0 TB");
    }

    #[test]
    fn test_truncate_str() {
        assert_eq!(truncate_str("hello", 10), "hello");
        assert_eq!(truncate_str("hello world", 8), "hello...");
        assert_eq!(truncate_str("hi", 2), "hi");
        assert_eq!(truncate_str("hello", 5), "hello");
    }
}
