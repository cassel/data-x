mod app;
mod cache;
mod export;
#[cfg(feature = "gui")]
mod gui;
mod remote;
mod scanner;
mod tree;
mod ui;

use std::io::{self, Write};
use std::panic;
use std::path::PathBuf;
use std::time::Duration;

use anyhow::Result;
use clap::Parser;
use crossterm::{
    event::{self, DisableMouseCapture, EnableMouseCapture, Event, KeyEventKind},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{backend::CrosstermBackend, Terminal};

use cache::CacheManager;

use app::App;
use export::{export_json, ExportOptions};
use scanner::ScanOptions;
use ui::{handle_key, ColorScheme};

#[derive(Parser, Debug)]
#[command(name = "data-x")]
#[command(author = "Cassel")]
#[command(version = "0.1.0")]
#[command(about = "TUI disk analyzer with colorful visualization", long_about = None)]
struct Args {
    /// Directory to analyze (default: current directory)
    #[arg(default_value = ".")]
    path: PathBuf,

    /// Maximum depth to scan
    #[arg(short, long)]
    depth: Option<usize>,

    /// Patterns to exclude (can be repeated)
    #[arg(short = 'x', long = "exclude", action = clap::ArgAction::Append)]
    exclude: Vec<String>,

    /// Output JSON instead of TUI
    #[arg(long)]
    json: bool,

    /// Show only N largest items (with --json)
    #[arg(short = 'n', long)]
    top: Option<usize>,

    /// Don't cross filesystem boundaries
    #[arg(long)]
    no_cross_mount: bool,

    /// Use apparent size instead of disk usage
    #[arg(long)]
    apparent_size: bool,

    /// Disable colors
    #[arg(long)]
    no_color: bool,

    /// Color scheme: default, dark, light, colorblind
    #[arg(long, default_value = "default")]
    color_scheme: String,

    /// Use ASCII instead of Unicode
    #[arg(long)]
    ascii: bool,

    /// Enable cache (experimental, disabled by default)
    #[arg(long)]
    use_cache: bool,

    /// Clear cache for the given path before scanning
    #[arg(long)]
    clear_cache: bool,

    /// Force TUI mode (default is GUI when gui feature is enabled)
    #[arg(long)]
    tui: bool,
}

fn main() -> Result<()> {
    let args = Args::parse();

    // Determine if we should use GUI mode
    // GUI is default when gui feature is enabled, unless --tui flag is passed
    #[cfg(feature = "gui")]
    let use_gui = !args.tui && !args.json;
    #[cfg(not(feature = "gui"))]
    let use_gui = false;

    // Check if this is a remote path (SSH)
    let path_str = args.path.to_string_lossy().to_string();
    if remote::is_remote_path(&path_str) {
        let ssh_target = remote::SshTarget::parse(&path_str)
            .ok_or_else(|| anyhow::anyhow!("Invalid SSH path format. Use: user@host:/path or ssh://user@host/path"))?;

        // JSON mode for remote
        if args.json {
            return run_remote_json_mode(&ssh_target, args.top);
        }

        // TUI mode for remote (GUI not supported for remote yet)
        return run_remote_tui_mode(ssh_target, &args.color_scheme, args.no_color);
    }

    // Local path - resolve it
    let root_path = args.path.canonicalize().unwrap_or(args.path.clone());

    // Create scan options
    let scan_options = ScanOptions {
        root_path: root_path.clone(),
        max_depth: args.depth,
        exclude_patterns: args.exclude,
        cross_mount: !args.no_cross_mount,
        apparent_size: args.apparent_size,
    };

    // Handle cache clearing
    if args.clear_cache {
        let cache_manager = CacheManager::new();
        if let Err(e) = cache_manager.clear(&root_path) {
            eprintln!("Warning: Could not clear cache: {}", e);
        }
    }

    // JSON mode - no TUI/GUI
    if args.json {
        return run_json_mode(scan_options, args.top);
    }

    // GUI mode (default when gui feature enabled and --tui not passed)
    if use_gui {
        #[cfg(feature = "gui")]
        {
            let options = eframe::NativeOptions {
                viewport: egui::ViewportBuilder::default()
                    .with_inner_size([1200.0, 800.0])
                    .with_title("Data-X - Disk Analyzer"),
                ..Default::default()
            };
            return eframe::run_native(
                "Data-X",
                options,
                Box::new(|cc| Ok(Box::new(gui::DataXApp::new(cc, args.path.clone())))),
            )
            .map_err(|e| anyhow::anyhow!("GUI error: {}", e));
        }
    }

    // TUI mode (cache disabled by default, use --use-cache to enable)
    run_tui_mode(scan_options, &args.color_scheme, args.no_color, args.use_cache)
}

fn run_json_mode(options: ScanOptions, top_n: Option<usize>) -> Result<()> {
    use std::sync::mpsc;

    let (tx, _rx) = mpsc::sync_channel(1000);
    let scanner = scanner::Scanner::new(options, tx);

    // Run scan synchronously for JSON mode
    let tree = scanner.scan()?;

    let export_options = ExportOptions { top_n };
    let mut stdout = io::stdout();
    export_json(&tree, &export_options, &mut stdout)?;
    println!(); // Final newline

    Ok(())
}

fn run_remote_json_mode(target: &remote::SshTarget, top_n: Option<usize>) -> Result<()> {
    use std::sync::mpsc;

    let (tx, _rx) = mpsc::sync_channel(1000);
    let scanner = remote::RemoteScanner::new(target.clone(), tx);

    eprintln!("Connecting to {}...", target.display());
    let tree = scanner.scan()?;

    let export_options = ExportOptions { top_n };
    let mut stdout = io::stdout();
    export_json(&tree, &export_options, &mut stdout)?;
    println!(); // Final newline

    Ok(())
}

fn run_remote_tui_mode(target: remote::SshTarget, color_scheme_name: &str, no_color: bool) -> Result<()> {
    // Set up panic handler to restore terminal on crash
    let original_hook = panic::take_hook();
    panic::set_hook(Box::new(move |panic_info| {
        let _ = disable_raw_mode();
        let _ = execute!(io::stdout(), LeaveAlternateScreen, DisableMouseCapture);
        original_hook(panic_info);
    }));

    // Setup terminal
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen, EnableMouseCapture)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;
    terminal.clear()?;

    // Select color scheme
    let color_scheme = if no_color {
        ColorScheme::default()
    } else {
        match color_scheme_name {
            "light" => ColorScheme::light(),
            "colorblind" => ColorScheme::colorblind(),
            "dark" | "default" | _ => ColorScheme::default(),
        }
    };

    // Create app with remote path display
    let display_path = PathBuf::from(target.display());
    let mut app = App::new(display_path, color_scheme);

    // Start remote scan in background
    app.start_remote_scan(target);

    // Main loop (no cache for remote)
    let cache_manager = CacheManager::new();
    let result = run_app(&mut terminal, &mut app, &cache_manager, false);

    // Restore terminal
    let cleanup_result = cleanup_terminal(&mut terminal);
    result.and(cleanup_result)
}

