#!/usr/bin/env bash
# public-claude.sh
# -----------------------------------------------------------------------------
# Installs the common Claude Code assets (shared across every project) into
# the target user's Claude config directory.
#
# The Claude config dir is auto-detected (see lib/common.sh::detect_claude_config_dir):
#   1. $CLAUDE_CONFIG_DIR (use 'sudo -E' to preserve)
#   2. ~/.claude  →  ~/.config/claude  →  ~/.config/claude-code  →  macOS path
#   3. Falls back to ~/.claude (will be created)
#
# Usage:
#   sudo -E bash public-claude.sh             # install for $SUDO_USER, keep env
#   sudo bash public-claude.sh                # install for $SUDO_USER
#   sudo bash public-claude.sh <user>         # install for a specific user
#   bash public-claude.sh                     # install for the current user
#   CLAUDE_CONFIG_DIR=/custom bash public-claude.sh
#
# Idempotent: safe to re-run. Does NOT overwrite settings.json (user-managed),
# only creates/refreshes agents/, skills/, rules/ and adds a CLAUDE.md stub
# if none exists.
# -----------------------------------------------------------------------------
set -euo pipefail

# ---- Locate dev-setting root regardless of cwd ----
DEV_SETTING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSETS_DIR="$DEV_SETTING_DIR/assets"
TEMPLATES_DIR="$DEV_SETTING_DIR/templates"
export DEV_SETTING_DIR ASSETS_DIR TEMPLATES_DIR

# shellcheck source=lib/common.sh
source "$DEV_SETTING_DIR/lib/common.sh"

# ---- Parse flags (order-independent) ----
# --skills-only        : refresh global skills only (skip uv/plugin install). Fast path
#                        used by setup.sh's [global] step.
# --set-global "<names>": overwrite presets.global.lock with these global-preset names
#                        (space-separated; "" clears) before installing. Omit to keep
#                        the existing lock (update-all path).
SKILLS_ONLY=0
SET_GLOBAL=""
SET_GLOBAL_GIVEN=0
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skills-only) SKILLS_ONLY=1; shift ;;
    --set-global) SET_GLOBAL="${2:-}"; SET_GLOBAL_GIVEN=1; shift 2 ;;
    --set-global=*) SET_GLOBAL="${1#--set-global=}"; SET_GLOBAL_GIVEN=1; shift ;;
    *) POSITIONAL+=("$1"); shift ;;
  esac
done
set -- "${POSITIONAL[@]+"${POSITIONAL[@]}"}"

