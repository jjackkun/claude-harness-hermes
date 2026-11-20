#!/usr/bin/env bash
# G2 Stop 훅 — 계획서를 completed 로 옮겼는데 main 에 합치지 않은 worktree 세션의 끝내기를 한 번 막는다.
# 막음 2(커밋된 이동 · 커밋 전 이동) · 통과 6(stop_hook_active · cwd 없음 · worktree 아님 · 이미 합침 · 같은 상태 두 번째 · 끄기)
# 계획: docs/exec-plans/completed/2026-11-20-worktree-finish-plan.md (G2)
set -uo pipefail
source "$(dirname "$0")/worktree-hooks-lib.bash"
GUARD="$HOOKS/claude-stop-worktree-finish-guard.sh"

stop_hook() {  # stop_hook <cwd> <session> [stop_hook_active] → stdout
  printf '{"session_id":"%s","cwd":"%s","stop_hook_active":%s,"hook_event_name":"Stop"}' "$2" "$1" "${3:-false}" \
    | CLAUDE_PROJECT_DIR="$1" bash "$GUARD" 2>/dev/null
}
blocked() { python3 -c 'import json,sys;t=sys.stdin.read().strip();print("yes" if t and json.loads(t).get("decision")=="block" else "no")' <<<"$1"; }

echo "[구조]"
bash -n "$GUARD"; assert "셸 문법" 0 "$?"
assert "harness 프리셋에 Stop 등록" 1 "$(grep -c 'STOP_HOOKS+=.*claude-stop-worktree-finish-guard.sh' "$REPO_ROOT/presets/workflow/harness.conf")"
assert "복사 목록에 판정 모듈" 1 "$(grep -cE '^\s+worktree_finish_guard.py$' "$REPO_ROOT/presets/workflow/harness.conf")"

echo "[막음] 커밋된 이동, main 에 없음"
repo a; W=$(add_wt a feat); move_plan "$W"; commit_in "$W" done
out=$(stop_hook "$W" s1); assert "막음" yes "$(blocked "$out")"
assert "이유에 계획서 이름" 1 "$(grep -c '2026-11-20-x-plan.md' <<<"$out")"
assert "이유에 마무리 스킬" 1 "$(grep -c 'worktree-finish' <<<"$out")"
assert "같은 상태 두 번째는 통과" no "$(blocked "$(stop_hook "$W" s1)")"
assert "다른 세션은 따로 센다" yes "$(blocked "$(stop_hook "$W" s2)")"
assert "기록은 git 공통 폴더 안, 세션마다 하나" 2 "$(find "$(git -C "$M" rev-parse --path-format=absolute --git-common-dir)/worktree-finish-guard" -type f | wc -l | tr -d ' ')"
assert "worktree 작업 트리에는 기록이 없음" 0 "$(git -C "$W" status --porcelain | grep -c guard)"
printf 'x\n' > "$W/extra.txt"; commit_in "$W" more
assert "같은 계획서면 커밋이 이어져도 다시 막지 않음(리뷰 M2)" no "$(blocked "$(stop_hook "$W" s1)")"

echo "[막음] 커밋 전 이동"
repo b; W=$(add_wt b feat); mkdir -p "$W/docs/exec-plans/completed"; mv "$W/$PLAN_REL" "$W/$DONE_REL"
assert "막음" yes "$(blocked "$(stop_hook "$W" s1)")"

echo "[막음] 가지에서 태어나 끝난 계획서(main 에 없던 것, 2026-11-20 복제본 실측)"
repo b2; W=$(add_wt b2 feat); mkdir -p "$W/docs/exec-plans/active" "$W/docs/exec-plans/completed"
printf '# born\n' > "$W/docs/exec-plans/active/2026-11-20-born-plan.md"; commit_in "$W" plan
git -C "$W" mv docs/exec-plans/active/2026-11-20-born-plan.md docs/exec-plans/completed/; commit_in "$W" done
assert "막음" yes "$(blocked "$(stop_hook "$W" s1)")"
assert "이유에 상대 경로 명령이 없음" 0 "$(grep -c 'bash .claude/skills' <<<"$(stop_hook "$W" s3)")"

