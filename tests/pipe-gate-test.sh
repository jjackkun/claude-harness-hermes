#!/usr/bin/env bash
# R-pipe 회귀 테스트 — 에이전트 파이프라인 출구 조건
#
# 스펙: docs/superpowers/specs/2026-08-24-agent-pipeline-enforcement-design.md
#
# 이 테스트가 고정하는 것:
#   .review-dirty 는 4개월간 기록만 되고 아무 판정에도 쓰이지 않았다. 그런데
#   core-beliefs.md#r-review 는 "안 지우면 commit 단계에서 차단" 이라고 적고 있었다.
#   R-test 가 죽어 있던 것과 같은 종류의 결함이다 — 문서가 주장하는 강제가 없다.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RECORD="$ROOT/assets/hooks/claude-posttooluse-review-record.sh"
PRECOMMIT="$ROOT/assets/hooks/pre-commit.sh"
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
nope() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }

# 전제를 크게 실패시킨다 — 훅이 없으면 아래 단언이 전부 공허하게 통과한다
# (2026-08-24 iface-gate-test 에서 실제로 겪은 결함).
[[ -f "$RECORD" ]] || { echo "  ✗ 전제: 기록 훅 없음 — $RECORD"; echo "PASS=0 FAIL=1"; exit 1; }
ok "전제: 기록 훅 존재"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# ── Part 1. 기록 훅 — 리뷰어 dispatch 가 리뷰 빚을 지운다 ────────────────
cd "$WORK"; mkdir -p .claude

# dispatch 페이로드를 훅에 먹이고, .review-dirty 가 남았는지 돌려준다.
dispatch() {
  local subagent="$1"
  mkdir -p .claude
  echo "edit: 1  scripts/foo.py" > .claude/.review-dirty
  printf '{"tool_name":"Task","tool_input":{"subagent_type":"%s","prompt":"p"}}' "$subagent" \
    | CLAUDE_PROJECT_DIR="$WORK" bash "$RECORD" >/dev/null 2>&1
  [[ -f .claude/.review-dirty ]] && echo KEPT || echo CLEARED
}

echo "── 리뷰어 dispatch 는 리뷰 빚을 청산한다 ──"
for r in code-reviewer python-reviewer typescript-reviewer database-reviewer; do
  [[ "$(dispatch "$r")" == CLEARED ]] && ok "$r → 기록 삭제" || nope "$r → 기록 삭제"
done

echo "── 리뷰어가 아닌 에이전트는 청산하지 않는다 ──"
for r in fullstack-developer general-purpose planner refactor-cleaner; do
  [[ "$(dispatch "$r")" == KEPT ]] && ok "$r → 기록 유지" || nope "$r → 기록 유지"
done

echo "── 훅이 죽지 않는다 ──"
echo "edit: 1  scripts/foo.py" > .claude/.review-dirty
printf 'not json at all' | CLAUDE_PROJECT_DIR="$WORK" bash "$RECORD" >/dev/null 2>&1
[[ $? -eq 0 ]] && ok "깨진 입력에도 exit 0" || nope "깨진 입력에도 exit 0"
[[ -f .claude/.review-dirty ]] && ok "깨진 입력은 기록을 지우지 않는다" || nope "깨진 입력은 기록을 지우지 않는다"

printf '{"tool_name":"Task","tool_input":{}}' | CLAUDE_PROJECT_DIR="$WORK" bash "$RECORD" >/dev/null 2>&1
[[ -f .claude/.review-dirty ]] && ok "subagent_type 부재는 기록을 지우지 않는다" || nope "subagent_type 부재는 기록을 지우지 않는다"

rm -f .claude/.review-dirty
printf '{"tool_name":"Task","tool_input":{"subagent_type":"code-reviewer"}}' \
  | CLAUDE_PROJECT_DIR="$WORK" bash "$RECORD" >/dev/null 2>&1