# ---- Resolve target user ----
if [[ $# -ge 1 && -n "${1:-}" ]]; then
  TARGET_USER="$1"
elif [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
  TARGET_USER="$SUDO_USER"
else
  TARGET_USER="$(id -un)"
fi

TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6 || true)
if [[ -z "$TARGET_HOME" || ! -d "$TARGET_HOME" ]]; then
  log_error "Cannot resolve home directory for user: $TARGET_USER"
  exit 1
fi

# ---- Resolve Claude config dir for the target user ----
# When invoked with sudo, $CLAUDE_CONFIG_DIR comes from the caller's env
# (use `sudo -E` to preserve). Otherwise we probe well-known locations.
CLAUDE_DIR=$(detect_claude_config_dir "$TARGET_HOME")

log_info "Target user  : $TARGET_USER"
log_info "Target home  : $TARGET_HOME"
log_info "Claude config: $CLAUDE_DIR"
if [[ ! -d "$CLAUDE_DIR" ]]; then
  log_warn "Claude config dir does not exist yet — it will be created."
fi

mkdir -p "$CLAUDE_DIR"

# ---- Load common preset ----
reset_preset_vars
COMMON_CONF="$DEV_SETTING_DIR/presets/_common.conf"
if [[ ! -f "$COMMON_CONF" ]]; then
  log_error "Missing common preset: $COMMON_CONF"
  exit 1
fi
# shellcheck source=/dev/null
source "$COMMON_CONF"

# ---- Global opt-in skills (presets/global/*) via presets.global.lock ----
# The lock lists global-preset names (one per line) the user opted into through
# setup.sh's [global] step. We source each so its SKILLS join the install set;
# install_skills then keeps exactly (baseline ∪ opted-in) and cleans the rest,
# so the selection survives every update-all (which re-runs this script).
GLOBAL_LOCK="$CLAUDE_DIR/presets.global.lock"
if [[ $SET_GLOBAL_GIVEN -eq 1 ]]; then
  # Overwrite the lock from --set-global (one name per line; empty clears it).
  : > "$GLOBAL_LOCK"
  for _name in $SET_GLOBAL; do
    [[ -n "$_name" ]] && echo "$_name" >> "$GLOBAL_LOCK"
  done
fi
GLOBAL_PRESETS=()
if [[ -f "$GLOBAL_LOCK" ]]; then
  while IFS= read -r _name; do
    [[ -z "$_name" ]] && continue
    _gf="$DEV_SETTING_DIR/presets/global/$_name.conf"
    if [[ -f "$_gf" ]]; then
      # shellcheck source=/dev/null
      source "$_gf"
      GLOBAL_PRESETS+=("$_name")
    else
      log_warn "global preset missing (skipped): $_name"
    fi
  done < "$GLOBAL_LOCK"
fi
[[ ${#GLOBAL_PRESETS[@]} -gt 0 ]] && log_info "Global opt-in: ${GLOBAL_PRESETS[*]}"

if [[ $SKILLS_ONLY -eq 1 ]]; then
  log_info "Installing global skills (skills-only)…"
  install_skills "$CLAUDE_DIR"
  # Fix ownership if root-installing for another user, then stop here.
  if [[ $EUID -eq 0 && "$TARGET_USER" != "root" ]]; then
    chown -R "$TARGET_USER:$TARGET_USER" "$CLAUDE_DIR"
  fi
  log_success "Global skills refresh complete."
  exit 0
fi

log_info "Installing common assets…"
install_skills "$CLAUDE_DIR"
install_agents "$CLAUDE_DIR"
install_rules  "$CLAUDE_DIR"

# ---- Create a minimal ~/.claude/CLAUDE.md if none exists ----
# NOTE: we NEVER overwrite an existing user ~/.claude/CLAUDE.md or
# ~/.claude/settings.json. The user owns those.
GLOBAL_CLAUDE_MD="$CLAUDE_DIR/CLAUDE.md"
if [[ ! -f "$GLOBAL_CLAUDE_MD" ]]; then
  if [[ -f "$TEMPLATES_DIR/global-claude.md.tpl" ]]; then
    cp "$TEMPLATES_DIR/global-claude.md.tpl" "$GLOBAL_CLAUDE_MD"
    log_info "  stub    → $GLOBAL_CLAUDE_MD"
  fi
fi

# ---- Fix ownership if we ran as root for another user ----
if [[ $EUID -eq 0 && "$TARGET_USER" != "root" ]]; then
  chown -R "$TARGET_USER:$TARGET_USER" "$CLAUDE_DIR"
  log_info "Restored ownership to $TARGET_USER"
fi

log_success "Common install complete."

# ---- target user 기준 실행 헬퍼 ----
# sudo 로 실행됐을 때 uv / claude plugin 설치가 root 홈(~root)에 들어가는 것을 방지.
# root 이고 대상 사용자가 따로 있으면 sudo -u 로 강등해 실행한다.
_run_as_target() {
  if [[ $EUID -eq 0 && "$TARGET_USER" != "root" ]]; then
    sudo -u "$TARGET_USER" -H \
      env PATH="$TARGET_HOME/.local/bin:$TARGET_HOME/.cargo/bin:$PATH" \
      bash -c "$*"
  else
    bash -c "$*"
  fi
}

# ---- uv 자동 설치 (Serena MCP 의존성, $TARGET_USER 홈 기준) ----
if ! _run_as_target 'command -v uv >/dev/null 2>&1'; then
  echo ""
  log_info "uv not found — installing for $TARGET_USER (Serena MCP requires uv)…"
  if _run_as_target 'curl -LsSf https://astral.sh/uv/install.sh | sh' >/dev/null 2>&1; then
    # 설치 후 현재 셸 PATH 반영 (target user 홈 기준)
    export PATH="$TARGET_HOME/.local/bin:$TARGET_HOME/.cargo/bin:$PATH"
    if _run_as_target 'command -v uv >/dev/null 2>&1'; then
      log_success "uv installed: $(_run_as_target 'uv --version')"
    else
      log_warn "uv installed but not in PATH — open a new shell or add ~/.local/bin to PATH"
    fi
  else
    log_warn "uv install failed — Serena MCP may not work. Install manually: https://astral.sh/uv"
  fi
else
  log_info "uv already installed: $(_run_as_target 'uv --version')"
fi

# ---- Claude Code 공식 플러그인 자동 설치 ($TARGET_USER 스코프) ----
# 설치된 플러그인 목록 캐시 (매번 조회 방지)
if _run_as_target 'command -v claude >/dev/null 2>&1'; then
  echo ""
  log_info "Installing Claude Code plugins…"
  _INSTALLED=$(_run_as_target 'claude plugin list' 2>/dev/null || true)

  _install_plugin() {
    local id="$1" label="$2"
    if echo "$_INSTALLED" | grep -q "^  ❯ ${id}"; then
      log_info "  plugin  → $label (already installed)"
    else
      if _run_as_target "claude plugin install '$id' --scope user" >/dev/null 2>&1; then
        log_success "  plugin  → $label"
      else
        log_warn "  plugin  → $label (install failed — try manually: claude plugin install $id --scope user)"
      fi
    fi
  }

  _install_plugin "session-report@claude-plugins-official"    "Session Report"
  _install_plugin "claude-md-management@claude-plugins-official" "Claude MD Management"
  _install_plugin "hookify@claude-plugins-official"           "Hookify"
  _install_plugin "serena@claude-plugins-official"            "Serena MCP"
else
  log_warn "claude CLI not found — skipping plugin install. Re-run after installing Claude Code."
fi

# ---- Serena 대시보드 자동 탭 열림 끄기 (설치 시 1회, idempotent) ----
# Serena 는 실행될 때마다 web_dashboard_open_on_launch 기본값(true)에 따라 브라우저 탭을
# 새로 연다. MCP 재기동마다 탭이 누적되므로 설치 시점에 false 로 고정한다.
# 대시보드 서버 자체(web_dashboard: true)는 유지되어 수동 접속은 계속 가능하다.
_SERENA_CFG="$TARGET_HOME/.serena/serena_config.yml"
_SERENA_KEY="web_dashboard_open_on_launch"
if [[ -f "$_SERENA_CFG" ]]; then
  if grep -qE "^${_SERENA_KEY}:" "$_SERENA_CFG"; then
    sed -i -E "s/^${_SERENA_KEY}:.*/${_SERENA_KEY}: false/" "$_SERENA_CFG"
    log_success "  serena  → 대시보드 자동 탭 열림 비활성화 (기존 설정 수정)"
  else
    printf '\n%s: false\n' "$_SERENA_KEY" >> "$_SERENA_CFG"
    log_success "  serena  → 대시보드 자동 탭 열림 비활성화 (키 추가)"
  fi
else
  # 파일 부재(첫 설치) — Serena from_config_file 은 `projects` 키가 없으면 실패하므로
  # 부분 stub 대신 최소 유효 설정을 생성한다. 나머지 필드는 Serena 가 기본값으로 머지한다.
  mkdir -p "$(dirname "$_SERENA_CFG")"
  cat > "$_SERENA_CFG" <<'YAML'
# Serena 전역 설정 — harness 최소 기본값. Serena 가 첫 실행 시 나머지 필드를 기본값으로 채운다.
projects: []
web_dashboard_open_on_launch: false
YAML
  log_success "  serena  → 대시보드 자동 탭 열림 비활성화 (최소 설정 생성)"
fi
# root 로 실행됐다면 소유권을 타깃 유저로 복구
if [[ $EUID -eq 0 && "$TARGET_USER" != "root" ]]; then
  chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.serena"
fi

echo ""
echo "Next step: set up a project with"
echo "  $DEV_SETTING_DIR/project-claude.sh <project_path> <preset1> [preset2] ..."
echo ""
echo "Example:"
echo "  $DEV_SETTING_DIR/project-claude.sh /home/$TARGET_USER/PROJECT/coin python fastapi postgres"
