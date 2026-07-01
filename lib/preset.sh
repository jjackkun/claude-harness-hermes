#!/usr/bin/env bash
# dev-setting/lib/preset.sh
# Responsibility: preset 시스템 운영 — config 디렉터리 탐지, 전역 배열 초기화, 권한 머지,
# dedupe/충돌 해소, preset 파일 탐색·나열.

# ---------- Claude config dir detection ----------
# detect_claude_config_dir <user_home>
# Resolves the per-user Claude Code config directory using this priority:
#   1. $CLAUDE_CONFIG_DIR (explicit override; sudo callers must use -E)
#   2. Conventional directory that already exists under <user_home>:
#       - <user_home>/.claude
#       - $XDG_CONFIG_HOME/claude (or <user_home>/.config/claude)
#       - <user_home>/.config/claude-code
#       - macOS: <user_home>/Library/Application Support/Claude
#   3. Fallback: <user_home>/.claude (will be created)
#
# Validation marker: any of settings.json / projects/ / sessions/ inside the
# candidate is treated as confirmation that it really is a Claude config dir.
detect_claude_config_dir() {
  local user_home="$1"

  # 1) explicit override
  if [[ -n "${CLAUDE_CONFIG_DIR:-}" ]]; then
    echo "$CLAUDE_CONFIG_DIR"
    return 0
  fi

  # 2) probe conventional locations
  local xdg="${XDG_CONFIG_HOME:-$user_home/.config}"
  local candidates=(
    "$user_home/.claude"
    "$xdg/claude"
    "$user_home/.config/claude-code"
  )
  if [[ "$(uname -s 2>/dev/null)" == "Darwin" ]]; then
    candidates+=("$user_home/Library/Application Support/Claude")
  fi

  local c marker
  for c in "${candidates[@]}"; do
    if [[ -d "$c" ]]; then
      # Prefer a candidate that looks like a real Claude dir.
      for marker in settings.json projects sessions plugins; do
        if [[ -e "$c/$marker" ]]; then
          echo "$c"
          return 0
        fi
      done
    fi
  done
  # Second pass: any existing dir, even without markers.
  for c in "${candidates[@]}"; do
    if [[ -d "$c" ]]; then
      echo "$c"
      return 0
    fi
  done

  # 3) fallback default
  echo "$user_home/.claude"
}

# ---------- Preset array reset ----------
# Call before sourcing presets so re-runs don't accumulate stale values.
reset_preset_vars() {
  SKILLS=()
  AGENTS=()
  RULES=()
  POST_EDIT_HOOKS=()
  STOP_HOOKS=()
  ENV_VARS=()
  DENY_AGENTS=()
  CLAUDE_MD_SECTIONS=()
  # Harness-engineering arrays (PDF 8~9쪽 "엄격한 경계" 강제 장치)
  USER_PROMPT_SUBMIT_HOOKS=()   # 매 턴 컨텍스트 주입 hook 스크립트 경로
  PRE_TOOL_USE_HOOKS=()          # "matcher::script" 형식 (e.g. "Bash::path/to/guard.sh")
  POST_TOOL_USE_HOOKS=()         # "matcher::script" 형식 (e.g. "mcp__foo::path/to/hook.sh")
  HARNESS_PERMISSIONS_ALLOW=()   # base.json 등에서 머지할 allow 항목
  HARNESS_HOOK_SOURCES=()        # assets/hooks 에서 프로젝트로 복사할 스크립트 파일명
  HARNESS_DOCS_TEMPLATES=0       # 1 이면 assets/docs-templates 를 프로젝트에 배치
  HARNESS_PRE_COMMIT=0           # 1 이면 assets/hooks/pre-commit.sh 를 .git/hooks/ 에 설치
  HARNESS_LINT_MAX_LINES=0       # 1 이면 assets/lint-configs/eslint/max-lines.config.js 를 프로젝트로 복사
  SESSION_START_HOOKS=()         # 세션 시작 시 1회 실행 hook 스크립트 경로
  VSCODE_EXTENSIONS=()           # code --install-extension 으로 설치할 익스텐션 ID 목록
  PLUGIN_MARKETPLACES=()         # claude plugin marketplace add 로 등록할 마켓 (e.g. "Egonex-AI/Understand-Anything")
  PLUGINS=()                     # claude plugin install --scope user 로 설치할 플러그인 (e.g. "name@marketplace")
}

