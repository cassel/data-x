//! Color scheme system for Data-X TUI disk analyzer.
//!
//! Provides vibrant, accessible color themes inspired by Disk Inventory X,
//! with support for dark, light, and colorblind-friendly palettes.

use ratatui::style::Color;

/// Size thresholds for file categorization
const SIZE_SMALL: u64 = 1_048_576; // 1 MB
const SIZE_MEDIUM: u64 = 104_857_600; // 100 MB
const SIZE_LARGE: u64 = 1_073_741_824; // 1 GB

/// Color scheme for the Data-X TUI application.
#[derive(Debug, Clone)]
pub struct ColorScheme {
    // File type colors
    /// Color for directories
    pub dirs: Color,
    /// Color for small files (< 1MB)
    pub small_files: Color,
    /// Color for medium files (1MB - 100MB)
    pub medium_files: Color,
    /// Color for large files (100MB - 1GB)
    pub large_files: Color,
    /// Color for huge files (>= 1GB)
    pub huge_files: Color,

    // Special file type colors
    /// Color for media files (audio, video, images)
    pub media: Color,
    /// Color for compressed/archive files
    pub compressed: Color,
    /// Color for hidden files (dotfiles)
    pub hidden: Color,
    /// Color for symbolic links
    pub symlink: Color,
    /// Color for broken symbolic links
    #[allow(dead_code)]
    pub broken_symlink: Color,

    // File category colors (for stats panel)
    /// Color for audio files
    pub audio: Color,
    /// Color for video files
    pub video: Color,
    /// Color for image files
    pub images: Color,
    /// Color for document files
    pub documents: Color,
    /// Color for code/source files
    pub code: Color,
    /// Color for archive files
    pub archives: Color,

    // UI element colors
    /// Color for selected/highlighted items
    pub selected: Color,
    /// Gradient colors for size visualization bars
    pub bar_gradient: Vec<Color>,

    // Text colors
    /// Primary text color
    pub text: Color,
    /// Dimmed/secondary text color
    pub text_dim: Color,
    /// Border color for panels/frames
    pub border: Color,

    // Header colors
    /// Header foreground color
    pub header_fg: Color,
    /// Header background color
    pub header_bg: Color,
    /// Accent color for highlights
    pub accent: Color,
    /// Path display color
    pub path_fg: Color,
    /// Hint text color
    pub hint_fg: Color,

    // Status bar colors
    /// Status bar foreground color
    pub status_fg: Color,
    /// Status bar background color
    pub status_bg: Color,
    /// Size display color
    pub size_fg: Color,
    /// Scanning indicator color
    pub scanning_fg: Color,
    /// Key shortcut color
    pub key_fg: Color,
    /// Search input color
    pub search_fg: Color,
    /// Error message color
    pub error_fg: Color,
    /// Warning message color
    pub warning_fg: Color,
}

impl Default for ColorScheme {
    /// Creates the default vibrant dark theme inspired by Disk Inventory X.
    fn default() -> Self {
        Self::dark()
    }
}

impl ColorScheme {
    /// Creates a vibrant dark theme inspired by Disk Inventory X.
    ///
    /// Features high-contrast colors optimized for dark terminal backgrounds
    /// with a colorful, engaging aesthetic.
    pub fn dark() -> Self {
        Self {
            // File type colors - vibrant and distinct
            dirs: Color::Rgb(100, 149, 237), // Cornflower blue
            small_files: Color::Rgb(144, 238, 144), // Light green
            medium_files: Color::Rgb(255, 215, 0), // Gold
            large_files: Color::Rgb(255, 140, 0), // Dark orange
            huge_files: Color::Rgb(255, 69, 0), // Red-orange

            // Special file types
            media: Color::Rgb(218, 112, 214), // Orchid (purple/magenta)
            compressed: Color::Rgb(0, 206, 209), // Dark turquoise (cyan)
            hidden: Color::Rgb(169, 169, 169), // Dark gray
            symlink: Color::Rgb(135, 206, 250), // Light sky blue
            broken_symlink: Color::Rgb(255, 99, 71), // Tomato red

            // File category colors (for stats panel)
            audio: Color::Rgb(65, 105, 225),     // Royal blue
            video: Color::Rgb(138, 43, 226),     // Blue violet
            images: Color::Rgb(50, 205, 50),     // Lime green
            documents: Color::Rgb(255, 165, 0),  // Orange
            code: Color::Rgb(0, 206, 209),       // Dark turquoise
            archives: Color::Rgb(220, 20, 60),   // Crimson

            // UI elements
            selected: Color::Rgb(255, 215, 0), // Gold highlight
            bar_gradient: vec![
                Color::Rgb(46, 204, 113),  // Emerald green
                Color::Rgb(155, 225, 93),  // Yellow-green
                Color::Rgb(241, 196, 15),  // Sunflower yellow
                Color::Rgb(243, 156, 18),  // Orange
                Color::Rgb(231, 76, 60),   // Alizarin red
            ],

            // Text
            text: Color::Rgb(248, 248, 242), // Off-white
            text_dim: Color::Rgb(136, 136, 136), // Medium gray
            border: Color::Rgb(98, 114, 164), // Muted purple-blue

            // Header colors
            header_fg: Color::Rgb(248, 248, 242), // Off-white
            header_bg: Color::Rgb(40, 42, 54), // Dark background
            accent: Color::Rgb(189, 147, 249), // Purple accent
            path_fg: Color::Rgb(139, 233, 253), // Cyan for paths
            hint_fg: Color::Rgb(98, 114, 164), // Muted for hints

            // Status bar colors
            status_fg: Color::Rgb(248, 248, 242), // Off-white
            status_bg: Color::Rgb(68, 71, 90), // Slightly lighter dark
            size_fg: Color::Rgb(80, 250, 123), // Green for sizes
            scanning_fg: Color::Rgb(241, 250, 140), // Yellow for scanning
            key_fg: Color::Rgb(255, 184, 108), // Orange for keys
            search_fg: Color::Rgb(139, 233, 253), // Cyan for search
            error_fg: Color::Rgb(255, 85, 85), // Red for errors
            warning_fg: Color::Rgb(255, 184, 108), // Orange for warnings
        }
    }

