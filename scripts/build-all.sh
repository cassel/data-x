#!/bin/bash
# Build Data-X for multiple platforms

set -e

echo "=== Data-X Multi-Platform Build ==="
echo ""

# Ensure we're in the right directory
cd "$(dirname "$0")/.."

# Setup PATH
export PATH="$HOME/.cargo/bin:/usr/local/bin:$PATH"

# Create dist directory
mkdir -p dist

# Build macOS TUI (native)
echo "1. Building macOS TUI..."
cargo build --release --no-default-features
cp target/release/data-x dist/data-x-macos
echo "   Done: dist/data-x-macos"

# Build Windows TUI (cross-compile)
echo ""
echo "2. Building Windows TUI..."
cargo build --release --no-default-features --target x86_64-pc-windows-gnu
cp target/x86_64-pc-windows-gnu/release/data-x.exe dist/data-x-windows.exe
echo "   Done: dist/data-x-windows.exe"

# Build macOS Tauri GUI
echo ""
echo "3. Building macOS Tauri GUI..."
cargo tauri build
cp -r src-tauri/target/release/bundle/dmg/*.dmg dist/
echo "   Done: dist/*.dmg"

echo ""
echo "=== Build Complete ==="
echo ""
echo "Files in dist/:"
ls -lh dist/

echo ""
echo "Note: Windows GUI requires GitHub Actions or Windows machine."
echo "      Use: gh workflow run release.yml"
