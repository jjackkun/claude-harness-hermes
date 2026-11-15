#!/usr/bin/env bash
# 공장 위치 기록 — 계획 docs/exec-plans/active/2026-11-15-upstream-version-watch-plan.md G6
#
#   - 메인 저장소에서 부르면 그 루트를 ~/.hermes/factory-path 에 쓴다
#   - 워크트리에서 불러도 메인 루트를 쓴다(사라질 워크트리 경로를 쓰지 않는다)
#   - 장부(assets/upstream.json)가 없는 저장소는 공장이 아니므로 쓰지 않는다
#   - 임시 경로 공장은 쓰지 않는다
#   - git 저장소가 아니면 조용히 넘어간다
#
# HOME 을 바꿔 진짜 ~/.hermes 를 건드리지 않는다.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d); export HOME="$TMP/fakehome"; mkdir -p "$HOME"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
assert() { if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; PASS=$((PASS+1)); else echo "  ✗ $1 (expected=$2 actual=$3)"; FAIL=$((FAIL+1)); fi; }

# shellcheck source=lib/registry.sh
source "$REPO_ROOT/lib/registry.sh"
# shellcheck source=lib/factory_path.sh
source "$REPO_ROOT/lib/factory_path.sh"
FP="$HOME/.hermes/factory-path"

mkrepo() {   # <dir> [with-ledger]
  mkdir -p "$1"; git -C "$1" init -q; git -C "$1" config user.name t; git -C "$1" config user.email t@t
  if [[ "${2:-}" == ledger ]]; then mkdir -p "$1/assets"; echo '{"version":1,"items":[]}' > "$1/assets/upstream.json"; fi
  echo x > "$1/f"; git -C "$1" add -A; git -C "$1" commit -qm init
}

# 임시 경로 판정을 끈 판으로 기록 규칙만 본다 (실제 판정은 마지막 절에서)
real_is_temp="$(declare -f registry_is_temp_path)"
registry_is_temp_path() { return 1; }

echo "== 메인 저장소 =="
F="$TMP/factory"; mkrepo "$F" ledger
factory_path_record "$F"
assert "메인 루트를 쓴다" "$(cd "$F" && pwd -P)" "$(cat "$FP" 2>/dev/null)"

echo "== 워크트리 =="
rm -f "$FP"
git -C "$F" worktree add -q "$TMP/wt" -b wt >/dev/null 2>&1
factory_path_record "$TMP/wt"
assert "워크트리에서도 메인 루트를 쓴다" "$(cd "$F" && pwd -P)" "$(cat "$FP" 2>/dev/null)"

echo "== 장부 없는 저장소 =="
rm -f "$FP"
N="$TMP/notfactory"; mkrepo "$N"
factory_path_record "$N"
assert "장부가 없으면 쓰지 않는다" 0 "$([[ -f "$FP" ]] && echo 1 || echo 0)"

echo "== git 아님 =="
mkdir -p "$TMP/plain/assets"; echo '{}' > "$TMP/plain/assets/upstream.json"
factory_path_record "$TMP/plain"; rc=$?
assert "rc 0" 0 "$rc"
assert "git 이 아니면 쓰지 않는다" 0 "$([[ -f "$FP" ]] && echo 1 || echo 0)"

echo "== 임시 경로 (실제 판정) =="
eval "$real_is_temp"
factory_path_record "$F"
assert "임시 경로 공장은 쓰지 않는다" 0 "$([[ -f "$FP" ]] && echo 1 || echo 0)"

echo "== 메인 루트 함수 =="
assert "워크트리 → 메인" "$(cd "$F" && pwd -P)" "$(factory_main_root "$TMP/wt")"
assert "git 아님 → rc 1" 1 "$(factory_main_root "$TMP/plain" >/dev/null 2>&1; echo $?)"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
