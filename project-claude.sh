#!/usr/bin/env bash
# project-claude.sh
# -----------------------------------------------------------------------------
# Installs Claude Code assets for a specific project, based on selected presets.
#
# Usage:
#   project-claude.sh <project_path> <preset1> [preset2] ...
#
# Examples:
#   project-claude.sh /home/user/PROJECT/coin python fastapi postgres
#   project-claude.sh /home/user/PROJECT/stock python fastapi postgres redis
#   project-claude.sh /home/user/legacy-erp java springboot mybatis oracle maven
#   project-claude.sh /home/user/dashboard node svelte
#
# Presets are category-agnostic: the script searches lang/, framework/,
# database/, build/, workflow/, permissions/ in that order. If you need to see what's available:
#   project-claude.sh --list
#
# Idempotent: re-running updates the project's .claude/ to match the new
# preset selection. User-managed parts of CLAUDE.md outside the managed
# block are preserved.
# -----------------------------------------------------------------------------
set -euo pipefail

# ---- Locate dev-setting root ----
DEV_SETTING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSETS_DIR="$DEV_SETTING_DIR/assets"
TEMPLATES_DIR="$DEV_SETTING_DIR/templates"
export DEV_SETTING_DIR ASSETS_DIR TEMPLATES_DIR

# shellcheck source=lib/common.sh
source "$DEV_SETTING_DIR/lib/common.sh"

usage() {
  cat <<EOF
Usage:
  $0 <project_path> <preset1> [preset2] ...
  $0 --list

Options:
  --list            List all available presets and exit.
  --dry-run         Resolve presets and print the plan without writing.
  -h, --help        Show this help.

Example:
  $0 /home/user/PROJECT/coin python fastapi postgres
EOF
}

# ---- Flag handling ----
DRY_RUN=0
case "${1:-}" in
  --list)
    echo "Available presets:"
    list_presets
    exit 0
    ;;
  -h|--help|"")
    usage
    exit 0
    ;;
  --dry-run)
    DRY_RUN=1
    shift
    ;;
esac

