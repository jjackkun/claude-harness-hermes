#!/usr/bin/env bash
# setup-codex.sh — convenience wrapper for Codex project setup.

set -euo pipefail

DEV_SETTING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$DEV_SETTING_DIR/setup.sh" --target codex "$@"
