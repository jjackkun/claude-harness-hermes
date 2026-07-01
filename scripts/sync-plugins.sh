#!/usr/bin/env bash
# sync-plugins.sh — assets/agents/ -> plugins/ai-dev-setting/agents/ 동기화
#
# plugins/ai-dev-setting/agents/ 에 존재하는 동명 파일만 assets 최신본으로
# 실파일 복사한다 (symlink 금지 — 플러그인 로더가 symlink를 읽지 못함).
#
# Usage:
#   scripts/sync-plugins.sh          # 동기화 (복사)
#   scripts/sync-plugins.sh --check  # CI용: 복사 없이 diff 발견 시 exit 1

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS_DIR="$REPO_ROOT/assets/agents"
PLUGIN_DIR="$REPO_ROOT/plugins/ai-dev-setting/agents"

CHECK_MODE=0
if [[ "${1:-}" == "--check" ]]; then
  CHECK_MODE=1
elif [[ -n "${1:-}" ]]; then
  echo "Usage: $0 [--check]" >&2
  exit 2
fi

if [[ ! -d "$ASSETS_DIR" ]]; then
  echo "[sync-plugins] ERROR: not found: $ASSETS_DIR" >&2
  exit 2
fi
if [[ ! -d "$PLUGIN_DIR" ]]; then
  echo "[sync-plugins] ERROR: not found: $PLUGIN_DIR" >&2
  exit 2
fi

drift=0
synced=0

for plugin_file in "$PLUGIN_DIR"/*.md; do
  [[ -e "$plugin_file" ]] || continue
  name="$(basename "$plugin_file")"
  asset_file="$ASSETS_DIR/$name"

  if [[ ! -f "$asset_file" ]]; then
    if [[ "$CHECK_MODE" -eq 1 ]]; then
      # plugins 에만 있는 에이전트도 drift — assets 가 단일 진실 공급원
      echo "[sync-plugins] DRIFT: agents/$name has no assets/agents counterpart"
      drift=1
    else
      echo "[sync-plugins] WARN: no assets counterpart for $name (skipped)" >&2
    fi
    continue
  fi

  if ! cmp -s "$asset_file" "$plugin_file"; then
    if [[ "$CHECK_MODE" -eq 1 ]]; then
      echo "[sync-plugins] DRIFT: agents/$name differs from assets/agents/$name"
      drift=1
    else
      cp "$asset_file" "$plugin_file"
      echo "[sync-plugins] synced: agents/$name"
      synced=$((synced + 1))
    fi
  fi
done

if [[ "$CHECK_MODE" -eq 1 ]]; then
  if [[ "$drift" -eq 1 ]]; then
    echo "[sync-plugins] FAIL: drift detected. Run scripts/sync-plugins.sh to fix." >&2
    exit 1
  fi
  echo "[sync-plugins] OK: plugins agents are in sync with assets."
else
  echo "[sync-plugins] done ($synced file(s) copied)."
fi
