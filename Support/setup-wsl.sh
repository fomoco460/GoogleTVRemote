#!/usr/bin/env bash
set -euo pipefail

# Run inside Ubuntu as your ordinary user. sudo is used only for Ubuntu packages.
if ! grep -qi ubuntu /etc/os-release; then
    echo 'This setup script expects Ubuntu.' >&2
    exit 1
fi
if [ "$(id -u)" = 0 ]; then
    echo 'Run this as your normal Ubuntu user, not with sudo bash.' >&2
    exit 1
fi
sudo apt-get update
sudo apt-get install -y ca-certificates curl git tar gzip libfuse2 usbmuxd libimobiledevice-utils

setup_dir=$(mktemp -d)
trap 'rm -f "$setup_dir/swiftly.tar.gz" "$setup_dir/swiftly" "$setup_dir/xtool.AppImage"; rmdir "$setup_dir" 2>/dev/null || true' EXIT
if ! command -v swift >/dev/null 2>&1; then
    if [ -f "$HOME/.local/share/swiftly/env.sh" ]; then
        . "$HOME/.local/share/swiftly/env.sh"
    fi
fi
if ! command -v swift >/dev/null 2>&1; then
    curl -fL "https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz" -o "$setup_dir/swiftly.tar.gz"
    tar -xzf "$setup_dir/swiftly.tar.gz" -C "$setup_dir"
    "$setup_dir/swiftly" init --quiet-shell-followup
    . "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh"
fi
swift --version

mkdir -p "$HOME/.local/bin"
if ! command -v xtool >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/xtool" ]; then
    curl -fL "https://github.com/xtool-org/xtool/releases/latest/download/xtool-$(uname -m).AppImage" -o "$setup_dir/xtool.AppImage"
    install -m 755 "$setup_dir/xtool.AppImage" "$HOME/.local/bin/xtool"
fi
export PATH="$HOME/.local/bin:$PATH"
xtool --help

echo
echo 'Swift and xtool are installed. Next, download the Xcode archive from Apple in your browser.'
echo 'Then run: ~/.local/bin/xtool setup'
echo 'Complete Apple sign-in yourself in this terminal. Do not send passwords or verification codes to chat.'
