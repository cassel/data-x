# Data-X Swift

Native macOS disk space analyzer with visual treemap, built in SwiftUI.

## Quick Start

```bash
# Build
xcodebuild -project DataX.xcodeproj -scheme DataX -configuration Debug build

# Run (GUI)
datax

# Run (TUI - uses Rust version)
datax --tui
```

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 15.0 or later

## Features

- **Treemap Visualization** - Squarify algorithm, 6 levels deep, color-coded by file type
- **Multiple Views** - Treemap, Sunburst, Icicle, Bar Chart, Circle Packing
- **File Tree Browser** - Searchable sidebar with breadcrumb navigation
- **Smart Interaction**:
  - Single click in tree = Highlight in treemap (cyan border)
  - Double click = Navigate into folder
  - Hover on treemap = Yellow border + info panel
- **File Categories** - Documents, Images, Videos, Audio, Code, Archives, Data, System
- **Fast Scanning** - GCD-based parallel scanning with live progress
- **Context Menu** - Reveal in Finder, Open in Terminal, Copy Path, Move to Trash

## Project Structure

```
DataX/
├── App/
│   ├── DataXApp.swift           # Entry point
│   └── AppState.swift           # Global state (@Observable)
├── Models/
│   ├── FileNode.swift           # File tree model
│   ├── FileCategory.swift       # File types & colors
│   └── DiskInfo.swift           # Volume info
├── Services/
│   ├── Scanner/
│   │   └── ScannerService.swift # GCD-based scanning
│   └── FileOperations/
│       └── FileOperationsService.swift
├── ViewModels/
│   ├── ScannerViewModel.swift   # Scan state
│   └── FilterViewModel.swift    # Filter state
├── Views/
│   ├── Main/
│   │   ├── ContentView.swift    # 3-pane layout
│   │   └── StatusBarView.swift
│   ├── Visualizations/
│   │   ├── TreemapView.swift    # Canvas + caching
│   │   ├── SunburstView.swift
│   │   ├── IcicleView.swift
│   │   ├── BarChartView.swift
│   │   └── CirclePackingView.swift
│   └── FileTree/
│       └── FileTreeView.swift
└── Utilities/
    ├── TreemapLayout.swift      # Squarify algorithm
    └── SizeFormatter.swift
```

## Architecture

### State Management
- `@Observable` pattern (macOS 14+)
- `AppState` - Global state (visualization type, highlighted node)
- `ScannerViewModel` - Scan lifecycle, current node, navigation

### Treemap Rendering

**TreemapLayout.swift** - Squarify algorithm
- Generates `[TreemapRect]` with pre-computed colors
- Max 5000-8000 rects (adaptive)
- Caches dominant folder colors

**TreemapView.swift** - Two-layer Canvas
```
┌─────────────────────────────────┐
│  Static Layer (.drawingGroup()) │  ← Rasterized, GPU cached
├─────────────────────────────────┤
│  Hover Overlay                  │  ← Lightweight borders only
└─────────────────────────────────┘
```

### Performance Optimizations

| Optimization | Description |
|--------------|-------------|
| GCD Scanning | Background queue, main thread callbacks |
| Cached Layout | Rects recalculated only on node/size change |
| Pre-computed Colors | Dominant color cached per folder |
| Limited Recursion | Color calculation max 3 levels deep |
| Rasterized Layer | `.drawingGroup()` for GPU rendering |
| Throttled Hover | 16ms throttle (~60fps) |
| Max Rects Limit | Prevents slowdown on huge folders |

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘O` | Open folder |
| `⌘R` | Refresh |
| `←` | Navigate back |
| `⌘↑` | Go to parent |

## CLI Usage

The `datax` command wrapper:

```bash
datax              # Opens Swift GUI
datax --tui        # Opens Rust TUI in terminal
datax --tui ~/Dir  # TUI for specific directory
```

## Building

```bash
# Command line
xcodebuild -project DataX.xcodeproj -scheme DataX -configuration Release build

# Or open in Xcode
open DataX.xcodeproj
# Then ⌘R to build and run
```

## TODO

- [ ] Filter by category/size/date
- [ ] Export scan results
- [ ] Duplicate file detection
- [ ] App Store sandboxing
- [ ] Notarization

## License

MIT
