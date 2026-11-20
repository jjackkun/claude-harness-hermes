#!/usr/bin/env bash
# G3 시작 알림 — main 에 안 들어간 worktree(앞선 커밋 또는 커밋 안 된 변경)만 알린다. 막지 않는다.
# 계획: docs/exec-plans/active/2026-11-20-worktree-finish-plan.md (G3)
set -uo pipefail
source "$(dirname "$0")/worktree-hooks-lib.bash"
NOTICE="$HOOKS/claude-sessionstart-unmerged-worktrees.sh"
notice() { printf '{"session_id":"s1","cwd":"%s","source":"%s"}' "$1" "${SRC:-startup}" | CLAUDE_PROJECT_DIR="$1" bash "$NOTICE" 2>/dev/null; echo "exit=$?"; }
ctx() { sed '/^exit=/d' <<<"$1" | python3 -c 'import json,sys;t=sys.stdin.read().strip();print(json.loads(t)["hookSpecificOutput"]["additionalContext"] if t else "")'; }

echo "[구조]"
bash -n "$NOTICE"; assert "셸 문법" 0 "$?"
assert "harness 프리셋에 SessionStart 등록" 1 "$(grep -c 'SESSION_START_HOOKS+=.*claude-sessionstart-unmerged-worktrees.sh' "$REPO_ROOT/presets/workflow/harness.conf")"

echo "[worktree 없음] 조용함"
repo a; out=$(notice "$M"); assert "종료 0" exit=0 "$(tail -1 <<<"$out")"; assert "출력 없음" "" "$(ctx "$out")"

echo "[3개: 합쳐짐 · 커밋 앞섬 · 변경만]"
repo b; W1=$(add_wt b merged); W2=$(add_wt b ahead); W3=$(add_wt b dirty)
printf 'x\n' > "$W2/a.txt"; commit_in "$W2"; printf 'x\n' > "$W3/b.txt"
for where in "$M" "$W1"; do
  text=$(ctx "$(notice "$where")")
  assert "($(basename "$where") 에서) ahead 를 알림" 1 "$(grep -cE '^\s+- ahead' <<<"$text")"
  assert "($(basename "$where") 에서) dirty 를 알림" 1 "$(grep -cE '^\s+- dirty' <<<"$text")"
  assert "($(basename "$where") 에서) merged 는 알리지 않음" 0 "$(grep -cE '^\s+- merged' <<<"$text")"
done
assert "앞선 커밋 수를 보임" 1 "$(grep -c 'ahead.*커밋 1' <<<"$text")"
assert "마무리 스킬을 가리킴" 1 "$(grep -c 'worktree-finish' <<<"$text")"

echo "[압축] compact 에서는 다시 알리지 않는다(리뷰 L1)"
assert "compact 조용함" "" "$(ctx "$(SRC=compact notice "$M")")"
assert "resume 은 알림" 1 "$(grep -cE '^\s+- ahead' <<<"$(ctx "$(SRC=resume notice "$M")")")"

echo "[master 저장소]"
repo m master; W=$(add_wt m mw); printf 'x\n' > "$W/f.txt"
assert "master 에서도 알림" 1 "$(grep -cE '^\s+- mw' <<<"$(ctx "$(notice "$M")")")"

echo "[끄기]"
assert "끄기 스위치" "" "$(ctx "$(WORKTREE_NOTICE_DISABLED=1 notice "$M")")"

echo "[11개] 10개까지만 이름을 보이고 나머지는 수로"
repo c; for i in $(seq -w 1 11); do W=$(add_wt c "w$i"); printf 'x\n' > "$W/f.txt"; done
text=$(ctx "$(notice "$M")")
assert "이름 줄 10개" 10 "$(grep -cE '^\s+- w[0-9]+' <<<"$text")"; assert "나머지 1개" 1 "$(grep -c '외 1개' <<<"$text")"

finish_tests
