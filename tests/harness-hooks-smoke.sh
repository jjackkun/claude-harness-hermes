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
echo "== 1b. pre-commit R-cx 차단 (라쳇) =="
# 배선 검사다 — 계산기 자체의 판정은 tests/complexity-gate-test.sh 가 본다.
# 여기서 보는 것은 "pre-commit 단계가 실제로 계산기를 부르는가" 뿐이다.
# 근거: docs/superpowers/specs/2026-08-24-complexity-gate-design.md
{ echo "def f(x):"; for i in $(seq 1 11); do echo "    if x == $i: return $i"; done; echo "    return 0"; } > cx.py
git add cx.py
HOOK_OUT=$(.git/hooks/pre-commit 2>&1); HOOK_EXIT=$?
assert "복잡도 12 스테이징 시 exit 1" "1" "$HOOK_EXIT"
echo "$HOOK_OUT" | grep -q "\[R-cx\]"
assert "실제 R-cx 메시지 출력 (silent-skip 방지)" "0" "$?"

# 라쳇: .cxbaseline 이 그 파일을 허용하면 통과해야 한다.
echo "cx.py 12" > .cxbaseline
HOOK_OUT=$(.git/hooks/pre-commit 2>&1); HOOK_EXIT=$?
assert "기준선이 허용하면 통과" "0" "$HOOK_EXIT"
rm -f .cxbaseline cx.py
git rm --cached cx.py >/dev/null 2>&1 || true

