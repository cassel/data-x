# Data-X macOS Installation Guide

## Download

Download `Data-X_0.3.0_aarch64.dmg` from the releases page.

## Installation

1. Open the DMG file
2. Drag `Data-X.app` to your Applications folder

## First Launch - "Damaged" or "Cannot be opened" Error

Since this app is not from the Mac App Store, macOS Gatekeeper may block it. Here's how to fix it:

### Option 1: Right-Click to Open (Easiest)

1. In Finder, navigate to `/Applications`
2. **Right-click** (or Control-click) on `Data-X.app`
3. Select **Open** from the menu
4. Click **Open** in the dialog that appears
5. The app will now open normally every time

### Option 2: Terminal Command

Open Terminal and run:

```bash
xattr -cr /Applications/Data-X.app
```

Then double-click the app to open it normally.

### Option 3: System Settings (macOS Ventura+)

1. Try to open Data-X (it will be blocked)
2. Go to **System Settings** > **Privacy & Security**
3. Scroll down to find the message about Data-X being blocked
4. Click **Open Anyway**
5. Enter your password when prompted

## Troubleshooting

### "Data-X.app is damaged and can't be opened"

This happens because macOS adds a quarantine flag to downloaded apps. Fix it with:

```bash
xattr -cr /Applications/Data-X.app
```

### App crashes on launch

Make sure you have macOS 10.14 (Mojave) or later.

### Need full disk access?

For scanning all files, Data-X may request Full Disk Access:
1. Go to **System Settings** > **Privacy & Security** > **Full Disk Access**
2. Click the + button and add Data-X

## Building from Source

```bash
git clone https://github.com/your-repo/data-x.git
cd data-x
cd ui && npm install
npm run tauri build
```

The built app will be at: `src-tauri/target/release/bundle/macos/Data-X.app`
