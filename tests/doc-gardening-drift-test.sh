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
echo "== 결과 =="
echo "  통과: $PASS / 실패: $FAIL"
[[ $FAIL -eq 0 ]]
