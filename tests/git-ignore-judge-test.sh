#!/usr/bin/env bash
# 무시 판정기 (계획 2026-09-22-gitignore-judge 목표 1) — git 판 차이와 무관하게 같은 답을 내는지.
# 옛 git(2.25.1)은 예외 규칙(`!`)에 걸린 경로에도 check-ignore 종료 코드 0 을 준다. 답은 `-v` 출력의 패턴에 있다.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"; JUDGE="$REPO_ROOT/scripts/git_ignore_judge.py"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
assert() { if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; PASS=$((PASS+1)); else echo "  ✗ $1 (expected=$2 actual=$3)"; FAIL=$((FAIL+1)); fi; }

P="$TMP/proj"; mkdir -p "$P/.claude" "$P/sub"
git -C "$P" init -q .; git -C "$P" config user.name t; git -C "$P" config user.email t@t
printf '.claude/*\n!.claude/keep.json\n' > "$P/.gitignore"
: > "$P/.claude/keep.json"; : > "$P/.claude/drop.json"; : > "$P/sub/free.txt"

# CLI: 종료 코드 0 = 무시됨, 1 = 무시 안 됨. 판정 불가(저장소 아님)는 2.
judge() { python3 "$JUDGE" --repo "$P" "$1" >/dev/null 2>&1; echo $?; }

echo "== 예외 규칙이 뒤에 오면 무시가 풀린다 =="
assert "예외로 되살아난 경로는 무시 아님" 1 "$(judge .claude/keep.json)"
assert "같은 블록의 다른 파일은 무시됨" 0 "$(judge .claude/drop.json)"
assert "규칙에 안 걸리는 경로는 무시 아님" 1 "$(judge sub/free.txt)"

echo "== 파이썬에서 직접 =="
py() { PYTHONPATH="$REPO_ROOT/scripts" python3 -c "
from git_ignore_judge import is_ignored
print(is_ignored('$P', '$1'))"; }
assert "is_ignored(keep) False" "False" "$(py .claude/keep.json)"
assert "is_ignored(drop) True" "True" "$(py .claude/drop.json)"

echo "== 저장소가 아니면 판정 불가 =="
N="$TMP/nogit"; mkdir -p "$N"; : > "$N/x"
python3 "$JUDGE" --repo "$N" x >/dev/null 2>&1; assert "git 저장소 아님 → rc 2" 2 "$?"

echo "== 판정이 한 곳에만 있다 (목표 2) =="
# 주석에 낱말이 남는 것은 괜찮다 — 세는 것은 **실제 호출**(`git … check-ignore`)이다.
OTHERS=$(grep -rn "git .*check-ignore" "$REPO_ROOT/scripts" "$REPO_ROOT/lib" "$REPO_ROOT/assets" 2>/dev/null \
  | grep -v "__pycache__" | grep -v "git_ignore_judge.py" | grep -vE ":[0-9]+: *#" | wc -l)
assert "판정기 밖에 check-ignore 호출 없음" 0 "$OTHERS"

echo; echo "git-ignore-judge: PASS=$PASS FAIL=$FAIL"; [[ $FAIL -eq 0 ]]