if [[ $# -lt 2 ]]; then
  usage
  exit 1
fi

PROJECT_PATH="$1"
shift
PRESETS=("$@")

# ---- Validate project path ----
if [[ ! -d "$PROJECT_PATH" ]]; then
  log_error "Project directory does not exist: $PROJECT_PATH"
  exit 1
fi
PROJECT_PATH=$(cd "$PROJECT_PATH" && pwd)
PROJECT_NAME=$(basename "$PROJECT_PATH")
CLAUDE_DIR="$PROJECT_PATH/.claude"

log_info "Project     : $PROJECT_NAME"
log_info "Path        : $PROJECT_PATH"
log_info "Presets     : ${PRESETS[*]}"
[[ $DRY_RUN -eq 1 ]] && log_warn "DRY RUN — no files will be written."

# ---- Resolve all presets up front so we fail fast on typos ----
RESOLVED_FILES=()
for preset in "${PRESETS[@]}"; do
  if f=$(resolve_preset "$preset"); then
    RESOLVED_FILES+=("$f")
  else
    log_error "Unknown preset: '$preset'"
    echo "Run '$0 --list' to see available presets." >&2
    exit 1
  fi
done

# ---- Source presets in order (lang → framework → database → build) ----
# Note: we source in the order the user passed them; presets are additive
# via the += operator, so later presets can rely on earlier state.
reset_preset_vars
for f in "${RESOLVED_FILES[@]}"; do
  log_info "Loading     : $(basename "$(dirname "$f")")/$(basename "$f" .conf)"
  # shellcheck source=/dev/null
  source "$f"
done

# Dedupe everything and resolve agent/deny conflicts before applying.
dedupe_preset_arrays

# Windows 타깃이면 hook 명령을 wsl bash "..." 형태로 변환
if is_windows_path "$PROJECT_PATH"; then
  log_info "Windows path detected — wrapping hooks for WSL2 execution"
  wrap_hooks_for_windows "$PROJECT_PATH"
fi

# ---- Dry run: print plan and exit ----
if [[ $DRY_RUN -eq 1 ]]; then
  echo ""
  echo "=== Resolved plan ==="
  echo "Skills  (${#SKILLS[@]}): ${SKILLS[*]:-<none>}"
  echo "Agents  (${#AGENTS[@]}): ${AGENTS[*]:-<none>}"
  echo "Rules   (${#RULES[@]}): ${RULES[*]:-<none>}"
  echo "Deny    (${#DENY_AGENTS[@]}): ${DENY_AGENTS[*]:-<none>}"
  echo "Env     (${#ENV_VARS[@]}): ${ENV_VARS[*]:-<none>}"
  echo "PostEdit hooks: ${#POST_EDIT_HOOKS[@]}"
  echo "Stop hooks    : ${#STOP_HOOKS[@]}"
  echo "CLAUDE.md sections: ${#CLAUDE_MD_SECTIONS[@]}"
  echo "User-prompt hooks: ${#USER_PROMPT_SUBMIT_HOOKS[@]}"
  echo "Pre-tool-use hooks: ${#PRE_TOOL_USE_HOOKS[@]}"
  echo "Permissions allow: ${#HARNESS_PERMISSIONS_ALLOW[@]}"
  echo "Harness hook sources: ${#HARNESS_HOOK_SOURCES[@]}"
  echo "Harness flags: docs=${HARNESS_DOCS_TEMPLATES:-0} pre-commit=${HARNESS_PRE_COMMIT:-0} max-lines=${HARNESS_LINT_MAX_LINES:-0}"
  echo "VSCode ext (${#VSCODE_EXTENSIONS[@]}): ${VSCODE_EXTENSIONS[*]:-<none>}"
  echo "Plugins (${#PLUGINS[@]}): ${PLUGINS[*]:-<none>}  [markets: ${PLUGIN_MARKETPLACES[*]:-<none>}]"
  sync_preset_plugins "$PROJECT_PATH" 1
  exit 0
fi

# ---- Apply ----
mkdir -p "$CLAUDE_DIR"

log_info "Installing assets…"
install_skills "$CLAUDE_DIR"
install_agents "$CLAUDE_DIR"
install_rules  "$CLAUDE_DIR"

# Hermes — preset(workflow/hermes.conf)이 정의한 setup 을 설치 단계에서 호출.
# 반드시 install_skills 이후여야 스킬 인덱싱이 동작하고,
# dry-run 분기 이후여야 --dry-run 에서 파일이 생성되지 않는다.
if declare -f _hermes_setup >/dev/null 2>&1; then
  _hermes_setup "$PROJECT_PATH"
fi

# Harness — PDF 8~9쪽 강제 장치 (preset 이 설정한 플래그·배열에 따라 동작).
install_harness_hooks         "$PROJECT_PATH"
install_harness_pre_commit    "$PROJECT_PATH"
install_harness_docs_templates "$PROJECT_PATH"
install_harness_lint_configs  "$PROJECT_PATH"
install_harness_gc_workflows  "$PROJECT_PATH"
install_memory_symlink        "$PROJECT_PATH" || log_warn "메모리 심링크 이관 일부 실패 — 네이티브 보존됨, 재설치로 재시도"
install_harness_gitignore     "$PROJECT_PATH" "claude"

generate_settings_json  "$CLAUDE_DIR/settings.json"
generate_settings_local "$CLAUDE_DIR/settings.local.json"
generate_claude_md "$PROJECT_PATH/CLAUDE.md" "$PROJECT_NAME"
write_manifest "$CLAUDE_DIR/.dev-setting-manifest.json"

# ---- Save preset list for setup_update.sh ----
printf '%s\n' "${PRESETS[@]}" > "$CLAUDE_DIR/presets.lock"
log_info "Saved presets → .claude/presets.lock"

# ---- package.json 에 serena 스크립트 주입 (serena preset 선택 + Node 프로젝트만) ----
SERENA_SELECTED=0
for _preset in "${PRESETS[@]}"; do
  [[ "$_preset" == "serena" ]] && { SERENA_SELECTED=1; break; }
done
unset _preset
PKG_JSON="$PROJECT_PATH/package.json"
if [[ $SERENA_SELECTED -eq 1 && -f "$PKG_JSON" ]] && command -v python3 >/dev/null 2>&1; then
  SERENA_CMD="$DEV_SETTING_DIR/bin/serena-dash"
  python3 - "$PKG_JSON" "$SERENA_CMD" <<'PYEOF'
import json, sys
pkg_path, cmd = sys.argv[1], sys.argv[2]
with open(pkg_path) as f:
    pkg = json.load(f)
scripts = pkg.setdefault("scripts", {})
if scripts.get("serena") != cmd:
    scripts["serena"] = cmd
    with open(pkg_path, "w") as f:
        json.dump(pkg, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"  ✔ package.json scripts.serena 등록 완료")
else:
    print(f"  ✔ package.json scripts.serena 이미 최신")
PYEOF
  log_info "Serena dash shortcut → package.json"
fi

# 머신 로컬 레지스트리에 등록 (dry-run 제외, 중복 방지)
if [[ $DRY_RUN -eq 0 ]]; then
  REGISTRY="$DEV_SETTING_DIR/.installed-projects"
  touch "$REGISTRY"
  if ! grep -qxF "$PROJECT_PATH" "$REGISTRY"; then
    echo "$PROJECT_PATH" >> "$REGISTRY"
    log_info "Registered → .installed-projects"
  fi
fi

cat <<'EOF'

⚠️  Opus 4.7 사용 시 권장 설정
────────────────────────────────
Claude Code 에서 모델 선택이 "Auto" 로 되어 있으면
도메인 에이전트(planner=opus, code-reviewer=sonnet 등)가
동적으로 강등될 수 있습니다.

권장: Claude Code 에서 모델을 명시적으로 선택 (Opus 4.7 등 고정).
참고: 본 프로젝트 에이전트는 YAML frontmatter 의 model: 필드로 고정됨.
EOF

# ---- VSCode 익스텐션 설치 ----
if [[ ${#VSCODE_EXTENSIONS[@]} -gt 0 ]]; then
  log_info "Installing VSCode extensions…"
  if command -v code >/dev/null 2>&1; then
    for ext in "${VSCODE_EXTENSIONS[@]}"; do
      code --install-extension "$ext" 2>&1 | grep -v "^$" || true
      log_info "  extension → $ext"
    done
  else
    log_warn "'code' 명령어를 찾을 수 없습니다. VSCode Command Palette 에서 직접 설치하세요:"
    for ext in "${VSCODE_EXTENSIONS[@]}"; do
      log_warn "  ext install $ext"
    done
  fi
fi

# ---- Claude Code 플러그인 동기화 (preset 의 PLUGINS / PLUGIN_MARKETPLACES) ----
# 플러그인은 user scope(전역)에 설치된다 — 프로젝트별이 아니라 한 번 깔면 모든
# 프로젝트에서 동작한다. preset 선택이 곧 "이 플러그인을 쓰겠다"는 opt-in 이고,
# 선택 해제 시에는 다른 프로젝트도 안 쓰는 경우에 한해 전역에서 제거된다(refcount).
# 선택이 비어 있어도 이전 선택을 정리해야 하므로 항상 호출한다.
sync_preset_plugins "$PROJECT_PATH"

log_success "Done. Open Claude Code at: $PROJECT_PATH"