[[ $? -eq 0 ]] && ok "기록이 없어도 exit 0" || nope "기록이 없어도 exit 0"

# ── Part 2. pre-commit R-pipe — 리뷰 빚을 커밋 시점에 알린다 ─────────────
REPO="$WORK/repo"; mkdir -p "$REPO"; cd "$REPO"
git init -q
git config user.email "harness-test@example.com"
git config user.name "harness-test"
mkdir -p .git/hooks .claude
for m in pre-commit.sh plan_state.py complexity.py depcheck.py check-secrets.py; do
  [[ -f "$ROOT/assets/hooks/$m" ]] && cp "$ROOT/assets/hooks/$m" ".git/hooks/${m/pre-commit.sh/pre-commit}"
done
chmod +x .git/hooks/pre-commit

run_hook() { .git/hooks/pre-commit 2>&1; }
hook_rc()  { .git/hooks/pre-commit >/dev/null 2>&1; echo $?; }

echo "── 코드 커밋 + 리뷰 빚 → 경고하되 차단하지 않는다 ──"
echo "x = 1" > scripts_foo.py
git add scripts_foo.py
echo "edit: 1  scripts_foo.py" > .claude/.review-dirty
OUT="$(run_hook)"
echo "$OUT" | grep -q '\[R-pipe\]' && ok "R-pipe 경고 출력" || nope "R-pipe 경고 출력"
[[ "$(hook_rc)" == "0" ]] && ok "차단하지 않는다 (exit 0)" || nope "차단하지 않는다 (exit 0)"
echo "$OUT" | grep -q 'core-beliefs.md#r-review' && ok "메시지에 근거 앵커" || nope "메시지에 근거 앵커"
echo "$OUT" | grep -q 'scripts_foo.py' && ok "기록된 파일명이 메시지에 나온다" || nope "기록된 파일명이 메시지에 나온다"

echo "── 리뷰 빚이 없으면 침묵한다 ──"
rm -f .claude/.review-dirty
run_hook | grep -q '\[R-pipe\]' && nope "리뷰 빚 없으면 침묵" || ok "리뷰 빚 없으면 침묵"

echo "── 문서만 바뀐 커밋은 침묵한다 ──"
git reset -q
echo "# doc" > README-x.md
git add README-x.md
echo "edit: 1  scripts_foo.py" > .claude/.review-dirty
run_hook | grep -q '\[R-pipe\]' && nope "문서 전용 커밋은 침묵" || ok "문서 전용 커밋은 침묵"

# ── Part 3. 배선 — 훅이 실제로 설치·등록되는가 ──────────────────────────
cd "$ROOT"
echo "── 배선 ──"
grep -q 'R-pipe' "$PRECOMMIT" && ok "pre-commit 에 R-pipe 단계 존재" || nope "pre-commit 에 R-pipe 단계 존재"
grep -q 'claude-posttooluse-review-record.sh' presets/workflow/harness.conf \
  && ok "harness.conf 에 기록 훅 등록" || nope "harness.conf 에 기록 훅 등록"
grep -q 'POST_TOOL_USE_HOOKS' presets/workflow/harness.conf \
  && ok "PostToolUse(Task) 매처로 등록" || nope "PostToolUse(Task) 매처로 등록"
grep -q 'claude-posttooluse-review-record.sh' <(grep -A 30 'HARNESS_HOOK_SOURCES' presets/workflow/harness.conf) \
  && ok "HARNESS_HOOK_SOURCES 에 등록 (설치 대상)" || nope "HARNESS_HOOK_SOURCES 에 등록 (설치 대상)"

echo "── 문서가 구현과 일치하는가 ──"
grep -A 6 'R-review — 리뷰 빚' docs/design-docs/core-beliefs.md | grep -q '차단' \
  && nope "core-beliefs 가 더 이상 '차단' 이라 주장하지 않는다" \
  || ok "core-beliefs 가 더 이상 '차단' 이라 주장하지 않는다"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
