#!/usr/bin/env bash
# R-cov 회귀 테스트 — 표준 라이브러리 커버리지 측정기
#
# 스펙: docs/superpowers/specs/2026-08-24-coverage-enforcement-design.md
#
# 이 테스트가 고정하는 것:
#   하위 프로세스 추적이 이 도구의 존재 이유다. 이 저장소의 검증 수단은 파이썬을
#   자식 프로세스로 띄우는 bash 통합 테스트라, 부모만 추적하면 전부 0% 로 나온다.
#   그리고 0% 는 "테스트가 없다" 로 읽히므로, 추적이 깨지면 게이트가 거짓 신고를 한다.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROBE="$ROOT/assets/hooks/coverage_probe.py"
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
nope() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }

[[ -f "$PROBE" ]] || { echo "  ✗ 전제: 측정기 없음 — $PROBE"; echo "PASS=0 FAIL=1"; exit 1; }
ok "전제: 측정기 존재"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cd "$WORK"; mkdir -p src

cat > src/mod.py <<'EOF'
"""docstring 은 실행 줄이 아니다."""

def used(n):
    if n > 0:
        return "positive"
    return "zero"

def never():
    return "dead"
EOF

cat > src/lonely.py <<'EOF'
def nobody_calls_me():
    return 1
EOF

cat > drive.py <<'EOF'
import sys
sys.path.insert(0, "src")
import mod
print(mod.used(1))
EOF

echo "── 하위 프로세스 추적 ──"
# bash 가 python 을 띄우는 구조. 이걸 못 잡으면 이 도구는 쓸모가 없다.
echo 'python3 drive.py' > suite.sh
python3 "$PROBE" run --data cov -- bash suite.sh >/dev/null 2>&1
[[ -n "$(ls cov 2>/dev/null)" ]] && ok "bash 가 띄운 파이썬의 커버리지가 수집됨" \
  || nope "bash 가 띄운 파이썬의 커버리지가 수집됨"

REPORT="$(python3 "$PROBE" report --data cov --scope src 2>/dev/null)"
echo "$REPORT" | grep -q 'src/mod.py' && ok "리포트에 실행된 파일이 나온다" \
  || nope "리포트에 실행된 파일이 나온다"

echo "── docstring 은 분모에서 빠진다 ──"
# 세면 문서를 잘 쓴 파일일수록 커버리지가 낮게 나와, 좋은 습관이 벌을 받는다.
TOTAL="$(echo "$REPORT" | awk '/src\/mod.py/ { split($2, a, "/"); print a[2] }')"
[[ "$TOTAL" == "6" ]] && ok "실행 가능 줄 6개로 계산 (docstring 제외)" \
  || nope "실행 가능 줄 6개로 계산 (실제 $TOTAL)"

echo "── 한 번도 실행 안 된 파일 ──"
# 리포트가 이 파일을 빠뜨리면 안 된다 — 찾으려는 대상이 바로 그 파일이다.
echo "$REPORT" | grep -q 'src/lonely.py' && ok "미실행 파일도 리포트에 나온다" \
  || nope "미실행 파일도 리포트에 나온다"

python3 "$PROBE" uncovered --data cov src/lonely.py >/dev/null 2>&1
[[ $? -eq 0 ]] && ok "미실행 파일 → exit 0(해당 있음)" || nope "미실행 파일 → exit 0(해당 있음)"
python3 "$PROBE" uncovered --data cov src/mod.py >/dev/null 2>&1
[[ $? -eq 1 ]] && ok "실행된 파일 → exit 1(해당 없음)" || nope "실행된 파일 → exit 1(해당 없음)"
OUT="$(python3 "$PROBE" uncovered --data cov src/mod.py src/lonely.py 2>/dev/null)"
[[ "$OUT" == "src/lonely.py" ]] && ok "미실행 파일만 stdout 에 나온다" \
  || nope "미실행 파일만 stdout 에 나온다 (실제 '$OUT')"

echo "── 판정불가와 위반을 구분한다 ──"
# 데이터가 없는 것은 "커버리지 0" 이 아니라 "측정한 적 없음" 이다. 섞으면 미설정이
# 위반으로 보고되고, 그 경고는 곧 무시된다.
python3 "$PROBE" uncovered --data nodata src/mod.py >/dev/null 2>&1
[[ $? -eq 2 ]] && ok "데이터 없음 → exit 2(판정불가)" || nope "데이터 없음 → exit 2(판정불가)"

echo "── 견고성 ──"
printf 'def broken(\n' > src/syntax.py
python3 "$PROBE" report --data cov --scope src >/dev/null 2>&1
[[ $? -eq 0 ]] && ok "문법 오류 파일이 있어도 죽지 않는다" || nope "문법 오류 파일이 있어도 죽지 않는다"
rm -f src/syntax.py

echo "bad json" > cov/broken.cov
python3 "$PROBE" report --data cov --scope src >/dev/null 2>&1
[[ $? -eq 0 ]] && ok "깨진 조각이 섞여도 나머지를 쓴다" || nope "깨진 조각이 섞여도 나머지를 쓴다"

python3 "$PROBE" nosuchcommand >/dev/null 2>&1
[[ $? -eq 2 ]] && ok "알 수 없는 명령 → exit 2" || nope "알 수 없는 명령 → exit 2"