echo ""
echo "== 1c. pre-commit R-dep 배선 =="
# R-cx 에서 complexity.py 가 .git/hooks/ 에 안 깔려 게이트가 죽어 있던 사고를 겪었다.
# 모듈 단위 테스트는 전부 통과하고 있었다. 그래서 배선을 따로 고정한다.
mkdir -p dep
cat > .deprc <<'EOF'
scope: dep/*.py
tier: 0  dep/low.py
tier: 1  dep/high.py
EOF
echo "import high" > dep/low.py
echo "x = 1"       > dep/high.py
git add .deprc dep/low.py dep/high.py
HOOK_OUT=$(.git/hooks/pre-commit 2>&1); HOOK_EXIT=$?
assert "계층 역전 스테이징 시 exit 1" "1" "$HOOK_EXIT"
echo "$HOOK_OUT" | grep -q "\[R-dep-1\]"
assert "실제 R-dep 메시지 출력 (silent-skip 방지)" "0" "$?"

echo "x = 1" > dep/low.py
git add dep/low.py
HOOK_OUT=$(.git/hooks/pre-commit 2>&1); HOOK_EXIT=$?
assert "계약을 지키면 통과" "0" "$HOOK_EXIT"
git rm --cached -q .deprc dep/low.py dep/high.py >/dev/null 2>&1 || true
rm -rf .deprc dep

echo ""
echo "== 1d. pre-commit R-test — 세 상태를 구분한다 =="
# 이 게이트는 파이썬 테스트가 0개인 상태로 exit 5 를 통과 처리하며
# **한 번도 무언가를 막은 적이 없었다.** 판정 자체는 옳다(파이썬 없는 프로젝트도 설치 대상).
# 문제는 그 예외 경로에 영구히 머물러 있다는 사실을 아무도 모른다는 것이었다.
#
# 그리고 "도구가 못 뜬 것" 과 "테스트가 실패한 것" 을 구분하지 못했다.
# 실제로 이 스모크가 HOME 을 격리하는 순간 pytest 가 자기 모듈을 import 하지 못해
# ModuleNotFoundError Traceback 이 "[R-test] pytest 실패" 로 보고되며 커밋을 막았다.
# 근거: docs/superpowers/specs/2026-08-24-coverage-enforcement-design.md 1단계
mkdir -p tests
echo "def add(a, b): return a + b" > lib_under_test.py
git add lib_under_test.py

# PATH 앞단에 가짜 pytest 를 놓아 종료코드를 통제한다.
# 실제 pytest 에 의존하면 이 스모크가 환경에 따라 흔들린다.
mkdir -p "$TMP/bin"
mock_pytest() {  # $1 = --version 성공 여부(ok/broken), $2 = 실행 종료코드
  cat > "$TMP/bin/pytest" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == "--version" ]]; then
  [[ "$1" == "ok" ]] && { echo "pytest 8.0.0"; exit 0; } || { echo "ModuleNotFoundError: No module named 'pytest'" >&2; exit 1; }
fi
echo "mock pytest run"
exit $2
EOF
  chmod +x "$TMP/bin/pytest"
}
export PATH="$TMP/bin:$PATH"

mock_pytest ok 5
HOOK_OUT=$(.git/hooks/pre-commit 2>&1); HOOK_EXIT=$?
assert "수집 0개(exit 5)는 커밋을 막지 않음" "0" "$HOOK_EXIT"
echo "$HOOK_OUT" | grep -q "\[R-test\]"
assert "수집 0개 사실을 경고로 표면화" "0" "$?"

mock_pytest ok 0
HOOK_OUT=$(.git/hooks/pre-commit 2>&1); HOOK_EXIT=$?
assert "테스트가 통과하면 커밋 통과" "0" "$HOOK_EXIT"
echo "$HOOK_OUT" | grep -q "\[R-test\]"
assert "테스트가 통과하면 침묵" "1" "$?"

mock_pytest ok 1
HOOK_OUT=$(.git/hooks/pre-commit 2>&1); HOOK_EXIT=$?
assert "테스트 실패는 차단" "1" "$HOOK_EXIT"

mock_pytest broken 1
HOOK_OUT=$(.git/hooks/pre-commit 2>&1); HOOK_EXIT=$?
assert "pytest 가 못 뜨면 차단하지 않음" "0" "$HOOK_EXIT"
echo "$HOOK_OUT" | grep -q "실행 불가"
assert "실행 불가를 테스트 실패와 구분해 알림" "0" "$?"

rm -f "$TMP/bin/pytest"
git rm --cached -q lib_under_test.py >/dev/null 2>&1 || true
rm -f lib_under_test.py; rmdir tests 2>/dev/null || true

echo ""
echo "== 1b-quater. 하네스 생성물은 R-fmt 대상이 아니다 =="
# 생성기가 프로젝트마다 다른 prettier 설정에 맞출 수 없다. 맞추려 들면 재설치할 때마다
# 자기 게이트에 자기가 걸린다 — 2026-08-25 전파에서 kis-trading 이 실제로 막혔다.
grep -q "lint-configs/" "$REPO_ROOT/assets/hooks/pre-commit.sh"
assert "GENERATED_RE 가 lint-configs/ 를 제외" "0" "$?"
grep -q "\\.hermes/" "$REPO_ROOT/assets/hooks/pre-commit.sh"
assert "GENERATED_RE 가 .hermes/ 를 제외" "0" "$?"
PF=$(grep -n 'PRETTIER_FILES=' "$REPO_ROOT/assets/hooks/pre-commit.sh" | head -1 | cut -d: -f1)
GR=$(grep -n 'GENERATED_RE=' "$REPO_ROOT/assets/hooks/pre-commit.sh" | head -1 | cut -d: -f1)
assert "GENERATED_RE 가 PRETTIER_FILES 보다 먼저 정의됨" "0" "$([[ $GR -lt $PF ]] && echo 0 || echo 1)"

echo ""
echo "== 1b-ter. 하네스 사본만 담긴 커밋은 프로젝트 pytest 에 막히지 않는다 =="
# 프로젝트 테스트가 이미 깨져 있으면 하네스 갱신 커밋이 무관한 실패에 막힌다.
# 2026-08-25 전파에서 실제로 발생했다(rim-kanban: pydantic 오류로 pytest 실패).
# 사본은 원본과 동일하고 상류에서 검증됐으므로 돌려도 알려주는 것이 없다.
mkdir -p tests scripts/hooks
cat > tests/test_always_fails.py <<'PYEOF'
def test_broken():
    assert False
PYEOF
git add tests/test_always_fails.py
git -c core.hooksPath=/dev/null commit -q -m "깨진 테스트 (설치 이전 상태)" 2>/dev/null || true
printf 'x = 1
' > scripts/hooks/harness_copy_probe.py
git add scripts/hooks/harness_copy_probe.py
HOOK_OUT=$(.git/hooks/pre-commit 2>&1); HOOK_RC=$?
assert "하네스 사본만 담긴 커밋은 통과" "0" "$HOOK_RC"
echo "$HOOK_OUT" | grep -q '\[R-test\]'
assert "하네스 사본만이면 R-test 단계에 들어가지도 않는다" "1" "$?"
# 대조군: 프로젝트 파이썬이 섞이면 R-test 단계가 실제로 돈다.
# 차단 여부로 단언하지 않는다 — 이 픽스처는 HOME 을 격리해 pytest 가 실행 불가이고,
# 그 경로는 설계상 경고다. "단계에 들어갔는가" 가 여기서 확인 가능한 성질이다.
echo "y = 2" > project_module.py
git add project_module.py
.git/hooks/pre-commit 2>&1 | grep -q '\[R-test\]'
assert "프로젝트 .py 가 섞이면 R-test 단계가 돈다" "0" "$?"
git rm --cached -q project_module.py >/dev/null 2>&1 || true; rm -f project_module.py
# hermes 스크립트도 하네스 소유다 — scripts/ 바로 아래라 경로 규칙이 다르다.
# 2026-08-25 전파에서 ai-create 가 이것 때문에 DB 미기동 pytest 에 막혔다.
echo "z = 3" > scripts/hermes-probe.py
git add scripts/hermes-probe.py
.git/hooks/pre-commit 2>&1 | grep -q '\[R-test\]'
assert "hermes 스크립트만이면 R-test 가 돌지 않는다" "1" "$?"
git rm --cached -q scripts/hermes-probe.py >/dev/null 2>&1 || true; rm -f scripts/hermes-probe.py
git rm --cached -q scripts/hooks/harness_copy_probe.py project_module.py >/dev/null 2>&1 || true
rm -f scripts/hooks/harness_copy_probe.py project_module.py
git rm -q --cached tests/test_always_fails.py >/dev/null 2>&1 || true
rm -f tests/test_always_fails.py
git -c core.hooksPath=/dev/null commit -q -m "깨진 테스트 제거" 2>/dev/null || true

echo ""
echo "== 1c-bis. 하네스 사본은 구조 검사(R-cx·R-dep) 대상이 아니다 =="
# scripts/hooks/*.py 는 assets/hooks/*.py 의 사본이다. 원본이 이미 검사받으므로
# 사본까지 보면 같은 결함을 두 번 보고하고, 계약 미등록으로 R-dep-4 가 매번 뜬다.
# (2026-08-25 자기 설치 첫 커밋에서 실제로 발화했다.)
cat > .deprc <<'DEPEOF'
scope: scripts/*.py
DEPEOF
mkdir -p scripts/hooks
printf 'import os
' > scripts/hooks/copied_module.py
git add .deprc scripts/hooks/copied_module.py
HOOK_OUT=$(.git/hooks/pre-commit 2>&1)
echo "$HOOK_OUT" | grep -q 'copied_module.py'
assert "하네스 사본은 R-dep 경고를 받지 않음" "1" "$?"
# 대조군: 같은 파일이 scripts/ 바로 아래면 경고를 받아야 한다(검사 자체는 살아있다)
printf 'import os
' > scripts/plain_module.py
git add scripts/plain_module.py
HOOK_OUT=$(.git/hooks/pre-commit 2>&1)
echo "$HOOK_OUT" | grep -q 'plain_module.py'
assert "사본이 아닌 파일은 그대로 경고" "0" "$?"
git rm --cached -q .deprc scripts/hooks/copied_module.py scripts/plain_module.py >/dev/null 2>&1 || true
rm -f .deprc scripts/hooks/copied_module.py scripts/plain_module.py

echo ""
echo "== 1d-bis. 하네스 룰 블록이 앵커를 중복 선언하지 않는다 =="
# 대상 문서가 같은 앵커를 정식 섹션으로 이미 가지면 블록은 링크로 바뀌어야 한다.
# 안 그러면 {#r-test} 가 두 번 선언돼 pre-commit 의 `근거:` 링크가 모호해진다
# (2026-08-25 이 저장소에 자기 설치를 하다 드러났다).
CB="docs/design-docs/core-beliefs.md"
mkdir -p "$(dirname "$CB")"
cat > "$CB" <<'CBEOF'
# Core Beliefs

## R-test — pytest {#r-test}

프로젝트가 직접 쓴 정식 섹션이다.
CBEOF
bash "$REPO_ROOT/project-claude.sh" . harness >/dev/null 2>&1
DUP=$(grep -c '{#r-test}' "$CB")
assert "이미 있는 앵커는 블록이 재선언하지 않음" "1" "$DUP"
grep -q '\[R-test\](#r-test)' "$CB"
assert "대신 정식 섹션으로 링크" "0" "$?"
grep -q '{#r-plan-stale}' "$CB"
assert "없던 앵커는 블록이 그대로 선언" "0" "$?"

echo ""
echo "== 1e. R-pipe 배선 — PostToolUse(Task|Agent) 가 실제 settings 에 렌더링되는가 =="
# POST_TOOL_USE_HOOKS 배열은 이 훅이 처음 채운다. 배열이 비어 있는 동안은
# 렌더링 경로가 죽어 있어도 아무도 모른다 — complexity.py 가 .git/hooks/ 로
# 복사되지 않던 것과 같은 자리다(2026-08-24). 실제 산출물을 단언한다.
python3 - <<'PYEOF'
import json, sys, glob
found = False
for f in glob.glob('.claude/settings*.json'):
    for e in (json.load(open(f)).get('hooks', {}) or {}).get('PostToolUse', []) or []:
        if 'Task' in (e.get('matcher') or ''):
            for h in e.get('hooks', []) or []:
                if 'review-record' in (h.get('command') or ''):
                    found = True
sys.exit(0 if found else 1)
PYEOF
assert "settings 에 PostToolUse(Task|Agent) review-record 등록" "0" "$?"
assert "기록 훅 파일이 설치됨" "0" "$([[ -f scripts/hooks/claude-posttooluse-review-record.sh ]] && echo 0 || echo 1)"

# 커밋 시점 판정이 실제로 붙었는가 — 리뷰 빚이 있으면 경고, 없으면 침묵.
mkdir -p .claude
echo "x = 1" > pipe_probe.py
git add pipe_probe.py
echo "edit: 1  pipe_probe.py" > .claude/.review-dirty
PIPE_OUT=$(.git/hooks/pre-commit 2>&1); PIPE_RC=$?
assert "리뷰 빚이 있어도 차단하지 않음" "0" "$PIPE_RC"
echo "$PIPE_OUT" | grep -q "\[R-pipe\]"
assert "R-pipe 경고가 커밋 경로에서 발화" "0" "$?"

# 리뷰어 dispatch 가 그 경고를 실제로 끈다 — 훅과 판정이 같은 파일을 본다는 확인.
printf '{"tool_name":"Task","tool_input":{"subagent_type":"code-reviewer"}}' \
  | CLAUDE_PROJECT_DIR="$TMP" scripts/hooks/claude-posttooluse-review-record.sh >/dev/null 2>&1
PIPE_OUT=$(.git/hooks/pre-commit 2>&1)
echo "$PIPE_OUT" | grep -q "\[R-pipe\]"
assert "리뷰어 dispatch 후에는 침묵" "1" "$?"
git rm --cached -q pipe_probe.py >/dev/null 2>&1 || true
rm -f pipe_probe.py .claude/.review-dirty

echo ""
echo "== 1f. R-acc 배선 — 계획서 §2 목표가 실행 가능한 형태인가 =="
mkdir -p docs/exec-plans/active docs/exec-plans/completed
cat > docs/exec-plans/active/2026-08-25-acc-probe.md <<'PLANEOF'
# 계획

## 2. 목표 (What — 검증 가능한 형태)

- [ ] 명령 없는 목표

## 8. 회고
- 잘된 것: x
PLANEOF
git add docs/exec-plans/active/2026-08-25-acc-probe.md
ACC_OUT=$(.git/hooks/pre-commit 2>&1); ACC_RC=$?
assert "R-acc 는 차단하지 않음" "0" "$ACC_RC"
echo "$ACC_OUT" | grep -q "\[R-acc\]"
assert "명령 없는 §2 목표에 R-acc-1 발화" "0" "$?"

# 명령을 붙이면 침묵해야 한다 — 오발화 확인.
cat > docs/exec-plans/active/2026-08-25-acc-probe.md <<'PLANEOF'
# 계획

## 2. 목표 (What — 검증 가능한 형태)

- [ ] 명령 있는 목표
      `bash tests/foo-test.sh`

## 8. 회고
- 잘된 것: x
PLANEOF
git add docs/exec-plans/active/2026-08-25-acc-probe.md
.git/hooks/pre-commit 2>&1 | grep -q "\[R-acc\]"
assert "명령이 붙으면 R-acc-1 침묵" "1" "$?"
git rm --cached -q docs/exec-plans/active/2026-08-25-acc-probe.md >/dev/null 2>&1 || true
rm -rf docs/exec-plans

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
# 기대값을 손으로 적지 않는다. 훅을 하나 추가할 때마다 이 숫자를 고쳐야 했고
# (2026-08-04 8→7, 08-13 7→8, 08-24 8→9), 그 갱신은 기능 회귀와 구분되지 않는다.
# 프리셋이 등록한 수를 그대로 기대값으로 쓰면 "등록한 것이 전부 렌더링됐는가" 라는
# 원래 묻고 싶던 질문이 된다.
EXPECT_ABS=$(grep -c '_HOOKS+=(.*\${CLAUDE_PROJECT_DIR}/scripts/hooks' \
  "$REPO_ROOT/presets/workflow/harness.conf" 2>/dev/null; true)
assert "프리셋이 등록한 훅이 전부 settings.json 에 렌더링됨" "$EXPECT_ABS" "$ABS_COUNT"

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
echo "== 13. R-plan 검사 범위 = 스테이징된 계획서만 =="
# 전역 find 로 스캔하면 커밋에 포함되지도 않은 남의 완료 계획서가 무관한 커밋을 막는다.
# 여러 세션이 워킹트리를 공유할 때 서로를 영구 차단하므로 스테이징 범위로 좁혔다.
# 근거: zeroday-frontend docs/audits/2026-07-23-r-plan-hook-scope.md
mkdir -p docs/exec-plans/active
cat > docs/exec-plans/active/all-done-fixture.md << 'FIXTURE'
# 전부 완료된 계획서 (범위 회귀 테스트 fixture)

- [x] 항목1
- [x] 항목2
FIXTURE

# (a) fixture 를 스테이징하지 않으면 → 통과해야 한다 (남의 계획서가 내 커밋을 막지 않음)
echo "x = 1" > small3.py
git add small3.py
.git/hooks/pre-commit >/dev/null 2>&1
assert "미스테이징 완료계획서는 커밋을 막지 않음" "0" "$?"

# (b) fixture 를 스테이징하면 → 차단해야 한다 (규칙 의도 유지)
git add docs/exec-plans/active/all-done-fixture.md
HOOK_OUT=$(.git/hooks/pre-commit 2>&1); HOOK_RC=$?
[[ $HOOK_RC -ne 0 ]]
assert "스테이징된 완료계획서는 차단됨" "0" "$?"
echo "$HOOK_OUT" | grep -q 'R-plan'
assert "차단 사유가 R-plan 으로 보고됨" "0" "$?"

git reset -q
rm -f docs/exec-plans/active/all-done-fixture.md small3.py

echo ""
echo "== 14. R-size 는 .vue(SFC) 도 검사한다 =="
# 회귀 방지: pre-commit CHECKABLE 과 size-warn case 목록에서 .vue 가 빠져 있었다.
# 같은 리포의 review-reminder·prettier-warn·dead-file-warn·codex size-warn 은 이미 .vue 를
# 검사하는데 R-size 두 곳만 누락돼, Vue 프로젝트의 화면 컴포넌트가 906 줄까지 자랐다.
# 근거: zeroday-frontend docs/exec-plans/backlog/vue-file-size-rule-gap.md
seq 1 15 | sed 's/.*/<!-- & -->/' > big.vue
git add big.vue
HOOK_OUT=$(MAX_LINES_HARD=10 .git/hooks/pre-commit 2>&1); HOOK_RC=$?
assert "한도 초과 .vue 는 커밋 차단" "1" "$HOOK_RC"
echo "$HOOK_OUT" | grep -q '\[R-size\] big\.vue'
assert "차단 사유가 R-size 로 보고됨 (silent-skip 방지)" "0" "$?"

