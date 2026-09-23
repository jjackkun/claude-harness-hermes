#!/usr/bin/env bash
# project-codex.sh
# -----------------------------------------------------------------------------
# Installs Codex-native assets for a specific project, based on selected presets.
#
# Usage:
#   project-codex.sh <project_path> <preset1> [preset2] ...
#   project-codex.sh --list
#   project-codex.sh --dry-run <project_path> <preset1> [preset2] ...
# -----------------------------------------------------------------------------
set -euo pipefail

DEV_SETTING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSETS_DIR="$DEV_SETTING_DIR/assets"
TEMPLATES_DIR="$DEV_SETTING_DIR/templates"
export DEV_SETTING_DIR ASSETS_DIR TEMPLATES_DIR

# shellcheck source=lib/common.sh
source "$DEV_SETTING_DIR/lib/common.sh"
# shellcheck source=lib/codex_installers.sh
source "$DEV_SETTING_DIR/lib/codex_installers.sh"
# shellcheck source=lib/codex_settings_gen.sh
source "$DEV_SETTING_DIR/lib/codex_settings_gen.sh"
# shellcheck source=lib/codex_md_gen.sh
source "$DEV_SETTING_DIR/lib/codex_md_gen.sh"

usage() {
  cat <<EOF
Usage:
  $0 <project_path> <preset1> [preset2] ...
  $0 --list

Options:
  --list            List all available presets and exit.
  --dry-run         Resolve presets and print the Codex plan without writing.
  -h, --help        Show this help.

Example:
  $0 /home/user/PROJECT/app node svelte postgres harness
EOF
}

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

if [[ ! -d "$PROJECT_PATH" ]]; then
  log_error "Project directory does not exist: $PROJECT_PATH"
  exit 1
fi

PROJECT_PATH=$(cd "$PROJECT_PATH" && pwd)

# pyenv shim 우회 — 실행 폴더 기준(shim 과 같은 버전), 따지는 단계만 건너뛴다.
# 끄기: HARNESS_NO_PYENV_BYPASS=1. 근거: 2026-09-23 실측 셔임 112ms vs 실제 19ms.
declare -F harness_pyenv_bypass >/dev/null 2>&1 && harness_pyenv_bypass
# 우회가 만든 임시 폴더를 끝에 지운다 — 안 지우면 설치마다 /tmp 에 하나씩 쌓인다(2026-09-23 리뷰 지적).
# 이 프로세스가 만든 것만 지운다(harness_pyenv_cleanup 이 PID 로 가린다).
trap 'declare -F harness_pyenv_cleanup >/dev/null 2>&1 && harness_pyenv_cleanup' EXIT
PROJECT_NAME=$(basename "$PROJECT_PATH")
CODEX_DIR="$PROJECT_PATH/.codex"

log_info "Target      : Codex"
log_info "Project     : $PROJECT_NAME"
log_info "Path        : $PROJECT_PATH"
log_info "Presets     : ${PRESETS[*]}"
[[ $DRY_RUN -eq 1 ]] && log_warn "DRY RUN — no files will be written."

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

reset_preset_vars
for f in "${RESOLVED_FILES[@]}"; do
  log_info "Loading     : $(basename "$(dirname "$f")")/$(basename "$f" .conf)"
  # shellcheck source=/dev/null
  source "$f"
done

dedupe_preset_arrays

if [[ $DRY_RUN -eq 1 ]]; then
  echo ""
  echo "=== Resolved Codex plan ==="
  echo "Skills  (${#SKILLS[@]}): ${SKILLS[*]:-<none>}"
  echo "Agents  (${#AGENTS[@]}): ${AGENTS[*]:-<none>}"
  echo "Rules   (${#RULES[@]}): ${RULES[*]:-<none>}"
  echo "Env     (${#ENV_VARS[@]}): ${ENV_VARS[*]:-<none>}"
  echo "PostEdit commands: ${#POST_EDIT_HOOKS[@]}"
  echo "Stop commands    : ${#STOP_HOOKS[@]}"
  echo "AGENTS.md sections: ${#CLAUDE_MD_SECTIONS[@]}"
  echo "Codex hooks      : native scripts from assets/codex/hooks"
  exit 0
fi

if [[ -e "$CODEX_DIR" && ! -d "$CODEX_DIR" ]]; then
  log_error "$CODEX_DIR exists but is not a directory. Move or remove it before installing Codex assets."
  exit 1
fi

mkdir -p "$CODEX_DIR"

log_info "Installing Codex assets…"
install_skills "$CODEX_DIR"
install_agents "$CODEX_DIR"
install_rules "$CODEX_DIR"
install_codex_plugin_bundle "$PROJECT_PATH"
install_codex_marketplace "$PROJECT_PATH"
install_skills "$PROJECT_PATH/plugins/claude-harness-hermes"
install_agents "$PROJECT_PATH/plugins/claude-harness-hermes"
install_rules "$PROJECT_PATH/plugins/claude-harness-hermes"

install_codex_hooks "$PROJECT_PATH"
install_codex_scripts "$PROJECT_PATH"
install_harness_pre_commit "$PROJECT_PATH"
install_codex_harness_docs_templates "$PROJECT_PATH"
install_harness_lint_configs "$PROJECT_PATH"
install_harness_gc_workflows "$PROJECT_PATH"
install_harness_gitignore    "$PROJECT_PATH" "codex"

generate_codex_hooks_json "$CODEX_DIR/hooks.json" "$PROJECT_PATH"
cp "$CODEX_DIR/hooks.json" "$PROJECT_PATH/plugins/claude-harness-hermes/hooks.json"
generate_agents_md "$PROJECT_PATH/AGENTS.md" "$PROJECT_NAME"
write_codex_manifest "$CODEX_DIR/.dev-setting-manifest.json"

printf '%s\n' "${PRESETS[@]}" > "$CODEX_DIR/presets.lock"
log_info "Saved presets → .codex/presets.lock"

# 판정(임시 경로·HERMES_NO_REGISTER)은 lib/registry.sh — Claude 쪽과 같은 가드를 쓴다.
if [[ $DRY_RUN -eq 0 ]]; then
  registry_register "$DEV_SETTING_DIR/.installed-projects.codex" "$PROJECT_PATH" ".installed-projects.codex"
fi

log_success "Done. Open Codex at: $PROJECT_PATH"
