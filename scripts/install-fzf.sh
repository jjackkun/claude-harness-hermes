#!/usr/bin/env bash
# Install a recent fzf binary into ai-dev-setting/bin/fzf.
# setup.sh requires fzf >= 0.48 (for `start` event and `pos(N)+select` chaining).

set -euo pipefail

DEV_SETTING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$DEV_SETTING_DIR/bin"
VERSION="0.71.0"

os="$(uname -s | tr '[:upper:]' '[:lower:]')"
arch="$(uname -m)"
WIN=0
case "$os-$arch" in
  linux-x86_64)   asset="fzf-${VERSION}-linux_amd64.tar.gz" ;;
  linux-aarch64)  asset="fzf-${VERSION}-linux_arm64.tar.gz" ;;
  darwin-x86_64)  asset="fzf-${VERSION}-darwin_amd64.tar.gz" ;;
  darwin-arm64)   asset="fzf-${VERSION}-darwin_arm64.tar.gz" ;;
  mingw64_nt-*|msys_nt-*) asset="fzf-${VERSION}-windows_amd64.zip"; WIN=1 ;;
  *) echo "Unsupported platform: $os-$arch"; exit 1 ;;
esac

mkdir -p "$BIN_DIR"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

url="https://github.com/junegunn/fzf/releases/download/v${VERSION}/${asset}"
echo "Downloading $url"

if [[ $WIN -eq 1 ]]; then
  curl -fsSL "$url" -o "$tmp/fzf.zip"
  unzip -q "$tmp/fzf.zip" -d "$tmp"
  install -m 0755 "$tmp/fzf.exe" "$BIN_DIR/fzf.exe"
  echo "Installed: $("$BIN_DIR/fzf.exe" --version)"
  echo "Path: $BIN_DIR/fzf.exe"
else
  curl -fsSL "$url" -o "$tmp/fzf.tar.gz"
  tar -xzf "$tmp/fzf.tar.gz" -C "$tmp"
  install -m 0755 "$tmp/fzf" "$BIN_DIR/fzf"
  echo "Installed: $("$BIN_DIR/fzf" --version)"
  echo "Path: $BIN_DIR/fzf"
fi