fn run_tui_mode(scan_options: ScanOptions, color_scheme_name: &str, no_color: bool, use_cache: bool) -> Result<()> {
    // Set up panic handler to restore terminal on crash
    let original_hook = panic::take_hook();
    panic::set_hook(Box::new(move |panic_info| {
        // Attempt to restore terminal
        let _ = disable_raw_mode();
        let _ = execute!(io::stdout(), LeaveAlternateScreen, DisableMouseCapture);

        // Call the original panic handler
        original_hook(panic_info);
    }));

    // Setup terminal
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen, EnableMouseCapture)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    // Clear screen to ensure clean state
    terminal.clear()?;

    // Select color scheme
    let color_scheme = if no_color {
        ColorScheme::default()
    } else {
        match color_scheme_name {
            "light" => ColorScheme::light(),
            "colorblind" => ColorScheme::colorblind(),
            "dark" | "default" | _ => ColorScheme::default(),
        }
    };

    // Try to load from cache first
    let cache_manager = CacheManager::new();
    let root_path = scan_options.root_path.clone();
    let mut app = App::new(root_path.clone(), color_scheme);

    let mut loaded_from_cache = false;
    if use_cache && cache_manager.has_valid_cache(&root_path) {
        if let Some(cache_entry) = cache_manager.load(&root_path) {
            if let Some(tree) = cache_manager.cache_entry_to_tree(&cache_entry) {
                // Successfully loaded from cache
                app.tree = Some(tree);
                app.scan_progress.total_files = cache_entry.total_files;
                app.scan_progress.total_size = cache_entry.total_size;
                app.scan_state = app::ScanState::Complete;
                app.scan_progress.phase = app::ScanPhase::Complete;

                // Expand root and refresh visible nodes
                if let Some(ref t) = app.tree {
                    if let Some(root) = t.root {
                        app.expanded_nodes.insert(root);
                    }
                }
                app.refresh_visible_nodes();
                loaded_from_cache = true;

                // Note: User can press 'r' to rescan and check for changes
            }
        }
    }

    // If not loaded from cache, do full scan
    if !loaded_from_cache {
        app.start_scan(scan_options.clone());
    }

    // Main loop
    let result = run_app(&mut terminal, &mut app, &cache_manager, use_cache);

    // Restore terminal (wrapped in closure to ensure it runs)
    let cleanup_result = cleanup_terminal(&mut terminal);

    // Return the first error if any
    result.and(cleanup_result)
}

