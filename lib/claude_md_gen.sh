#!/usr/bin/env bash
# dev-setting/lib/claude_md_gen.sh
# Responsibility: 프로젝트 루트의 CLAUDE.md 관리 블록(마커 사이 내용) 생성·갱신, 그리고
# .dev-setting-manifest.json 작성. 둘 다 재실행 시 사용자 편집 보존이 핵심.
#
# Markers are intentionally exotic so that grep / awk match them as full
# lines and don't get fooled by docs that mention "<!-- dev-setting:begin -->"
# inside a code span. We compare with `$0 == marker` (line equality), not
# substring match, for the same reason.

DS_MARKER_BEGIN="<!--===DS:BEGIN===-->"
DS_MARKER_END="<!--===DS:END===-->"

# _managed_block_preamble <target>
# target: claude | codex
# 관리 블록 최상단에 들어가는 고정 서문. CLAUDE.md / AGENTS.md 양쪽 생성기가 공유한다.
#   (A) "기억 말고 문서 먼저" 가드 — 모델이 사전학습 지식으로 단정하지 않게 한다.
#   (B) 설치된 규칙·스킬·에이전트의 압축 목차 — 스킬을 "모델이 알아서 호출"하길 기대하지 않고
#       항상 보이는 메모가 직접 가리키게 한다(자동 호출 누락 방지).
# SKILLS/AGENTS/RULES 전역 배열을 읽어 이 프로젝트에 실제 설치된 것만 나열한다.
# set -u 안전: 배열이 미선언이어도 ${arr[@]+...} 로 빈 확장 처리.
_managed_block_preamble() {
  local target="${1:-claude}"
  local -a _rules=( ${RULES[@]+"${RULES[@]}"} )
  local -a _skills=( ${SKILLS[@]+"${SKILLS[@]}"} )
  local -a _agents=( ${AGENTS[@]+"${AGENTS[@]}"} )
  local rules_dir skills_dir agents_dir global_rules
  if [[ "$target" == "codex" ]]; then
    rules_dir=".codex/rules/"; skills_dir=".codex/skills/"; agents_dir=".codex/agents/"
    global_rules="Codex 전역 공통 규칙"
  else
    rules_dir=".claude/rules/"; skills_dir=".claude/skills/"; agents_dir=".claude/agents/"
    global_rules="\`~/.claude/rules/common/\`"
  fi

  # (A) 최우선 가드
  echo "## ⚠️ 최우선 — 기억 말고 문서 먼저"
  echo ""
  echo "사전학습으로 외운 지식으로 단정하지 말고, **이 문서와 아래 규칙·프로젝트 문서를 먼저 확인한 뒤** 판단·작업한다."
  echo "도구·라이브러리·프로젝트 규칙이 기억과 다를 수 있다. 충돌 시 항상 프로젝트의 실제 파일·규칙이 우선이다."
  echo ""

  # (B) 압축 목차 — 설치된 것만 나열
  echo "## 설치된 규칙·스킬 목차 (필요할 때 펼쳐 본다)"
  echo ""
  echo "- **항상 적용되는 규칙**: \`$rules_dir\` (및 $global_rules) — 코딩 스타일·보안·테스트·git·리뷰 등. 관련 작업 전 해당 규칙을 먼저 확인한다."
  [[ ${#_rules[@]} -gt 0 ]]  && echo "  - 이 프로젝트 룰셋: ${_rules[*]}"
  [[ ${#_skills[@]} -gt 0 ]] && echo "- **스킬** (특별·대형 작업 시 직접 호출): \`$skills_dir\` — ${_skills[*]}"
  [[ ${#_agents[@]} -gt 0 ]] && echo "- **에이전트** (검토·위임): \`$agents_dir\` — ${_agents[*]}"
  echo ""
}

generate_claude_md() {
  local output="$1"
  local project_name="${2:-$(basename "$(dirname "$output")")}"
  local begin="$DS_MARKER_BEGIN"
  local end="$DS_MARKER_END"

  # Compose the managed block into a temp file.
  local managed
  managed=$(mktemp)
  {
    echo "$begin"
    echo "<!-- Managed by dev-setting/project-claude.sh. Edits inside this block are overwritten on re-run. -->"
    echo ""
    _managed_block_preamble claude
    if [[ ${#CLAUDE_MD_SECTIONS[@]} -gt 0 ]]; then
      local section
      for section in "${CLAUDE_MD_SECTIONS[@]}"; do
        [[ -z "$section" ]] && continue
        printf '%s\n\n' "$section"
      done
    fi
    echo "$end"
  } > "$managed"

  # Has the file an existing managed block? Use grep -Fx so we match the
  # marker only when it sits on its own line.
  if [[ -f "$output" ]] && grep -qFx "$begin" "$output"; then
    # 가드: BEGIN 마커만 있고 END 가 유실된 경우, awk 치환이 BEGIN 이후의
    # 사용자 내용 전부를 블록으로 간주해 삭제해버린다. 갱신을 중단하고 경고.
    if ! grep -qFx "$end" "$output"; then
      log_warn "CLAUDE.md 관리 블록의 END 마커($end)가 없습니다 — 사용자 내용 보호를 위해 갱신을 건너뜁니다: $output"
      log_warn "  복구: BEGIN 마커 줄을 지우거나 END 마커를 다시 추가한 뒤 재실행하세요."
      rm -f "$managed"
      return 0
    fi
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
    # CLAUDE.md exists but has no managed block → append.
    printf '\n' >> "$output"
    cat "$managed" >> "$output"
  else
    # Create new CLAUDE.md from template.
    if [[ -f "$TEMPLATES_DIR/CLAUDE.md.tpl" ]]; then
      sed "s|{{PROJECT_NAME}}|$project_name|g" "$TEMPLATES_DIR/CLAUDE.md.tpl" > "$output"
    else
      echo "# $project_name" > "$output"
    fi
    printf '\n' >> "$output"
    cat "$managed" >> "$output"
  fi

  rm -f "$managed"
  log_info "  CLAUDE.md→ $output"
}

# _manifest_json_array <item...>
# 빈 배열이면 [] 를 출력 — 종전 printf 방식은 빈 배열에서 [""] 를 만들었다.
_manifest_json_array() {
  local -a items=()
  local it
  for it in "$@"; do
    [[ -n "$it" ]] && items+=("$it")
  done
  if [[ ${#items[@]} -eq 0 ]]; then
    echo "[]"
    return 0
  fi
  local csv
  csv=$(printf '"%s",' "${items[@]}")
  echo "[${csv%,}]"
}

# Manifest for idempotent re-runs.
write_manifest() {
  local output="$1"
  local presets_csv skills_csv agents_csv
  presets_csv=$(_manifest_json_array "${PRESETS[@]+"${PRESETS[@]}"}")
  skills_csv=$(_manifest_json_array "${SKILLS[@]+"${SKILLS[@]}"}")
  agents_csv=$(_manifest_json_array "${AGENTS[@]+"${AGENTS[@]}"}")

  cat > "$output" <<EOF
{
  "synced_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "dev_setting_dir": "$DEV_SETTING_DIR",
  "presets": $presets_csv,
  "skills": $skills_csv,
  "agents": $agents_csv
}
EOF
  log_info "  manifest→ $output"
}