echo "── 추적이 대상 프로그램의 결과를 바꾸지 않는다 ──"
# 추적 때문에 종료코드나 stdout 이 달라지면 테스트 스위트 전체가 흔들린다.
echo 'python3 -c "import sys; print(\"hello\"); sys.exit(3)"' > exitcode.sh
OUT="$(python3 "$PROBE" run --data cov2 -- bash exitcode.sh 2>/dev/null)"; RC=$?
[[ "$RC" -eq 3 ]] && ok "대상의 종료코드를 그대로 전달" || nope "대상의 종료코드를 그대로 전달 (실제 $RC)"
[[ "$OUT" == "hello" ]] && ok "대상의 stdout 을 오염시키지 않는다" \
  || nope "대상의 stdout 을 오염시키지 않는다 (실제 '$OUT')"

echo "── PYTHONPATH 를 덮어쓰지 않는다 ──"
# 테스트들이 PYTHONPATH="$SCRIPTS" 로 덮어쓰면 부트스트랩이 떨어져 나가 그 프로세스가
# 통째로 0% 로 나온다. 2026-08-25 첫 실측에서 hermes_mesh_gate.py 가 전용 테스트
# 24/24 통과 상태로 0% 를 기록했다 — 게이트가 거짓 신고를 할 뻔했다.
grep -rn 'PYTHONPATH="\$S"$\|PYTHONPATH="\$SCRIPTS"$' "$ROOT"/tests/*.sh >/dev/null 2>&1
[[ $? -eq 1 ]] && ok "테스트가 PYTHONPATH 를 덮어쓰지 않고 덧붙인다" \
  || nope "테스트가 PYTHONPATH 를 덮어쓴다 — 그 프로세스는 측정에서 빠진다"

echo "── baseline 명령 ──"
BASE="$(python3 "$PROBE" baseline --data cov --scope src 2>/dev/null)"
echo "$BASE" | grep -q '^src/lonely.py 0/' && ok "미실행 파일이 0/N 으로 기록된다" \
  || nope "미실행 파일이 0/N 으로 기록된다"
echo "$BASE" | grep -q '^# ' && ok "갱신 방법이 주석으로 남는다" || nope "갱신 방법이 주석으로 남는다"
python3 "$PROBE" baseline --data nodata --scope src >/dev/null 2>&1
[[ $? -eq 2 ]] && ok "데이터 없으면 baseline 도 exit 2" || nope "데이터 없으면 baseline 도 exit 2"

# ── R-cov 게이트 — pre-commit 단계 ───────────────────────────────────────
echo "── R-cov 게이트 ──"
REPO="$WORK/repo"; mkdir -p "$REPO"; cd "$REPO"
git init -q
git config user.email "harness-test@example.com"
git config user.name "harness-test"
mkdir -p .git/hooks
for m in pre-commit.sh plan_state.py complexity.py depcheck.py check-secrets.py coverage_probe.py; do
  [[ -f "$ROOT/assets/hooks/$m" ]] && cp "$ROOT/assets/hooks/$m" ".git/hooks/${m/pre-commit.sh/pre-commit}"
done
chmod +x .git/hooks/pre-commit

echo "x = 1" > dead.py
echo "y = 2" > live.py
git add dead.py live.py
cat > .covbaseline <<'EOF'
dead.py 0/40
live.py 30/40
EOF
OUT="$(.git/hooks/pre-commit 2>&1)"; RC=$?
[[ "$RC" -eq 0 ]] && ok "R-cov 는 차단하지 않는다" || nope "R-cov 는 차단하지 않는다 (rc=$RC)"
echo "$OUT" | grep -q '\[R-cov\]' && ok "0% 파일 수정 시 경고" || nope "0% 파일 수정 시 경고"
echo "$OUT" | grep -q 'dead.py' && ok "메시지에 해당 파일명" || nope "메시지에 해당 파일명"
echo "$OUT" | grep -q 'core-beliefs.md#r-cov' && ok "메시지에 근거 앵커" || nope "메시지에 근거 앵커"
echo "$OUT" | grep '\[R-cov\]' | grep -q 'live.py' \
  && nope "커버된 파일은 언급되지 않는다" || ok "커버된 파일은 언급되지 않는다"

echo "── 오발화 방지 ──"
git rm --cached -q dead.py >/dev/null 2>&1
.git/hooks/pre-commit 2>&1 | grep -q '\[R-cov\]' \
  && nope "커버된 파일만 커밋하면 침묵" || ok "커버된 파일만 커밋하면 침묵"

git add dead.py
rm -f .covbaseline
.git/hooks/pre-commit 2>&1 | grep -q '\[R-cov\]' \
  && nope "기준선이 없으면 조용히 통과(미설정 != 고장)" || ok "기준선이 없으면 조용히 통과(미설정 != 고장)"

# 측정 기록에 없는 새 파일은 "모른다" 이지 "0%" 가 아니다.
echo "z = 3" > brandnew.py
git add brandnew.py
printf 'live.py 30/40\n' > .covbaseline
.git/hooks/pre-commit 2>&1 | grep -q '\[R-cov\]' \
  && nope "기록에 없는 새 파일은 판정하지 않는다" || ok "기록에 없는 새 파일은 판정하지 않는다"

cd "$WORK"

echo "── 배선 ──"
grep -q 'R-cov' "$ROOT/assets/hooks/pre-commit.sh" && ok "pre-commit 에 R-cov 단계" || nope "pre-commit 에 R-cov 단계"
grep -q 'coverage_probe.py' "$ROOT/presets/workflow/harness.conf" \
  && ok "harness.conf 에 측정기 등록" || nope "harness.conf 에 측정기 등록"
grep -q 'coverage_probe.py' "$ROOT/lib/harness_installers.sh" \
  && ok ".git/hooks 로 설치됨" || nope ".git/hooks 로 설치됨"
grep -q 'coverage_probe.py' "$ROOT/lib/uninstall_helpers.sh" \
  && ok "언인스톨 경로 존재" || nope "언인스톨 경로 존재"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
