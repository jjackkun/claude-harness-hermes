#!/usr/bin/env bash
# doc-gardening-drift.sh 단위 테스트.
#
# 왜 필요한가: 이 로직의 이전 버전(weekly-doc-gardening.yml 인라인 grep)은 템플릿에
# 존재하지 않는 `status:` 필드를 찾아 한 번도 발동하지 않았고, 아무도 몰랐다.
# CI 안에만 있으면 다운스트림에서조차 관측되지 않는다.
#
# 실행: bash tests/doc-gardening-drift-test.sh
# 종료 코드: 0 = 모든 단언 통과, 1 = 실패

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DRIFT="$REPO_ROOT/assets/hooks/doc-gardening-drift.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  ✓ $desc"; PASS=$((PASS+1))
  else
    echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1))
  fi
}

mkdir -p "$TMP/scripts/hooks" "$TMP/docs/exec-plans/active" "$TMP/docs/exec-plans/completed"
cp "$REPO_ROOT/assets/hooks/plan_state.py" "$TMP/scripts/hooks/"
cp "$DRIFT" "$TMP/scripts/hooks/" 2>/dev/null || true
cp "$REPO_ROOT/assets/docs-templates/docs/exec-plans/template.md" "$TMP/docs/exec-plans/active/"

cat > "$TMP/docs/exec-plans/active/done.md" << 'EOF'
# 완료된 계획
- [x] 항목1
- [x] 항목2
EOF

cat > "$TMP/docs/exec-plans/active/ongoing.md" << 'EOF'
# 진행 중
- [x] 항목1
- [ ] 항목2
EOF

cat > "$TMP/docs/exec-plans/completed/noretro.md" << 'EOF'
# 옛 계획
- [x] 항목1

## 8. 회고 (완료 시 작성)

- 잘된 것:
- 잘못된 것:
- 다음 룰 후보:
EOF

cat > "$TMP/docs/exec-plans/completed/withretro.md" << 'EOF'
# 옛 계획
- [x] 항목1

## 8. 회고 (완료 시 작성)

- 잘된 것: 잘 됐다
EOF

echo "== 1. 편차 탐지 =="
REPORT="$TMP/report.md"
: > "$REPORT"
( cd "$TMP" && bash scripts/hooks/doc-gardening-drift.sh "$REPORT" )
assert "종료코드 0" "0" "$?"

grep -q "plan-graduation.*done.md" "$REPORT"
assert "완료 계획이 active/ 에 남은 것을 탐지" "0" "$?"
grep -q "ongoing.md" "$REPORT"
assert "진행 중 계획은 탐지 대상 아님" "1" "$?"
grep -q "template.md" "$REPORT"
assert "template.md 는 탐지 대상 아님" "1" "$?"
grep -q "plan-noretro.*noretro.md" "$REPORT"
assert "회고 없는 completed 계획 탐지" "0" "$?"
grep -q "withretro.md" "$REPORT"
assert "회고 있는 계획은 탐지 대상 아님" "1" "$?"

echo ""
echo "== 2. 모듈 부재 시 조용히 넘어가지 않는다 =="
rm -f "$TMP/scripts/hooks/plan_state.py"
: > "$REPORT"
( cd "$TMP" && bash scripts/hooks/doc-gardening-drift.sh "$REPORT" )
grep -q "plan-check-skipped" "$REPORT"
assert "모듈 부재를 리포트에 기록" "0" "$?"

echo ""
echo "== 3. 워크플로가 공용 스크립트를 호출한다 =="
# 인라인 복제로 되돌아가면(§1-2 재발) 여기서 잡힌다.
for wf in "$REPO_ROOT/assets/cron-templates/github-actions/weekly-doc-gardening.yml" \
          "$REPO_ROOT/assets/cron-templates/gitlab-ci/weekly-doc-gardening.gitlab-ci.yml"; do
  # $? 를 먼저 담는다 — assert 인자의 $(basename) 명령 치환이 $? 를 덮어쓴다.
  wf_name="$(basename "$wf")"
  grep -q "doc-gardening-drift.sh" "$wf"; _rc=$?
  assert "$wf_name 가 공용 스크립트 호출" "0" "$_rc"
  grep -qE "grep -qiE .*(status|상태)" "$wf"; _rc=$?
  assert "$wf_name 에 죽은 status grep 없음" "1" "$_rc"
