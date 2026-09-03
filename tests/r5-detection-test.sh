#!/usr/bin/env bash
# R5 우회 탐지의 정탐·오탐 경계 — `-n` 은 `git commit` 문맥에서만 --no-verify 다.
#
# 근거: docs/exec-plans/active/2026-09-03-r5-false-positive.md
#       docs/audits/2026-09-03-gate-firing-first-observation.md (발화율 100%, 20건 전부 오탐)
#
# 실행: bash tests/r5-detection-test.sh
# 종료 코드: 0 = 모든 단언 통과, 1 = 실패

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$REPO_ROOT/assets/hooks/claude-pretooluse-bash-guard.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/proj/.claude"

PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  ✓ $desc"; PASS=$((PASS+1))
  else
    echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1))
  fi
}

# fires <command> — R5 경고가 나오면 1, 아니면 0
fires() {
  local out
  out=$(python3 -c "
import json, sys
print(json.dumps({'tool_input': {'command': sys.argv[1]}}))
" "$1" | CLAUDE_PROJECT_DIR="$TMP/proj" bash "$HOOK" 2>&1)
  grep -q '\[R5\]' <<< "$out" && echo 1 || echo 0
}

echo "== 오탐이어서는 안 되는 명령 (-n 이 --no-verify 가 아닌 문맥) =="

assert "grep -n"              "0" "$(fires 'grep -n foo file.txt')"
assert "sort -n"              "0" "$(fires 'sort -k1 -n -r data.txt')"
assert "head -n"              "0" "$(fires 'head -n 5 file.txt')"
assert "echo -n"              "0" "$(fires 'echo -n hello')"
assert "uniq -c | sort -n"    "0" "$(fires 'uniq -c | sort -n')"
assert "docker run -n"        "0" "$(fires 'docker ps -n 3')"
assert "평범한 명령"           "0" "$(fires 'ls -la')"
assert "git 이지만 commit 아님" "0" "$(fires 'git log -n 5')"

# 체이닝 — `-n` 과 `git commit` 이 **서로 다른 세그먼트**에 있으면 우회가 아니다.
# 명령 전체에서 두 조건을 따로 물으면 여기서 오탐이 난다 (code-reviewer 지적, 2026-09-03).
assert "git log -n 5 && 깨끗한 commit"  "0" "$(fires 'git log -n 5 && git commit -m "fix"')"
assert "grep -n 뒤 깨끗한 commit"       "0" "$(fires 'grep -n foo file.txt; git commit -m x')"
assert "head -n 뒤 깨끗한 commit"       "0" "$(fires 'head -n 5 file.txt && git commit -m x')"
assert "파이프 뒤 깨끗한 commit"         "0" "$(fires 'sort -n data.txt | tee out.txt && git commit -m x')"

echo "== 반드시 잡아야 하는 우회 =="

assert "git commit --no-verify"      "1" "$(fires 'git commit --no-verify -m x')"
assert "git commit -n"               "1" "$(fires 'git commit -n -m x')"
assert "git commit -nm (묶음 플래그)"  "1" "$(fires 'git commit -nm "메시지"')"
assert "git -c ... commit -n"        "1" "$(fires 'git -c user.email=t@t commit -n -m x')"
assert "--no-verify 가 뒤에"          "1" "$(fires 'git commit -m x --no-verify')"
assert "git push --no-verify"        "1" "$(fires 'git push --no-verify')"
assert "체이닝된 git commit -n"       "1" "$(fires 'git add . && git commit -n -m x')"
assert "앞 세그먼트에 -n 이 있어도 뒤 commit 이 진짜 우회면 잡는다" "1" \
  "$(fires 'grep -n foo f && git commit -n -m x')"
assert "파이프 뒤 우회"               "1" "$(fires 'echo x | tee f; git commit -nm y')"

echo
echo "통과 $PASS / 실패 $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