    /// Creates a light theme suitable for light terminal backgrounds.
    ///
    /// Uses darker, more saturated colors that remain visible and
    /// aesthetically pleasing on white/light backgrounds.
    pub fn light() -> Self {
        Self {
            // File type colors - darker variants for light backgrounds
            dirs: Color::Rgb(30, 80, 180), // Deep blue
            small_files: Color::Rgb(34, 139, 34), // Forest green
            medium_files: Color::Rgb(184, 134, 11), // Dark goldenrod
            large_files: Color::Rgb(210, 105, 30), // Chocolate
            huge_files: Color::Rgb(178, 34, 34), // Firebrick

            // Special file types
            media: Color::Rgb(148, 0, 211), // Dark violet
            compressed: Color::Rgb(0, 139, 139), // Dark cyan
            hidden: Color::Rgb(105, 105, 105), // Dim gray
            symlink: Color::Rgb(70, 130, 180), // Steel blue
            broken_symlink: Color::Rgb(220, 20, 60), // Crimson

            // File category colors (for stats panel)
            audio: Color::Rgb(30, 80, 180),      // Deep blue
            video: Color::Rgb(100, 30, 180),     // Dark purple
            images: Color::Rgb(0, 140, 0),       // Dark green
            documents: Color::Rgb(200, 120, 0),  // Dark orange
            code: Color::Rgb(0, 130, 130),       // Dark cyan
            archives: Color::Rgb(180, 0, 40),    // Dark red

            // UI elements
            selected: Color::Rgb(0, 100, 200), // Strong blue
            bar_gradient: vec![
                Color::Rgb(22, 160, 90),   // Dark emerald
                Color::Rgb(120, 180, 70),  // Olive green
                Color::Rgb(200, 160, 0),   // Dark gold
                Color::Rgb(200, 120, 0),   // Dark orange
                Color::Rgb(180, 50, 50),   // Dark red
            ],

            // Text
            text: Color::Rgb(30, 30, 30), // Near black
            text_dim: Color::Rgb(100, 100, 100), // Dark gray
            border: Color::Rgb(80, 80, 120), // Muted blue-gray

            // Header colors
            header_fg: Color::Rgb(30, 30, 30), // Near black
            header_bg: Color::Rgb(230, 230, 235), // Light gray background
            accent: Color::Rgb(100, 60, 180), // Deep purple accent
            path_fg: Color::Rgb(0, 100, 150), // Dark cyan for paths
            hint_fg: Color::Rgb(120, 120, 140), // Muted for hints

            // Status bar colors
            status_fg: Color::Rgb(30, 30, 30), // Near black
            status_bg: Color::Rgb(210, 210, 220), // Slightly darker light
            size_fg: Color::Rgb(22, 130, 80), // Dark green for sizes
            scanning_fg: Color::Rgb(180, 140, 0), // Dark yellow for scanning
            key_fg: Color::Rgb(180, 100, 50), // Brown for keys
            search_fg: Color::Rgb(0, 100, 150), // Dark cyan for search
            error_fg: Color::Rgb(180, 30, 30), // Dark red for errors
            warning_fg: Color::Rgb(180, 100, 50), // Brown for warnings
        }
    }

