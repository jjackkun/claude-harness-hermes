#!/usr/bin/env bash
# uninstall.sh — ai-dev-setting 프로젝트 언인스톨
#
# Usage:
#   bash uninstall.sh                    # fzf 멀티선택
#   bash uninstall.sh /path/to/project   # 직접 경로 지정 (상대경로/~ 허용)
#   bash uninstall.sh --dry-run          # 삭제 예정 항목만 출력 (실제 삭제 없음)
#   bash uninstall.sh --dry-run /path    # 특정 경로 dry-run

set -euo pipefail

DEV_SETTING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FZF="$DEV_SETTING_DIR/bin/fzf"
REGISTRY="$DEV_SETTING_DIR/.installed-projects"

BOLD='\033[1m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
RESET='\033[0m'

DRY_RUN=0
TARGET_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help)
      cat <<EOF
Usage:
  $0 [--dry-run] [/path/to/project]
EOF
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
    *)
      if [[ -n "$TARGET_PATH" ]]; then
        echo "경로는 하나만 지정할 수 있습니다: $1" >&2
        exit 1
      fi
      # 상대경로 / ~ 허용 → realpath 로 정규화
      TARGET_PATH="${1/#\~/$HOME}"
      shift
      ;;
  esac
done

# shellcheck source=lib/uninstall_helpers.sh
source "$DEV_SETTING_DIR/lib/uninstall_helpers.sh"

# ── 삭제 대상 선택 ────────────────────────────────────────────────────────────
declare -a TARGETS=()

if [[ -n "$TARGET_PATH" ]]; then
  TARGET_PATH="$(realpath -e "$TARGET_PATH" 2>/dev/null)" || {
    echo "❌ 존재하지 않는 경로: $TARGET_PATH" >&2
    exit 1
  }
  TARGETS=("$TARGET_PATH")
else
  if [[ ! -f "$REGISTRY" ]] || [[ ! -s "$REGISTRY" ]]; then
    echo "등록된 프로젝트가 없습니다."
    exit 0
  fi

  _fzf_version_ok() {
    local ver min="0.48.0"
    ver=$("$FZF" --version 2>/dev/null | awk '{print $1}')
    [[ -n "$ver" ]] && [[ "$(printf '%s\n' "$min" "$ver" | sort -V | head -1)" == "$min" ]]
  }

  if [[ ! -x "$FZF" ]] || ! _fzf_version_ok; then
    echo "⚙️  fzf 설치 중..."
    bash "$DEV_SETTING_DIR/scripts/install-fzf.sh"
  fi

  chosen=$(
    grep -v '^#' "$REGISTRY" | grep -v '^$' \
    | "$FZF" \
        --multi \
        --ansi \
        --header="언인스톨할 프로젝트 선택  Tab=토글  Enter=확정  ESC=취소" \
        --prompt="  > " \
        2>/dev/tty
  ) || true

  [[ -z "$chosen" ]] && { echo "취소합니다."; exit 0; }

  while IFS= read -r line; do
    [[ -n "$line" ]] && TARGETS+=("$line")
  done <<< "$chosen"
fi

