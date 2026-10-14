#!/usr/bin/env bash
# R-size 의 원본(upstream) 소유 파일 제외 — 계획 docs/exec-plans/active/2026-10-15-r-size-upstream-owned.md
#
#   G1 UPSTREAM_REF 에 이미 있는 파일은 500줄을 넘어도 R-size 가 막지 않는다
#   G2 포크가 새로 만든 파일은 지금처럼 막는다
#   G3 UPSTREAM_REF 가 설정됐는데 ref 가 없으면 막고, 안내에 git fetch 를 적는다
#   G4 UPSTREAM_REF 가 없으면 동작이 그대로다 (원본 파일도 막는다)
#   G5 빠진 판정은 출력에 원본 소유 안내 줄로 남는다
#
# 실행: bash tests/r-size-upstream-owned-test.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PC="$ROOT/assets/hooks/pre-commit.sh"
PASS=0; FAIL=0
assert() {
  if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; PASS=$((PASS+1))
  else echo "  ✗ $1 (expected=$2 actual=$3)"; FAIL=$((FAIL+1)); fi
}

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
big() { seq 1 600 | sed 's/^/x = /'; }   # 600줄짜리 .py

# 원본 저장소를 흉내 내는 임시 저장소: upstream_owned.py 는 원본에 있고,
# refs/remotes/upstream/main 이 그 커밋을 가리킨다.
make_repo() {
  local r="$1"
  mkdir -p "$r" && cd "$r" || exit 1
  git init -q && git config user.email t@t && git config user.name t
  big > upstream_owned.py
  git add upstream_owned.py && git commit -qm upstream
  git update-ref refs/remotes/upstream/main HEAD
}

# 스테이징된 상태에서 pre-commit 을 돌려 R-size 관련 줄만 남긴다.
rsize_lines() { bash "$PC" 2>&1 | grep -E '^\[R-size' ; return 0; }

echo "[1] UPSTREAM_REF 있음 · ref 있음"
make_repo "$T/a"
echo 'UPSTREAM_REF=upstream/main' > .harnessrc
echo 'y = 1' >> upstream_owned.py
big > fork_new.py
git add upstream_owned.py fork_new.py
OUT="$(rsize_lines)"
assert "G1 원본 파일(upstream_owned.py)은 차단 안 함" "0" "$(grep -c '^\[R-size\] upstream_owned.py' <<<"$OUT")"
assert "G2 포크 새 파일(fork_new.py)은 차단" "1" "$(grep -c '^\[R-size\] fork_new.py' <<<"$OUT")"
assert "G5 원본 파일은 안내 줄로 남는다" "1" "$(grep -c '^\[R-size:upstream\] upstream_owned.py' <<<"$OUT")"

echo "[2] UPSTREAM_REF 있음 · ref 없음 (받아오지 않은 클론)"
make_repo "$T/b"
git update-ref -d refs/remotes/upstream/main
echo 'UPSTREAM_REF=upstream/main' > .harnessrc
echo 'y = 1' >> upstream_owned.py
git add upstream_owned.py
OUT="$(bash "$PC" 2>&1)"
assert "G3 ref 없으면 원본 파일도 차단" "1" "$(grep -c '^\[R-size\] upstream_owned.py' <<<"$OUT")"
assert "G3 안내에 git fetch 가 있다" "1" "$(grep -c 'git fetch' <<<"$OUT" | awk '{print ($1>0)?1:0}')"

echo "[3] UPSTREAM_REF 없음"
make_repo "$T/c"
echo 'y = 1' >> upstream_owned.py
git add upstream_owned.py
OUT="$(rsize_lines)"
assert "G4 설정 없으면 원본 파일도 지금처럼 차단" "1" "$(grep -c '^\[R-size\] upstream_owned.py' <<<"$OUT")"
assert "G4 설정 없으면 원본 안내 줄 없음" "0" "$(grep -c '^\[R-size:upstream\]' <<<"$OUT")"

echo
echo "r-size-upstream-owned: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
