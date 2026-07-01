#!/usr/bin/env bash
# update-all.sh — target별 .installed-projects registry 에 등록된 프로젝트 전체 재설치
#
# Usage:
#   bash update-all.sh [--target claude|codex|both]
#   bash setup.sh --update-all [--target claude|codex|both]

set -uo pipefail

DEV_SETTING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TARGET="claude"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      TARGET="${2:-}"
      shift 2
      ;;
    --target=*)
      TARGET="${1#--target=}"
      shift
      ;;
    --codex)
      TARGET="codex"
      shift
      ;;
    --claude)
      TARGET="claude"
      shift
      ;;
    --both)
      TARGET="both"
      shift
      ;;
    -h|--help)
      cat <<EOF
Usage:
  $0 [--target claude|codex|both]

Defaults:
  --target claude
EOF
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

case "$TARGET" in
  claude|codex|both) ;;
  *)
    echo "Invalid target: $TARGET (expected claude, codex, or both)" >&2
    exit 1
    ;;
esac

BOLD='\033[1m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
RESET='\033[0m'

echo -e "${BOLD}${CYAN}━━━ update-all (${TARGET}) ━━━${RESET}"
echo ""

OK=0; FAIL=0; SKIP=0
OK_NAMES=()
FAIL_NAMES=()
SKIP_NAMES=()

