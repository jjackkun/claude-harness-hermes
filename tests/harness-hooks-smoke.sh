#!/usr/bin/env bash
# 하네스 hook 스모크 테스트 — 실제 차단 경로를 통과시켜 silent-failure 회귀 방지.
#
# 왜 이 테스트가 필요한가:
#   2026-04-14 1차 PR 자가 검증은 "project-claude.sh 가 에러 없이 끝났다" 만 확인했고,
#   pre-commit.sh 의 filter_files() 가 set -e 와 충돌해 *모든 검사 단계가 조용히 skip*
#   되는 버그를 놓쳤다. 실제 위반 파일을 스테이징하고 exit code 를 단언하는 테스트만이
#   그런 결함을 잡을 수 있다.
#
# 실행: bash tests/harness-hooks-smoke.sh
# 종료 코드: 0 = 모든 단언 통과, 1 = 실패

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d)
export HOME="$TMP/fakehome"         # 실 ~/.claude/projects 절대 격리 (install_memory_symlink)
mkdir -p "$HOME"

# 테스트 설치가 .installed-projects 레지스트리를 오염시키지 않도록 끝에서 원복
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
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  ✓ $desc"
    PASS=$((PASS+1))
  else
    echo "  ✗ $desc (expected=$expected actual=$actual)"
    FAIL=$((FAIL+1))
  fi
}

echo "== Setting up fixture project =="
cd "$TMP"
git init -q
# CI 등 git identity 미설정 환경에서도 fixture commit 이 동작하도록 로컬 설정
git config user.email "harness-test@example.com"
git config user.name "harness-test"
bash "$REPO_ROOT/project-claude.sh" . harness >/dev/null

echo ""
echo "== 1. pre-commit R-size 차단 =="
seq 1 15 | sed 's/.*/x = &/' > big.py
git add big.py
HOOK_OUT=$(MAX_LINES_HARD=10 .git/hooks/pre-commit 2>&1); HOOK_EXIT=$?
assert "위반 파일 스테이징 시 exit 1" "1" "$HOOK_EXIT"
echo "$HOOK_OUT" | grep -q "\[R-size\]"
assert "실제 R-size 메시지 출력 (silent-skip 방지)" "0" "$?"

MAX_LINES_HARD=10 git commit -m "should block" >/dev/null 2>&1
assert "git commit end-to-end 차단" "1" "$?"

echo ""
echo "== 2. pre-commit 통과 경로 =="
echo "x = 1" > small.py
git add small.py
git rm --cached big.py >/dev/null
rm -f big.py
git commit -m "should pass" >/dev/null 2>&1
assert "정상 파일은 통과" "0" "$?"

echo ""
echo "== 3. PreToolUse git commit 감지 =="
OUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' \
  | scripts/hooks/claude-pretooluse-bash-guard.sh 2>&1)
echo "$OUT" | grep -q "code-reviewer"
assert "git commit 시 리뷰 검토 안내" "0" "$?"

echo ""
echo "== 4. PreToolUse --no-verify 탐지 =="
OUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"git commit --no-verify -m x"}}' \
  | scripts/hooks/claude-pretooluse-bash-guard.sh 2>&1)
echo "$OUT" | grep -q "\[R5\]"
assert "--no-verify 탐지" "0" "$?"

echo ""
echo "== 5. PreToolUse 정상 명령 무간섭 =="
OUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"git status"}}' \
  | scripts/hooks/claude-pretooluse-bash-guard.sh 2>&1)
assert "git status 는 간섭 없음" "" "$OUT"

echo ""
echo "== 6. UserPromptSubmit 리마인더 출력 =="
OUT=$(echo '{}' | scripts/hooks/claude-userpromptsubmit-reminders.sh 2>&1)
echo "$OUT" | grep -q "Harness Reminders"
assert "리마인더 블록 출력" "0" "$?"

echo ""
echo "== 7. PostToolUse size-warn SOFT/HARD =="
seq 1 410 | sed 's/.*/x = &/' > soft.py
OUT=$(echo '{"tool_input":{"file_path":"'"$TMP"'/soft.py"}}' \
  | scripts/hooks/claude-posttooluse-size-warn.sh 2>&1)
echo "$OUT" | grep -q "R-size SOFT"
assert "400 줄 초과 soft 경고" "0" "$?"

seq 1 520 | sed 's/.*/x = &/' > hard.py
OUT=$(echo '{"tool_input":{"file_path":"'"$TMP"'/hard.py"}}' \
  | scripts/hooks/claude-posttooluse-size-warn.sh 2>&1)
