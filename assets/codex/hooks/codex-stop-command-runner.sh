#!/usr/bin/env bash
# Run a resolved preset Stop command under Codex.

set -euo pipefail

COMMAND="${1:-}"
[[ -z "$COMMAND" ]] && exit 0

project_dir="${CODEX_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}"
cd "$project_dir" 2>/dev/null || true

export CODEX_PROJECT_DIR="$project_dir"
bash -lc "$COMMAND"
