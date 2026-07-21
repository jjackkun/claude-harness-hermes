#!/usr/bin/env bash
# SessionStart 가드 — 네이티브 메모리 심링크가 소실/오손되면 <project>/.claude/memory 로 재링크.
# stdout 무출력(세션 컨텍스트 오염 방지). 진단은 .hermes/hooks.log.
[[ "${HERMES_DISABLED:-0}" == "1" ]] && exit 0
command -v sed >/dev/null 2>&1 || exit 0

raw_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
project_dir="$(printf '%s' "$raw_dir" | sed 's|/.claude/worktrees/[^/]*$||')"
[[ -d "$project_dir/.hermes" ]] || exit 0            # 비-hermes 프로젝트 no-op
repo_mem="$project_dir/.claude/memory"
[[ -d "$repo_mem" || -L "$repo_mem" ]] || exit 0     # Part A 미설치면 no-op

key="$(printf '%s' "$project_dir" | sed 's/[^a-zA-Z0-9]/-/g')"
native="$HOME/.claude/projects/$key/memory"
log="$project_dir/.hermes/hooks.log"

# 이미 올바른 심링크면 종료
if [[ -L "$native" && "$(readlink "$native")" == "$repo_mem" ]]; then exit 0; fi

case "$native" in
  /mnt/[a-z]/*) exit 0 ;;                             # NTFS 마운트는 심링크 스킵(복사 모드)
esac

# 오손 상태 복구: 실디렉터리면 내용 보존 후 재링크
if [[ -d "$native" && ! -L "$native" ]]; then
  # 실디렉터리(오손) — repo 로 비파괴 이관 후에만 제거(cp 전량 성공 검증 없이는 삭제 금지)
  copy_failed=0
  while IFS= read -r -d '' f; do
    rel="${f#"$native"/}"
    dest="$repo_mem/$rel"
    mkdir -p "$(dirname "$dest")"
    if [[ -e "$dest" ]]; then
      if ! cmp -s "$f" "$dest"; then
        native_dest="$dest.native" n=1
        while [[ -e "$native_dest" ]]; do
          cmp -s "$f" "$native_dest" && native_dest=""
          [[ -z "$native_dest" ]] && break
          native_dest="$dest.native.$n"
          n=$((n + 1))
        done
        if [[ -n "$native_dest" ]] && ! cp -p "$f" "$native_dest" 2>/dev/null; then
          copy_failed=1
        fi
      fi
    elif ! cp -p "$f" "$dest" 2>/dev/null; then
      copy_failed=1
    fi
  done < <(find "$native" -type f -print0)
  if [[ "$copy_failed" -ne 0 ]]; then
    printf '[memory-guard] 이관 실패 — 네이티브 보존, 재링크 생략(다음 세션 재시도)\n' >>"$log" 2>/dev/null || true
    exit 0
  fi
  rm -rf "$native"
elif [[ -L "$native" ]]; then
  rm -f "$native"
fi
mkdir -p "$(dirname "$native")"
if ln -s "$repo_mem" "$native" 2>>"$log"; then
  printf '[memory-guard] 심링크 복구: %s -> %s\n' "$native" "$repo_mem" >>"$log" 2>/dev/null || true
fi
exit 0
