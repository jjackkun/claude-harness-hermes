#!/usr/bin/env bash
# dev-setting/lib/installers.sh
# Responsibility: 범용 에셋 installer — assets/{skills,agents,rules} 를 프로젝트의
# .claude/ 아래로 심볼릭. 이미 사라진 preset 의 잔존 심볼릭 정리 포함.

# _cleanup_stale_symlinks <dir> <ext> <current_names...>
# ai-dev-setting/assets 를 가리키는 심볼릭 중 현재 preset에 없는 것을 제거.
# Windows 경로(NTFS)에는 WSL symlink 가 없으므로 early-return.
_cleanup_stale_symlinks() {
  local dir="$1" ext="$2"
  shift 2
  # Windows NTFS 마운트에는 WSL symlink 가 존재하지 않음 — 스킵
  is_windows_path "$dir" && return 0

  local -A keep=()
  for name in "$@"; do keep["$name"]=1; done

  [[ -d "$dir" ]] || return 0
  for entry in "$dir"/*; do
    [[ -L "$entry" ]] || continue
    local target; target="$(readlink "$entry")"
    [[ "$target" == "$ASSETS_DIR"* ]] || continue  # 로컬 파일은 건드리지 않음
    local name; name="$(basename "$entry" "$ext")"
    if [[ -z "${keep[$name]:-}" ]]; then
      rm -rf "$entry"
      log_info "  removed → $name"
    fi
  done
}

# _backup_user_asset <dst> <label>
# preset 과 같은 이름의 *사용자 자체* 에셋(non-symlink 실디렉터리)이 있으면
# 삭제하지 않고 <name>.backup-<타임스탬프> 로 이동 후 경고하고 설치를 계속한다.
# Windows(NTFS) 타깃은 preset 설치 자체가 실디렉터리 복사라 구분 불가 → 호출측에서 스킵.
_backup_user_asset() {
  local dst="$1" label="$2"
  [[ -e "$dst" && ! -L "$dst" ]] || return 0
  local backup
  backup="${dst}.backup-$(date +%Y%m%d-%H%M%S)"
  mv "$dst" "$backup"
  log_warn "  ${label} '$(basename "$dst")' 는 사용자 로컬 항목 → $(basename "$backup") 로 백업 후 preset 설치"
}

# install_skills <target_claude_dir>
install_skills() {
  local target="$1"
  mkdir -p "$target/skills"
  _cleanup_stale_symlinks "$target/skills" "" "${SKILLS[@]+"${SKILLS[@]}"}"
  [[ ${#SKILLS[@]} -eq 0 ]] && return 0
  local skill src dst
  for skill in "${SKILLS[@]}"; do
    [[ -z "$skill" ]] && continue
    src="$ASSETS_DIR/skills/$skill"
    dst="$target/skills/$skill"
    if [[ ! -d "$src" ]]; then
      log_warn "skill missing in assets: $skill (skipped)"
      continue
    fi
    is_windows_path "$target" || _backup_user_asset "$dst" "skill"
    rm -rf "$dst"
    if is_windows_path "$target"; then
      cp -r "$src" "$dst"
    else
      ln -s "$src" "$dst"
    fi
    log_info "  skill   → $skill"
  done
}

# install_agents <target_claude_dir>
install_agents() {
  local target="$1"
  mkdir -p "$target/agents"
  _cleanup_stale_symlinks "$target/agents" ".md" "${AGENTS[@]+"${AGENTS[@]}"}"
  [[ ${#AGENTS[@]} -eq 0 ]] && return 0
  local agent src dst
  for agent in "${AGENTS[@]}"; do
    [[ -z "$agent" ]] && continue
    src="$ASSETS_DIR/agents/$agent.md"
    dst="$target/agents/$agent.md"
    if [[ ! -f "$src" ]]; then
      log_warn "agent missing in assets: $agent.md (skipped)"
      continue
    fi
    rm -f "$dst"
    if is_windows_path "$target"; then
      cp "$src" "$dst"
    else
      ln -s "$src" "$dst"
    fi
    log_info "  agent   → $agent"
  done
}

# install_rules <target_claude_dir>
install_rules() {
  local target="$1"
  mkdir -p "$target/rules"
  _cleanup_stale_symlinks "$target/rules" "" "${RULES[@]+"${RULES[@]}"}"
  [[ ${#RULES[@]} -eq 0 ]] && return 0
  local rule src dst
  for rule in "${RULES[@]}"; do
    [[ -z "$rule" ]] && continue
    src="$ASSETS_DIR/rules/$rule"
    dst="$target/rules/$rule"
    if [[ ! -d "$src" ]]; then
      log_warn "rule set missing in assets: $rule (skipped)"
      continue
    fi
    is_windows_path "$target" || _backup_user_asset "$dst" "rule"
    rm -rf "$dst"
    if is_windows_path "$target"; then
      cp -r "$src" "$dst"
    else
      ln -s "$src" "$dst"
    fi
    log_info "  rules   → $rule"
  done
}