git reset -q
rm -f big.vue

seq 1 520 | sed 's/.*/<!-- & -->/' > hard.vue
OUT=$(echo '{"tool_input":{"file_path":"'"$TMP"'/hard.vue"}}' \
  | scripts/hooks/claude-posttooluse-size-warn.sh 2>&1)
echo "$OUT" | grep -q "R-size HARD"
assert "편집 경고도 .vue 를 본다 (경고/차단 목록 일치)" "0" "$?"
rm -f hard.vue

echo ""
echo "== 15. R-secret — 자격증명이 실린 파일은 커밋 차단 =="
# 설치 경로 회귀 방지: check-secrets.py 와 정답지 모듈이 .git/hooks/ 로 함께
# 복사되지 않으면 이 단계는 조용히 skip 된다 — 그게 원래 결함의 4번째 겹이었다.
# ⚠️ 아래는 가짜 값이다.
assert "check-secrets.py 설치됨" "0" "$([[ -f .git/hooks/check-secrets.py ]]; echo $?)"
assert "정답지 모듈 설치됨" "0" "$([[ -f .git/hooks/hermes_secret_values.py ]]; echo $?)"

printf 'password = "Hunter2xyz!"\n' > leak.txt
git add leak.txt
HOOK_OUT=$(.git/hooks/pre-commit 2>&1); HOOK_RC=$?
assert "자격증명이 실린 파일은 커밋 차단" "1" "$HOOK_RC"
echo "$HOOK_OUT" | grep -q '\[P9\]'
assert "차단 사유가 P9 로 보고됨 (silent-skip 방지)" "0" "$?"

