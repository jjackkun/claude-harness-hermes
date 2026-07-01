#!/usr/bin/env bash
# setup.sh — 대화형 프로젝트 설정 UI (카테고리별 스텝 선택)
# 재실행 시 target별 presets.lock 을 읽어 이전 선택을 pre-select

set -euo pipefail

DEV_SETTING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TARGET="claude"
UPDATE_ALL=0

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
    --update-all)
      UPDATE_ALL=1
      shift
      ;;
    -h|--help)
      cat <<EOF
Usage:
  $0 [--target claude|codex|both]
  $0 --update-all [--target claude|codex|both]

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

if [[ $UPDATE_ALL -eq 1 ]]; then
  exec bash "$DEV_SETTING_DIR/update-all.sh" --target "$TARGET"
fi

FZF="$DEV_SETTING_DIR/bin/fzf"

_fzf_version_ok() {
  local ver min="0.48.0"
  ver=$("$FZF" --version 2>/dev/null | awk '{print $1}')
  [[ -n "$ver" ]] && [[ "$(printf '%s\n' "$min" "$ver" | sort -V | head -1)" == "$min" ]]
}

if [[ ! -x "$FZF" ]] || ! _fzf_version_ok; then
  echo "⚙️  fzf not found 또는 버전 낮음 (0.48+ 필요) — 자동 설치 중..."
  bash "$DEV_SETTING_DIR/scripts/install-fzf.sh"
  if [[ ! -x "$FZF" ]]; then
    echo "❌ fzf 설치 실패. 수동으로 실행해주세요:"
    echo "   bash $DEV_SETTING_DIR/scripts/install-fzf.sh"
    exit 1
  fi
  echo ""
fi

