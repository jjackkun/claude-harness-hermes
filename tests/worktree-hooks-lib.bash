#!/usr/bin/env bash
# worktree 훅 시험 3개(G2·G3·G4)가 함께 쓰는 도우미 — source 해서 쓴다. 모델 0, 네트워크 0.
# 시험은 임시 폴더 안에서만 돈다(2026-11-20 사고: 상대 git 경로로 공장 .git 을 덮었다).
# 계획: docs/exec-plans/completed/2026-11-20-worktree-finish-plan.md (Step 3)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS="$REPO_ROOT/assets/hooks"
# 커밋 게이트 안에서 돌면 git 이 넘기는 위치 변수가 임시 저장소 대신 이 저장소를 가리킨다 — 지운다.
unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_PREFIX
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cd "$TMP" || exit 1
PASS=0; FAIL=0
assert() { if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; PASS=$((PASS+1)); else echo "  ✗ $1 (expected=$2 actual=$3)"; FAIL=$((FAIL+1)); fi; }
PLAN_REL="docs/exec-plans/active/2026-11-20-x-plan.md"
DONE_REL="docs/exec-plans/completed/2026-11-20-x-plan.md"

# 새 저장소 $TMP/<이름>/main(계획서 하나) — 전역 M 을 채운다. 둘째 인자는 기본 브랜치 이름(기본 main).
repo() {
  M="$TMP/$1/main"; mkdir -p "$M/docs/exec-plans/active" && git -C "$M" init -q -b "${2:-main}"
  printf '# plan\n' > "$M/$PLAN_REL"
  printf '.hermes/hooks.log\n' > "$M/.gitignore"   # 설치된 프로젝트와 같게 — 훅이 남기는 로그는 변경으로 세지 않는다
  git -C "$M" add -A && git -C "$M" commit -qm init
}
# worktree $TMP/<저장소>/<이름>(브랜치 같은 이름) — 경로를 출력한다.
add_wt() { local p="$TMP/$1/$2"; git -C "$M" worktree add -q -b "$2" "$p"; echo "$p"; }
commit_in() { git -C "$1" add -A && git -C "$1" commit -qm "${2:-work}"; }
move_plan() { mkdir -p "$1/docs/exec-plans/completed" && git -C "$1" mv "$PLAN_REL" "$DONE_REL"; }
finish_tests() { echo "결과: $PASS 통과 · $FAIL 실패"; [[ "$FAIL" -eq 0 ]]; }
