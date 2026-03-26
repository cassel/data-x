//! Input handling for the Data-X TUI disk analyzer.
//!
//! This module provides key event handling with support for multiple input modes:
//! Normal navigation, Search input, and Confirmation dialogs.

use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};

/// The current input mode of the application.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum InputMode {
    /// Normal navigation mode for browsing the filesystem.
    Normal,
    /// Search mode for filtering entries.
    Search,
    /// Path input mode for changing the scan directory.
    PathInput,
    /// Confirmation mode for dangerous actions.
    Confirm(ConfirmAction),
    /// Help overlay showing all keyboard shortcuts.
    Help,
}

/// Actions that require user confirmation.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[allow(dead_code)]
pub enum ConfirmAction {
    /// Confirm file/directory deletion.
    Delete,
    /// Confirm application quit.
    Quit,
}

/// Available sorting options for directory entries.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum SortBy {
    /// Sort by size (largest first).
    #[default]
    Size,
    /// Sort alphabetically by name.
    Name,
    /// Sort by number of files (for directories).
    FileCount,
    /// Sort by modification time (newest first).
    Modified,
}

/// View mode for the main display area.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum ViewMode {
    /// Split view: tree on left, treemap on right (default)
    #[default]
    Split,
    /// Tree view only (classic mode)
    TreeOnly,
    /// Treemap only (visual mode)
    TreemapOnly,
}

/// File category for filtering the display.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum FileCategory {
    /// Show all files (no filter)
    #[default]
    All,
    /// Audio files (mp3, wav, flac, aac, ogg, m4a, wma)
    Audio,
    /// Video files (mp4, mkv, avi, mov, wmv, flv, webm)
    Video,
    /// Image files (jpg, jpeg, png, gif, bmp, svg, webp, ico, tiff)
    Images,
    /// Document files (pdf, doc, docx, txt, rtf, odt, xls, xlsx, ppt, pptx)
    Documents,
    /// Code files (rs, py, js, ts, c, cpp, h, java, go, rb, php, html, css)
    Code,
    /// Archive files (zip, tar, gz, rar, 7z, bz2, xz)
    Archives,
}

impl FileCategory {
    /// Get the display name for this category.
    pub fn display_name(&self) -> &'static str {
        match self {
            FileCategory::All => "All",
            FileCategory::Audio => "Audio",
            FileCategory::Video => "Video",
            FileCategory::Images => "Images",
            FileCategory::Documents => "Docs",
            FileCategory::Code => "Code",
            FileCategory::Archives => "Archives",
        }
    }

    /// Get the key binding for this category.
    pub fn key_binding(&self) -> char {
        match self {
            FileCategory::All => '1',
            FileCategory::Audio => '2',
            FileCategory::Video => '3',
            FileCategory::Images => '4',
            FileCategory::Documents => '5',
            FileCategory::Code => '6',
            FileCategory::Archives => '7',
        }
    }

    /// Get all categories for iteration.
    pub fn all_categories() -> &'static [FileCategory] {
        &[
            FileCategory::All,
            FileCategory::Audio,
            FileCategory::Video,
            FileCategory::Images,
            FileCategory::Documents,
            FileCategory::Code,
            FileCategory::Archives,
        ]
    }

    /// Get the category for a file extension.
    pub fn from_extension(ext: &str) -> FileCategory {
        let ext_lower = ext.to_lowercase();
        match ext_lower.as_str() {
            // Audio
            "mp3" | "wav" | "flac" | "aac" | "ogg" | "m4a" | "wma" | "aiff" | "alac" => {
                FileCategory::Audio
            }
            // Video
            "mp4" | "mkv" | "avi" | "mov" | "wmv" | "flv" | "webm" | "m4v" | "mpeg" | "mpg" => {
                FileCategory::Video
            }
            // Images
            "jpg" | "jpeg" | "png" | "gif" | "bmp" | "svg" | "webp" | "ico" | "tiff" | "tif"
            | "raw" | "heic" | "heif" => FileCategory::Images,
            // Documents
            "pdf" | "doc" | "docx" | "txt" | "rtf" | "odt" | "xls" | "xlsx" | "ppt" | "pptx"
            | "csv" | "md" | "epub" | "mobi" => FileCategory::Documents,
            // Code
            "rs" | "py" | "js" | "ts" | "tsx" | "jsx" | "c" | "cpp" | "cc" | "h" | "hpp"
            | "java" | "go" | "rb" | "php" | "html" | "htm" | "css" | "scss" | "sass" | "less"
            | "json" | "xml" | "yaml" | "yml" | "toml" | "sql" | "sh" | "bash" | "zsh"
            | "swift" | "kt" | "scala" | "lua" | "r" | "pl" | "pm" => FileCategory::Code,
            // Archives
            "zip" | "tar" | "gz" | "tgz" | "rar" | "7z" | "bz2" | "xz" | "lz" | "lzma" | "cab"
            | "iso" | "dmg" => FileCategory::Archives,
            // Default to All (no specific category)
            _ => FileCategory::All,
        }
    }
}

