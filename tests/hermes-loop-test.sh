#!/usr/bin/env bash
# 헤르메스 루프 통합 테스트 — init → run(모킹 claude) → 안전캡/교차검증/재개/
# 아카이브/마스킹까지 목표 기반 자율 루프 전체 검증 (설계 G1~G13).
#
# 격리 원칙 (hermes-pipeline-test.sh 패턴):
#   - HOME 을 임시 디렉터리로 오버라이드 → 실 ~/.hermes 절대 접근 금지
#   - 프로젝트 DB 는 임시 프로젝트 하위 .hermes/state.db
#   - claude 를 PATH 가짜 바이너리로 모킹 (MOCK_LOOP_PLAN=콤마 구분 시나리오)
#
# 실행: bash tests/hermes-loop-test.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$REPO_ROOT/scripts"

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export HOME="$T/fakehome"   # ~/.hermes 격리 — 실DB 보호
mkdir -p "$HOME" "$T/bin" "$T/proj"
PROJ="$T/proj"
DB="$PROJ/.hermes/state.db"

# git 픽스처 — 루프 브랜치(G14)·진전 판정 검증용
git -C "$PROJ" init -q -b main
git -C "$PROJ" -c user.email=t@test -c user.name=t commit --allow-empty -qm "init"
MAIN_HEAD=$(git -C "$PROJ" rev-parse main)

pass=0; fail=0
check() { # check <desc> <cond...>
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "  ✓ $desc"; pass=$((pass+1));
  else echo "  ✗ $desc"; fail=$((fail+1)); fi
}
sql() { python3 -c "
import sqlite3,sys
con=sqlite3.connect('$DB')
print(con.execute(sys.argv[1]).fetchone()[0])
" "$1"; }
loop_cli() { python3 "$S/hermes-loop.py" --project-dir "$PROJ" "$@"; }
new_loop() { # new_loop [init 추가 인자...] → LOOP_ID 출력
  loop_cli init --goal "테스트 목표" "$@" | sed -n 's/^LOOP_ID://p'; }

# ── mock claude (PATH 가짜 실행파일) — Task 4 의 run 테스트에서 사용 ──
cat > "$T/bin/claude" <<'EOF'
#!/usr/bin/env bash
# mock claude -p — MOCK_LOOP_PLAN="스펙1,스펙2,..." (마지막 스펙 반복)
# 스펙: continue | goalmet-pass | goalmet-fail | blocked | noreport
cnt_file="${MOCK_COUNT_FILE:?}"
n=$(cat "$cnt_file" 2>/dev/null || echo 0)
echo $((n+1)) > "$cnt_file"
IFS=',' read -ra plan <<< "${MOCK_LOOP_PLAN:-continue}"
idx=$n; [[ $idx -ge ${#plan[@]} ]] && idx=$((${#plan[@]}-1))
emit() { # emit <verdict> <verify>
  echo "작업 서술..."
  echo "=== HERMES-LOOP REPORT ==="
  echo "ACTION: mock action $((n+1)) ${MOCK_ACTION_EXTRA:-}"
  echo "VERDICT: $1"
  echo "VERIFY: $2"
  echo "NEXT: 다음 단계"
  echo "=== END REPORT ==="
}
case "${plan[$idx]}" in
  continue)     emit continue none ;;
  goalmet-pass) emit "goal-met" true ;;
  goalmet-fail) emit "goal-met" false ;;
  blocked)      emit blocked none ;;
  noreport)     echo "리포트 없음" ;;
esac
EOF
chmod +x "$T/bin/claude"
export PATH="$T/bin:$PATH"
run_loop() { # run_loop <loop-id> <plan> [run|resume]
  MOCK_COUNT_FILE="$T/cnt-$1" MOCK_LOOP_PLAN="$2" loop_cli "${3:-run}" "$1"; }

echo "== 1. init — G1·G13 =="
python3 "$S/hermes-init.py" --both "$PROJ" >/dev/null
lt=$(sql "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='loops'")
check "hermes-init 가 loops 테이블 생성 (G13)" test "$lt" = "1"
ls2=$(sql "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='loop_steps'")
check "loop_steps 테이블 생성 (G13)" test "$ls2" = "1"
python3 "$S/hermes-init.py" --both "$PROJ" >/dev/null 2>&1
check "init 재실행 멱등 (G13)" test "$?" = "0"

ID1=$(new_loop --condition "조건 A" --condition "조건 B")
check "GOAL.md 생성 (G1)" test -f "$PROJ/.hermes/loops/$ID1/GOAL.md"
st=$(sql "SELECT status FROM loops WHERE id='$ID1'")
check "loops 행 status=running (G1)" test "$st" = "running"
mi=$(sql "SELECT max_iterations FROM loops WHERE id='$ID1'")
check "max_iterations = 조건2×3=6 (§6.1)" test "$mi" = "6"
mi0=$(sql "SELECT max_iterations FROM loops WHERE id='$(new_loop)'")
check "조건 0개 → 최소 5회 (§6.1)" test "$mi0" = "5"
check "GOAL.md 에 완료 조건 체크박스" bash -c "grep -q '\- \[ \] 조건 A' '$PROJ/.hermes/loops/$ID1/GOAL.md'"

echo ""
echo "PASS=$pass FAIL=$fail"
[[ $fail -eq 0 ]]
