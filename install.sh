#!/bin/bash
# Claude Gauge — installer
#
# Usage:
#   ./install.sh              Full install (macOS menu bar app + statusline hook)
#   ./install.sh --hook       Statusline hook only (any platform)
#   ./install.sh --uninstall  Remove everything

set -e

INSTALL_DIR="$HOME/.claude-gauge"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SETTINGS="$HOME/.claude/settings.json"

# Uses jq to safely merge into settings.json without clobbering existing keys
add_statusline() {
  local cmd="$1"
  [ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
  local tmp=$(jq --arg cmd "$cmd" '.statusLine = {"type": "command", "command": $cmd}' "$SETTINGS")
  echo "$tmp" > "$SETTINGS"
  echo "Statusline configured in settings.json"
}

remove_statusline() {
  if [ -f "$SETTINGS" ]; then
    if jq -e '.statusLine.command' "$SETTINGS" 2>/dev/null | grep -q 'claude-gauge\|statusline.sh'; then
      local tmp=$(jq 'del(.statusLine)' "$SETTINGS")
      echo "$tmp" > "$SETTINGS"
      echo "Removed statusline from settings.json"
    else
      echo "No claude-gauge statusline found in settings.json"
    fi
  fi
}

# ── Uninstall ──────────────────────────────────────────────

if [ "$1" = "--uninstall" ]; then
    echo "Uninstalling Claude Gauge..."
    pkill -f claude-gauge 2>/dev/null || true
    remove_statusline
    # Remove Login Item
    osascript -e 'tell application "System Events" to delete login item "claude-gauge"' 2>/dev/null || true
    rm -rf "$INSTALL_DIR"
    echo "Done."
    exit 0
fi

# ── Check jq ──────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
    echo "Error: 'jq' is required. Install it:"
    echo "  macOS:  brew install jq"
    echo "  Ubuntu: sudo apt install jq"
    exit 1
fi

# ── Install statusline script ─────────────────────────────

echo "Installing Claude Gauge..."
mkdir -p "$INSTALL_DIR/scripts" "$INSTALL_DIR/assets"

cp "$REPO_DIR/scripts/statusline.sh" "$INSTALL_DIR/scripts/"
chmod +x "$INSTALL_DIR/scripts/statusline.sh"

add_statusline "$INSTALL_DIR/scripts/statusline.sh"

if [ "$1" = "--hook" ] || [ "$1" = "--statusline" ]; then
    echo ""
    echo "Installed statusline hook to $INSTALL_DIR/"
    echo "Usage bars will appear at the bottom of every Claude Code session."
    echo ""
    echo "To uninstall: ./install.sh --uninstall"
    exit 0
fi

# ── Full install (macOS menu bar app) ─────────────────────

if [ "$(uname)" != "Darwin" ]; then
    echo ""
    echo "Menu bar app requires macOS. Statusline was installed successfully."
    echo "Use './install.sh --statusline' to skip this check."
    exit 0
fi

if ! command -v swiftc &>/dev/null; then
    echo "Error: Xcode Command Line Tools required. Run: xcode-select --install"
    exit 1
fi

cp "$REPO_DIR/assets/claude-menubar-icon.png" "$INSTALL_DIR/assets/"

echo "Compiling menu bar app..."
swiftc -o "$INSTALL_DIR/claude-gauge" "$REPO_DIR/src/claude-menubar.swift" -framework Cocoa

# Kill old instance if running
pkill -f claude-gauge 2>/dev/null || true
sleep 1

# Launch
"$INSTALL_DIR/claude-gauge" &
disown

echo ""
echo "Installed and running."
echo ""

# Offer to add to Login Items
read -p "Add to Login Items (auto-start on boot)? [y/N] " ADD_LOGIN
if [[ "$ADD_LOGIN" =~ ^[Yy]$ ]]; then
    osascript -e "tell application \"System Events\" to make login item at end with properties {path:\"$INSTALL_DIR/claude-gauge\", hidden:true}" 2>/dev/null \
      && echo "Added to Login Items." \
      || echo "Could not add automatically. Add manually: System Settings > General > Login Items"
fi

echo ""
echo "To uninstall: ./install.sh --uninstall"