#[allow(dead_code)]
impl SortBy {
    /// Cycle to the next sort option.
    pub fn next(self) -> Self {
        match self {
            SortBy::Size => SortBy::Name,
            SortBy::Name => SortBy::FileCount,
            SortBy::FileCount => SortBy::Modified,
            SortBy::Modified => SortBy::Size,
        }
    }
}

impl ViewMode {
    /// Cycle to the next view mode.
    pub fn next(self) -> Self {
        match self {
            ViewMode::Split => ViewMode::TreeOnly,
            ViewMode::TreeOnly => ViewMode::TreemapOnly,
            ViewMode::TreemapOnly => ViewMode::Split,
        }
    }
}

/// Commands that can be issued by the user.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Command {
    /// Move selection up.
    MoveUp,
    /// Move selection down.
    MoveDown,
    /// Enter the selected directory or open file details.
    Enter,
    /// Go back to the parent directory.
    Back,
    /// Toggle visibility of hidden files.
    ToggleHidden,
    /// Enter search mode.
    StartSearch,
    /// Add a character to the search query.
    SearchInput(char),
    /// Remove the last character from the search query.
    SearchBackspace,
    /// Confirm the current search and stay on selected item.
    ConfirmSearch,
    /// Exit search mode and clear the search query.
    ExitSearch,
    /// Change the sort order.
    Sort(SortBy),
    /// Delete the selected file or directory.
    Delete,
    /// Rescan the current directory.
    Rescan,
    /// Copy the path of the selected item to clipboard.
    CopyPath,
    /// Open the selected item in the system file manager.
    OpenInFM,
    /// Export the current view to a file.
    Export,
    /// Show detailed information about the selected item.
    ShowDetails,
    /// Quit the application.
    Quit,
    /// Jump to the first item.
    GotoTop,
    /// Jump to the last item.
    GotoBottom,
    /// Exclude the selected item from analysis.
    Exclude,
    /// Confirm the current action (in Confirm mode).
    Confirm,
    /// Cancel the current action (in Confirm mode).
    Cancel,
    /// Toggle view mode (split/tree/treemap).
    ToggleView,
    /// Set a specific view mode.
    SetViewMode(ViewMode),
    /// Page up navigation.
    PageUp,
    /// Page down navigation.
    PageDown,
    /// Navigate into selected directory (set as treemap root).
    DrillDown,
    /// Navigate up to parent directory.
    DrillUp,
    /// Show help/about screen.
    ShowHelp,
    /// Hide help screen.
    HideHelp,
    /// Start path input mode.
    StartPathInput,
    /// Add a character to the path input.
    PathInput(char),
    /// Remove the last character from the path input.
    PathBackspace,
    /// Confirm path input and start scan.
    ConfirmPath,
    /// Cancel path input.
    CancelPath,
    /// Toggle file category filter.
    ToggleFilter(FileCategory),
    /// Toggle file type statistics panel visibility.
    ToggleStats,
    /// No operation - key was not recognized or not applicable.
    Noop,
}

/// Handle a key event and return the corresponding command.
///
/// The behavior depends on the current input mode:
/// - `Normal`: Full navigation and action commands
/// - `Search`: Text input with limited navigation
/// - `Confirm`: Yes/No confirmation only
///
/// # Arguments
///
/// * `key` - The key event to handle
/// * `mode` - The current input mode
///
/// # Returns
///
/// The command corresponding to the key press, or `Command::Noop` if the key
/// is not recognized in the current mode.
pub fn handle_key(key: KeyEvent, mode: &InputMode) -> Command {
    match mode {
        InputMode::Normal => handle_normal_mode(key),
        InputMode::Search => handle_search_mode(key),
        InputMode::PathInput => handle_path_input_mode(key),
        InputMode::Confirm(_) => handle_confirm_mode(key),
        InputMode::Help => handle_help_mode(key),
    }
}

