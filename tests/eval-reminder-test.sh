#!/usr/bin/env bash
# R-eval — 규칙·강제 파일이 바뀐 공장 커밋에서 harness-eval 을 돌릴 때라고 알린다
# (계획 2026-09-21-harness-eval-trigger-gap 목표 1·2).
#
#   [a] harness-eval 이 없는 저장소(소우주)는 조용하다
#   [b] 공장 + 규칙 파일 스테이징 + 실행 기록 없음 → 경고 "기록 없음"
#   [c] 공장 + 규칙 파일 + 기록 3일 전 → 경고 "3일 전"
#   [d] 공장 + 무관 파일만 스테이징 → 조용하다
#   [e] 경고일 뿐 차단하지 않는다(게이트 이벤트가 warn)
#
# 픽스처에 harness 를 실제로 설치하고 .git/hooks/pre-commit 을 돌린다.
# 실행: bash tests/eval-reminder-test.sh
set -uo pipefail
export HARNESS_TOOL_INSTALL=0 HARNESS_SYNC_AUTOENABLE=0
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
REGISTRY="$REPO_ROOT/.installed-projects"
cleanup() {
  if [[ -f "$REGISTRY" ]]; then
    grep -vxF "$TMP" "$REGISTRY" > "$REGISTRY.tmp$$" || true
    mv "$REGISTRY.tmp$$" "$REGISTRY"
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
PASS=0; FAIL=0
assert() { if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; PASS=$((PASS+1)); else echo "  ✗ $1 (expected=$2 actual=$3)"; FAIL=$((FAIL+1)); fi; }

cd "$TMP"
git init -q
git config user.email "harness-test@example.com"; git config user.name "harness-test"
bash "$REPO_ROOT/project-claude.sh" . harness >/dev/null 2>&1
git add -A >/dev/null 2>&1; git commit -qm base --no-gpg-sign >/dev/null 2>&1 || git commit -qm base >/dev/null 2>&1
mkdir -p assets/rules scripts docs
reval() { .git/hooks/pre-commit 2>&1 | grep -c '^\[R-eval\]'; }
stage() { git reset -q >/dev/null 2>&1; git add "$@"; }

echo "[a] harness-eval 이 없으면(소우주) 조용하다"
echo "# 규칙" > assets/rules/x.md; stage assets/rules/x.md
assert "경고 0" "0" "$(reval)"

echo "[b] 공장 + 규칙 파일 + 기록 없음"
echo "# 공장 표식" > scripts/harness-eval.py
echo "# 규칙 수정" >> assets/rules/x.md; stage assets/rules/x.md
OUT=$(.git/hooks/pre-commit 2>&1)
assert "경고 1" "1" "$(grep -c '^\[R-eval\]' <<<"$OUT")"
assert "기록 없음이라고 말한다" "1" "$(grep -c '기록 없음' <<<"$OUT")"
assert "돌릴 명령을 준다" "1" "$(grep -c 'python3 scripts/harness-eval.py --k 2' <<<"$OUT")"
assert "바뀐 파일을 적는다" "1" "$(grep -c 'assets/rules/x.md' <<<"$OUT")"

echo "[c] 기록 3일 전"
mkdir -p .harness/evals; echo '{}' > .harness/evals/old.json; touch -d '3 days ago' .harness/evals/old.json
OUT=$(.git/hooks/pre-commit 2>&1)
assert "며칠 전인지 말한다" "1" "$(grep -c '3일 전' <<<"$OUT")"

echo "[d] 무관 파일만 스테이징"
echo "메모" > docs/note.md; stage docs/note.md
assert "경고 0" "0" "$(reval)"

echo "[e] 차단 아님 — 게이트 이벤트가 warn"
stage assets/rules/x.md
.git/hooks/pre-commit >/dev/null 2>&1
assert "gate-events 에 R-eval warn" "yes" "$(grep '"R-eval"' .harness/gate-events.jsonl 2>/dev/null | tail -1 | grep -q '"warn"' && echo yes || echo no)"

echo; echo "eval-reminder: PASS=$PASS FAIL=$FAIL"; [[ $FAIL -eq 0 ]]