echo "[통과]"
assert "stop_hook_active" no "$(blocked "$(stop_hook "$W" s9 true)")"
assert "cwd 가 없음(마무리로 지움)" no "$(blocked "$(stop_hook "$TMP/gone" s1)")"
repo c; move_plan "$M"
assert "메인 체크아웃(worktree 아님)" no "$(blocked "$(stop_hook "$M" s1)")"
repo d; W=$(add_wt d feat); move_plan "$W"; commit_in "$W" done; git -C "$M" merge -q --ff-only feat
assert "이미 main 에 합침" no "$(blocked "$(stop_hook "$W" s1)")"
repo e; W=$(add_wt e feat); printf 'x\n' > "$W/a.txt"; commit_in "$W"
assert "계획 진행 중(completed 이동 없음)" no "$(blocked "$(stop_hook "$W" s1)")"
repo f; W=$(add_wt f feat); move_plan "$W"; commit_in "$W" done
assert "끄기 스위치" no "$(blocked "$(WORKTREE_FINISH_GUARD_DISABLED=1 stop_hook "$W" s1)")"
repo g; W=$(add_wt g feat); move_plan "$W"; commit_in "$W" done
git -C "$M" merge -q --squash feat && git -C "$M" commit -qm squashed
assert "squash 로 이미 들어감(main 과 내용이 같음, 리뷰 M3)" no "$(blocked "$(stop_hook "$W" s1)")"
mkdir -p "$TMP/plain"
assert "git 저장소가 아닌 cwd" no "$(blocked "$(stop_hook "$TMP/plain" s1)")"

echo "[main 이름] master 저장소에서도 막는다(리뷰 M4)"
repo h master; W=$(add_wt h feat); move_plan "$W"; commit_in "$W" done
assert "master 에서 막음" yes "$(blocked "$(stop_hook "$W" s1)")"

echo "[로그] 판정 실패는 worktree 에서도 .hermes/hooks.log 에 남는다(리뷰 H1)"
repo i trunk; W=$(add_wt i feat); move_plan "$W"; commit_in "$W" done
assert "막지 않음" no "$(blocked "$(stop_hook "$W" s1)")"
assert "로그에 판정 실패" 1 "$(grep -c 'worktree-finish-guard.*판정 실패' "$W/.hermes/hooks.log" 2>/dev/null)"

echo "[설치] 임시 프로젝트에 harness 를 깔면 훅 3개가 등록되고 모듈 4개·스킬이 복사된다"
export HARNESS_TOOL_INSTALL=0 HARNESS_SYNC_AUTOENABLE=0 HERMES_NO_REGISTER=1
REGISTRY="$REPO_ROOT/.installed-projects"
trap 'if [[ -f "$REGISTRY" ]]; then grep -vF "$TMP" "$REGISTRY" > "$REGISTRY.tmp$$" || true; mv "$REGISTRY.tmp$$" "$REGISTRY"; fi; rm -rf "$TMP"' EXIT
P="$TMP/proj"; mkdir -p "$P" && git -C "$P" init -q
if bash "$REPO_ROOT/project-claude.sh" "$P" harness > "$TMP/install.log" 2>&1; then
  for h in claude-stop-worktree-finish-guard.sh claude-sessionstart-unmerged-worktrees.sh claude-pretooluse-plan-overlap-guard.sh; do
    assert "settings.json 에 $h" 1 "$(grep -c "$h" "$P/.claude/settings.json")"
  done
  for m in worktree_state.py worktree_finish_guard.py worktree_notice.py plan_overlap.py; do
    assert "scripts/hooks/$m 복사" yes "$([[ -f "$P/scripts/hooks/$m" ]] && echo yes || echo no)"
  done
  assert "스킬 finish.sh 복사" yes "$([[ -f "$P/.claude/skills/worktree-finish/scripts/finish.sh" ]] && echo yes || echo no)"
  assert "Stop 칸에 등록" 1 "$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(sum("worktree-finish-guard" in json.dumps(e) for e in d["hooks"].get("Stop",[])))' "$P/.claude/settings.json")"
else
  assert "설치 성공" 0 1; tail -5 "$TMP/install.log"
fi

finish_tests