echo "$OUT" | grep -q "R-size HARD"
assert "500 줄 초과 hard 경고" "0" "$?"

echo "x = 1" > tiny.py
OUT=$(echo '{"tool_input":{"file_path":"'"$TMP"'/tiny.py"}}' \
  | scripts/hooks/claude-posttooluse-size-warn.sh 2>&1)
assert "작은 파일은 조용함" "" "$OUT"

echo ""
echo "== 8. PostToolUse review-reminder 편집 기록 =="
rm -f .claude/.review-dirty
OUT=$(echo '{"tool_input":{"file_path":"x.py"}}' \
  | scripts/hooks/claude-posttooluse-review-reminder.sh 2>&1)
echo "$OUT" | grep -q "R-review"
assert "첫 코드 편집은 리뷰 검토 안내" "0" "$?"
assert "편집 기록 파일 생성됨" "0" "$([[ -f .claude/.review-dirty ]] && echo 0 || echo 1)"

OUT=$(echo '{"tool_input":{"file_path":"y.py"}}' \
  | scripts/hooks/claude-posttooluse-review-reminder.sh 2>&1)
assert "두 번째 코드 편집은 조용히 누적" "" "$OUT"

OUT=$(echo '{"tool_input":{"file_path":"README.md"}}' \
  | scripts/hooks/claude-posttooluse-review-reminder.sh 2>&1)
assert "문서 파일은 dirty 영향 없음" "" "$OUT"

echo ""
echo "== 8b. bash-guard 가 편집 기록 상태에서 git commit 허용 =="
OUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' \
  | scripts/hooks/claude-pretooluse-bash-guard.sh 2>&1); EXIT=$?
assert "편집 기록 상태 commit 은 통과(경고만)" "0" "$EXIT"
echo "$OUT" | grep -q "최근 코드 편집 기록"
assert "편집 기록 메시지 출력" "0" "$?"

rm -f .claude/.review-dirty
OUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' \
  | scripts/hooks/claude-pretooluse-bash-guard.sh 2>&1); EXIT=$?
assert "clean 상태 commit 은 통과(경고만)" "0" "$EXIT"

echo ""
echo "== 10. hook 을 다른 CWD 에서 호출해도 정상 (CWD 의존 버그 방지) =="
# 근거: 2026-04-17-harness-hook-path-cwd-bug — settings 의 상대 경로 command 가
#        CWD 가 프로젝트 루트가 아닐 때 hook 을 silent 하게 못 찾던 버그 회귀 방지.
# hooks 는 settings 분리 구조에서 .claude/settings.json (committed) 으로 이동했다.
# 10a: 등록된 command 가 ${CLAUDE_PROJECT_DIR} 기반 절대 참조인지 검증.
REL_COUNT=$(grep -c '"command": *"scripts/hooks' .claude/settings.json 2>/dev/null; true)
REL_COUNT=${REL_COUNT:-0}
assert "settings.json 에 상대 scripts/hooks 경로 없음" "0" "$REL_COUNT"

ABS_COUNT=$(grep -c '\${CLAUDE_PROJECT_DIR}/scripts/hooks' .claude/settings.json 2>/dev/null; true)
ABS_COUNT=${ABS_COUNT:-0}
assert "settings.json 에 \${CLAUDE_PROJECT_DIR} 기반 경로 존재" "8" "$ABS_COUNT"

# 10b: 실제로 다른 CWD 에서 hook 을 호출해도 self-locate 가드로 정상 동작.
PROJ_ABS="$(pwd)"
pushd / >/dev/null
OUT=$(CLAUDE_PROJECT_DIR="$PROJ_ABS" bash "$PROJ_ABS/scripts/hooks/claude-userpromptsubmit-reminders.sh" <<< '{}' 2>&1)
popd >/dev/null
echo "$OUT" | grep -q "Harness Reminders"
assert "다른 CWD 에서 reminders hook 정상 출력" "0" "$?"

# 10c: CLAUDE_PROJECT_DIR 미설정 시 self-locate 가드만으로도 동작.
rm -f .claude/.review-dirty
pushd / >/dev/null
OUT=$(unset CLAUDE_PROJECT_DIR; echo '{"tool_input":{"file_path":"x.py"}}' \
  | bash "$PROJ_ABS/scripts/hooks/claude-posttooluse-review-reminder.sh" 2>&1)