git reset -q
rm -f leak.txt

echo ""
echo "== 16. .gitignore 블록 멱등 — CRLF 파일에서도 중복되지 않는다 =="
# 회귀 방지: 마커 탐지에 정규식(`\r\?$`)을 쓰면 grep 구현에 따라 `\?` 해석이 갈려
# **조용히** 매칭에 실패하고, 갱신 대신 블록이 덧붙는다. 재설치할 때마다 늘어난다.
# 실제로 jjackkun_bot(Windows 에서 만들어진 CRLF .gitignore)에서 두 벌이 쌓였다.
for _le in CRLF LF; do
  GT=$(mktemp -d)
  ( cd "$GT" && git init -q && git config user.email "t@e.com" && git config user.name "t" )
  if [[ "$_le" == CRLF ]]; then printf '# 사용자\r\nnode_modules/\r\n' > "$GT/.gitignore"
  else printf '# 사용자\nnode_modules/\n' > "$GT/.gitignore"; fi
  bash "$REPO_ROOT/project-claude.sh" "$GT" harness >/dev/null 2>&1
  bash "$REPO_ROOT/project-claude.sh" "$GT" harness >/dev/null 2>&1
  assert "$_le: 재설치해도 하네스 블록 1개" "1" \
    "$(grep -c '>>> harness-agent-preset >>>' "$GT/.gitignore")"
  assert "$_le: 마커 밖 사용자 항목 보존" "1" \
    "$(grep -c 'node_modules/' "$GT/.gitignore")"
  if [[ -f "$REGISTRY" ]]; then
    grep -vxF "$GT" "$REGISTRY" > "$REGISTRY.tmp$$" || true
    mv "$REGISTRY.tmp$$" "$REGISTRY"
  fi
  rm -rf "$GT"