done

echo ""
echo "== 4. SessionStart 주기 점검 훅 =="
# CI 배선(.gitlab-ci.yml include + 웹 UI 스케줄)이 없어도 가드닝이 도는 경로다.
HOOK="$REPO_ROOT/assets/hooks/claude-sessionstart-doc-gardening.sh"
cp "$REPO_ROOT/assets/hooks/plan_state.py" "$TMP/scripts/hooks/" 2>/dev/null
cp "$HOOK" "$TMP/scripts/hooks/"
( cd "$TMP" && git init -q . 2>/dev/null )

OUT=$( cd "$TMP" && CLAUDE_PROJECT_DIR="$TMP" bash scripts/hooks/claude-sessionstart-doc-gardening.sh </dev/null 2>/dev/null )
_rc=$?
assert "훅이 세션 시작을 막지 않음 (exit 0)" "0" "$_rc"
echo "$OUT" | grep -q "Doc Gardening"; _rc=$?
assert "편차가 있으면 컨텍스트에 주입" "0" "$_rc"
echo "$OUT" | grep -q "plan-noretro"; _rc=$?
assert "실제 편차 항목이 포함됨" "0" "$_rc"

# 스로틀 — 방금 돌았으므로 두 번째 호출은 조용해야 한다.
OUT2=$( cd "$TMP" && CLAUDE_PROJECT_DIR="$TMP" bash scripts/hooks/claude-sessionstart-doc-gardening.sh </dev/null 2>/dev/null )
assert "스로틀 내 재호출은 무출력" "" "$OUT2"

# 옵트아웃
rm -f "$TMP/.git/.harness-gardening-marker"
OUT3=$( cd "$TMP" && HARNESS_GARDENING_ON_SESSION_START=0 CLAUDE_PROJECT_DIR="$TMP" \
        bash scripts/hooks/claude-sessionstart-doc-gardening.sh </dev/null 2>/dev/null )
assert "옵트아웃 시 무출력" "" "$OUT3"

# 모듈 부재 — 조용히 죽지 말고 그냥 통과해야 한다(세션 차단 금지)
rm -f "$TMP/.git/.harness-gardening-marker" "$TMP/scripts/hooks/plan_state.py"
( cd "$TMP" && CLAUDE_PROJECT_DIR="$TMP" bash scripts/hooks/claude-sessionstart-doc-gardening.sh </dev/null >/dev/null 2>&1 )
assert "모듈 부재에도 exit 0" "0" "$?"

echo ""
echo "== 5. 설치기가 CI 미배선을 경고로 보고한다 =="
# 안내를 INFO 로 흘리던 탓에 9개 프로젝트 전부에서 가드닝이 한 번도 돈 적이 없었다.
grep -q 'CI 에서 실행되지 않습니다' "$REPO_ROOT/lib/harness_installers.sh"; _rc=$?
assert "미배선 경고 문구 존재" "0" "$_rc"
grep -A2 'CI 에서 실행되지 않습니다' "$REPO_ROOT/lib/harness_installers.sh" | grep -q 'log_warn'; _rc=$?
assert "INFO 가 아니라 log_warn 로 보고" "0" "$_rc"
grep -q 'gitlab-ci.yml" 2>/dev/null; then' "$REPO_ROOT/lib/harness_installers.sh"; _rc=$?
assert "실제 include 유무를 grep 으로 검사" "0" "$_rc"

echo ""
echo "== 결과 =="
echo "  통과: $PASS / 실패: $FAIL"
[[ $FAIL -eq 0 ]]
