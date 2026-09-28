#!/usr/bin/env bash
# .gitattributes 에 하네스 마커 블록을 쓰는 것만 담당한다 (install_harness_gitignore 와 같은 방식 — 마커 밖은 안 건드린다).
#
# 왜: 에이전트 기억(.hermes/agents/*/memory.jsonl)과 작업 이력(.hermes/journal.jsonl)은 추가만 하는 파일이다.
# 두 컴퓨터가 같은 파일 끝에 줄을 더하면 git 병합이 충돌한다 — merge=union 이면 양쪽 줄을 모두 살린다.
# 들이는 쪽이 id 로 중복을 거르므로 겹친 줄은 해가 없다.
# 계획: docs/exec-plans/completed/2026-09-28-carry-agent-knowledge.md 목표 7
#
# 공개 함수 1개: install_harness_gitattributes <project_path>
#   프리셋이 GITATTRIBUTES_ENTRIES 배열을 채웠을 때만 쓴다. 비었는데 옛 블록이 있으면 블록을 걷는다.

install_harness_gitattributes() {
  local project_path="$1"
  local file="$project_path/.gitattributes"
  local begin="# >>> harness-agent-preset >>>"
  local end="# <<< harness-agent-preset <<<"
  local count=0
  [[ -n "${GITATTRIBUTES_ENTRIES+x}" ]] && count=${#GITATTRIBUTES_ENTRIES[@]}

  local block=""
  if (( count > 0 )); then
    block="$begin"$'\n'"# Auto-managed by claude-harness-hermes. Do not edit between markers."$'\n'
    local e
    for e in "${GITATTRIBUTES_ENTRIES[@]}"; do block+="$e"$'\n'; done
    block+="$end"
  fi

  if [[ -f "$file" ]] && { grep -qxF "$begin" "$file" || grep -qxF "$begin"$'\r' "$file"; }; then
    local tmp
    tmp="$(mktemp)"
    awk -v b="$begin" -v e="$end" -v repl="$block" '
      { line = $0; sub(/\r$/, "", line) }
      line == b { skip=1; if (repl != "") print repl; next }
      skip && line == e { skip=0; next }
      !skip { print }
    ' "$file" > "$tmp"
    mv "$tmp" "$file"
    log_info "  gitattributes → .gitattributes (블록 갱신, ${count}개 항목)"
    return 0
  fi
  (( count > 0 )) || return 0
  if [[ -s "$file" ]]; then
    [[ -n "$(tail -c1 "$file")" ]] && printf '\n' >> "$file"
    printf '\n%s\n' "$block" >> "$file"
  else
    printf '%s\n' "$block" > "$file"
  fi
  log_info "  gitattributes → .gitattributes (블록 추가, ${count}개 항목)"
}