done

echo ""
echo "== 17. R-fmt 는 하네스 생성물을 검사하지 않는다 =="
# 회귀 방지: 설치가 만든 CLAUDE.md·.claude/settings.json 은 프로젝트의 .prettierrc 와
# 맞을 수 없다(프로젝트마다 설정이 다르다). 검사 대상에 넣으면 재설치할 때마다
# 하네스가 자기 게이트에 자기가 걸려 커밋이 막힌다 — 실제로 3개 프로젝트에서 발생했다.
GEN_RE='^(CLAUDE\.md|AGENTS\.md|\.claude/(settings(\.local)?\.json|\.dev-setting-manifest\.json)|\.codex/settings(\.local)?\.json)$|^\.claude/memory/'
for _gen in "CLAUDE.md" ".claude/settings.json" ".claude/.dev-setting-manifest.json" \
            ".claude/memory/MEMORY.md" ".claude/memory/feedback_x.md"; do
  echo "$_gen" | grep -qE "$GEN_RE"
  assert "R-fmt 제외 대상: $_gen" "0" "$?"
done
# 일반 소스는 여전히 검사 대상이어야 한다 (제외가 너무 넓어지지 않았는지)
for _src in "src/App.svelte" "docs/guide.md" "package.json"; do
  echo "$_src" | grep -qE "$GEN_RE"
  assert "R-fmt 검사 유지: $_src" "1" "$?"