/// Handle key events in Normal mode.
fn handle_normal_mode(key: KeyEvent) -> Command {
    match key.code {
        // Navigation - Back / Drill Up
        KeyCode::Char('h') | KeyCode::Left | KeyCode::Backspace => Command::Back,

        // Navigation - Down
        KeyCode::Char('j') | KeyCode::Down => Command::MoveDown,

        // Navigation - Up
        KeyCode::Char('k') | KeyCode::Up => Command::MoveUp,

        // Navigation - Enter/Select / Drill Down
        KeyCode::Char('l') | KeyCode::Right | KeyCode::Enter => Command::Enter,

        // Page navigation
        KeyCode::PageUp => Command::PageUp,
        KeyCode::PageDown => Command::PageDown,
        KeyCode::Char('u') if key.modifiers.contains(KeyModifiers::CONTROL) => Command::PageUp,
        KeyCode::Char('d') if key.modifiers.contains(KeyModifiers::CONTROL) => Command::PageDown,

        // Jump to top
        KeyCode::Char('g') => Command::GotoTop,

        // Jump to bottom (Shift+G)
        KeyCode::Char('G') => Command::GotoBottom,

        // Quit
        KeyCode::Char('q') => Command::Quit,

        // Delete
        KeyCode::Char('d') => Command::Delete,

        // Rescan
        KeyCode::Char('r') => Command::Rescan,

        // Copy path
        KeyCode::Char('c') => Command::CopyPath,

        // Open in file manager
        KeyCode::Char('o') => Command::OpenInFM,

        // Export
        KeyCode::Char('e') => Command::Export,

        // Show details/info
        KeyCode::Char('i') => Command::ShowDetails,

        // Sort (cycle through options)
        KeyCode::Char('s') => Command::Sort(SortBy::Size),

        // Toggle hidden files
        KeyCode::Char('.') => Command::ToggleHidden,

        // Toggle view mode (split/tree/treemap)
        // v/Tab cycles through modes, m goes to treemap, t goes to tree
        KeyCode::Char('v') | KeyCode::Tab => Command::ToggleView,
        KeyCode::Char('m') => Command::SetViewMode(ViewMode::TreemapOnly),
        KeyCode::Char('t') => Command::SetViewMode(ViewMode::TreeOnly),

        // Start search
        KeyCode::Char('/') => Command::StartSearch,

        // Exclude
        KeyCode::Char('x') => Command::Exclude,

        // Drill into selected directory (set as treemap root)
        KeyCode::Char('z') => Command::DrillDown,

        // Drill up to parent
        KeyCode::Char('Z') => Command::DrillUp,

        // Help/About
        KeyCode::Char('?') => Command::ShowHelp,

        // Change path
        KeyCode::Char('p') => Command::StartPathInput,

        // Filter by file category (1-7)
        KeyCode::Char('1') => Command::ToggleFilter(FileCategory::All),
        KeyCode::Char('2') => Command::ToggleFilter(FileCategory::Audio),
        KeyCode::Char('3') => Command::ToggleFilter(FileCategory::Video),
        KeyCode::Char('4') => Command::ToggleFilter(FileCategory::Images),
        KeyCode::Char('5') => Command::ToggleFilter(FileCategory::Documents),
        KeyCode::Char('6') => Command::ToggleFilter(FileCategory::Code),
        KeyCode::Char('7') => Command::ToggleFilter(FileCategory::Archives),

        // Toggle file type statistics panel (Shift+T)
        KeyCode::Char('T') => Command::ToggleStats,

        // Unrecognized key
        _ => Command::Noop,
    }
}

/// Handle key events in Help mode.
fn handle_help_mode(_key: KeyEvent) -> Command {
    // Any key closes help
    Command::HideHelp
}

/// Handle key events in Path Input mode.
fn handle_path_input_mode(key: KeyEvent) -> Command {
    match key.code {
        // Cancel path input
        KeyCode::Esc => Command::CancelPath,

        // Confirm path and start scan
        KeyCode::Enter => Command::ConfirmPath,

        // Delete last character
        KeyCode::Backspace => Command::PathBackspace,

        // Character input
        KeyCode::Char(c) => Command::PathInput(c),

        // Tab for path completion hint (just insert tab for now)
        KeyCode::Tab => Command::PathInput('\t'),

        // Unrecognized key
        _ => Command::Noop,
    }
}