popd >/dev/null
echo "$OUT" | grep -q "R-review"
assert "CLAUDE_PROJECT_DIR 없어도 self-locate 로 동작" "0" "$?"
assert "self-locate 경로에서 dirty 파일 생성" "0" "$([[ -f .claude/.review-dirty ]] && echo 0 || echo 1)"
rm -f .claude/.review-dirty

echo ""
echo "== 11. install_harness_gc_workflows — remote host 감지 =="
# 3 케이스: github / gitlab / remote 없음.
# 현재 fixture 프로젝트에는 remote 없음 → .github/workflows 가 *이미* 없어야 함.
GC_PROJ_GH=$(mktemp -d)
git -C "$GC_PROJ_GH" init -q
git -C "$GC_PROJ_GH" remote add origin https://github.com/test/foo.git
(
  source "$REPO_ROOT/lib/common.sh"
  ASSETS_DIR="$REPO_ROOT/assets"
  HARNESS_DOC_GARDENING=1
  install_harness_gc_workflows "$GC_PROJ_GH"
) >/dev/null
assert "github.com remote → .github/workflows/weekly-doc-gardening.yml 생성" \
  "0" "$([[ -f $GC_PROJ_GH/.github/workflows/weekly-doc-gardening.yml ]] && echo 0 || echo 1)"
rm -rf "$GC_PROJ_GH"

GC_PROJ_GL=$(mktemp -d)
git -C "$GC_PROJ_GL" init -q
git -C "$GC_PROJ_GL" remote add origin git@gitlab.com:test/foo.git
(
  source "$REPO_ROOT/lib/common.sh"
  ASSETS_DIR="$REPO_ROOT/assets"
  HARNESS_DOC_GARDENING=1
  install_harness_gc_workflows "$GC_PROJ_GL"
) >/dev/null
assert "gitlab.com remote → .gitlab/doc-gardening.yml 생성" \
  "0" "$([[ -f $GC_PROJ_GL/.gitlab/doc-gardening.yml ]] && echo 0 || echo 1)"
rm -rf "$GC_PROJ_GL"

GC_PROJ_NO=$(mktemp -d)
git -C "$GC_PROJ_NO" init -q
(
  source "$REPO_ROOT/lib/common.sh"
  ASSETS_DIR="$REPO_ROOT/assets"
  HARNESS_DOC_GARDENING=1
  install_harness_gc_workflows "$GC_PROJ_NO"
) >/dev/null
assert "remote 없음 → 워크플로 파일 생성 안 됨 (.github 없음)" \
  "0" "$([[ ! -d $GC_PROJ_NO/.github ]] && echo 0 || echo 1)"
assert "remote 없음 → 워크플로 파일 생성 안 됨 (.gitlab 없음)" \
  "0" "$([[ ! -d $GC_PROJ_NO/.gitlab ]] && echo 0 || echo 1)"
rm -rf "$GC_PROJ_NO"

echo ""
echo "== 9. CLAUDE.md 100 줄 한도 =="
LINES=$(wc -l < CLAUDE.md)
if (( LINES <= 100 )); then
  assert "CLAUDE.md <= 100 줄 ($LINES)" "ok" "ok"
else
  assert "CLAUDE.md <= 100 줄 ($LINES)" "ok" "fail"
fi

echo ""
echo "== 12. R-plan grep -c 산술 비교 버그 회귀 =="
# 체크박스 없는 .md 파일이 active/ 에 있을 때 pre-commit stderr 에
# 'syntax error' 가 없어야 함. (grep -c || echo 0 이중 출력 버그 회귀 방지)
mkdir -p docs/exec-plans/active
cat > docs/exec-plans/active/no-checkbox-fixture.md << 'FIXTURE'
# 체크박스 없는 계획서 (회귀 테스트 fixture)
이 파일은 R-plan grep -c 버그 회귀 테스트용입니다.
FIXTURE
echo "x = 1" > small2.py
git add small2.py docs/exec-plans/active/no-checkbox-fixture.md
HOOK_STDERR=$(.git/hooks/pre-commit 2>&1 >/dev/null); HOOK_EXIT=$?
echo "$HOOK_STDERR" | grep -qv 'syntax error'
assert "체크박스 없는 .md 에서 syntax error 없음" "0" "$?"
assert "pre-commit 정상 종료 (0 또는 위반 없음)" "0" "$HOOK_EXIT"
rm -f docs/exec-plans/active/no-checkbox-fixture.md small2.py

echo ""
echo "== 결과 =="
echo "  통과: $PASS / 실패: $FAIL"
[[ $FAIL -eq 0 ]]
