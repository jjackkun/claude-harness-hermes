#!/usr/bin/env bash
# dev-setting/lib/plugins.sh
# Responsibility: preset 의 PLUGINS / PLUGIN_MARKETPLACES 를 현재 선택에 맞춰 동기화.
# 플러그인은 user scope(전역)에 설치되므로 "프로젝트 A는 쓰고 B는 안 씀" 상황이
# 생긴다. 그래서 어느 프로젝트가 어떤 plugin 을 요구하는지 manifest 에 기록(refcount)
# 하고, 어떤 프로젝트도 더 이상 요구하지 않는 preset-플러그인만 전역에서 제거한다.
# setup.sh 가 강제 설치하는 baseline official 플러그인은 manifest 에 등록되지 않으므로
# 절대 제거 대상이 되지 않는다.
#
# manifest 한 줄 포맷:  "<plugin_id>\t<project_path>"

# _plugin_manifest_path
# preset-플러그인 참조 기록 파일 경로. claude config 디렉터리 하위에 둔다.
_plugin_manifest_path() {
  local claude_dir
  claude_dir="$(detect_claude_config_dir "$HOME")"
  echo "$claude_dir/.ai-dev-setting/preset-plugins.tsv"
}

# sync_preset_plugins <project_path> [dry_run]
# 전역 배열 PLUGINS / PLUGIN_MARKETPLACES 를 입력으로 사용한다.
#   - 선택된 marketplace/plugin 을 설치
#   - 이 프로젝트가 '뺀' plugin 중 다른 프로젝트도 안 쓰는 것만 전역 제거
# dry_run=1 이면 claude 명령과 manifest 쓰기를 생략하고 계획만 출력한다.
sync_preset_plugins() {
  local project="$1" dry="${2:-0}"
  local manifest
  manifest="$(_plugin_manifest_path)"

  local has_claude=0
  command -v claude >/dev/null 2>&1 && has_claude=1

  # ---- 1) manifest 읽기: 이 프로젝트가 이전에 요구한 plugin / 다른 프로젝트 참조 ----
  local -A prev_for_project=()   # 이전에 이 프로젝트가 요구한 plugin
  local -A other_refs=()         # 다른 프로젝트가 아직 요구하는 plugin
  local tmp pid ppath
  tmp="$(mktemp)"
  if [[ -f "$manifest" ]]; then
    while IFS=$'\t' read -r pid ppath; do
      [[ -z "$pid" ]] && continue
      if [[ "$ppath" == "$project" ]]; then
        prev_for_project["$pid"]=1          # 이 프로젝트 줄 — 재기록 위해 tmp 에서 제외
      else
        other_refs["$pid"]=1
        printf '%s\t%s\n' "$pid" "$ppath" >> "$tmp"
      fi
    done < "$manifest"
  fi

  # ---- 2) marketplace 등록 (선택분) ----
  local market plugin
  if [[ ${#PLUGIN_MARKETPLACES[@]} -gt 0 ]]; then
    for market in "${PLUGIN_MARKETPLACES[@]+"${PLUGIN_MARKETPLACES[@]}"}"; do
      [[ -z "$market" ]] && continue
      if [[ $dry -eq 1 ]]; then
        log_info "  market  would-add → $market"
      elif [[ $has_claude -eq 1 ]]; then
        claude plugin marketplace add "$market" >/dev/null 2>&1 || true
        log_info "  market  → $market"
      else
        log_warn "  market  → $market (claude 없음 — 수동: claude plugin marketplace add $market)"
      fi
    done
  fi

  # ---- 3) 선택된 plugin 설치 + 이 프로젝트 줄로 재기록 ----
  local -A now_selected=()
  if [[ ${#PLUGINS[@]} -gt 0 ]]; then
    for plugin in "${PLUGINS[@]+"${PLUGINS[@]}"}"; do
      [[ -z "$plugin" ]] && continue
      now_selected["$plugin"]=1
      printf '%s\t%s\n' "$plugin" "$project" >> "$tmp"
      if [[ $dry -eq 1 ]]; then
        log_info "  plugin  would-install → $plugin"
      elif [[ $has_claude -eq 1 ]]; then
        if claude plugin install "$plugin" --scope user >/dev/null 2>&1; then
          log_info "  plugin  → $plugin"
        else
          log_warn "  plugin  → $plugin (설치 실패 — 수동: claude plugin install $plugin --scope user)"
        fi
      else
        log_warn "  plugin  → $plugin (claude 없음 — 수동: claude plugin install $plugin --scope user)"
      fi
    done
  fi

  # ---- 4) 이 프로젝트가 뺀 plugin 중 참조 0 인 것만 전역 제거 ----
  for pid in "${!prev_for_project[@]}"; do
    [[ -n "${now_selected[$pid]:-}" ]] && continue          # 여전히 선택됨 → 유지
    if [[ -n "${other_refs[$pid]:-}" ]]; then               # 다른 프로젝트가 사용 중 → 유지
      log_info "  plugin  keep → $pid (다른 프로젝트가 사용 중)"
      continue
    fi
    if [[ $dry -eq 1 ]]; then
      log_info "  plugin  would-remove → $pid (선택 해제, 참조 0)"
    elif [[ $has_claude -eq 1 ]]; then
      if claude plugin uninstall "$pid" >/dev/null 2>&1; then
        log_info "  plugin  removed → $pid (선택 해제, 참조 0)"
      else
        log_warn "  plugin  remove 실패 → $pid (수동: claude plugin uninstall $pid)"
      fi
    else
      log_warn "  plugin  → $pid (선택 해제 — 수동 제거: claude plugin uninstall $pid)"
    fi
  done

  # ---- 5) manifest 갱신 (dry-run 은 건드리지 않음) ----
  if [[ $dry -eq 1 ]]; then
    rm -f "$tmp"
    return 0
  fi
  mkdir -p "$(dirname "$manifest")"
  mv "$tmp" "$manifest"
}