[[ ${#TARGETS[@]} -eq 0 ]] && { echo "선택된 프로젝트가 없습니다."; exit 0; }

# ── 언인스톨 함수 ─────────────────────────────────────────────────────────────
do_uninstall() {
  local project_path="$1"
  local remove_hermes="${2:-0}"

  echo -e "${BOLD}▸ $(basename "$project_path")${RESET}  ($project_path)"

  # 1. .gitignore 마커 블록
  local gitignore="$project_path/.gitignore"
  if [[ -f "$gitignore" ]] && grep -qxF "# >>> harness-agent-preset >>>" "$gitignore"; then
    if [[ $DRY_RUN -eq 1 ]]; then
      echo -e "  ${YELLOW}[dry]${RESET} .gitignore 하네스 블록 제거"
    else
      _remove_marker_block "$gitignore" "# >>> harness-agent-preset >>>" "# <<< harness-agent-preset <<<"
      echo -e "  ${GREEN}✔${RESET} .gitignore 하네스 블록 제거"
    fi
  fi

  # 2. CLAUDE.md 관리 블록
  local claude_md="$project_path/CLAUDE.md"
  if [[ -f "$claude_md" ]] && grep -qxF "<!--===DS:BEGIN===-->" "$claude_md"; then
    if [[ $DRY_RUN -eq 1 ]]; then
      echo -e "  ${YELLOW}[dry]${RESET} CLAUDE.md 관리 블록 제거"
    else
      _remove_marker_block "$claude_md" "<!--===DS:BEGIN===-->" "<!--===DS:END===-->"
      echo -e "  ${GREEN}✔${RESET} CLAUDE.md 관리 블록 제거"
    fi
  fi

  # 3. .claude/settings.json — 하네스 hooks 항목만 제거 (사용자 항목 보존)
  uninstall_settings_hooks "$project_path"

  # 4. .claude/ 관리 파일들
  local claude_files=(
    "$project_path/.claude/settings.local.json"
    "$project_path/.claude/presets.lock"
    "$project_path/.claude/.dev-setting-manifest.json"
    "$project_path/.claude/.review-dirty"
  )
  local f
  for f in "${claude_files[@]}"; do
    _rm_path file "$f" "${f#$project_path/}"
  done

  # 5. .claude/{skills,agents,rules} 하네스 symlink (사용자 실파일 보존)
  uninstall_asset_symlinks "$project_path"

  # 6. scripts/hooks/ — assets/hooks/ 에 있는 파일만 제거
  local hooks_dir="$project_path/scripts/hooks"
  if [[ -d "$hooks_dir" ]]; then
    local hook_name
    while IFS= read -r hook_name; do
      _rm_path file "$hooks_dir/$hook_name" "scripts/hooks/$hook_name"
    done < <(_known_hooks)
    # scripts/hooks/ 가 비었으면 디렉토리도 제거
    if [[ $DRY_RUN -eq 0 ]] && [[ -d "$hooks_dir" ]]; then
      local remaining
      remaining=$(find "$hooks_dir" -maxdepth 1 -mindepth 1 2>/dev/null | wc -l)
      if [[ $remaining -eq 0 ]]; then
        rmdir "$hooks_dir"
        echo -e "  ${GREEN}✔${RESET} 삭제: scripts/hooks/ (비어있어 제거)"
      fi
    fi
  fi

  # 7. .git/hooks/pre-commit (마커 확인) + check-component-structure.mjs
  uninstall_pre_commit "$project_path"

  # 8. lint-configs/harness-*.config.js
  uninstall_lint_configs "$project_path"

  # 9. GC 워크플로 (weekly-doc-gardening)
  uninstall_gc_workflows "$project_path"

  # 10. package.json scripts.serena
  uninstall_pkg_serena "$project_path"

  # 11. scripts/hermes-*.py + hermes_loop*.py + hermes-*-run.sh
  local scripts_dir="$project_path/scripts"
  if [[ -d "$scripts_dir" ]]; then
    local hermes_scripts
    mapfile -t hermes_scripts < <(find "$scripts_dir" -maxdepth 1 \( -name "hermes-*.py" -o -name "hermes-cron-run.sh" -o -name "hermes-loop-run.sh" -o -name "hermes_loop.py" -o -name "hermes_loop_prompt.py" -o -name "hermes_loop_report.py" \) 2>/dev/null)
    for f in "${hermes_scripts[@]}"; do
      _rm_path file "$f" "scripts/$(basename "$f")"
    done
  fi

  # 12. Codex 설치물 (.codex/, AGENTS.md 블록, codex-hooks, 레지스트리 등)
  uninstall_codex "$project_path"

  # 12-1. scripts/ 가 완전히 비었으면 디렉토리 제거
  if [[ $DRY_RUN -eq 0 && -d "$scripts_dir" ]] && [[ -z "$(ls -A "$scripts_dir" 2>/dev/null)" ]]; then
    rmdir "$scripts_dir"
    echo -e "  ${GREEN}✔${RESET} 삭제: scripts/ (비어있어 제거)"
  fi

  # 13. .hermes/
  local hermes_dir="$project_path/.hermes"
  if [[ -d "$hermes_dir" ]]; then
    if [[ $remove_hermes -eq 1 ]]; then
      _rm_path dir "$hermes_dir" ".hermes/ (DB 포함)"
    else
      echo -e "  ${YELLOW}⚠${RESET}  .hermes/ 는 유지됩니다 (수동 삭제: rm -rf $hermes_dir)"
    fi
  fi

  # 14. 레지스트리에서 제거
  if [[ $DRY_RUN -eq 0 ]]; then
    _remove_registry_entry "$REGISTRY" "$project_path"
    echo -e "  ${GREEN}✔${RESET} .installed-projects 에서 제거"
  else
    echo -e "  ${YELLOW}[dry]${RESET} .installed-projects 에서 제거"
  fi

  echo ""
}

# ── 실행 ──────────────────────────────────────────────────────────────────────
echo -e "${BOLD}${CYAN}━━━ ai-dev-setting 언인스톨$([ $DRY_RUN -eq 1 ] && echo " (dry-run)") ━━━${RESET}"
echo ""

# 각 프로젝트 미리보기
for path in "${TARGETS[@]}"; do
  echo -e "${BOLD}삭제 예정: $(basename "$path")${RESET}  ($path)"
  [[ -f "$path/.gitignore" ]] && grep -qxF "# >>> harness-agent-preset >>>" "$path/.gitignore" \
    && echo "  • .gitignore 하네스 블록"
  [[ -f "$path/CLAUDE.md" ]] && grep -qxF "<!--===DS:BEGIN===-->" "$path/CLAUDE.md" \
    && echo "  • CLAUDE.md 관리 블록"
  [[ -f "$path/AGENTS.md" ]] && grep -qxF "<!--===DS-CODEX:BEGIN===-->" "$path/AGENTS.md" \
    && echo "  • AGENTS.md 관리 블록 (Codex)"
  [[ -f "$path/.claude/settings.json" ]] && echo "  • .claude/settings.json 하네스 hooks 항목"
  for f in settings.local.json presets.lock .dev-setting-manifest.json .review-dirty; do
    [[ -f "$path/.claude/$f" ]] && echo "  • .claude/$f"
  done
  for d in skills agents rules; do
    [[ -d "$path/.claude/$d" ]] && echo "  • .claude/$d/ 하네스 symlink"
  done
  if [[ -d "$path/scripts/hooks" ]]; then
    local_count=0
    while IFS= read -r hook_name; do
      [[ -f "$path/scripts/hooks/$hook_name" ]] && local_count=$((local_count+1))
    done < <(_known_hooks)
    [[ $local_count -gt 0 ]] && echo "  • scripts/hooks/ (${local_count}개 파일)"
  fi
  [[ -f "$path/.git/hooks/pre-commit" ]] && grep -qF "4단 검사" "$path/.git/hooks/pre-commit" \
    && echo "  • .git/hooks/pre-commit (하네스)"
  [[ -d "$path/lint-configs" ]] && compgen -G "$path/lint-configs/harness-*.config.js" >/dev/null \
    && echo "  • lint-configs/harness-*.config.js"
  [[ -f "$path/.github/workflows/weekly-doc-gardening.yml" ]] \
    && echo "  • .github/workflows/weekly-doc-gardening.yml"
  [[ -d "$path/.codex" ]] && echo "  • .codex/"
  [[ -d "$path/scripts/codex-hooks" ]] && echo "  • scripts/codex-hooks/"
  hermes_py_count=$(find "$path/scripts" -maxdepth 1 \( -name "hermes-*.py" -o -name "hermes-cron-run.sh" -o -name "hermes-loop-run.sh" -o -name "hermes_loop.py" -o -name "hermes_loop_prompt.py" -o -name "hermes_loop_report.py" \) 2>/dev/null | wc -l)
  [[ $hermes_py_count -gt 0 ]] && echo "  • scripts/hermes-* (${hermes_py_count}개)"
  [[ -d "$path/.hermes" ]] && echo -e "  ${YELLOW}• .hermes/ (DB 포함 — 별도 확인)${RESET}"
  echo ""
done

if [[ $DRY_RUN -eq 1 ]]; then
  echo -e "${YELLOW}dry-run 모드: 실제 삭제 없음${RESET}"
  for path in "${TARGETS[@]}"; do
    do_uninstall "$path" 0
  done
  exit 0
fi

# 실제 실행 확인
read -rp "$(echo -e "${BOLD}진행할까요?${RESET} (y/N): ")" confirm
[[ "${confirm,,}" != "y" ]] && { echo "취소합니다."; exit 0; }

# .hermes/ 삭제 여부 (한 번만 물어봄)
REMOVE_HERMES=0
for path in "${TARGETS[@]}"; do
  [[ -d "$path/.hermes" ]] && { HAS_HERMES=1; break; }
done
if [[ "${HAS_HERMES:-0}" -eq 1 ]]; then
  read -rp "$(echo -e "${YELLOW}.hermes/ (DB 포함)도 삭제할까요?${RESET} (y/N): ")" hermes_confirm
  [[ "${hermes_confirm,,}" == "y" ]] && REMOVE_HERMES=1
fi

echo ""

OK=0; FAIL=0
for path in "${TARGETS[@]}"; do
  if do_uninstall "$path" "$REMOVE_HERMES"; then
    OK=$((OK+1))
  else
    FAIL=$((FAIL+1))
  fi
done

echo -e "${BOLD}━━━ 결과 ━━━${RESET}"
echo -e "  ${GREEN}완료: $OK${RESET}  ${RED}실패: $FAIL${RESET}"
