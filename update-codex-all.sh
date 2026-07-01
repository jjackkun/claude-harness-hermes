#!/usr/bin/env bash
# update-codex-all.sh — convenience wrapper for Codex project updates.

set -euo pipefail

DEV_SETTING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$DEV_SETTING_DIR/update-all.sh" --target codex "$@"