# ── 색상 ──────────────────────────────────────────────────────────────────────
BOLD='\033[1m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RESET='\033[0m'

# ── 헤더 ──────────────────────────────────────────────────────────────────────
echo -e "${BOLD}${CYAN}━━━ AI 개발 환경 프로젝트 설정 (${TARGET}) ━━━${RESET}"
echo ""

# ── ai-dev-setting 플러그인 자동 등록 (머신 전역, idempotent) ────────────────
# 머신 단위로 한 번만 필요. 이미 설치돼 있으면 no-op.
# directory-type marketplace 라 source 경로를 직접 바라보므로 agents/*.md 수정은
# 재설치 없이 Claude Code 재시작만으로 반영됨.
if [[ "$TARGET" == "claude" || "$TARGET" == "both" ]] && command -v claude >/dev/null 2>&1; then
  if ! claude plugin list 2>/dev/null | grep -q "ai-dev-setting@ai-dev-setting"; then
    echo -e "${YELLOW}▸ ai-dev-setting 플러그인 등록 중...${RESET}"
    claude plugin marketplace add "$DEV_SETTING_DIR" >/dev/null 2>&1 \
      || echo -e "  ${YELLOW}⚠ marketplace 등록 실패 (이미 등록된 경우 무시 가능)${RESET}"
    if claude plugin install ai-dev-setting@ai-dev-setting --scope user >/dev/null 2>&1; then
      echo -e "  ${GREEN}✔ 등록 완료${RESET} (Claude Code 재시작 후 에이전트 사용 가능)"
    else
      echo -e "  ${YELLOW}⚠ 자동 등록 실패 — 수동 실행 필요:${RESET}"
      echo -e "    claude plugin marketplace add $DEV_SETTING_DIR"
      echo -e "    claude plugin install ai-dev-setting@ai-dev-setting --scope user"
    fi
    echo ""
  fi

  # ── 공식 플러그인 4종 자동 설치 (머신 전역, idempotent) ──────────────────
  # uv: Serena MCP 서버 구동에 필요한 Python 패키지 관리자
  if ! command -v uv >/dev/null 2>&1; then
    echo -e "${YELLOW}▸ uv 설치 중 (Serena MCP 필요)...${RESET}"
    if curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null 2>&1; then
      # 설치 직후 현재 셸에 PATH 반영 (uv 기본 설치 위치: ~/.local/bin)
      export PATH="$HOME/.local/bin:$PATH"
      echo -e "  ${GREEN}✔ uv 설치 완료${RESET}"
    else
      echo -e "  ${YELLOW}⚠ uv 설치 실패 — Serena MCP 가 동작하지 않을 수 있습니다${RESET}"
      echo -e "  ${YELLOW}  수동 설치: curl -LsSf https://astral.sh/uv/install.sh | sh${RESET}"
    fi
    echo ""
  fi

  _INSTALLED_PLUGINS=$(claude plugin list 2>/dev/null || true)
  _install_plugin() {
    local id="$1" label="$2"
    if echo "$_INSTALLED_PLUGINS" | grep -q "$id"; then
      return 0
    fi
    echo -e "${YELLOW}▸ $label 플러그인 설치 중...${RESET}"
    if claude plugin install "$id" --scope user >/dev/null 2>&1; then
      echo -e "  ${GREEN}✔ $label 설치 완료${RESET}"
    else
      echo -e "  ${YELLOW}⚠ $label 설치 실패 — 수동: claude plugin install $id --scope user${RESET}"
    fi
  }
  _install_plugin "session-report@claude-plugins-official"      "Session Report"
  _install_plugin "claude-md-management@claude-plugins-official" "Claude MD Management"
  _install_plugin "hookify@claude-plugins-official"              "Hookify"
  _install_plugin "serena@claude-plugins-official"               "Serena MCP"
  unset _INSTALLED_PLUGINS _install_plugin
  echo ""
fi

# ── Codex: Serena MCP 서버 등록 (머신 전역, idempotent) ────────────────────
if [[ "$TARGET" == "codex" || "$TARGET" == "both" ]]; then
  # uv: Serena 실행에 필요
  if ! command -v uv >/dev/null 2>&1; then
    echo -e "${YELLOW}▸ uv 설치 중 (Serena MCP 필요)...${RESET}"
    if curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null 2>&1; then
      # 설치 직후 현재 셸에 PATH 반영 (uv 기본 설치 위치: ~/.local/bin)
      export PATH="$HOME/.local/bin:$PATH"
      echo -e "  ${GREEN}✔ uv 설치 완료${RESET}"
    else
      echo -e "  ${YELLOW}⚠ uv 설치 실패 — Serena MCP 가 동작하지 않을 수 있습니다${RESET}"
      echo -e "  ${YELLOW}  수동 설치: curl -LsSf https://astral.sh/uv/install.sh | sh${RESET}"
    fi
    echo ""
  fi

  # serena 설치
  if ! command -v serena >/dev/null 2>&1; then
    echo -e "${YELLOW}▸ Serena 설치 중...${RESET}"
    if uv tool install -p 3.13 serena-agent@latest --prerelease=allow >/dev/null 2>&1; then
      echo -e "  ${GREEN}✔ Serena 설치 완료${RESET}"
    else
      echo -e "  ${YELLOW}⚠ Serena 설치 실패 — 수동: uv tool install -p 3.13 serena-agent@latest --prerelease=allow${RESET}"
    fi
    echo ""
  fi

  # ~/.codex/config.toml 에 MCP 서버 등록 (이미 있으면 skip)
  _CODEX_CONFIG="$HOME/.codex/config.toml"
  if ! grep -q '\[mcp_servers.serena\]' "$_CODEX_CONFIG" 2>/dev/null; then
    echo -e "${YELLOW}▸ Codex config.toml 에 Serena MCP 등록 중...${RESET}"
    mkdir -p "$HOME/.codex"
    cat >> "$_CODEX_CONFIG" <<'TOML'

[mcp_servers.serena]
startup_timeout_sec = 15
command = "serena"
args = ["start-mcp-server", "--project-from-cwd", "--context=codex"]
TOML
    echo -e "  ${GREEN}✔ Serena MCP 등록 완료${RESET} (~/.codex/config.toml)"
    echo ""
  fi
  unset _CODEX_CONFIG
fi

# ── 프로젝트 경로 입력 ────────────────────────────────────────────────────────
read -rp "$(echo -e "${BOLD}프로젝트 경로${RESET} (Enter = 현재 폴더): ")" PROJECT_PATH
PROJECT_PATH="${PROJECT_PATH:-$(pwd)}"
PROJECT_PATH="${PROJECT_PATH/#\~/$HOME}"
ORIG_DIR="$(pwd)"
PROJECT_PATH="$(cd "$ORIG_DIR" && cd "$PROJECT_PATH" 2>/dev/null && pwd)" || {
  echo "❌ 존재하지 않는 경로입니다."
  exit 1
}
echo -e "  → ${GREEN}${PROJECT_PATH}${RESET}"
echo ""

# ── presets.lock 읽기 ─────────────────────────────────────────────────────────
case "$TARGET" in
  codex) LOCK_FILE="$PROJECT_PATH/.codex/presets.lock" ;;
  *) LOCK_FILE="$PROJECT_PATH/.claude/presets.lock" ;;
