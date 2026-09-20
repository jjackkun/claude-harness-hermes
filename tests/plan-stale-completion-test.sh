#!/usr/bin/env bash
# R-plan-stale · R-plan-missing 완료 커밋 맹점 (계획 2026-09-18-plan-stale-completion).
#
#   (a) active → completed 로 git mv + 작업 코드      → 두 게이트 모두 발화 없음, 이벤트 사유 "완료 커밋"
#   (b) completed/ 에 새 계획서를 바로 추가 + 코드     → 발화 없음
#   (c) 기존 completed/*.md 수정(M)만 + 코드          → 여전히 R-plan-stale 경고 (예외가 우회로가 아니다)
#   (d) 완료 계획서 없이 코드만                        → 여전히 경고 (회귀 없음)
#
# 임시 저장소에 pre-commit.sh · plan_state.py · gate_emit.sh · gate_event.py 만 복사한다 —
# 전체 설치(project-claude.sh)는 harness-hooks-smoke.sh 몫이다.
# 실행: bash tests/plan-stale-completion-test.sh

set -uo pipefail
export HARNESS_TOOL_INSTALL=0 HARNESS_SYNC_AUTOENABLE=0   # 설치기의 외부 도구 다운로드는 테스트에서 끈다(네트워크 0) — tests/tool-installers-test.sh 가 따로 실측
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo "  ✓ $desc"; PASS=$((PASS+1))
  else echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1)); fi
}
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cd "$T"; git init -q; git config user.email t@t; git config user.name t
cp "$ROOT/assets/hooks/pre-commit.sh" .git/hooks/pre-commit; chmod +x .git/hooks/pre-commit
cp "$ROOT/assets/hooks/plan_state.py" "$ROOT/assets/hooks/gate_emit.sh" "$ROOT/assets/hooks/gate_event.py" .git/hooks/
mkdir -p docs/exec-plans/active docs/exec-plans/completed docs/design-docs
printf '# core\n' > docs/design-docs/core-beliefs.md

plan() { printf '# %s\n\n## 2. 목표\n\n- [x] 목표 — 검증: `true`\n\n## 8. 회고\n\n- 잘된 것: 있음\n' "$1"; }
plan "완료될 계획" > docs/exec-plans/active/done-fixture.md
plan "옛 완료 계획" > docs/exec-plans/completed/old-fixture.md
printf '# 다른 진행 계획\n\n- [ ] 항목\n' > docs/exec-plans/active/other-fixture.md
git add -A; git commit -qm "fixtures" --no-verify

run_hook() { .git/hooks/pre-commit 2>&1; }
stale()   { grep -c '\[R-plan-stale\]' <<<"$1"; }
missing() { grep -c '\[R-plan-missing\]' <<<"$1"; }

echo "[a] git mv active→completed + 코드 (다른 active 계획은 스테이징 안 함)"
git mv docs/exec-plans/active/done-fixture.md docs/exec-plans/completed/done-fixture.md
echo "a = 1" > work_a.py; git add work_a.py
OUT=$(run_hook); RC=$?
assert "차단하지 않음" "0" "$RC"
assert "R-plan-stale 발화 없음" "0" "$(stale "$OUT")"
assert "R-plan-missing 발화 없음" "0" "$(missing "$OUT")"
assert "이벤트 사유가 완료 커밋" "1" "$(grep -c '"R-plan-stale".*완료 커밋' .harness/gate-events.jsonl 2>/dev/null; true)"
git reset -q --hard >/dev/null; git clean -qfd

echo "[a2] 마지막 active 계획을 옮기면 active/ 가 비어도 R-plan-missing 없음"
git rm -q docs/exec-plans/active/other-fixture.md; git commit -qm "drop other" --no-verify
git mv docs/exec-plans/active/done-fixture.md docs/exec-plans/completed/done-fixture.md
echo "a = 2" > work_a2.py; git add work_a2.py
OUT=$(run_hook)
assert "R-plan-missing 발화 없음(active 0건)" "0" "$(missing "$OUT")"
assert "R-plan-stale 발화 없음(active 0건)" "0" "$(stale "$OUT")"
git reset -q --hard >/dev/null; git clean -qfd; git reset -q --hard HEAD~1 >/dev/null

echo "[b] completed/ 에 새 계획서 추가 + 코드"
plan "바로 완료" > docs/exec-plans/completed/new-fixture.md
echo "b = 1" > work_b.py; git add work_b.py docs/exec-plans/completed/new-fixture.md
OUT=$(run_hook)
assert "R-plan-stale 발화 없음" "0" "$(stale "$OUT")"
git reset -q --hard >/dev/null; git clean -qfd

echo "[c] 기존 completed/*.md 수정만 + 코드 → 우회 불가"
echo "- 오타 수정" >> docs/exec-plans/completed/old-fixture.md
echo "c = 1" > work_c.py; git add work_c.py docs/exec-plans/completed/old-fixture.md
OUT=$(run_hook)
assert "R-plan-stale 여전히 경고" "1" "$(stale "$OUT")"
git reset -q --hard >/dev/null; git clean -qfd

echo "[d] 코드만 → 회귀 없음"
echo "d = 1" > work_d.py; git add work_d.py
OUT=$(run_hook)
assert "R-plan-stale 경고" "1" "$(stale "$OUT")"
git reset -q --hard >/dev/null; git clean -qfd

echo; echo "plan-stale-completion: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
