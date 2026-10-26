#!/usr/bin/env bash
set -e

# 1. Get the directory where this script is located, then go one level up
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(dirname "$SCRIPT_DIR")"
FLUTTER_DIR="$INSTALL_DIR/flutter"
FLUTTER_BIN="$FLUTTER_DIR/bin"

echo "=== 1. Ensuring installation directory exists at: $INSTALL_DIR ==="
mkdir -p "$INSTALL_DIR"

echo "=== 2. Checking Flutter SDK installation ==="
if [ ! -d "$FLUTTER_DIR/.git" ]; then
    echo "Flutter SDK not found. Cloning repository via git..."
    git clone https://github.com/flutter/flutter.git -b stable "$FLUTTER_DIR"
else
    echo "Flutter SDK already present. Checking for updates..."
    cd "$FLUTTER_DIR"
    
    # Stash local changes, fetch stable, pull updates, and pop stash if needed
    git stash --include-untracked || true
    git fetch origin
    git checkout stable
    git pull origin stable
    git stash pop || true
    
    cd - > /dev/null
    echo "Flutter repository updated successfully."
fi

echo "=== 3. Configuring PATH environment ==="
# Check if Flutter bin is already in ~/.bashrc
if ! grep -q "$FLUTTER_BIN" "$HOME/.bashrc"; then
    echo "export PATH=\"\$PATH:$FLUTTER_BIN\"" >> "$HOME/.bashrc"
    echo "Added $FLUTTER_BIN to ~/.bashrc PATH."
else
    echo "Flutter bin already present in ~/.bashrc PATH."
fi

# Export for the current shell session immediately
export PATH="$PATH:$FLUTTER_BIN"

echo "=== 4. Running flutter doctor ==="
flutter doctor

echo "=== Flutter setup on Linux completed successfully! Run 'source ~/.bashrc' or restart your terminal. ==="