esac
declare -A PREV_PRESETS=()
if [[ -f "$LOCK_FILE" ]]; then
  echo -e "  ${YELLOW}이전 설정 감지 — 기존 선택이 체크되어 있습니다.${RESET}"
  echo ""
  while IFS= read -r line; do
    [[ -n "$line" ]] && PREV_PRESETS["$line"]=1
  done < "$LOCK_FILE"
fi

# ── 전역(global) opt-in 스킬 선택 ─────────────────────────────────────────────
# 프로젝트와 무관하게 ~/.claude 에 한 번 설치되어 모든 프로젝트에서 쓰이는 스킬.
# presets/global/*.conf 를 후보로 띄우고, 선택분을 presets.global.lock 에 기록 +
# public-claude.sh --skills-only 로 즉시 설치한다. update-all 에도 유지된다.
# Claude 타깃에서만 노출 (전역 스킬은 ~/.claude/skills 대상).
if [[ "$TARGET" == "claude" || "$TARGET" == "both" ]] \
   && [[ -d "$DEV_SETTING_DIR/presets/global" ]] \
   && compgen -G "$DEV_SETTING_DIR/presets/global/*.conf" >/dev/null; then

  GLOBAL_CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  GLOBAL_LOCK="$GLOBAL_CLAUDE_DIR/presets.global.lock"

  declare -A PREV_GLOBAL=()
  if [[ -f "$GLOBAL_LOCK" ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] && PREV_GLOBAL["$line"]=1
    done < "$GLOBAL_LOCK"
  fi

  GLOBAL_ITEMS=()
  for f in "$DEV_SETTING_DIR/presets/global/"*.conf; do
    [[ -f "$f" ]] || continue
    GLOBAL_ITEMS+=("$(basename "$f" .conf)")
  done

  g_start="pos(1)"; g_idx=0
  for item in "${GLOBAL_ITEMS[@]}"; do
    g_idx=$((g_idx + 1))
    [[ -n "${PREV_GLOBAL[$item]:-}" ]] && g_start="${g_start}+pos(${g_idx})+select"
  done
  g_start="${g_start}+pos(1)"

  g_chosen=$(
    printf '%s\n' "${GLOBAL_ITEMS[@]}" \
    | "$FZF" \
        --multi --ansi --sync \
        --height="$((${#GLOBAL_ITEMS[@]} + 4))" \
        --header="[global]  모든 프로젝트 공통 설치  Tab=토글  Enter=확정  ESC=건너뜀" \
        --prompt="  > " \
        --bind "start:${g_start}" \
        --bind 'enter:transform:[[ $FZF_SELECT_COUNT -gt 0 ]] && echo accept || echo abort' \
        2>/dev/tty
  ) || true

  if [[ -n "$g_chosen" ]]; then
    GLOBAL_SELECTED="$(echo "$g_chosen" | tr '\n' ' ')"
    echo -e "  ${BOLD}전역 설치:${RESET} ${CYAN}${GLOBAL_SELECTED}${RESET}"
    bash "$DEV_SETTING_DIR/public-claude.sh" --skills-only --set-global "$GLOBAL_SELECTED"
    echo ""
  else
    echo -e "  ${YELLOW}[global] 변경 없음 (건너뜀)${RESET}"
    echo ""
  fi
  unset PREV_GLOBAL
fi

# ── 카테고리별 선택 ───────────────────────────────────────────────────────────
SELECTED_PRESETS=()

for category in lang framework database build workflow permissions tools; do
  dir="$DEV_SETTING_DIR/presets/$category"
  [[ -d "$dir" ]] || continue

  ITEMS=()
  for f in "$dir"/*.conf; do
    [[ -f "$f" ]] || continue
    ITEMS+=("$(basename "$f" .conf)")
  done
  [[ ${#ITEMS[@]} -eq 0 ]] && continue

  # 이전에 선택된 항목들의 1-indexed 위치 계산
  # start:pos(N)+select 를 체이닝하여 초기 선택 상태 복원
  start_chain="pos(1)"
  idx=0
  for item in "${ITEMS[@]}"; do
    idx=$((idx + 1))
    if [[ -n "${PREV_PRESETS[$item]:-}" ]]; then
      start_chain="${start_chain}+pos(${idx})+select"
    fi
  done
  start_chain="${start_chain}+pos(1)"

  chosen=$(
    printf '%s\n' "${ITEMS[@]}" \
    | "$FZF" \
        --multi \
        --ansi \
        --sync \
        --height="$((${#ITEMS[@]} + 4))" \
        --header="[$category]  Tab=토글  Enter=확정  ESC=skip" \
        --prompt="  > " \
        --bind "start:${start_chain}" \
        --bind 'enter:transform:[[ $FZF_SELECT_COUNT -gt 0 ]] && echo accept || echo abort' \
        2>/dev/tty
  ) || true   # ESC = 빈 결과, 에러 아님

  while IFS= read -r name; do
    [[ -n "$name" ]] && SELECTED_PRESETS+=("$name")
  done <<< "$chosen"
done

# ── 선택 결과 확인 ────────────────────────────────────────────────────────────
if [[ ${#SELECTED_PRESETS[@]} -eq 0 ]]; then
  echo "선택된 프리셋이 없습니다. 취소합니다."
  exit 0
fi

PRESETS_ARGS="${SELECTED_PRESETS[*]}"

echo -e "${BOLD}선택된 preset:${RESET} ${CYAN}${PRESETS_ARGS}${RESET}"
echo ""
echo -e "${BOLD}실행할 명령:${RESET}"
case "$TARGET" in
  claude)
    echo -e "  ${CYAN}project-claude.sh $(basename "$PROJECT_PATH") $PRESETS_ARGS${RESET}"
    ;;
  codex)
    echo -e "  ${CYAN}project-codex.sh $(basename "$PROJECT_PATH") $PRESETS_ARGS${RESET}"
    ;;
  both)
    echo -e "  ${CYAN}project-claude.sh $(basename "$PROJECT_PATH") $PRESETS_ARGS${RESET}"
    echo -e "  ${CYAN}project-codex.sh  $(basename "$PROJECT_PATH") $PRESETS_ARGS${RESET}"
    ;;
esac
echo ""

read -rp "진행할까요? (y/N): " confirm
if [[ "${confirm,,}" != "y" ]]; then
  echo "취소합니다."
  exit 0
fi

# ── 실행 ──────────────────────────────────────────────────────────────────────
echo ""
# shellcheck disable=SC2086
case "$TARGET" in
  claude)
    bash "$DEV_SETTING_DIR/project-claude.sh" "$PROJECT_PATH" $PRESETS_ARGS
    ;;
  codex)
    bash "$DEV_SETTING_DIR/project-codex.sh" "$PROJECT_PATH" $PRESETS_ARGS
    ;;
  both)
    bash "$DEV_SETTING_DIR/project-claude.sh" "$PROJECT_PATH" $PRESETS_ARGS
    bash "$DEV_SETTING_DIR/project-codex.sh" "$PROJECT_PATH" $PRESETS_ARGS
    ;;
esac
