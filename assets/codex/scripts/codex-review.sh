#!/usr/bin/env bash
# Convenience wrapper for the Codex review workflow.

set -euo pipefail

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

if ! command -v codex >/dev/null 2>&1; then
  echo "codex CLI not found in PATH" >&2
  exit 127
fi

exec codex review --uncommitted "$@"