/// Clean up terminal state.
fn cleanup_terminal<B: ratatui::backend::Backend + Write>(terminal: &mut Terminal<B>) -> Result<()> {
    disable_raw_mode()?;
    execute!(
        terminal.backend_mut(),
        LeaveAlternateScreen,
        DisableMouseCapture
    )?;
    terminal.show_cursor()?;
    Ok(())
}

fn run_app<B: ratatui::backend::Backend>(
    terminal: &mut Terminal<B>,
    app: &mut App,
    cache_manager: &CacheManager,
    use_cache: bool,
) -> Result<()> {
    let mut last_scan_state = app.scan_state.clone();

    loop {
        // Update app state (check scan progress)
        app.update();

        // Check if scan just completed - save to cache
        if use_cache && app.scan_state == app::ScanState::Complete && last_scan_state != app::ScanState::Complete {
            if let Some(ref tree) = app.tree {
                let _ = cache_manager.save(tree, &app.root_path);
            }
        }
        last_scan_state = app.scan_state.clone();

        // Render UI
        terminal.draw(|frame| {
            ui::render_ui(frame, app);
        })?;

        // Handle input with timeout (for animations)
        if event::poll(Duration::from_millis(50))? {
            match event::read()? {
                Event::Key(key) => {
                    // Only handle key press, not release
                    if key.kind == KeyEventKind::Press {
                        let command = handle_key(key, &app.input_mode);
                        app.handle_command(command);
                    }
                }
                Event::Mouse(mouse_event) => {
                    use crossterm::event::{MouseButton, MouseEventKind};
                    let x = mouse_event.column;
                    let y = mouse_event.row;

                    match mouse_event.kind {
                        MouseEventKind::Down(MouseButton::Left) => {
                            // Check for double-click (click same area within 400ms)
                            let now = std::time::Instant::now();
                            let pos = (x, y);

                            let is_double_click = app.last_click.map_or(false, |(last_time, last_pos)| {
                                now.duration_since(last_time).as_millis() < 400
                                    && last_pos == pos
                            });

                            // Try breadcrumb click first (always single click navigation)
                            if app.handle_breadcrumb_click(x, y) {
                                app.last_click = None;
                            } else if is_double_click {
                                // Double-click - enter directory in treemap
                                app.handle_treemap_double_click(x, y);
                                app.last_click = None;
                            } else {
                                // Single click - select block in treemap
                                app.handle_treemap_click(x, y);
                                app.last_click = Some((now, pos));
                            }
                        }
                        MouseEventKind::Moved => {
                            // Track mouse position for hover tooltips
                            app.update_mouse_pos(x, y);
                        }
                        _ => {}
                    }
                }
                _ => {}
            }
        }

        // Check if should quit
        if app.should_quit {
            break;
        }
    }

    Ok(())
}
