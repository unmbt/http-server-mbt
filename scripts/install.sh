#!/bin/bash
set -e

REPO="unmbt/http-server-mbt"
INSTALL_DIR="$HOME/.unmbt"
BIN_NAME="http-server-mbt"
BIN_PATH="$INSTALL_DIR/$BIN_NAME"

# Check if uninstall flag is passed
if [ "$1" == "uninstall" ] || [ "$1" == "--uninstall" ]; then
    echo "Uninstalling $BIN_NAME..."
    rm -f "$BIN_PATH"
    echo "Uninstalled successfully."
    exit 0
fi

# Detect OS and Architecture
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"

if [ "$OS" != "linux" ] && [ "$OS" != "darwin" ]; then
    echo "Unsupported OS: $OS"
    exit 1
fi

if [ "$OS" == "darwin" ]; then
    OS="macos"
fi

if [ "$ARCH" == "x86_64" ]; then
    ARCH="amd64"
elif [ "$ARCH" == "aarch64" ] || [ "$ARCH" == "arm64" ]; then
    ARCH="arm64"
else
    echo "Unsupported architecture: $ARCH"
    exit 1
fi

ASSET_NAME="${BIN_NAME}-${OS}-${ARCH}"

# Fetch latest release info
echo "Fetching latest version info from GitHub..."
LATEST_RELEASE=$(curl -s https://api.github.com/repos/$REPO/releases/latest)
LATEST_VERSION=$(echo "$LATEST_RELEASE" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' | sed 's/^v//')
DOWNLOAD_URL=$(echo "$LATEST_RELEASE" | grep "browser_download_url.*$ASSET_NAME" | cut -d '"' -f 4)

if [ -z "$LATEST_VERSION" ] || [ -z "$DOWNLOAD_URL" ]; then
    echo "Failed to fetch latest version or download URL. Please check your network or check if a Release exists."
    exit 1
fi

# Check if already installed and version matches
if [ -f "$BIN_PATH" ]; then
    CURRENT_VERSION=$("$BIN_PATH" -v 2>/dev/null || echo "unknown")
    if [ "$CURRENT_VERSION" == "$LATEST_VERSION" ]; then
        echo "✨ You already have the latest version ($LATEST_VERSION) installed at $BIN_PATH."
        exit 0
    else
        echo "🚀 Updating from $CURRENT_VERSION to $LATEST_VERSION..."
    fi
else
    echo "🚀 Installing version $LATEST_VERSION..."
fi

mkdir -p "$INSTALL_DIR"

echo "Downloading $ASSET_NAME..."
curl -L -o "$BIN_PATH" "$DOWNLOAD_URL"
chmod +x "$BIN_PATH"

echo ""
echo "✅ Installed $BIN_NAME v$LATEST_VERSION successfully to $BIN_PATH"

# Auto add to PATH
export_path_line="export PATH=\"\$HOME/.unmbt:\$PATH\""
add_to_path() {
    local rc_file="$1"
    if [ -f "$rc_file" ]; then
        if ! grep -q '\$HOME/.unmbt' "$rc_file"; then
            echo "" >> "$rc_file"
            echo "$export_path_line" >> "$rc_file"
            echo "✅ Automatically added ~/.unmbt to $rc_file"
        fi
        return 0
    fi
    return 1
}

added_to_path=false
if [ -n "$ZSH_VERSION" ] || [ "$SHELL" == *"zsh"* ]; then
    add_to_path "$HOME/.zshrc" && added_to_path=true
elif [ -n "$BASH_VERSION" ] || [ "$SHELL" == *"bash"* ]; then
    add_to_path "$HOME/.bashrc" || add_to_path "$HOME/.bash_profile" && added_to_path=true
else
    # Fallback to try both common files
    add_to_path "$HOME/.zshrc" || true
    add_to_path "$HOME/.bashrc" || true
    added_to_path=true
fi

if [ "$added_to_path" = true ]; then
    echo "💡 Note: Please restart your terminal or run 'source ~/.bashrc' (or ~/.zshrc) for the changes to take effect."
else
    echo "⚠️  Could not automatically detect your shell configuration file."
    echo "💡 To use it globally, please ensure $INSTALL_DIR is in your PATH. You can add it by running:"
    echo "   echo '$export_path_line' >> ~/.bashrc"
fi
