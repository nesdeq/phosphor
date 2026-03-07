#!/usr/bin/env bash
set -euo pipefail

APP_NAME="phosphor"
INSTALL_DIR="$HOME/.local/share/$APP_NAME"
BIN_DIR="$HOME/.local/bin"
ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"
DESKTOP_DIR="$HOME/.local/share/applications"

# Determine bundle location (directory where this script lives)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Installing Phosphor..."

# Create directories
mkdir -p "$INSTALL_DIR" "$BIN_DIR" "$ICON_DIR" "$DESKTOP_DIR"

# Copy bundle
cp -r "$SCRIPT_DIR"/phosphor "$SCRIPT_DIR"/lib "$SCRIPT_DIR"/data "$INSTALL_DIR/"

# Symlink binary
ln -sf "$INSTALL_DIR/phosphor" "$BIN_DIR/phosphor"

# Install icon
cp "$INSTALL_DIR/data/phosphor.png" "$ICON_DIR/$APP_NAME.png"

# Create .desktop file
cat > "$DESKTOP_DIR/$APP_NAME.desktop" << EOF
[Desktop Entry]
Name=Phosphor
Comment=A retro AI terminal emulator
Exec=$INSTALL_DIR/phosphor
Icon=$APP_NAME
Terminal=false
Type=Application
Categories=System;TerminalEmulator;
StartupWMClass=phosphor
EOF

# Update icon cache if available
if command -v gtk-update-icon-cache &> /dev/null; then
  gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
fi

echo "Installed to $INSTALL_DIR"
echo "Binary linked at $BIN_DIR/phosphor"
echo "Desktop entry created — Phosphor should appear in your app launcher."