    /// Creates a colorblind-friendly palette.
    ///
    /// Uses colors that are distinguishable for users with common forms
    /// of color vision deficiency (protanopia, deuteranopia, tritanopia).
    /// The palette relies on luminance contrast and blue-orange opposition
    /// which remains visible across most color vision types.
    pub fn colorblind() -> Self {
        Self {
            // File type colors - optimized for color vision deficiency
            // Uses blue-orange axis which is preserved in most types of CVD
            dirs: Color::Rgb(86, 180, 233), // Sky blue (CVD-safe)
            small_files: Color::Rgb(0, 158, 115), // Bluish green (CVD-safe)
            medium_files: Color::Rgb(240, 228, 66), // Yellow (high luminance)
            large_files: Color::Rgb(230, 159, 0), // Orange (CVD-safe)
            huge_files: Color::Rgb(213, 94, 0), // Vermillion (CVD-safe)

            // Special file types - distinct luminance and saturation
            media: Color::Rgb(204, 121, 167), // Reddish purple
            compressed: Color::Rgb(0, 114, 178), // Blue
            hidden: Color::Rgb(153, 153, 153), // Medium gray
            symlink: Color::Rgb(170, 170, 255), // Light periwinkle
            broken_symlink: Color::Rgb(200, 60, 60), // Distinct red

            // File category colors (for stats panel) - CVD-safe
            audio: Color::Rgb(0, 114, 178),      // CVD-safe blue
            video: Color::Rgb(204, 121, 167),    // CVD-safe reddish purple
            images: Color::Rgb(0, 158, 115),     // CVD-safe bluish green
            documents: Color::Rgb(230, 159, 0),  // CVD-safe orange
            code: Color::Rgb(240, 228, 66),      // CVD-safe yellow
            archives: Color::Rgb(213, 94, 0),    // CVD-safe vermillion

            // UI elements
            selected: Color::Rgb(255, 255, 255), // White for maximum contrast
            bar_gradient: vec![
                Color::Rgb(0, 114, 178),   // Blue
                Color::Rgb(0, 158, 115),   // Bluish green
                Color::Rgb(240, 228, 66),  // Yellow
                Color::Rgb(230, 159, 0),   // Orange
                Color::Rgb(213, 94, 0),    // Vermillion
            ],

            // Text
            text: Color::Rgb(255, 255, 255), // White
            text_dim: Color::Rgb(170, 170, 170), // Light gray
            border: Color::Rgb(136, 136, 136), // Medium gray

            // Header colors - CVD-safe with high contrast
            header_fg: Color::Rgb(255, 255, 255), // White
            header_bg: Color::Rgb(40, 40, 50), // Dark background
            accent: Color::Rgb(86, 180, 233), // CVD-safe blue
            path_fg: Color::Rgb(240, 228, 66), // CVD-safe yellow
            hint_fg: Color::Rgb(153, 153, 153), // Neutral gray

            // Status bar colors - CVD-safe
            status_fg: Color::Rgb(255, 255, 255), // White
            status_bg: Color::Rgb(60, 60, 70), // Slightly lighter dark
            size_fg: Color::Rgb(0, 158, 115), // CVD-safe bluish green
            scanning_fg: Color::Rgb(240, 228, 66), // CVD-safe yellow
            key_fg: Color::Rgb(230, 159, 0), // CVD-safe orange
            search_fg: Color::Rgb(86, 180, 233), // CVD-safe blue
            error_fg: Color::Rgb(213, 94, 0), // CVD-safe vermillion
            warning_fg: Color::Rgb(230, 159, 0), // CVD-safe orange
        }
    }

    /// Maps a file size to a gradient color based on its proportion of the maximum.
    ///
    /// The gradient transitions from green (small) through yellow and orange
    /// to red (huge), providing intuitive visual feedback about relative file sizes.
    ///
    /// # Arguments
    /// * `size` - The file size in bytes
    /// * `max_size` - The maximum file size for normalization (used for gradient position)
    ///
    /// # Returns
    /// A `Color` representing the file's size category
    pub fn size_to_color(&self, size: u64, max_size: u64) -> Color {
        // Return categorical colors for absolute size thresholds
        if size < SIZE_SMALL {
            return self.small_files;
        } else if size < SIZE_MEDIUM {
            return self.medium_files;
        } else if size < SIZE_LARGE {
            return self.large_files;
        } else if size >= SIZE_LARGE {
            return self.huge_files;
        }

        // For gradient-based coloring (when using bar visualization)
        if max_size == 0 || self.bar_gradient.is_empty() {
            return self.small_files;
        }

        // Calculate position in gradient (0.0 to 1.0)
        let ratio = (size as f64) / (max_size as f64);
        let ratio = ratio.clamp(0.0, 1.0);

        // Map to gradient index
        let max_index = self.bar_gradient.len() - 1;
        let position = ratio * max_index as f64;
        let index = (position as usize).min(max_index);

        // Interpolate between adjacent gradient colors
        if index >= max_index {
            return self.bar_gradient[max_index];
        }

        let frac = position - index as f64;
        Self::interpolate_colors(self.bar_gradient[index], self.bar_gradient[index + 1], frac)
    }

    /// Maps a file extension to an appropriate color based on file type.
    ///
    /// # Arguments
    /// * `ext` - The file extension (without the leading dot)
    ///
    /// # Returns
    /// A `Color` appropriate for the file type:
    /// - Media files (audio, video, images): purple/magenta
    /// - Compressed archives: cyan
    /// - Source code: green
    /// - Documents: blue
    /// - Other: white/gray
    pub fn extension_to_color(&self, ext: &str) -> Color {
        let ext_lower = ext.to_lowercase();
        match ext_lower.as_str() {
            // Media files - audio, video, images
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
            | "sql" | "graphql" | "proto" => Color::Rgb(152, 195, 121), // Soft green

            // Document files
            "pdf" | "doc" | "docx" | "txt" | "md" | "markdown" | "rtf" | "odt" | "xls"
            | "xlsx" | "ppt" | "pptx" | "csv" | "json" | "xml" | "yaml" | "yml" | "toml"
            | "ini" | "cfg" | "conf" | "html" | "htm" | "css" | "scss" | "sass" | "less" => {
                Color::Rgb(97, 175, 239) // Soft blue
            }

            // Default for unknown extensions
            _ => self.text_dim,
        }
    }

    /// Interpolates between two RGB colors.
    ///
    /// # Arguments
    /// * `c1` - The starting color
    /// * `c2` - The ending color
    /// * `t` - Interpolation factor (0.0 = c1, 1.0 = c2)
    fn interpolate_colors(c1: Color, c2: Color, t: f64) -> Color {
        match (c1, c2) {
            (Color::Rgb(r1, g1, b1), Color::Rgb(r2, g2, b2)) => {
                let r = Self::lerp(r1, r2, t);
                let g = Self::lerp(g1, g2, t);
                let b = Self::lerp(b1, b2, t);
                Color::Rgb(r, g, b)
            }
            // Fallback for non-RGB colors
            _ => c1,
        }
    }

