#!/bin/bash
set -e

REPO="unmbt/http-server-mbt"
INSTALL_DIR="$HOME/.unmbt"
BIN_NAME="http-server-mbt"
BIN_PATH="$INSTALL_DIR/$BIN_NAME"

VARIANT="full"
ACTION="install"

for arg in "$@"; do
    case "$arg" in
        uninstall|--uninstall)
            ACTION="uninstall"
            ;;
        thin|--thin|-t|min|--min|-m)
            VARIANT="thin"
            ;;
        full|--full)
            VARIANT="full"
            ;;
        *)
            ;;
    esac
done

# Check if uninstall flag is passed
if [ "$ACTION" == "uninstall" ]; then
    echo "Uninstalling $BIN_NAME..."
    rm -f "$BIN_PATH" "$INSTALL_DIR/http-server-mbt-thin" "$INSTALL_DIR/http-server-min"
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

if [ "$VARIANT" == "thin" ]; then
    ASSET_PREFIX="http-server-mbt-thin"
else
    ASSET_PREFIX="http-server-mbt"
fi
ASSET_NAME="${ASSET_PREFIX}-${OS}-${ARCH}"

# Fetch latest release info
echo "Fetching latest version info from GitHub..."
if ! LATEST_RELEASE=$(curl --fail --silent --show-error --location "https://api.github.com/repos/$REPO/releases/latest"); then
    echo "Failed to fetch release info. Please check your network or check if a Release exists."
    exit 1
fi
LATEST_VERSION=$(echo "$LATEST_RELEASE" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' | sed 's/^v//')
DOWNLOAD_URL=$(echo "$LATEST_RELEASE" | grep "browser_download_url.*$ASSET_NAME" | cut -d '"' -f 4)

if [ -z "$LATEST_VERSION" ] || [ -z "$DOWNLOAD_URL" ]; then
    echo "Failed to fetch latest version or download URL for $ASSET_NAME. Please check your network or check if a Release exists."
    exit 1
fi

# Check if already installed and version matches
VARIANT_DESC="full"
if [ "$VARIANT" == "thin" ]; then
    VARIANT_DESC="thin"
fi

if [ -f "$BIN_PATH" ]; then
    CURRENT_VERSION=$("$BIN_PATH" -v 2>/dev/null || echo "unknown")
    if [ "$CURRENT_VERSION" == "$LATEST_VERSION" ]; then
        echo "✨ You already have the latest version ($LATEST_VERSION) installed at $BIN_PATH."
        if [ "$VARIANT" == "thin" ]; then
            ln -sf "$BIN_NAME" "$INSTALL_DIR/http-server-mbt-thin"
        fi
        exit 0
    else
        echo "🚀 Updating from $CURRENT_VERSION to $LATEST_VERSION ($VARIANT_DESC variant)..."
    fi
else
    echo "🚀 Installing version $LATEST_VERSION ($VARIANT_DESC variant)..."
fi

mkdir -p "$INSTALL_DIR"

echo "Downloading $ASSET_NAME..."
TEMP_PATH=$(mktemp "$INSTALL_DIR/${BIN_NAME}.download.XXXXXX")
cleanup() {
    rm -f "$TEMP_PATH"
}
trap cleanup EXIT

if ! curl --fail --show-error --location --output "$TEMP_PATH" "$DOWNLOAD_URL"; then
    echo "Failed to download $ASSET_NAME. The existing installation was not changed."
    exit 1
fi

if [ ! -s "$TEMP_PATH" ]; then
    echo "Failed to download $ASSET_NAME: the downloaded file is empty."
    exit 1
fi

chmod +x "$TEMP_PATH"
mv -f "$TEMP_PATH" "$BIN_PATH"
if [ "$VARIANT" == "thin" ]; then
    ln -sf "$BIN_NAME" "$INSTALL_DIR/http-server-mbt-thin"
fi
trap - EXIT

echo ""
if [ "$VARIANT" == "thin" ]; then
    echo "✅ Installed http-server-mbt (thin variant) v$LATEST_VERSION successfully to $BIN_PATH"
    echo "   (Also available as $INSTALL_DIR/http-server-mbt-thin)"
else
    echo "✅ Installed $BIN_NAME v$LATEST_VERSION successfully to $BIN_PATH"
fi

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
