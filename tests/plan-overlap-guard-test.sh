#!/usr/bin/env bash
# G4 같은 계획서 편집 경고 — 다른 worktree(또는 메인 체크아웃)가 같은 active 계획서를 고치는 중이면 편집 전에 알린다. 막지 않는다.
# 계획: docs/exec-plans/active/2026-11-20-worktree-finish-plan.md (G4)
set -uo pipefail
source "$(dirname "$0")/worktree-hooks-lib.bash"
GUARD="$HOOKS/claude-pretooluse-plan-overlap-guard.sh"
edit() {  # edit <cwd> <file_path> → additionalContext (없으면 빈 줄)
  printf '{"session_id":"s1","cwd":"%s","tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$1" "$2" \
    | CLAUDE_PROJECT_DIR="$1" bash "$GUARD" 2>/dev/null \
    | python3 -c 'import json,sys;t=sys.stdin.read().strip();print(json.loads(t)["hookSpecificOutput"]["additionalContext"] if t else "")'
}

echo "[구조]"
bash -n "$GUARD"; assert "셸 문법" 0 "$?"
assert "harness 프리셋에 PreToolUse 등록(Edit|Write|MultiEdit)" 1 "$(grep -c "PRE_TOOL_USE_HOOKS+=('Edit|Write|MultiEdit::.*claude-pretooluse-plan-overlap-guard.sh')" "$REPO_ROOT/presets/workflow/harness.conf")"
assert "복사 목록에 판정 모듈" 1 "$(grep -cE '^\s+plan_overlap.py$' "$REPO_ROOT/presets/workflow/harness.conf")"

repo a; A=$(add_wt a sa); B=$(add_wt a sb)
echo "[겹침] 다른 worktree 가 같은 계획서를 커밋으로 고침"
printf '# plan\n- [x] G1\n' > "$B/$PLAN_REL"; commit_in "$B"
text=$(edit "$A" "$A/$PLAN_REL")
assert "경고" 1 "$(grep -c 'plan-overlap' <<<"$text")"; assert "worktree 이름을 보임" 1 "$(grep -c 'sb' <<<"$text")"
echo "[겹침] 메인 체크아웃이 같은 계획서를 커밋 안 하고 고침"
printf '# plan\n- edited\n' > "$M/$PLAN_REL"
assert "메인도 알림" 1 "$(grep -c 'main' <<<"$(edit "$A" "$A/$PLAN_REL")")"
echo "[조용함]"
git -C "$M" checkout -q -- "$PLAN_REL"; git -C "$B" reset -q --hard main
assert "아무도 안 고침" "" "$(edit "$A" "$A/$PLAN_REL")"
mkdir -p "$B/docs" && printf 'x\n' > "$B/docs/notes.md"; commit_in "$B"
assert "active 밖 .md(다른 worktree 가 같은 파일을 고쳐도)" "" "$(edit "$A" "$A/docs/notes.md")"
git -C "$B" reset -q --hard main
printf '# plan\n- [x] G1\n' > "$B/$PLAN_REL"; commit_in "$B"
assert "끄기 스위치" "" "$(PLAN_OVERLAP_GUARD_DISABLED=1 edit "$A" "$A/$PLAN_REL")"
assert "자기 worktree 의 변경은 알리지 않음" 0 "$(grep -c 'sb' <<<"$(edit "$B" "$B/$PLAN_REL")")"

echo "[master 저장소]"
repo m master; A=$(add_wt m ma); B=$(add_wt m mb)
printf '# plan\n- x\n' > "$B/$PLAN_REL"; commit_in "$B"
assert "master 에서도 경고" 1 "$(grep -c 'mb' <<<"$(edit "$A" "$A/$PLAN_REL")")"

finish_tests