    /// Linear interpolation between two u8 values.
    fn lerp(a: u8, b: u8, t: f64) -> u8 {
        let result = a as f64 + (b as f64 - a as f64) * t;
        result.round().clamp(0.0, 255.0) as u8
    }

    /// Returns the color for a directory.
    #[allow(dead_code)]
    pub fn dir_color(&self) -> Color {
        self.dirs
    }

    /// Returns the color for hidden files.
    #[allow(dead_code)]
    pub fn hidden_color(&self) -> Color {
        self.hidden
    }

    /// Returns the color for symbolic links.
    #[allow(dead_code)]
    pub fn symlink_color(&self) -> Color {
        self.symlink
    }

    /// Returns the color for broken symbolic links.
    #[allow(dead_code)]
    pub fn broken_symlink_color(&self) -> Color {
        self.broken_symlink
    }

    /// Returns the selection/highlight color.
    #[allow(dead_code)]
    pub fn selection_color(&self) -> Color {
        self.selected
    }
}

/// File type categories for extension-based coloring.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[allow(dead_code)]
pub enum FileType {
    /// Audio files (mp3, wav, flac, m4a, ogg, aac)
    Audio,
    /// Video files (mp4, mkv, avi, mov, wmv, webm)
    Video,
    /// Image files (jpg, jpeg, png, gif, webp, svg, bmp, ico)
    Image,
    /// Document files (pdf, doc, docx, txt, md, rtf, odt)
    Document,
    /// Code/source files (rs, py, js, ts, go, java, c, cpp, h, rb, php)
    Code,
    /// Archive files (zip, tar, gz, rar, 7z, bz2)
    Archive,
    /// Directory
    Directory,
    /// Unknown/other file types
    Other,
}

impl FileType {
    /// Determine file type from extension.
    pub fn from_extension(ext: Option<&str>) -> Self {
        let ext = match ext {
            Some(e) => e.to_lowercase(),
            None => return FileType::Other,
        };

        match ext.as_str() {
            // Audio files - Blue shades
            "mp3" | "wav" | "flac" | "m4a" | "ogg" | "aac" | "wma" | "aiff" | "alac" | "opus" => {
                FileType::Audio
            }

            // Video files - Purple shades
            "mp4" | "mkv" | "avi" | "mov" | "wmv" | "webm" | "flv" | "m4v" | "mpeg" | "mpg"
            | "3gp" | "vob" => FileType::Video,

            // Image files - Green shades
            "jpg" | "jpeg" | "png" | "gif" | "webp" | "svg" | "bmp" | "ico" | "tiff" | "tif"
            | "psd" | "raw" | "heic" | "heif" | "avif" => FileType::Image,

            // Document files - Orange/Yellow shades
            "pdf" | "doc" | "docx" | "txt" | "md" | "rtf" | "odt" | "xls" | "xlsx" | "ppt"
            | "pptx" | "csv" | "pages" | "numbers" | "key" | "epub" | "mobi" => FileType::Document,

            // Code/source files - Cyan shades
            "rs" | "py" | "js" | "ts" | "go" | "java" | "c" | "cpp" | "h" | "rb" | "php" | "cs"
            | "swift" | "kt" | "scala" | "clj" | "ex" | "exs" | "erl" | "hs" | "ml" | "lua"
            | "r" | "jl" | "nim" | "zig" | "v" | "vue" | "svelte" | "jsx" | "tsx" | "sh"
            | "bash" | "zsh" | "fish" | "ps1" | "sql" | "graphql" | "proto" | "hpp" | "cc"
            | "cxx" | "hxx" | "fs" | "fsx" | "html" | "htm" | "css" | "scss" | "sass" | "less"
            | "json" | "xml" | "yaml" | "yml" | "toml" | "ini" | "cfg" | "conf" => FileType::Code,

            // Archive files - Red shades
            "zip" | "tar" | "gz" | "rar" | "7z" | "bz2" | "xz" | "zst" | "lz4" | "lzma" | "cab"
            | "iso" | "dmg" | "pkg" | "deb" | "rpm" | "tgz" | "tbz2" | "txz" => FileType::Archive,

            // Other/unknown
            _ => FileType::Other,
        }
    }
}

/// Color palette for file type coloring in treemap.
/// Provides distinct color shades for each file type category.
#[derive(Debug, Clone)]
#[allow(dead_code)]
pub struct FileTypeColors {
    // Audio - Blue shades
    pub audio_base: Color,
    pub audio_light: Color,
    pub audio_dark: Color,

    // Video - Purple shades
    pub video_base: Color,
    pub video_light: Color,
    pub video_dark: Color,

    // Image - Green shades
    pub image_base: Color,
    pub image_light: Color,
    pub image_dark: Color,

    // Document - Orange/Yellow shades
    pub document_base: Color,
    pub document_light: Color,
    pub document_dark: Color,

    // Code - Cyan shades
    pub code_base: Color,
    pub code_light: Color,
    pub code_dark: Color,

    // Archive - Red shades
    pub archive_base: Color,
    pub archive_light: Color,
    pub archive_dark: Color,