# ---------- Permissions file merge helper ----------
# assets/permissions/*.json 의 permissions.allow 배열을 읽어
# HARNESS_PERMISSIONS_ALLOW 에 append. 여러 preset 이 호출해도 누적된다.
merge_permissions_file() {
  local json_file="$1"
  [[ -f "$json_file" ]] || return 0
  command -v python3 >/dev/null 2>&1 || return 0
  while IFS= read -r line; do
    [[ -n "$line" ]] && HARNESS_PERMISSIONS_ALLOW+=("$line")
  done < <(python3 -c "
import json, sys
try:
    d = json.load(open('$json_file'))
    for item in d.get('permissions', {}).get('allow', []):
        print(item)
except Exception as e:
    sys.stderr.write(f'[merge_permissions_file] $json_file 읽기 실패: {e}\n')
")
}

# ---------- Dedupe + conflict resolution ----------
# When two presets contribute the same skill/agent/rule, or when one preset's
# DENY_AGENTS conflicts with another preset's AGENTS (e.g. node.conf denies
# python-reviewer which python.conf added), the resulting settings file is
# incoherent.
#
# This function:
#   1. Dedupes every preset array, preserving the first occurrence.
#   2. For ENV_VARS (KEY=VALUE), dedupes by KEY only — the first preset wins.
#   3. Removes from DENY_AGENTS anything that ended up in AGENTS.
#
# Call AFTER sourcing all presets, BEFORE installing.
dedupe_preset_arrays() {
  local v k
  local -a out
  local -A seen

  # SKILLS
  seen=(); out=()
  for v in "${SKILLS[@]:-}"; do
    [[ -z "$v" || -n "${seen[$v]+x}" ]] && continue
    seen[$v]=1; out+=("$v")
  done
  SKILLS=("${out[@]}")

  # AGENTS
  seen=(); out=()
  for v in "${AGENTS[@]:-}"; do
    [[ -z "$v" || -n "${seen[$v]+x}" ]] && continue
    seen[$v]=1; out+=("$v")
  done
  AGENTS=("${out[@]}")

  # RULES
  seen=(); out=()
  for v in "${RULES[@]:-}"; do
    [[ -z "$v" || -n "${seen[$v]+x}" ]] && continue
    seen[$v]=1; out+=("$v")
  done
  RULES=("${out[@]}")

  # ENV_VARS — dedupe by KEY only
  seen=(); out=()
  for v in "${ENV_VARS[@]:-}"; do
    [[ -z "$v" ]] && continue
    k="${v%%=*}"
    if [[ -z "${seen[$k]+x}" ]]; then
      seen[$k]=1; out+=("$v")
    fi
  done
  ENV_VARS=("${out[@]}")

  # POST_EDIT_HOOKS — dedupe by full command
  seen=(); out=()
  for v in "${POST_EDIT_HOOKS[@]:-}"; do
    [[ -z "$v" || -n "${seen[$v]+x}" ]] && continue
    seen[$v]=1; out+=("$v")
  done
  POST_EDIT_HOOKS=("${out[@]}")

  # STOP_HOOKS
  seen=(); out=()
  for v in "${STOP_HOOKS[@]:-}"; do
    [[ -z "$v" || -n "${seen[$v]+x}" ]] && continue
    seen[$v]=1; out+=("$v")
  done
  STOP_HOOKS=("${out[@]}")

  # CLAUDE_MD_SECTIONS
  seen=(); out=()
  for v in "${CLAUDE_MD_SECTIONS[@]:-}"; do
    [[ -z "$v" || -n "${seen[$v]+x}" ]] && continue
    seen[$v]=1; out+=("$v")
  done
  CLAUDE_MD_SECTIONS=("${out[@]}")

  # Harness arrays — dedupe.
  for arr in USER_PROMPT_SUBMIT_HOOKS SESSION_START_HOOKS PRE_TOOL_USE_HOOKS POST_TOOL_USE_HOOKS HARNESS_PERMISSIONS_ALLOW HARNESS_HOOK_SOURCES VSCODE_EXTENSIONS PLUGIN_MARKETPLACES PLUGINS; do
    seen=(); out=()
    eval "local items=(\"\${$arr[@]:-}\")"
    for v in "${items[@]}"; do
      [[ -z "$v" || -n "${seen[$v]+x}" ]] && continue
      seen[$v]=1; out+=("$v")
    done
    eval "$arr=(\"\${out[@]}\")"
  done

  # DENY_AGENTS — dedupe AND drop any agent that's actually used in AGENTS.
  seen=()
  for v in "${AGENTS[@]:-}"; do
    [[ -n "$v" ]] && seen[$v]=1
  done
  out=()
  for v in "${DENY_AGENTS[@]:-}"; do
    [[ -z "$v" || -n "${seen[$v]+x}" ]] && continue
    seen[$v]=1; out+=("$v")
  done
  DENY_AGENTS=("${out[@]}")
}

# ---------- Preset loader ----------
# Resolves a preset name by scanning the preset category directories.
# Echoes the resolved file path; returns nonzero if not found.
resolve_preset() {
  local name="$1"
  local category
  for category in lang framework database build workflow permissions tools; do
    local f="$DEV_SETTING_DIR/presets/$category/$name.conf"
    if [[ -f "$f" ]]; then
      echo "$f"
      return 0
    fi
  done
  return 1
}

# list_presets: prints all available presets, grouped.
list_presets() {
  local category
  for category in lang framework database build workflow permissions tools; do
    printf '  [%s]\n' "$category"
    local f
    for f in "$DEV_SETTING_DIR/presets/$category/"*.conf; do
      [[ -f "$f" ]] || continue
      printf '    - %s\n' "$(basename "$f" .conf)"
    done
  done
}