/// Handle key events in Search mode.
fn handle_search_mode(key: KeyEvent) -> Command {
    match key.code {
        // Exit search mode
        KeyCode::Esc => Command::ExitSearch,

        // Confirm search
        KeyCode::Enter => Command::ConfirmSearch,

        // Delete last character
        KeyCode::Backspace => Command::SearchBackspace,

        // Navigation while searching
        KeyCode::Char('j') | KeyCode::Down => Command::MoveDown,
        KeyCode::Char('k') | KeyCode::Up => Command::MoveUp,

        // Character input
        KeyCode::Char(c) => {
            // Only accept printable characters (not control characters)
            if c.is_ascii_graphic() || c == ' ' {
                Command::SearchInput(c)
            } else {
                Command::Noop
            }
        }

        // Unrecognized key
        _ => Command::Noop,
    }
}

/// Handle key events in Confirm mode.
fn handle_confirm_mode(key: KeyEvent) -> Command {
    match key.code {
        // Confirm action
        KeyCode::Char('y') | KeyCode::Char('Y') | KeyCode::Enter => Command::Confirm,

        // Cancel action
        KeyCode::Char('n') | KeyCode::Char('N') | KeyCode::Esc => Command::Cancel,

        // Any other key is a no-op in confirm mode
        _ => Command::Noop,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[allow(unused_imports)]
    use crossterm::event::KeyEventKind;

    fn key_event(code: KeyCode) -> KeyEvent {
        KeyEvent::new(code, KeyModifiers::empty())
    }

    #[allow(dead_code)]
    fn key_event_with_modifiers(code: KeyCode, modifiers: KeyModifiers) -> KeyEvent {
        KeyEvent::new(code, modifiers)
    }

    #[test]
    fn test_normal_mode_navigation() {
        let mode = InputMode::Normal;

        assert_eq!(handle_key(key_event(KeyCode::Char('h')), &mode), Command::Back);
        assert_eq!(handle_key(key_event(KeyCode::Left), &mode), Command::Back);
        assert_eq!(handle_key(key_event(KeyCode::Backspace), &mode), Command::Back);

        assert_eq!(handle_key(key_event(KeyCode::Char('j')), &mode), Command::MoveDown);
        assert_eq!(handle_key(key_event(KeyCode::Down), &mode), Command::MoveDown);

        assert_eq!(handle_key(key_event(KeyCode::Char('k')), &mode), Command::MoveUp);
        assert_eq!(handle_key(key_event(KeyCode::Up), &mode), Command::MoveUp);

        assert_eq!(handle_key(key_event(KeyCode::Char('l')), &mode), Command::Enter);
        assert_eq!(handle_key(key_event(KeyCode::Right), &mode), Command::Enter);
        assert_eq!(handle_key(key_event(KeyCode::Enter), &mode), Command::Enter);
    }

    #[test]
    fn test_normal_mode_jump() {
        let mode = InputMode::Normal;

        assert_eq!(handle_key(key_event(KeyCode::Char('g')), &mode), Command::GotoTop);
        assert_eq!(
            handle_key(
                key_event_with_modifiers(KeyCode::Char('G'), KeyModifiers::SHIFT),
                &mode
            ),
            Command::GotoBottom
        );
    }

    #[test]
    fn test_normal_mode_actions() {
        let mode = InputMode::Normal;

        assert_eq!(handle_key(key_event(KeyCode::Char('q')), &mode), Command::Quit);
        assert_eq!(handle_key(key_event(KeyCode::Char('d')), &mode), Command::Delete);
        assert_eq!(handle_key(key_event(KeyCode::Char('r')), &mode), Command::Rescan);
        assert_eq!(handle_key(key_event(KeyCode::Char('c')), &mode), Command::CopyPath);
        assert_eq!(handle_key(key_event(KeyCode::Char('o')), &mode), Command::OpenInFM);
        assert_eq!(handle_key(key_event(KeyCode::Char('e')), &mode), Command::Export);
        assert_eq!(handle_key(key_event(KeyCode::Char('i')), &mode), Command::ShowDetails);
        assert_eq!(handle_key(key_event(KeyCode::Char('x')), &mode), Command::Exclude);
    }

    #[test]
    fn test_normal_mode_toggles() {
        let mode = InputMode::Normal;

        assert_eq!(handle_key(key_event(KeyCode::Char('.')), &mode), Command::ToggleHidden);
        assert_eq!(handle_key(key_event(KeyCode::Char('/')), &mode), Command::StartSearch);
        assert!(matches!(handle_key(key_event(KeyCode::Char('s')), &mode), Command::Sort(_)));
    }

    #[test]
    fn test_search_mode() {
        let mode = InputMode::Search;

        assert_eq!(handle_key(key_event(KeyCode::Esc), &mode), Command::ExitSearch);
        assert_eq!(handle_key(key_event(KeyCode::Enter), &mode), Command::ConfirmSearch);
        assert_eq!(handle_key(key_event(KeyCode::Backspace), &mode), Command::SearchBackspace);

        assert_eq!(handle_key(key_event(KeyCode::Char('j')), &mode), Command::MoveDown);
        assert_eq!(handle_key(key_event(KeyCode::Down), &mode), Command::MoveDown);
        assert_eq!(handle_key(key_event(KeyCode::Char('k')), &mode), Command::MoveUp);
        assert_eq!(handle_key(key_event(KeyCode::Up), &mode), Command::MoveUp);

        assert_eq!(handle_key(key_event(KeyCode::Char('a')), &mode), Command::SearchInput('a'));
        assert_eq!(handle_key(key_event(KeyCode::Char('Z')), &mode), Command::SearchInput('Z'));
        assert_eq!(handle_key(key_event(KeyCode::Char('5')), &mode), Command::SearchInput('5'));
        assert_eq!(handle_key(key_event(KeyCode::Char(' ')), &mode), Command::SearchInput(' '));
    }

    #[test]
    fn test_confirm_mode() {
        let mode = InputMode::Confirm(ConfirmAction::Delete);

        assert_eq!(handle_key(key_event(KeyCode::Char('y')), &mode), Command::Confirm);
        assert_eq!(handle_key(key_event(KeyCode::Char('Y')), &mode), Command::Confirm);
        assert_eq!(handle_key(key_event(KeyCode::Enter), &mode), Command::Confirm);

        assert_eq!(handle_key(key_event(KeyCode::Char('n')), &mode), Command::Cancel);
        assert_eq!(handle_key(key_event(KeyCode::Char('N')), &mode), Command::Cancel);
        assert_eq!(handle_key(key_event(KeyCode::Esc), &mode), Command::Cancel);

        assert_eq!(handle_key(key_event(KeyCode::Char('x')), &mode), Command::Noop);
        assert_eq!(handle_key(key_event(KeyCode::Char('q')), &mode), Command::Noop);
    }

    #[test]
    fn test_sort_by_cycle() {
        assert_eq!(SortBy::Size.next(), SortBy::Name);
        assert_eq!(SortBy::Name.next(), SortBy::FileCount);
        assert_eq!(SortBy::FileCount.next(), SortBy::Modified);
        assert_eq!(SortBy::Modified.next(), SortBy::Size);
    }

    #[test]
    fn test_unrecognized_keys() {
        let mode = InputMode::Normal;
        assert_eq!(handle_key(key_event(KeyCode::F(1)), &mode), Command::Noop);
    }

    #[test]
    fn test_view_mode_toggle() {
        let mode = InputMode::Normal;
        assert_eq!(handle_key(key_event(KeyCode::Char('v')), &mode), Command::ToggleView);
        assert_eq!(handle_key(key_event(KeyCode::Tab), &mode), Command::ToggleView);
    }

    #[test]
    fn test_view_mode_set() {
        let mode = InputMode::Normal;
        assert_eq!(handle_key(key_event(KeyCode::Char('m')), &mode), Command::SetViewMode(ViewMode::TreemapOnly));
        assert_eq!(handle_key(key_event(KeyCode::Char('t')), &mode), Command::SetViewMode(ViewMode::TreeOnly));
    }

    #[test]
    fn test_view_mode_cycle() {
        assert_eq!(ViewMode::Split.next(), ViewMode::TreeOnly);
        assert_eq!(ViewMode::TreeOnly.next(), ViewMode::TreemapOnly);
        assert_eq!(ViewMode::TreemapOnly.next(), ViewMode::Split);
    }

    #[test]
    fn test_drill_commands() {
        let mode = InputMode::Normal;
        assert_eq!(handle_key(key_event(KeyCode::Char('z')), &mode), Command::DrillDown);
        assert_eq!(handle_key(key_event(KeyCode::Char('Z')), &mode), Command::DrillUp);
    }

    #[test]
    fn test_page_navigation() {
        let mode = InputMode::Normal;
        assert_eq!(handle_key(key_event(KeyCode::PageUp), &mode), Command::PageUp);
        assert_eq!(handle_key(key_event(KeyCode::PageDown), &mode), Command::PageDown);
    }
}