    // Directory - Blue (cornflower)
    pub directory_base: Color,
    pub directory_light: Color,
    pub directory_dark: Color,

    // Other/Unknown - Gray shades
    pub other_base: Color,
    pub other_light: Color,
    pub other_dark: Color,
}

impl Default for FileTypeColors {
    fn default() -> Self {
        Self::dark()
    }
}

impl FileTypeColors {
    /// Create dark theme file type colors.
    pub fn dark() -> Self {
        Self {
            // Audio - Blue shades (rich blues)
            audio_base: Color::Rgb(65, 105, 225),    // Royal blue
            audio_light: Color::Rgb(100, 149, 237),  // Cornflower blue
            audio_dark: Color::Rgb(30, 60, 180),     // Darker blue

            // Video - Purple shades
            video_base: Color::Rgb(138, 43, 226),    // Blue violet
            video_light: Color::Rgb(186, 85, 211),   // Medium orchid
            video_dark: Color::Rgb(75, 0, 130),      // Indigo

            // Image - Green shades
            image_base: Color::Rgb(34, 139, 34),     // Forest green
            image_light: Color::Rgb(50, 205, 50),    // Lime green
            image_dark: Color::Rgb(0, 100, 0),       // Dark green

            // Document - Orange/Yellow shades
            document_base: Color::Rgb(255, 165, 0),  // Orange
            document_light: Color::Rgb(255, 200, 50), // Light orange/yellow
            document_dark: Color::Rgb(210, 105, 30), // Chocolate

            // Code - Cyan shades
            code_base: Color::Rgb(0, 206, 209),      // Dark turquoise
            code_light: Color::Rgb(0, 255, 255),     // Cyan
            code_dark: Color::Rgb(0, 139, 139),      // Dark cyan

            // Archive - Red shades
            archive_base: Color::Rgb(220, 20, 60),   // Crimson
            archive_light: Color::Rgb(255, 99, 71),  // Tomato
            archive_dark: Color::Rgb(139, 0, 0),     // Dark red

            // Directory - Cornflower blue (keep existing)
            directory_base: Color::Rgb(100, 149, 237), // Cornflower blue
            directory_light: Color::Rgb(135, 206, 250), // Light sky blue
            directory_dark: Color::Rgb(70, 130, 180),  // Steel blue

            // Other/Unknown - Gray shades
            other_base: Color::Rgb(128, 128, 128),   // Gray
            other_light: Color::Rgb(169, 169, 169),  // Dark gray (lighter)
            other_dark: Color::Rgb(80, 80, 80),      // Dim gray
        }
    }

    /// Create light theme file type colors.
    #[allow(dead_code)]
    pub fn light() -> Self {
        Self {
            // Audio - Blue shades (darker for light bg)
            audio_base: Color::Rgb(30, 80, 180),
            audio_light: Color::Rgb(65, 105, 225),
            audio_dark: Color::Rgb(0, 50, 140),

            // Video - Purple shades
            video_base: Color::Rgb(100, 30, 180),
            video_light: Color::Rgb(138, 43, 226),
            video_dark: Color::Rgb(60, 0, 100),

            // Image - Green shades
            image_base: Color::Rgb(0, 100, 0),
            image_light: Color::Rgb(34, 139, 34),
            image_dark: Color::Rgb(0, 60, 0),

            // Document - Orange/Yellow shades
            document_base: Color::Rgb(200, 120, 0),
            document_light: Color::Rgb(255, 165, 0),
            document_dark: Color::Rgb(160, 80, 0),

            // Code - Cyan shades
            code_base: Color::Rgb(0, 130, 130),
            code_light: Color::Rgb(0, 180, 180),
            code_dark: Color::Rgb(0, 90, 90),

            // Archive - Red shades
            archive_base: Color::Rgb(180, 0, 40),
            archive_light: Color::Rgb(220, 20, 60),
            archive_dark: Color::Rgb(120, 0, 20),

            // Directory - Blue
            directory_base: Color::Rgb(30, 80, 180),
            directory_light: Color::Rgb(70, 130, 180),
            directory_dark: Color::Rgb(0, 50, 140),

            // Other - Gray
            other_base: Color::Rgb(100, 100, 100),
            other_light: Color::Rgb(128, 128, 128),
            other_dark: Color::Rgb(60, 60, 60),
        }
    }

    /// Create colorblind-friendly file type colors.
    /// Uses the CVD-safe palette with distinct luminance values.
    #[allow(dead_code)]
    pub fn colorblind() -> Self {
        Self {
            // Audio - CVD-safe blue
            audio_base: Color::Rgb(0, 114, 178),
            audio_light: Color::Rgb(86, 180, 233),
            audio_dark: Color::Rgb(0, 70, 130),

            // Video - CVD-safe reddish purple
            video_base: Color::Rgb(204, 121, 167),
            video_light: Color::Rgb(230, 160, 200),
            video_dark: Color::Rgb(160, 80, 130),

            // Image - CVD-safe bluish green
            image_base: Color::Rgb(0, 158, 115),
            image_light: Color::Rgb(0, 200, 150),
            image_dark: Color::Rgb(0, 110, 80),

            // Document - CVD-safe orange
            document_base: Color::Rgb(230, 159, 0),
            document_light: Color::Rgb(255, 200, 50),
            document_dark: Color::Rgb(180, 120, 0),

            // Code - CVD-safe yellow (high luminance)
            code_base: Color::Rgb(200, 190, 50),
            code_light: Color::Rgb(240, 228, 66),
            code_dark: Color::Rgb(150, 140, 30),

            // Archive - CVD-safe vermillion
            archive_base: Color::Rgb(213, 94, 0),
            archive_light: Color::Rgb(250, 130, 40),
            archive_dark: Color::Rgb(160, 60, 0),

            // Directory - CVD-safe sky blue
            directory_base: Color::Rgb(86, 180, 233),
            directory_light: Color::Rgb(130, 210, 255),
            directory_dark: Color::Rgb(40, 140, 190),

            // Other - Neutral gray
            other_base: Color::Rgb(153, 153, 153),
            other_light: Color::Rgb(190, 190, 190),
            other_dark: Color::Rgb(100, 100, 100),
        }
    }