run_target() {
  local target="$1"
  local registry lock_rel script
  case "$target" in
    claude)
      registry="$DEV_SETTING_DIR/.installed-projects"
      lock_rel=".claude/presets.lock"
      script="$DEV_SETTING_DIR/project-claude.sh"
      ;;
    codex)
      registry="$DEV_SETTING_DIR/.installed-projects.codex"
      lock_rel=".codex/presets.lock"
      script="$DEV_SETTING_DIR/project-codex.sh"
      ;;
  esac

  echo -e "${BOLD}${CYAN}== target: $target ==${RESET}"

  if [[ ! -f "$registry" ]] || [[ ! -s "$registry" ]]; then
    echo "등록된 프로젝트가 없습니다. 먼저 $(basename "$script") 를 실행하세요."
    echo ""
    return 0
  fi

  local -a paths stale presets preset_args
  mapfile -t paths < "$registry"
  stale=()

  local path lock tmp line stale_path local_found
  for path in "${paths[@]}"; do
    [[ -z "$path" ]] && continue
    echo -e "${BOLD}▸ $path${RESET}"

    if [[ ! -d "$path" ]]; then
      echo -e "  ${YELLOW}⚠ 경로 없음 — 레지스트리에서 제거합니다${RESET}"
      stale+=("$path")
      SKIP=$((SKIP + 1))
      SKIP_NAMES+=("$(basename "$path") (경로 없음)")
      echo ""
      continue
    fi

    lock="$path/$lock_rel"
    if [[ ! -f "$lock" ]] || [[ ! -s "$lock" ]]; then
      echo -e "  ${YELLOW}⚠ presets.lock 없음 또는 빈 파일 — 스킵${RESET}"
      SKIP=$((SKIP + 1))
      SKIP_NAMES+=("$(basename "$path") (presets.lock 없음)")
      echo ""
      continue
    fi

    mapfile -t presets < "$lock"
    preset_args=("${presets[@]}")

    if bash "$script" "$path" "${preset_args[@]}"; then
      echo -e "  ${GREEN}✔ 완료 — $(basename "$path")${RESET}"
      OK=$((OK + 1))
      OK_NAMES+=("$(basename "$path")")
    else
      echo -e "  ${RED}✗ 실패 — $(basename "$path")${RESET}"
      FAIL=$((FAIL + 1))
      FAIL_NAMES+=("$(basename "$path")")
    fi
    echo ""
  done

  if [[ ${#stale[@]} -gt 0 ]]; then
    tmp=$(mktemp)
    while IFS= read -r line; do
      local_found=0
      for stale_path in "${stale[@]}"; do
        [[ "$line" == "$stale_path" ]] && local_found=1 && break
      done
      [[ $local_found -eq 0 ]] && echo "$line"
    done < "$registry" > "$tmp"
    mv "$tmp" "$registry"
  fi
}

# ── 머신 전역 도구 체크 (uv + 플러그인 4종 + Codex Serena) ────────────────
if ! command -v uv >/dev/null 2>&1; then
  echo -e "${YELLOW}▸ uv 미설치 — 설치 중...${RESET}"
  if curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null 2>&1; then
    # 설치 직후 현재 셸에 PATH 반영 (uv 기본 설치 위치: ~/.local/bin)
    export PATH="$HOME/.local/bin:$PATH"
    echo -e "  ${GREEN}✔ uv 설치 완료${RESET}"
  else
    echo -e "  ${YELLOW}⚠ uv 설치 실패 — 수동 설치: curl -LsSf https://astral.sh/uv/install.sh | sh${RESET}"
  fi
  echo ""
fi

if [[ "$TARGET" == "claude" || "$TARGET" == "both" ]] && command -v claude >/dev/null 2>&1; then
  _INSTALLED_PLUGINS=$(claude plugin list 2>/dev/null || true)
  _install_plugin() {
    local id="$1" label="$2"
    if echo "$_INSTALLED_PLUGINS" | grep -q "$id"; then return 0; fi
    echo -e "${YELLOW}▸ $label 플러그인 미설치 — 설치 중...${RESET}"
    if claude plugin install "$id" --scope user >/dev/null 2>&1; then
      echo -e "  ${GREEN}✔ $label 설치 완료${RESET}"
    else
      echo -e "  ${YELLOW}⚠ $label 설치 실패 — 수동: claude plugin install $id --scope user${RESET}"
    fi
  }
  _install_plugin "session-report@claude-plugins-official"       "Session Report"
  _install_plugin "claude-md-management@claude-plugins-official" "Claude MD Management"
  _install_plugin "hookify@claude-plugins-official"              "Hookify"
  _install_plugin "serena@claude-plugins-official"               "Serena MCP"
  unset _INSTALLED_PLUGINS _install_plugin
fi

if [[ "$TARGET" == "codex" || "$TARGET" == "both" ]]; then
  if ! command -v serena >/dev/null 2>&1; then
    echo -e "${YELLOW}▸ Serena 미설치 — 설치 중...${RESET}"
    uv tool install -p 3.13 serena-agent@latest --prerelease=allow >/dev/null 2>&1 \
      && echo -e "  ${GREEN}✔ Serena 설치 완료${RESET}" \
      || echo -e "  ${YELLOW}⚠ Serena 설치 실패${RESET}"
    echo ""
  fi
  _CODEX_CONFIG="$HOME/.codex/config.toml"
  if ! grep -q '\[mcp_servers.serena\]' "$_CODEX_CONFIG" 2>/dev/null; then
    echo -e "${YELLOW}▸ Codex config.toml 에 Serena MCP 미등록 — 등록 중...${RESET}"
    mkdir -p "$HOME/.codex"
    cat >> "$_CODEX_CONFIG" <<'TOML'

[mcp_servers.serena]
startup_timeout_sec = 15
command = "serena"
args = ["start-mcp-server", "--project-from-cwd", "--context=codex"]
TOML
    echo -e "  ${GREEN}✔ Serena MCP 등록 완료${RESET}"
    echo ""
  fi
  unset _CODEX_CONFIG
fi

# ── 전역 공통 assets 갱신 (public-claude.sh) ──────────────────────────────────
if [[ "$TARGET" == "claude" || "$TARGET" == "both" ]]; then
  echo -e "${BOLD}${CYAN}== 전역 공통 assets 갱신 (public-claude.sh) ==${RESET}"
  if bash "$DEV_SETTING_DIR/public-claude.sh"; then
    echo -e "  ${GREEN}✔ 전역 assets 갱신 완료${RESET}"
  else
    echo -e "  ${YELLOW}⚠ 전역 assets 갱신 실패${RESET}"
  fi
  echo ""
fi

case "$TARGET" in
  claude|codex) run_target "$TARGET" ;;
  both)
    run_target claude
    run_target codex
    ;;
esac

echo -e "${BOLD}━━━ 결과 ━━━${RESET}"
echo -e "  ${GREEN}성공: $OK${RESET}  ${RED}실패: $FAIL${RESET}  ${YELLOW}스킵: $SKIP${RESET}"
if [[ ${#OK_NAMES[@]} -gt 0 ]]; then
  echo -e "  ${GREEN}성공 목록:${RESET}"
  for n in "${OK_NAMES[@]}"; do echo -e "    ✔ $n"; done
fi
if [[ ${#FAIL_NAMES[@]} -gt 0 ]]; then
  echo -e "  ${RED}실패 목록:${RESET}"
  for n in "${FAIL_NAMES[@]}"; do echo -e "    ✗ $n"; done
fi
if [[ ${#SKIP_NAMES[@]} -gt 0 ]]; then
  echo -e "  ${YELLOW}스킵 목록:${RESET}"
  for n in "${SKIP_NAMES[@]}"; do echo -e "    ⚠ $n"; done
fi

[[ $FAIL -eq 0 ]]
