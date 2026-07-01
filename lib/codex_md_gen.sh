#!/usr/bin/env bash
# dev-setting/lib/codex_md_gen.sh
# Responsibility: project AGENTS.md managed block generation for Codex.

CODEX_MARKER_BEGIN="<!--===DS-CODEX:BEGIN===-->"
CODEX_MARKER_END="<!--===DS-CODEX:END===-->"

_codex_section_text() {
  sed \
    -e 's|scripts/hooks/claude-userpromptsubmit-reminders.sh|scripts/codex-hooks/codex-userpromptsubmit-reminders.sh|g' \
    -e 's|scripts/hooks/claude-pretooluse-bash-guard.sh|scripts/codex-hooks/codex-pretooluse-bash-guard.sh|g' \
    -e 's|scripts/hooks/claude-pretooluse-agent-guard.sh|Codex review/agent workflow|g' \
    -e 's|scripts/hooks/claude-posttooluse-prettier-warn.sh|Codex preset formatter hook|g' \
    -e 's|scripts/hooks/claude-posttooluse-size-warn.sh|scripts/codex-hooks/codex-posttooluse-size-warn.sh|g' \
    -e 's|scripts/hooks/claude-posttooluse-review-reminder.sh|Codex review workflow|g' \
    -e 's|scripts/hooks/claude-posttooluse-dead-file-warn.sh|Codex review workflow|g' \
    -e 's|\.claude/memory/|Codex memory/|g' \
    -e 's|code-reviewer dispatch|`codex review --uncommitted`|g' \
    -e 's|Codex review workflow|`codex review --uncommitted`|g' \
    -e 's|계획 → 구현 → 검증 흐름. 깊은 리뷰는 위험 신호가 있을 때 승격|계획 → 구현 → 검증 흐름. 큰 변경이면 Codex review로 승격|g' \
    -e 's|Haiku 금지\.|저품질/저추론 모드 남용 금지.|g'
}

generate_agents_md() {
  local output="$1"
  local project_name="${2:-$(basename "$(dirname "$output")")}"
  local begin="$CODEX_MARKER_BEGIN"
  local end="$CODEX_MARKER_END"

  local managed
  managed=$(mktemp)
  {
    echo "$begin"
    echo "<!-- Managed by dev-setting/project-codex.sh. Edits inside this block are overwritten on re-run. -->"
    echo ""
    # (A)가드 + (B)목차 서문 — claude_md_gen.sh 공유 헬퍼. codex 경로로 출력하며
    # _codex_section_text(sed)를 거치지 않는다(이미 codex용 경로를 쓰므로).
    _managed_block_preamble codex
    if [[ ${#CLAUDE_MD_SECTIONS[@]} -gt 0 ]]; then
      local section
      for section in "${CLAUDE_MD_SECTIONS[@]}"; do
        [[ -z "$section" ]] && continue
        printf '%s\n\n' "$section" | _codex_section_text
      done
    fi
    echo "$end"
  } > "$managed"

  if [[ -f "$output" ]] && grep -qFx "$begin" "$output"; then
    local tmp
    tmp=$(mktemp)
    awk -v begin="$begin" -v end="$end" -v newfile="$managed" '
      BEGIN { in_block=0 }
      $0 == begin {
        in_block=1
        while ((getline line < newfile) > 0) print line
        close(newfile)
        next
      }
      $0 == end { in_block=0; next }
      in_block == 0 { print }
    ' "$output" > "$tmp"
    mv "$tmp" "$output"
  elif [[ -f "$output" ]]; then
    printf '\n' >> "$output"
    cat "$managed" >> "$output"
  else
    if [[ -f "$TEMPLATES_DIR/AGENTS.md.tpl" ]]; then
      sed "s|{{PROJECT_NAME}}|$project_name|g" "$TEMPLATES_DIR/AGENTS.md.tpl" > "$output"
    else
      echo "# $project_name" > "$output"
    fi
    printf '\n' >> "$output"
    cat "$managed" >> "$output"
  fi

  rm -f "$managed"
  log_info "  AGENTS.md→ $output"
}

write_codex_manifest() {
  local output="$1"
  local presets_csv skills_csv agents_csv
  presets_csv=$(printf '"%s",' "${PRESETS[@]}")
  presets_csv="[${presets_csv%,}]"
  skills_csv=$(printf '"%s",' "${SKILLS[@]:-}")
  skills_csv="[${skills_csv%,}]"
  agents_csv=$(printf '"%s",' "${AGENTS[@]:-}")
  agents_csv="[${agents_csv%,}]"

  cat > "$output" <<EOF
{
  "target": "codex",
  "synced_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "dev_setting_dir": "$DEV_SETTING_DIR",
  "presets": $presets_csv,
  "skills": $skills_csv,
  "agents": $agents_csv
}
EOF
  log_info "  manifest→ $output"
}