    /// Get the base color for a file type.
    pub fn get_color(&self, file_type: FileType) -> Color {
        match file_type {
            FileType::Audio => self.audio_base,
            FileType::Video => self.video_base,
            FileType::Image => self.image_base,
            FileType::Document => self.document_base,
            FileType::Code => self.code_base,
            FileType::Archive => self.archive_base,
            FileType::Directory => self.directory_base,
            FileType::Other => self.other_base,
        }
    }

    /// Get a lighter shade color for a file type (for selection/hover).
    pub fn get_light_color(&self, file_type: FileType) -> Color {
        match file_type {
            FileType::Audio => self.audio_light,
            FileType::Video => self.video_light,
            FileType::Image => self.image_light,
            FileType::Document => self.document_light,
            FileType::Code => self.code_light,
            FileType::Archive => self.archive_light,
            FileType::Directory => self.directory_light,
            FileType::Other => self.other_light,
        }
    }

    /// Get a darker shade color for a file type.
    #[allow(dead_code)]
    pub fn get_dark_color(&self, file_type: FileType) -> Color {
        match file_type {
            FileType::Audio => self.audio_dark,
            FileType::Video => self.video_dark,
            FileType::Image => self.image_dark,
            FileType::Document => self.document_dark,
            FileType::Code => self.code_dark,
            FileType::Archive => self.archive_dark,
            FileType::Directory => self.directory_dark,
            FileType::Other => self.other_dark,
        }
    }
}

/// Get the color for a file based on its extension and whether it's a directory.
///
/// This is the main function for extension-based treemap coloring.
///
/// # Arguments
/// * `extension` - The file extension (without leading dot), or None
/// * `is_dir` - Whether this is a directory
///
/// # Returns
/// A `Color` appropriate for the file type:
/// - Audio (mp3, wav, flac, m4a, ogg, aac) -> Blue shades
/// - Video (mp4, mkv, avi, mov, wmv, webm) -> Purple shades
/// - Images (jpg, jpeg, png, gif, webp, svg, bmp, ico) -> Green shades
/// - Documents (pdf, doc, docx, txt, md, rtf, odt) -> Orange/Yellow shades
/// - Code (rs, py, js, ts, go, java, c, cpp, h, rb, php) -> Cyan shades
/// - Archives (zip, tar, gz, rar, 7z, bz2) -> Red shades
/// - Directories -> Cornflower blue
/// - Other -> Gray shades
pub fn get_file_type_color(extension: Option<&str>, is_dir: bool) -> Color {
    let colors = FileTypeColors::dark();
    get_file_type_color_with_palette(extension, is_dir, &colors)
}

/// Get the color for a file using a specific color palette.
///
/// # Arguments
/// * `extension` - The file extension (without leading dot), or None
/// * `is_dir` - Whether this is a directory
/// * `colors` - The file type color palette to use
///
/// # Returns
/// The appropriate color for the file type.
#[allow(dead_code)]
pub fn get_file_type_color_with_palette(
    extension: Option<&str>,
    is_dir: bool,
    colors: &FileTypeColors,
) -> Color {
    if is_dir {
        return colors.directory_base;
    }

    let file_type = FileType::from_extension(extension);
    colors.get_color(file_type)
}

