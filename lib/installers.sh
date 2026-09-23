#!/usr/bin/env bash
# dev-setting/lib/installers.sh
# Responsibility: 범용 에셋 installer — assets/{skills,agents,rules} 를 프로젝트의
# .claude/ 아래로 **복사**하고 설치 목록(.factory-manifest.json)에 기록. 이미 사라진
# preset 의 잔존 항목 정리는 목록 기준.
# 설계: docs/hermes-universe/design/world/copy-install.md (I-01·I-02). 심링크 설치는 폐지.

# _migrate_legacy_symlinks <dir> <kind> <ext>
# 첫 재설치 이행 분기: 목록이 없던 시절의 심링크(대상이 $ASSETS_DIR 아래)를 목록에 옮겨 적는다.
# 두 번째 실행부터는 목록이 있으므로 아무것도 하지 않는다. 3개월 뒤 제거 후보(계획 §6).
_migrate_legacy_symlinks() {
  local dir="$1" kind="$2" ext="$3"
  [[ -d "$dir" ]] || return 0
  local entry target name n=0
  for entry in "$dir"/*; do
    [[ -L "$entry" ]] || continue
    target="$(readlink "$entry")"
    [[ "$target" == "$ASSETS_DIR"* ]] || continue
    name="$(basename "$entry" "$ext")"
    manifest_add "$(dirname "$dir")" "$kind" "$name" "$entry"
    n=$((n+1))
  done
  [[ $n -gt 0 ]] && log_info "  이행: 기존 심링크 ${n}건을 설치 목록에 옮겨 적음 ($kind)"
  return 0
}

# _cleanup_stale_assets <dir> <kind> <ext> <current_names...>
# 설치 목록에 있으나 현재 preset 에 없는 항목만 제거. 목록에 없는 실디렉터리는 사용자 자산 — 건드리지 않음.
_cleanup_stale_assets() {
  local dir="$1" kind="$2" ext="$3"
  shift 3
  [[ -d "$dir" ]] || return 0
  _migrate_legacy_symlinks "$dir" "$kind" "$ext"
  # 지우기 전에 git 에 묻는다 — **추적된** 설치물을 지우는 것은 커밋된 것을 없애는 일이다(R-lock).
  # 2026-09-22: 로컬 presets.lock 이 커밋된 매니페스트보다 모자라 추적된 심링크 2개가 사라졌다.
  # 차단하지 않는다 — 프리셋을 빼는 것은 정당한 작업이다. 사람이 보게만 한다.
  local project_root; project_root="$(cd "$(dirname "$dir")/.." 2>/dev/null && pwd)"
  local dropped=()
  local name
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    _is_tracked_asset "$project_root" "$dir" "$name$ext" && dropped+=("$kind/$name")
    rm -rf "$dir/$name$ext"
    log_info "  removed → $name"
  done < <(manifest_prune "$(dirname "$dir")" "$kind" "$@")
  if [[ ${#dropped[@]} -gt 0 ]]; then
    log_warn "  [preset-drop WARN] git 에 추적된 설치물 ${#dropped[@]}건을 프리셋에서 빼며 지웠습니다: ${dropped[*]}"
    log_warn "            ↳ 의도한 것이면 그대로 커밋하십시오. 아니면 프리셋 인자를 확인하십시오 —"
    log_warn "            ↳ .claude/presets.lock 은 마지막으로 친 인자를 그대로 적습니다 (R-lock)"
  fi
}

# _is_tracked_asset <project_root> <dir> <basename> — 그 경로가 git 에 추적되는가 (rc 0 = 추적됨)
_is_tracked_asset() {
  local project_root="$1" dir="$2" base="$3"
  [[ -n "$project_root" ]] || return 1
  local rel="${dir#"$project_root"/}/$base"
  git -C "$project_root" ls-files --error-unmatch "$rel" >/dev/null 2>&1
}

# _backup_user_asset <claude_dir> <kind> <name> <dst> <label>
# 지우지 않고 <name>.backup-<타임스탬프> 로 옮긴 뒤 교체하는 경우 둘:
#   rc=2 목록에 없는 실디렉터리 — 사용자 자체 에셋이 preset 과 이름이 겹침
#   rc=1 목록에 있으나 내용이 다름 — 공장 설치물을 로컬에서 고쳤음 (훅 경고를 놓쳤거나 세션 밖 편집).
#        덮어쓰면 편집 내용이 완전히 사라지므로 백업한다(리뷰 2026-09-16 MEDIUM).
#   rc=0 목록과 같음 — 그냥 교체.
_backup_user_asset() {
  local claude_dir="$1" kind="$2" name="$3" dst="$4" label="$5"
  [[ -e "$dst" && ! -L "$dst" ]] || return 0
  local rc=0
  manifest_verify "$claude_dir" "$kind" "$name" "$dst" || rc=$?   # set -e 아래서도 종료 코드를 받는다
  [[ $rc -ne 0 ]] || return 0
  local backup why
  backup="${dst}.backup-$(date +%Y%m%d-%H%M%S)"
  mv "$dst" "$backup"
  [[ $rc -eq 2 ]] && why="사용자 로컬 항목" || why="공장 설치물이 로컬에서 수정됨"
  log_warn "  ${label} '$name' 는 ${why} → $(basename "$backup") 로 백업 후 preset 설치"
}

# _install_asset <claude_dir> <kind> <ext> <label> <name>
# 한 항목을 복사하고 목록에 기록한다. 심링크였다면 복사본으로 바뀐 건수를 센다.
_install_asset() {
  local claude_dir="$1" kind="$2" ext="$3" label="$4" name="$5"
  local src="$ASSETS_DIR/$kind/$name$ext" dst="$claude_dir/$kind/$name$ext"
  if [[ ! -e "$src" ]]; then
    log_warn "$label missing in assets: $name$ext (skipped)"
    return 0
  fi
  _backup_user_asset "$claude_dir" "$kind" "$name" "$dst" "$label"
  if [[ -L "$dst" ]] && ! _is_factory_self "$claude_dir"; then
    _CONVERTED_LINKS=$((_CONVERTED_LINKS+1))
  fi
  rm -rf "$dst"
  if _is_factory_self "$claude_dir"; then
    # 공장 자기 설치(E-02): 대상이 저장소 안이므로 상대경로 링크. 두 벌 관리 없이 clone 에서도 안 깨진다.
    ln -s "../../assets/$kind/$name$ext" "$dst"
  else
    cp -r "$src" "$dst"
  fi
  manifest_add "$claude_dir" "$kind" "$name" "$dst"
  log_info "  $label → $name"
}

# _is_factory_self <claude_dir> — 설치 대상이 공장 저장소 자신인가
_is_factory_self() {
  [[ "$(cd "$1/.." 2>/dev/null && pwd -P)" == "$(cd "${DEV_SETTING_DIR:-$ASSETS_DIR/..}" && pwd -P)" ]]
}

# _install_kind <claude_dir> <kind> <ext> <label> <names...>
_install_kind() {
  local claude_dir="$1" kind="$2" ext="$3" label="$4"
  shift 4
  mkdir -p "$claude_dir/$kind"
  _cleanup_stale_assets "$claude_dir/$kind" "$kind" "$ext" "$@"
  local name
  for name in "$@"; do
    [[ -n "$name" ]] && _install_asset "$claude_dir" "$kind" "$ext" "$label" "$name"
  done
  return 0
}

_CONVERTED_LINKS=0

# install_skills <target_claude_dir>
install_skills() { _install_kind "$1" skills ""    "skill  " "${SKILLS[@]+"${SKILLS[@]}"}"; }
# install_agents <target_claude_dir>
install_agents() { _install_kind "$1" agents ".md" "agent  " "${AGENTS[@]+"${AGENTS[@]}"}"; }
# install_rules <target_claude_dir>
install_rules()  { _install_kind "$1" rules  ""    "rules  " "${RULES[@]+"${RULES[@]}"}"; }

# report_converted_links — 이번 설치에서 심링크 → 복사본으로 바뀐 건수를 한 줄 보고 (계획 Step 7 ②)
report_converted_links() {
  [[ $_CONVERTED_LINKS -gt 0 ]] && log_info "링크 → 복사본 ${_CONVERTED_LINKS}건 (설치 목록 기준으로 전환됨)"
  return 0
}
