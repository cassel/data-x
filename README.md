# Data-X

A fast, visual disk space analyzer with modern GUI and TUI interfaces.

![Data-X Screenshot](assets/screenshot.png)

## Features

- **Multiple Visualizations**: Treemap, Sunburst, Icicle, Bar Chart, Circle Packing
- **Dual Interface**: Modern GUI (Tauri + React) and Terminal UI (TUI)
- **Fast Scanning**: Parallel directory scanning with real-time progress
- **Cross-Platform**: macOS, Windows, Linux
- **Remote Scanning**: Analyze remote servers via SSH
- **File Management**: Open in Finder/Explorer, Move to Trash

## Installation

### macOS

Download the latest `.dmg` from [Releases](https://github.com/cassel/data-x/releases).

```bash
# Or build from source
git clone https://github.com/cassel/data-x.git
cd data-x
cargo tauri build
```

### Windows

Download the latest `.exe` installer or portable version from [Releases](https://github.com/cassel/data-x/releases).

### Linux

```bash
git clone https://github.com/cassel/data-x.git
cd data-x
cargo tauri build
```

## Usage

### GUI Mode (Default)

Double-click the app or run:

```bash
data-x
```

### TUI Mode (Terminal)

```bash
# Analyze current directory
data-x --tui

# Analyze specific path
data-x --tui /path/to/folder

# Remote server via SSH
data-x user@server:/remote/path

# JSON output for scripting
data-x --json /path/to/folder
```

### Command Line Options

```
Usage: data-x [OPTIONS] [PATH]

Arguments:
  [PATH]  Directory to analyze (default: current directory)

Options:
  -d, --depth <DEPTH>         Maximum depth to scan
  -x, --exclude <PATTERN>     Patterns to exclude (can be repeated)
      --json                  Output JSON instead of TUI
  -n, --top <N>               Show only N largest items (with --json)
      --no-cross-mount        Don't cross filesystem boundaries
      --apparent-size         Use apparent size instead of disk usage
      --tui                   Force TUI mode
      --color-scheme <NAME>   Color scheme: default, dark, light, colorblind
  -h, --help                  Print help
  -V, --version               Print version
```

## Building from Source

### Prerequisites

- [Rust](https://rustup.rs/) (1.70+)
- [Node.js](https://nodejs.org/) (18+)
- [Tauri CLI](https://tauri.app/)

### Build

```bash
# Clone the repository
git clone https://github.com/cassel/data-x.git
cd data-x

# Install frontend dependencies
cd ui && npm install && cd ..

# Build GUI app
cargo tauri build

# Build TUI only (no GUI dependencies)
cargo build --release --no-default-features
```

### Development

```bash
# Run in development mode with hot reload
cd ui && npm run tauri dev
```

## Tech Stack

- **Backend**: Rust
- **GUI**: Tauri 2.x + React + TypeScript
- **TUI**: Ratatui + Crossterm
- **Styling**: Tailwind CSS
- **Visualizations**: D3.js + HTML Canvas

## License

MIT License - see [LICENSE](LICENSE) for details.

## Author

Created by [Cassel](https://github.com/cassel)
