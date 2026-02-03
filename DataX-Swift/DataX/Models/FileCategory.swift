import SwiftUI

enum FileCategory: String, CaseIterable, Sendable {
    case documents
    case images
    case videos
    case audio
    case archives
    case code
    case data
    case system
    case folders
    case other

    // Vibrant colors for file categories
    var color: Color {
        switch self {
        case .documents: return Color(red: 0.0, green: 0.45, blue: 1.0)    // Bright blue
        case .images: return Color(red: 0.0, green: 0.85, blue: 0.35)      // Vivid green
        case .videos: return Color(red: 0.7, green: 0.0, blue: 0.9)        // Bright purple
        case .audio: return Color(red: 1.0, green: 0.5, blue: 0.0)         // Bright orange
        case .archives: return Color(red: 1.0, green: 0.85, blue: 0.0)     // Bright yellow
        case .code: return Color(red: 0.0, green: 0.8, blue: 0.8)          // Cyan
        case .data: return Color(red: 1.0, green: 0.2, blue: 0.5)          // Hot pink
        case .system: return Color(red: 0.5, green: 0.5, blue: 0.55)       // Gray
        case .folders: return Color(red: 0.65, green: 0.5, blue: 0.25)     // Brown/tan
        case .other: return Color(red: 0.6, green: 0.6, blue: 0.65)        // Light gray
        }
    }

    var icon: String {
        switch self {
        case .documents: return "doc.fill"
        case .images: return "photo.fill"
        case .videos: return "film.fill"
        case .audio: return "music.note"
        case .archives: return "archivebox.fill"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .data: return "cylinder.fill"
        case .system: return "gearshape.fill"
        case .folders: return "folder.fill"
        case .other: return "doc.fill"
        }
    }

    var displayName: String {
        rawValue.capitalized
    }

    static func categorize(_ extension: String?) -> FileCategory {
        guard let ext = `extension`?.lowercased(), !ext.isEmpty else {
            return .other
        }

        switch ext {
        // Documents
        case "pdf", "doc", "docx", "txt", "rtf", "odt", "pages", "md", "markdown",
             "epub", "mobi", "xps", "tex", "latex":
            return .documents

        // Images
        case "jpg", "jpeg", "png", "gif", "bmp", "svg", "webp", "heic", "heif",
             "raw", "psd", "ai", "ico", "tiff", "tif", "cr2", "nef", "arw":
            return .images

        // Videos
        case "mp4", "mov", "avi", "mkv", "wmv", "flv", "webm", "m4v", "mpeg",
             "mpg", "3gp", "ogv", "ts", "mts", "m2ts":
            return .videos

        // Audio
        case "mp3", "wav", "flac", "aac", "ogg", "m4a", "wma", "aiff", "ape",
             "opus", "mid", "midi":
            return .audio

        // Archives
        case "zip", "rar", "7z", "tar", "gz", "bz2", "xz", "dmg", "iso", "pkg",
             "deb", "rpm", "cab", "lz", "lzma", "zst":
            return .archives

        // Code
        case "swift", "rs", "js", "jsx", "tsx", "py", "java", "kt", "c",
             "cpp", "cc", "h", "hpp", "go", "rb", "php", "html", "htm", "css",
             "scss", "sass", "less", "json", "xml", "yaml", "yml", "toml",
             "sh", "bash", "zsh", "fish", "ps1", "bat", "cmd", "lua", "r",
             "scala", "clj", "ex", "exs", "erl", "hs", "ml", "fs", "vb", "cs",
             "m", "mm", "pl", "pm", "tcl", "vim", "el", "lisp", "scm", "asm",
             "s", "wasm", "sol", "v", "sv", "vhd", "vhdl":
            return .code

        // Data
        case "db", "sqlite", "sqlite3", "sql", "csv", "xlsx", "xls", "ods",
             "numbers", "parquet", "avro", "arrow", "feather", "hdf5", "h5",
             "nc", "mat", "sav", "dta", "rds", "rdata", "pickle", "pkl":
            return .data

        // System
        case "app", "exe", "dll", "dylib", "so", "framework", "plist", "log",
             "sys", "ini", "cfg", "conf", "config", "lock", "pid", "socket",
             "service", "desktop", "lnk", "url", "webloc":
            return .system

        default:
            return .other
        }
    }
}