done
# 훅 파일이 실제로 같은 규칙을 쓰는지 (테스트만 통과하는 사태 방지)
grep -q 'GENERATED_RE=' "$REPO_ROOT/assets/hooks/pre-commit.sh"
assert "pre-commit 이 생성물 제외 규칙을 갖고 있음" "0" "$?"

echo ""
echo "== 18. 경고 단독 발생 시에도 출력된다 =="
# 회귀 방지: VIOLATIONS 는 FAIL=1 일 때만 출력되므로, 경고 등급 위반이 단독으로
# 발생하면 아무것도 보이지 않는다. R-plan-missing 이 그 상태로 방치돼 있었다
# (2026-08-13 확인). 차단 위반이 하나도 없는 상태에서 경고가 나오는지 본다.
git reset -q
git checkout -- . 2>/dev/null || true
rm -rf docs/exec-plans/active
mkdir -p docs/exec-plans/active
echo "y = 1" > warn_only.py
git add warn_only.py
WARN_OUT=$(.git/hooks/pre-commit 2>&1); WARN_RC=$?
assert "경고만 있을 때 exit 0" "0" "$WARN_RC"
echo "$WARN_OUT" | grep -q "R-plan-missing"
assert "경고가 실제로 출력됨 (침묵 회귀 방지)" "0" "$?"
git reset -q; rm -f warn_only.py

echo ""
echo "== 19. plan_state.py 이중 배치 =="
[[ -f "$TMP/scripts/hooks/plan_state.py" ]]
assert "scripts/hooks/plan_state.py 배치됨" "0" "$?"
[[ -f "$TMP/.git/hooks/plan_state.py" ]]
assert ".git/hooks/plan_state.py 배치됨" "0" "$?"

echo ""
echo "== 20. hook_inventory .py 확장이 기존 자산을 지우지 않음 =="
# assets/hooks/check-secrets.py 가 인벤토리에 들어가면서 scripts/hooks/check-secrets.py
# 삭제를 시도할 수 있다(실제로는 .git/hooks/ 에만 있어 무해). 재설치 후 확인한다.
bash "$REPO_ROOT/project-claude.sh" "$TMP" harness >/dev/null 2>&1
[[ -f "$TMP/.git/hooks/check-secrets.py" ]]
assert "재설치 후 check-secrets.py 보존" "0" "$?"
[[ -f "$TMP/scripts/hooks/plan_state.py" ]]
assert "재설치 후 plan_state.py 보존" "0" "$?"

echo ""
echo "== 21. R-plan-stale — 계획서가 코드를 따라오지 않음 =="
git reset -q
git checkout -- . 2>/dev/null || true
rm -rf docs/exec-plans/active docs/exec-plans/completed
mkdir -p docs/exec-plans/active docs/exec-plans/completed
cat > docs/exec-plans/active/stale-fixture.md << 'FIXTURE'
# 진행 중 계획

- [x] 항목1
- [ ] 항목2
FIXTURE
git add docs/exec-plans/active/stale-fixture.md
git -c user.email=t@t -c user.name=t commit -qm "add plan" --no-verify

echo "z = 1" > stale_code.py
git add stale_code.py
STALE_OUT=$(.git/hooks/pre-commit 2>&1); STALE_RC=$?
assert "R-plan-stale 은 차단하지 않음" "0" "$STALE_RC"
echo "$STALE_OUT" | grep -q "\[R-plan-stale\]"
assert "R-plan-stale 경고 출력" "0" "$?"

# 계획서를 함께 스테이징하면 경고가 사라진다
echo "- [ ] 항목3" >> docs/exec-plans/active/stale-fixture.md
git add docs/exec-plans/active/stale-fixture.md
STALE_OUT=$(.git/hooks/pre-commit 2>&1)
echo "$STALE_OUT" | grep -q "\[R-plan-stale\]"
assert "계획서 동반 스테이징 시 경고 없음" "1" "$?"
git reset -q; rm -f stale_code.py
git checkout -- docs/exec-plans/active/stale-fixture.md 2>/dev/null || true

# 계획서 2개 중 1개만 스테이징해도 통과한다 — 어느 계획에 속한 커밋인지 훅은 모른다.
cat > docs/exec-plans/active/second-fixture.md << 'FIXTURE'
# 두 번째 계획

- [ ] 항목A
FIXTURE
git add docs/exec-plans/active/second-fixture.md
git -c user.email=t@t -c user.name=t commit -qm "add second plan" --no-verify
echo "z = 2" > partial_code.py
echo "- [ ] 항목B" >> docs/exec-plans/active/second-fixture.md
git add partial_code.py docs/exec-plans/active/second-fixture.md
PARTIAL_OUT=$(.git/hooks/pre-commit 2>&1)
echo "$PARTIAL_OUT" | grep -q "\[R-plan-stale\]"
assert "계획서 2개 중 1개만 스테이징해도 경고 없음" "1" "$?"
git reset -q; rm -f partial_code.py
git checkout -- docs/exec-plans/active/second-fixture.md 2>/dev/null || true

