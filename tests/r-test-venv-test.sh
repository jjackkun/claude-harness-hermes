#!/usr/bin/env bash
# R-test 게이트: 프로젝트 가상환경의 pytest 를 먼저 쓰고, 걸린 시간·건너뜀을 보이게 한다
# (계획 docs/exec-plans/completed/2026-09-30-test-speed-gate.md 목표 1·2).
#
#   1 backend/.venv 의 pytest 를 고른다(uv 프로젝트) · .venv 와 venv 가 함께 있으면 .venv
#   2 가상환경이 없으면 시스템 pytest(경고 없음 — 정상) · 가상환경 폴더가 있는데 pytest 가 없으면 시스템 + 경고
#   3 걸린 시간을 게이트 기록 detail 에 남기고, 기준을 넘으면 원인(원격 DB 등)을 짚는 경고
#   4 통과여도 건너뜀이 통과보다 많으면 "시험 DB 가 꺼져 있을 수 있다" 경고
#
# 픽스처에 harness 를 실제로 설치하고 .git/hooks/pre-commit 을 돌린다. pytest 는 가짜(부른 경로를 적는다).
set -uo pipefail
export HARNESS_TOOL_INSTALL=0 HARNESS_SYNC_AUTOENABLE=0
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
REGISTRY="$REPO_ROOT/.installed-projects"
cleanup() {
  if [[ -f "$REGISTRY" ]]; then
    grep -vxF "$TMP/p" "$REGISTRY" > "$REGISTRY.tmp$$" || true
    mv "$REGISTRY.tmp$$" "$REGISTRY"
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
PASS=0; FAIL=0
assert() { if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; PASS=$((PASS+1)); else echo "  ✗ $1 (expected=$2 actual=$3)"; FAIL=$((FAIL+1)); fi; }
has() { grep -qF -- "$2" <<<"$1" && echo 1 || echo 0; }

P="$TMP/p"; mkdir -p "$P"; cd "$P"
git init -q; git config user.email t@t; git config user.name t
bash "$REPO_ROOT/project-claude.sh" . harness >/dev/null 2>&1
git add -A >/dev/null 2>&1; git commit -qm base --no-gpg-sign >/dev/null 2>&1 || git commit -qm base >/dev/null 2>&1
mkdir -p backend/tests
printf 'def test_ok():\n    assert True\n' > backend/tests/test_ok.py

WHO="$TMP/who"; SLEEP_S=0; SUMMARY="3 passed in 0.10s"
fake() {   # fake <경로> — 부른 경로를 적고 SUMMARY 를 찍는 가짜 pytest
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<SH
#!/usr/bin/env bash
[[ "\${1:-}" == "--version" ]] && { echo "pytest 8.0.0"; exit 0; }
echo "$1" > "$WHO"
sleep "\${FAKE_SLEEP:-0}"
echo "\${FAKE_SUMMARY:-3 passed in 0.10s}"
exit 0
SH
  chmod +x "$1"
}
run_gate() {   # 새 .py 를 스테이징하고 pre-commit 을 돈다 → 출력
  : > "$WHO"
  echo "x = $RANDOM" > "backend/mod_$RANDOM.py"; git add -A backend >/dev/null 2>&1
  .git/hooks/pre-commit 2>&1
}
last_detail() { python3 -c "
import json,sys
rows=[json.loads(l) for l in open('.harness/gate-events.jsonl') if '\"R-test\"' in l]
print(rows[-1].get('detail','') if rows else '')" 2>/dev/null; }

echo "== 1. 프로젝트 가상환경을 먼저 고른다"
fake "$P/backend/.venv/bin/pytest"
OUT="$(run_gate)"
assert "backend/.venv 의 pytest 가 불린다" "$P/backend/.venv/bin/pytest" "$(cat "$WHO")"
assert "시스템 대체 경고는 없다" 0 "$(has "$OUT" "시스템 pytest")"
fake "$P/backend/venv/bin/pytest"
run_gate >/dev/null
assert ".venv 와 venv 가 함께 있으면 .venv" "$P/backend/.venv/bin/pytest" "$(cat "$WHO")"
rm -rf backend/.venv
run_gate >/dev/null
assert ".venv 가 없으면 venv(기존 동작 유지)" "$P/backend/venv/bin/pytest" "$(cat "$WHO")"
rm -rf backend/venv

echo "== 2. 시스템 pytest 로 떨어질 때"
BIN="$TMP/bin"; fake "$BIN/pytest"
OUT="$(PATH="$BIN:$PATH" run_gate)"
assert "가상환경이 없으면 시스템 pytest 가 불린다" "$BIN/pytest" "$(cat "$WHO")"
assert "가상환경이 없으면 경고하지 않는다(정상 구성)" 0 "$(has "$OUT" "시스템 pytest")"
mkdir -p backend/.venv/bin
OUT="$(PATH="$BIN:$PATH" run_gate)"
assert "가상환경 폴더가 있는데 pytest 가 없으면 시스템으로 돈다" "$BIN/pytest" "$(cat "$WHO")"
assert "  … 그때는 경고한다(조용한 대체 금지)" 1 "$(has "$OUT" "시스템 pytest")"
fake "$P/backend/.venv/bin/pytest"

echo "== 3. 걸린 시간을 남기고, 길면 원인을 짚는다"
OUT="$(run_gate)"
assert "게이트 기록에 걸린 시간(초)이 남는다" 1 "$(has "$(last_detail)" "초")"
assert "짧으면 시간 경고가 없다" 0 "$(has "$OUT" "오래 걸렸다")"
OUT="$(FAKE_SLEEP=2 HARNESS_RTEST_WARN_SEC=1 run_gate)"
assert "기준을 넘으면 시간 경고" 1 "$(has "$OUT" "오래 걸렸다")"
assert "경고가 원인(원격 DB·네트워크)을 짚는다" 1 "$(has "$OUT" "원격")"

echo "== 4. 건너뜀이 통과보다 많으면 경고"
OUT="$(FAKE_SUMMARY='1 passed, 5 skipped in 0.20s' run_gate)"
assert "건너뜀이 많다고 경고" 1 "$(has "$OUT" "건너뜀")"
assert "통과 판정 자체는 유지(차단 아님)" 1 "$(has "$(last_detail)" "통과")"
OUT="$(FAKE_SUMMARY='5 passed, 1 skipped in 0.20s' run_gate)"
assert "건너뜀이 적으면 경고 없음" 0 "$(has "$OUT" "대부분 건너뜀")"

echo
echo "결과: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