/// Get the selection highlight color for a file type.
/// Returns a brighter/lighter version of the file type color.
///
/// # Arguments
/// * `extension` - The file extension (without leading dot), or None
/// * `is_dir` - Whether this is a directory
///
/// # Returns
/// A lighter/brighter color for the selected state.
pub fn get_file_type_selection_color(extension: Option<&str>, is_dir: bool) -> Color {
    let colors = FileTypeColors::dark();

    if is_dir {
        return colors.directory_light;
    }

    let file_type = FileType::from_extension(extension);
    colors.get_light_color(file_type)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_scheme() {
        let scheme = ColorScheme::default();
        // Verify it's the same as dark theme
        assert!(matches!(scheme.dirs, Color::Rgb(100, 149, 237)));
    }

    #[test]
    fn test_size_to_color_thresholds() {
        let scheme = ColorScheme::dark();

        // Small file (< 1MB)
        assert_eq!(scheme.size_to_color(500_000, 1_000_000_000), scheme.small_files);

        // Medium file (1MB - 100MB)
        assert_eq!(scheme.size_to_color(50_000_000, 1_000_000_000), scheme.medium_files);

        // Large file (100MB - 1GB)
        assert_eq!(scheme.size_to_color(500_000_000, 1_000_000_000), scheme.large_files);

        // Huge file (>= 1GB)
        assert_eq!(scheme.size_to_color(2_000_000_000, 2_000_000_000), scheme.huge_files);
    }

    #[test]
    fn test_extension_to_color_media() {
        let scheme = ColorScheme::dark();

        // Test various media extensions
        assert_eq!(scheme.extension_to_color("mp3"), scheme.media);
        assert_eq!(scheme.extension_to_color("MP4"), scheme.media);
        assert_eq!(scheme.extension_to_color("jpg"), scheme.media);
        assert_eq!(scheme.extension_to_color("PNG"), scheme.media);
    }

    #[test]
    fn test_extension_to_color_compressed() {
        let scheme = ColorScheme::dark();

        assert_eq!(scheme.extension_to_color("zip"), scheme.compressed);
        assert_eq!(scheme.extension_to_color("TAR"), scheme.compressed);
        assert_eq!(scheme.extension_to_color("gz"), scheme.compressed);
    }

    #[test]
    fn test_extension_to_color_code() {
        let scheme = ColorScheme::dark();
        let code_color = Color::Rgb(152, 195, 121);

        assert_eq!(scheme.extension_to_color("rs"), code_color);
        assert_eq!(scheme.extension_to_color("py"), code_color);
        assert_eq!(scheme.extension_to_color("JS"), code_color);
    }

    #[test]
    fn test_extension_to_color_documents() {
        let scheme = ColorScheme::dark();
        let doc_color = Color::Rgb(97, 175, 239);

        assert_eq!(scheme.extension_to_color("pdf"), doc_color);
        assert_eq!(scheme.extension_to_color("txt"), doc_color);
        assert_eq!(scheme.extension_to_color("MD"), doc_color);
    }

    #[test]
    fn test_extension_to_color_unknown() {
        let scheme = ColorScheme::dark();

        // Unknown extensions should return text_dim color
        assert_eq!(scheme.extension_to_color("xyz"), scheme.text_dim);
        assert_eq!(scheme.extension_to_color("unknown"), scheme.text_dim);
    }

    #[test]
    fn test_colorblind_scheme() {
        let scheme = ColorScheme::colorblind();

        // Verify colorblind scheme uses CVD-safe colors
        // Blue should be in the safe range
        assert!(matches!(scheme.dirs, Color::Rgb(86, 180, 233)));
    }

    #[test]
    fn test_light_scheme() {
        let scheme = ColorScheme::light();

        // Light scheme should have dark text
        assert!(matches!(scheme.text, Color::Rgb(30, 30, 30)));
    }

    #[test]
    fn test_interpolate_colors() {
        // Test midpoint interpolation
        let c1 = Color::Rgb(0, 0, 0);
        let c2 = Color::Rgb(100, 100, 100);
        let mid = ColorScheme::interpolate_colors(c1, c2, 0.5);

        assert!(matches!(mid, Color::Rgb(50, 50, 50)));
    }

    #[test]
    fn test_bar_gradient_length() {
        let dark = ColorScheme::dark();
        let light = ColorScheme::light();
        let colorblind = ColorScheme::colorblind();

        assert_eq!(dark.bar_gradient.len(), 5);
        assert_eq!(light.bar_gradient.len(), 5);
        assert_eq!(colorblind.bar_gradient.len(), 5);
    }

    // Tests for file type coloring
    #[test]
    fn test_file_type_from_extension_audio() {
        assert_eq!(FileType::from_extension(Some("mp3")), FileType::Audio);
        assert_eq!(FileType::from_extension(Some("MP3")), FileType::Audio);
        assert_eq!(FileType::from_extension(Some("wav")), FileType::Audio);
        assert_eq!(FileType::from_extension(Some("flac")), FileType::Audio);
        assert_eq!(FileType::from_extension(Some("m4a")), FileType::Audio);
        assert_eq!(FileType::from_extension(Some("ogg")), FileType::Audio);
        assert_eq!(FileType::from_extension(Some("aac")), FileType::Audio);
    }

    #[test]
    fn test_file_type_from_extension_video() {
        assert_eq!(FileType::from_extension(Some("mp4")), FileType::Video);
        assert_eq!(FileType::from_extension(Some("mkv")), FileType::Video);
        assert_eq!(FileType::from_extension(Some("avi")), FileType::Video);
        assert_eq!(FileType::from_extension(Some("mov")), FileType::Video);
        assert_eq!(FileType::from_extension(Some("wmv")), FileType::Video);
        assert_eq!(FileType::from_extension(Some("webm")), FileType::Video);
    }

    #[test]
    fn test_file_type_from_extension_image() {
        assert_eq!(FileType::from_extension(Some("jpg")), FileType::Image);
        assert_eq!(FileType::from_extension(Some("jpeg")), FileType::Image);
        assert_eq!(FileType::from_extension(Some("png")), FileType::Image);
        assert_eq!(FileType::from_extension(Some("gif")), FileType::Image);
        assert_eq!(FileType::from_extension(Some("webp")), FileType::Image);
        assert_eq!(FileType::from_extension(Some("svg")), FileType::Image);
        assert_eq!(FileType::from_extension(Some("bmp")), FileType::Image);
        assert_eq!(FileType::from_extension(Some("ico")), FileType::Image);
    }

    #[test]
    fn test_file_type_from_extension_document() {
        assert_eq!(FileType::from_extension(Some("pdf")), FileType::Document);
        assert_eq!(FileType::from_extension(Some("doc")), FileType::Document);
        assert_eq!(FileType::from_extension(Some("docx")), FileType::Document);
        assert_eq!(FileType::from_extension(Some("txt")), FileType::Document);
        assert_eq!(FileType::from_extension(Some("md")), FileType::Document);
        assert_eq!(FileType::from_extension(Some("rtf")), FileType::Document);
        assert_eq!(FileType::from_extension(Some("odt")), FileType::Document);
    }

    #[test]
    fn test_file_type_from_extension_code() {
        assert_eq!(FileType::from_extension(Some("rs")), FileType::Code);
        assert_eq!(FileType::from_extension(Some("py")), FileType::Code);
        assert_eq!(FileType::from_extension(Some("js")), FileType::Code);
        assert_eq!(FileType::from_extension(Some("ts")), FileType::Code);
        assert_eq!(FileType::from_extension(Some("go")), FileType::Code);
        assert_eq!(FileType::from_extension(Some("java")), FileType::Code);
        assert_eq!(FileType::from_extension(Some("c")), FileType::Code);
        assert_eq!(FileType::from_extension(Some("cpp")), FileType::Code);
        assert_eq!(FileType::from_extension(Some("h")), FileType::Code);
        assert_eq!(FileType::from_extension(Some("rb")), FileType::Code);
        assert_eq!(FileType::from_extension(Some("php")), FileType::Code);
    }

    #[test]
    fn test_file_type_from_extension_archive() {
        assert_eq!(FileType::from_extension(Some("zip")), FileType::Archive);
        assert_eq!(FileType::from_extension(Some("tar")), FileType::Archive);
        assert_eq!(FileType::from_extension(Some("gz")), FileType::Archive);
        assert_eq!(FileType::from_extension(Some("rar")), FileType::Archive);
        assert_eq!(FileType::from_extension(Some("7z")), FileType::Archive);
        assert_eq!(FileType::from_extension(Some("bz2")), FileType::Archive);
    }

    #[test]
    fn test_file_type_from_extension_other() {
        assert_eq!(FileType::from_extension(Some("xyz")), FileType::Other);
        assert_eq!(FileType::from_extension(Some("unknown")), FileType::Other);
        assert_eq!(FileType::from_extension(None), FileType::Other);
    }

    #[test]
    fn test_get_file_type_color_directory() {
        let colors = FileTypeColors::dark();
        let color = get_file_type_color(Some("rs"), true);
        assert_eq!(color, colors.directory_base);
    }

    #[test]
    fn test_get_file_type_color_audio_blue() {
        let colors = FileTypeColors::dark();
        let color = get_file_type_color(Some("mp3"), false);
        assert_eq!(color, colors.audio_base);
    }

    #[test]
    fn test_get_file_type_color_video_purple() {
        let colors = FileTypeColors::dark();
        let color = get_file_type_color(Some("mp4"), false);
        assert_eq!(color, colors.video_base);
    }

    #[test]
    fn test_get_file_type_color_image_green() {
        let colors = FileTypeColors::dark();
        let color = get_file_type_color(Some("png"), false);
        assert_eq!(color, colors.image_base);
    }

    #[test]
    fn test_get_file_type_color_document_orange() {
        let colors = FileTypeColors::dark();
        let color = get_file_type_color(Some("pdf"), false);
        assert_eq!(color, colors.document_base);
    }

    #[test]
    fn test_get_file_type_color_code_cyan() {
        let colors = FileTypeColors::dark();
        let color = get_file_type_color(Some("rs"), false);
        assert_eq!(color, colors.code_base);
    }

    #[test]
    fn test_get_file_type_color_archive_red() {
        let colors = FileTypeColors::dark();
        let color = get_file_type_color(Some("zip"), false);
        assert_eq!(color, colors.archive_base);
    }

    #[test]
    fn test_get_file_type_color_other_gray() {
        let colors = FileTypeColors::dark();
        let color = get_file_type_color(Some("xyz"), false);
        assert_eq!(color, colors.other_base);
    }

    #[test]
    fn test_get_file_type_selection_color() {
        let colors = FileTypeColors::dark();

        // Directory selection should be light
        let dir_color = get_file_type_selection_color(Some("rs"), true);
        assert_eq!(dir_color, colors.directory_light);

        // Audio file selection should be light blue
        let audio_color = get_file_type_selection_color(Some("mp3"), false);
        assert_eq!(audio_color, colors.audio_light);
    }

    #[test]
    fn test_file_type_colors_themes() {
        // Verify all three themes create valid palettes
        let dark = FileTypeColors::dark();
        let light = FileTypeColors::light();
        let colorblind = FileTypeColors::colorblind();

        // Each should have distinct colors for all file types
        for file_type in [
            FileType::Audio,
            FileType::Video,
            FileType::Image,
            FileType::Document,
            FileType::Code,
            FileType::Archive,
            FileType::Directory,
            FileType::Other,
        ] {
            // Just ensure colors can be retrieved without panic
            let _ = dark.get_color(file_type);
            let _ = light.get_color(file_type);
            let _ = colorblind.get_color(file_type);

            let _ = dark.get_light_color(file_type);
            let _ = light.get_light_color(file_type);
            let _ = colorblind.get_light_color(file_type);

            let _ = dark.get_dark_color(file_type);
            let _ = light.get_dark_color(file_type);
            let _ = colorblind.get_dark_color(file_type);
        }
    }
}