echo ""
echo "== 22. 하네스 생성물만 바뀐 커밋은 경고하지 않음 (자기 게이트 회귀) =="
echo "# touched by reinstall" >> scripts/hooks/claude-pretooluse-bash-guard.sh
git add scripts/hooks/claude-pretooluse-bash-guard.sh
MANAGED_OUT=$(.git/hooks/pre-commit 2>&1)
echo "$MANAGED_OUT" | grep -q "\[R-plan-stale\]"
assert "scripts/hooks/ 만 수정 시 경고 없음" "1" "$?"
git reset -q
git checkout -- scripts/hooks/ 2>/dev/null || true

echo ""
echo "== 23. plan_state.py 부재 시 원인이 구분된 경고 =="
mv .git/hooks/plan_state.py .git/hooks/plan_state.py.bak
echo "w = 1" > nomod.py
git add nomod.py
NOMOD_OUT=$(.git/hooks/pre-commit 2>&1); NOMOD_RC=$?
assert "모듈 부재는 차단하지 않음" "0" "$NOMOD_RC"
echo "$NOMOD_OUT" | grep -q "plan_state.py 없음"
assert "모듈 부재 원인 명시" "0" "$?"
git reset -q; rm -f nomod.py
mv .git/hooks/plan_state.py.bak .git/hooks/plan_state.py

echo ""
echo "== 24. R-retro — 회고 없이 completed/ 로 이동 =="
git reset -q
git checkout -- . 2>/dev/null || true
mkdir -p docs/exec-plans/active docs/exec-plans/completed
cat > docs/exec-plans/active/retro-fixture.md << 'FIXTURE'
# 완료된 계획

- [x] 항목1

## 8. 회고 (완료 시 작성)

- 잘된 것:
- 잘못된 것:
- 다음 룰 후보:
FIXTURE
git add docs/exec-plans/active/retro-fixture.md
git -c user.email=t@t -c user.name=t commit -qm "add retro fixture" --no-verify

git mv docs/exec-plans/active/retro-fixture.md docs/exec-plans/completed/retro-fixture.md
RETRO_OUT=$(.git/hooks/pre-commit 2>&1); RETRO_RC=$?
assert "R-retro 는 차단하지 않음" "0" "$RETRO_RC"
echo "$RETRO_OUT" | grep -q "\[R-retro\]"
assert "git mv 이동이 감지됨 (ACM 은 rename 을 놓친다)" "0" "$?"

# 회고를 채우면 경고가 사라진다
sed -i 's/^- 잘된 것:$/- 잘된 것: 판정 규칙을 한 곳에 모았다/' docs/exec-plans/completed/retro-fixture.md
git add docs/exec-plans/completed/retro-fixture.md
RETRO_OUT=$(.git/hooks/pre-commit 2>&1)
echo "$RETRO_OUT" | grep -q "\[R-retro\]"
assert "회고를 채우면 경고 없음" "1" "$?"
git -c user.email=t@t -c user.name=t commit -qm "move plan" --no-verify

echo ""
echo "== 25. completed/ 내용 수정만으로는 경고하지 않음 (M 제외 회귀) =="
printf '\n오타 수정.\n' >> docs/exec-plans/completed/retro-fixture.md
git add docs/exec-plans/completed/retro-fixture.md
MOD_OUT=$(.git/hooks/pre-commit 2>&1)
echo "$MOD_OUT" | grep -q "\[R-retro\]"
assert "수정(M)은 R-retro 대상 아님" "1" "$?"
git reset -q
git checkout -- docs/exec-plans/completed/ 2>/dev/null || true

echo ""
echo "== 26. R-size 책임 신호 — 줄 수와 무관하게 책임 증가를 잡는다 =="
# 근거: docs/superpowers/specs/2026-08-21-responsibility-over-linecount-design.md
# 실측 재생: data-model.md 는 물리 설계가 유입돼 책임이 둘이 된 커밋에서 397 줄이었다.
# soft 400 을 3 줄 차이로 비껴가 어떤 장치도 말하지 않았다. 하위 절은 4→17 로 뛰었다.
mkdir -p rsize
{ echo "# 자료 모델"; for i in $(seq 1 4); do echo "### 논리 $i"; done; } > rsize/data-model.md
git add rsize/data-model.md && git commit -qm "rsize fixture" >/dev/null
{ echo "# 자료 모델"; for i in $(seq 1 4);  do echo "### 논리 $i"; done
                     for i in $(seq 1 13); do echo "### 물리 $i"; done; } > rsize/data-model.md
OUT=$(echo '{"tool_input":{"file_path":"'"$TMP"'/rsize/data-model.md"}}' \
  | scripts/hooks/claude-posttooluse-size-warn.sh 2>&1)
echo "$OUT" | grep -q "R-size 책임"
assert "400 줄 한참 아래에서도 책임 증가는 경고된다" "0" "$?"
echo "$OUT" | grep -q "4 → 17"
assert "증가량을 기준선과 함께 보고한다" "0" "$?"

# 오탐 방지: 정상적인 점진 성장(임계 미만)은 조용해야 한다. 과발화하면 사람이 hook 을 끈다.
{ echo "# 자료 모델"; for i in $(seq 1 6); do echo "### 논리 $i"; done; } > rsize/data-model.md
OUT=$(echo '{"tool_input":{"file_path":"'"$TMP"'/rsize/data-model.md"}}' \
  | scripts/hooks/claude-posttooluse-size-warn.sh 2>&1)
assert "임계 미만 증가는 조용함" "" "$OUT"
git checkout -q -- rsize/data-model.md

# 신규 파일은 기준선이 없다 — 한 번에 써 내려간 문서를 오탐으로 잡지 않는다.
{ echo "# 새 문서"; for i in $(seq 1 20); do echo "### 절 $i"; done; } > rsize/brand-new.md
OUT=$(echo '{"tool_input":{"file_path":"'"$TMP"'/rsize/brand-new.md"}}' \
  | scripts/hooks/claude-posttooluse-size-warn.sh 2>&1)
assert "HEAD 에 없는 신규 파일은 조용함" "" "$OUT"
rm -f rsize/brand-new.md

# 코드 파일도 같은 신호를 받는다 (최상위 def/class 기준).
echo "def a(): pass" > rsize/svc.py
git add rsize/svc.py && git commit -qm "rsize py fixture" >/dev/null
{ echo "def a(): pass"; for i in $(seq 1 6); do echo "def f$i(): pass"; done; } > rsize/svc.py
OUT=$(echo '{"tool_input":{"file_path":"'"$TMP"'/rsize/svc.py"}}' \
  | scripts/hooks/claude-posttooluse-size-warn.sh 2>&1)
echo "$OUT" | grep -q "R-size 책임"
assert "코드 파일도 책임 증가를 경고" "0" "$?"

# 오탐 방지(2026-08-24): 비공개 헬퍼만 늘어난 편집은 인터페이스를 넓히지 않는다.
# 내부를 깊게 만드는 *개선* 편집이므로 책임 증가로 오인하면 안 된다.
# 근거: docs/superpowers/specs/2026-08-24-interface-width-gate-design.md 축 B
echo "def a(): pass" > rsize/deep.py
git add rsize/deep.py && git commit -qm "rsize deep fixture" >/dev/null
{ echo "def a(): pass"; for i in $(seq 1 6); do echo "def _h$i(): pass"; done; } > rsize/deep.py
OUT=$(echo '{"tool_input":{"file_path":"'"$TMP"'/rsize/deep.py"}}' \
  | scripts/hooks/claude-posttooluse-size-warn.sh 2>&1)
assert "비공개 헬퍼만 늘면 조용함(오탐 방지)" "" "$OUT"

# 공개가 함께 늘면 여전히 경고한다 — 침묵이 과해지지 않는지 확인한다.
{ echo "def a(): pass"; for i in $(seq 1 3); do echo "def _h$i(): pass"; done
                        for i in $(seq 1 3); do echo "def p$i(): pass"; done; } > rsize/deep.py
OUT=$(echo '{"tool_input":{"file_path":"'"$TMP"'/rsize/deep.py"}}' \
  | scripts/hooks/claude-posttooluse-size-warn.sh 2>&1)
echo "$OUT" | grep -q "R-size 책임"
assert "공개가 함께 늘면 여전히 경고" "0" "$?"
git checkout -q -- rsize/deep.py 2>/dev/null || true

# 줄 수 경고가 이미 나갔으면 침묵한다 — 같은 편집에 두 경고를 겹치지 않는다.
# 기준선은 soft(400) 초과 · hard(500) 미만으로 잡는다 — pre-commit 차단에 걸리면
# 파일이 HEAD 에 없어져, 억제가 아니라 "기준선 부재" 로 조용해지는 가짜 통과가 된다.
{ seq 1 450 | sed 's/.*/x = &/'; } > rsize/big.py
git add rsize/big.py && git commit -qm "rsize big fixture" >/dev/null
git ls-files --error-unmatch rsize/big.py >/dev/null 2>&1
assert "억제 검사의 기준선이 실제로 커밋됨" "0" "$?"
{ seq 1 450 | sed 's/.*/x = &/'; for i in $(seq 1 9); do echo "def g$i(): pass"; done; } > rsize/big.py
OUT=$(echo '{"tool_input":{"file_path":"'"$TMP"'/rsize/big.py"}}' \
  | scripts/hooks/claude-posttooluse-size-warn.sh 2>&1)
echo "$OUT" | grep -q "R-size SOFT"
assert "줄 수 경고는 정상 발화" "0" "$?"
echo "$OUT" | grep -q "R-size 책임"
assert "줄 수 경고가 나가면 책임 경고는 겹치지 않음" "1" "$?"
git checkout -q -- rsize/ 2>/dev/null || true

echo ""
echo "== 결과 =="
echo "  통과: $PASS / 실패: $FAIL"
[[ $FAIL -eq 0 ]]
