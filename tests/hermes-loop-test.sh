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
# bash -c 서브셸(check 헬퍼가 파이프 조건 검증에 사용)에서 loop_cli 를 쓸 수 있도록 노출
export S PROJ
export -f loop_cli

# ── mock claude (PATH 가짜 실행파일) — Task 4 의 run 테스트에서 사용 ──
cat > "$T/bin/claude" <<'EOF'
#!/usr/bin/env bash
# mock claude -p — MOCK_LOOP_PLAN="스펙1,스펙2,..." (마지막 스펙 반복)
# 스펙: continue | goalmet-pass | goalmet-fail | blocked | noreport
cnt_file="${MOCK_COUNT_FILE:?}"
n=$(cat "$cnt_file" 2>/dev/null || echo 0)
echo $((n+1)) > "$cnt_file"
# MOCK_COMMIT=1 이면 반복마다 파일 수정 + 커밋 (G14 브랜치 격리 검증용, Minor 3)
if [[ -n "${MOCK_COMMIT:-}" ]]; then
  echo "mock change $n" > mock-commit-file.txt
  git add -A -- mock-commit-file.txt 2>/dev/null
  git -c user.email=t@test -c user.name=t commit -qm "mock commit iter $n" 2>/dev/null
fi
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
echo "== 2. run — continue×2 후 goal-met (G2·G4) =="
ID2=$(new_loop)
run_loop "$ID2" "continue,continue,goalmet-pass" >/dev/null
check "status=done (G4)" test "$(sql "SELECT status FROM loops WHERE id='$ID2'")" = "done"
check "finish_reason=goal-met (G4)" test "$(sql "SELECT finish_reason FROM loops WHERE id='$ID2'")" = "goal-met"
check "3회 반복 (G2)" test "$(sql "SELECT iterations_used FROM loops WHERE id='$ID2'")" = "3"
check "loop_steps 3행 기록" test "$(sql "SELECT COUNT(*) FROM loop_steps WHERE loop_id='$ID2'")" = "3"
lg=$(grep -c '^- \[iter ' "$PROJ/.hermes/loops/$ID2/GOAL.md")
check "GOAL.md 진행 로그 3줄" test "$lg" = "3"
check "GOAL.md status=done 동기화" bash -c "grep -q 'status: done' '$PROJ/.hermes/loops/$ID2/GOAL.md'"
check "루프 브랜치 생성·체크아웃 (G14)" test "$(git -C "$PROJ" branch --show-current)" = "loop/$ID2"
check "main HEAD 미변경 (G14)" test "$(git -C "$PROJ" rev-parse main)" = "$MAIN_HEAD"
check "loops.branch 기록 (G14)" test "$(sql "SELECT branch FROM loops WHERE id='$ID2'")" = "loop/$ID2"

echo ""
echo "== 3. 교차검증 — goal-met + VERIFY fail 은 강등 (G3) =="
ID3=$(new_loop)
run_loop "$ID3" "goalmet-fail,goalmet-pass" >/dev/null
check "1회차 기각 → 2회 반복 후 완료" test "$(sql "SELECT iterations_used FROM loops WHERE id='$ID3'")" = "2"
check "1회차 verdict continue 강등" test "$(sql "SELECT verdict FROM loop_steps WHERE loop_id='$ID3' AND iteration=1")" = "continue"
check "1회차 objective_signal=fail" test "$(sql "SELECT objective_signal FROM loop_steps WHERE loop_id='$ID3' AND iteration=1")" = "fail"
check "최종 done" test "$(sql "SELECT status FROM loops WHERE id='$ID3'")" = "done"

echo ""
echo "== 4. 안전캡 — max-iter (G5) =="
ID4=$(new_loop --max-iter 2)
run_loop "$ID4" "continue" >/dev/null
check "finish_reason=max-iter" test "$(sql "SELECT finish_reason FROM loops WHERE id='$ID4'")" = "max-iter"
check "status=stopped" test "$(sql "SELECT status FROM loops WHERE id='$ID4'")" = "stopped"
check "2회에서 중단" test "$(sql "SELECT iterations_used FROM loops WHERE id='$ID4'")" = "2"

echo ""
echo "== 5. 안전캡 — no-progress (G6) =="
ID5=$(new_loop)   # max_iter=5, no_progress_limit=3
run_loop "$ID5" "continue" >/dev/null
check "finish_reason=no-progress" test "$(sql "SELECT finish_reason FROM loops WHERE id='$ID5'")" = "no-progress"
check "3회 무진전에서 중단" test "$(sql "SELECT iterations_used FROM loops WHERE id='$ID5'")" = "3"

echo ""
echo "== 6. blocked → 사람 개입 (G7) =="
ID6=$(new_loop)
run_loop "$ID6" "blocked" >/dev/null
check "status=stopped" test "$(sql "SELECT status FROM loops WHERE id='$ID6'")" = "stopped"
check "finish_reason=blocked" test "$(sql "SELECT finish_reason FROM loops WHERE id='$ID6'")" = "blocked"

echo ""
echo "== 7. 재개 준비 — step 커맨드 (G8 전반부·G10 공용 판정 코어) =="
ID7=$(new_loop)
sout=$(loop_cli step "$ID7" --action "부분 작업" --verdict continue --signal none)
check "step 출력 DECISION:continue" bash -c "echo '$sout' | grep -q 'DECISION:continue'"
check "step 후 iterations_used=1" test "$(sql "SELECT iterations_used FROM loops WHERE id='$ID7'")" = "1"
check "step 후 status=running (중단 상태 재현)" test "$(sql "SELECT status FROM loops WHERE id='$ID7'")" = "running"
check "step 이 GOAL.md 진행 로그 기록" bash -c "grep -q '\- \[iter 1\]' '$PROJ/.hermes/loops/$ID7/GOAL.md'"
run_loop "$ID7" "goalmet-pass" resume >/dev/null
check "resume 후 완료 (G8)" test "$(sql "SELECT status FROM loops WHERE id='$ID7'")" = "done"
check "iterations_used 이어짐 (=2) (G8)" test "$(sql "SELECT iterations_used FROM loops WHERE id='$ID7'")" = "2"

echo ""
echo "== 8. 완료 아카이브 (G11) =="
ar=$(sql "SELECT COUNT(*) FROM messages WHERE from_agent='loop' AND to_agent='archive' AND content LIKE '%$ID2%'")
check "messages 아카이브 행 존재" test "$ar" = "1"

echo ""
echo "== 9. 마스킹 (G12) =="
ID9=$(new_loop)
MOCK_ACTION_EXTRA="ghp_abcdefghijklmnopqrstuvwxyz0123456789" run_loop "$ID9" "goalmet-pass" >/dev/null
raw=$(sql "SELECT COUNT(*) FROM loop_steps WHERE loop_id='$ID9' AND action_summary LIKE '%ghp_abcdef%'")
check "DB 에 원문 토큰 없음" test "$raw" = "0"
red=$(sql "SELECT COUNT(*) FROM loop_steps WHERE loop_id='$ID9' AND action_summary LIKE '%[REDACTED:TOKEN]%'")
check "DB 에 [REDACTED:TOKEN] 치환" test "$red" = "1"
check "GOAL.md 로그도 치환" bash -c "grep -q 'REDACTED:TOKEN' '$PROJ/.hermes/loops/$ID9/GOAL.md' && ! grep -q 'ghp_abcdef' '$PROJ/.hermes/loops/$ID9/GOAL.md'"

echo ""
echo "== 10. 오류 안전 — REPORT 파싱 실패는 무진전 취급 (§7) =="
ID10=$(new_loop)
run_loop "$ID10" "noreport,goalmet-pass" >/dev/null
check "파싱 실패 후에도 완료" test "$(sql "SELECT status FROM loops WHERE id='$ID10'")" = "done"
check "실패 반복 기록됨 (2회)" test "$(sql "SELECT iterations_used FROM loops WHERE id='$ID10'")" = "2"

echo ""
echo "== 12. stop — user-stop =="
ID12=$(new_loop)
loop_cli stop "$ID12" >/dev/null
check "finish_reason=user-stop" test "$(sql "SELECT finish_reason FROM loops WHERE id='$ID12'")" = "user-stop"
check "status=stopped" test "$(sql "SELECT status FROM loops WHERE id='$ID12'")" = "stopped"
check "stop 후 status 커맨드 조회 가능" bash -c "loop_cli status '$ID12' | grep -q 'user-stop'"

echo ""
echo "== 13. 헤드리스 래퍼 =="
badargs=$("$S/hermes-loop-run.sh" 2>&1 || true)
check "인자 검증 (usage)" bash -c "echo '$badargs' | grep -q 'usage'"
wout=$(MOCK_COUNT_FILE="$T/cnt-wrap" MOCK_LOOP_PLAN="goalmet-pass" "$S/hermes-loop-run.sh" "$PROJ" "래퍼 테스트 목표")
check "래퍼가 loop-id/pid/log 출력" bash -c "echo '$wout' | grep -q 'id=loop-'"
wid=$(echo "$wout" | sed -n 's/.*id=\(loop-[^ ]*\).*/\1/p')
# nohup 백그라운드 완료 폴링 (고정 sleep 은 CI 고부하에서 flaky)
python3 - "$DB" "$wid" <<'EOF'
import sqlite3, sys, time
for _ in range(100):
    st = sqlite3.connect(sys.argv[1]).execute(
        "SELECT status FROM loops WHERE id=?", (sys.argv[2],)).fetchone()
    if st and st[0] == "done":
        break
    time.sleep(0.3)
EOF
check "백그라운드 루프 완료" test "$(sql "SELECT status FROM loops WHERE id='$wid'")" = "done"
check "래퍼 로그 생성" test -f "$PROJ/.hermes/logs/loop-$wid.log"

echo ""
echo "== 11. G9 — 파괴적 작업 차단 + REPORT 계약 =="
pout=$(python3 -c "
import sys; sys.path.insert(0, '$S')
from hermes_loop_prompt import build_iteration_prompt
print(build_iteration_prompt('/p', '/g', '목표', [], [], 'none', 1, 5, 'loop/test-id'))
")
check "프롬프트에 파괴적 금지 문구 (G9)" bash -c "echo '$pout' | grep -q '파괴적'"
check "프롬프트에 REPORT 계약 지시" bash -c "echo '$pout' | grep -q 'HERMES-LOOP REPORT'"
check "프롬프트에 루프 브랜치 규칙 (G14)" bash -c "echo '$pout' | grep -q 'loop/test-id' && echo '$pout' | grep -q '머지'"
parse_ok=$(python3 -c "
import sys; sys.path.insert(0, '$S')
from hermes_loop_prompt import parse_report
r = parse_report('''잡담
=== HERMES-LOOP REPORT ===
ACTION: 라우터 수정
VERDICT: continue
VERIFY: pytest -q
NEXT: 경계 테스트
=== END REPORT ===''')
assert r == {'action': '라우터 수정', 'verdict': 'continue',
             'verify': 'pytest -q', 'next': '경계 테스트'}, r
assert parse_report('리포트 없음') is None
assert parse_report('=== HERMES-LOOP REPORT ===\nVERDICT: maybe\n=== END REPORT ===') is None
print('OK')
")
check "REPORT 파서 정상/실패 경로" test "$parse_ok" = "OK"
check "run 이 dangerously-skip 미사용 (G9)" bash -c "! grep -q 'dangerously-skip-permissions' '$S/hermes-loop.py'"
check "래퍼도 dangerously-skip 미사용 (G9)" bash -c "! grep -q 'dangerously-skip-permissions' '$S/hermes-loop-run.sh'"

echo ""
echo "== 14. 설치·제거 매니페스트 정합성 (G10·G13·§8) =="
CONF="$REPO_ROOT/presets/workflow/hermes.conf"
for f in hermes_loop.py hermes_loop_prompt.py hermes_loop_report.py hermes-loop.py hermes-loop-run.sh; do
  check "hermes.conf 매니페스트: $f" bash -c "grep -q '$f' '$CONF'"
done
check "SKILLS 에 hermes-loop 등록 (G10)" bash -c "grep -qE '^  hermes-loop$' '$CONF'"
check "스킬 파일 존재 (G10)" test -f "$REPO_ROOT/assets/skills/hermes-loop/SKILL.md"
check "uninstall 매니페스트에 루프 스크립트" bash -c "grep -q 'hermes_loop' '$REPO_ROOT/uninstall.sh'"
check "run-all.sh 에 루프 테스트 등록" bash -c "grep -q 'hermes-loop-test.sh' '$REPO_ROOT/tests/run-all.sh'"

echo ""
echo "== 15. G14 커밋 격리 — 루프 브랜치에만 쌓이고 main 불변 (Important 2 검증) =="
ID15=$(new_loop)
MOCK_COMMIT=1 run_loop "$ID15" "continue,goalmet-pass" >/dev/null
check "루프 브랜치에 커밋 2건 추가" test "$(git -C "$PROJ" rev-list --count "loop/$ID15" "^main")" = "2"
check "main HEAD 여전히 불변 (G14)" test "$(git -C "$PROJ" rev-parse main)" = "$MAIN_HEAD"
check "현재 브랜치가 loop 브랜치로 유지 (G14)" test "$(git -C "$PROJ" branch --show-current)" = "loop/$ID15"

echo ""
echo "== 16. ensure_loop_branch — non-git=None / 체크아웃 실패=예외 (Important 2 단위검증) =="
branch_py=$(python3 -c "
import sys, os, subprocess, tempfile
sys.path.insert(0, '$S')
import hermes_loop

# (a) non-git 디렉터리 → None (기존 G14 동작 보존)
nongit = tempfile.mkdtemp()
db_a = os.path.join(nongit, 'a.db')
hermes_loop.ensure_schema(db_a)
res = hermes_loop.ensure_loop_branch(db_a, nongit, 'loop-a')
print('A_NONE' if res is None else 'A_FAIL:' + repr(res))

# (b) 실제 git 저장소이지만 loop/<id> 체크아웃이 실패하도록 ref 를 막아둠
# → 격리 실패이므로 None 대신 RuntimeError 를 던져야 함
repo = tempfile.mkdtemp()
subprocess.run(['git', 'init', '-q', '-b', 'main'], cwd=repo, check=True)
subprocess.run(['git', '-c', 'user.email=t@test', '-c', 'user.name=t',
                 'commit', '--allow-empty', '-qm', 'init'], cwd=repo, check=True)
refs_dir = os.path.join(repo, '.git', 'refs', 'heads')
os.makedirs(refs_dir, exist_ok=True)
with open(os.path.join(refs_dir, 'loop'), 'w') as f:
    f.write('bad')  # 'loop' 를 파일로 선점 → 'loop/<id>' 중첩 ref 생성 불가
db_b = os.path.join(repo, 'b.db')
hermes_loop.ensure_schema(db_b)
try:
    hermes_loop.ensure_loop_branch(db_b, repo, 'x')
    print('B_NO_RAISE')
except RuntimeError:
    print('B_RAISED')
")
check "(a) non-git → None 유지" bash -c "echo '$branch_py' | grep -q 'A_NONE'"
check "(b) 체크아웃 실패 → RuntimeError" bash -c "echo '$branch_py' | grep -q 'B_RAISED'"

echo ""
echo "== 17. 완료 HTML 보고서 (G15) =="
IDR=$(new_loop --condition "조건 X")
run_loop "$IDR" "goalmet-pass" >/dev/null
RP="$PROJ/.hermes/loops/$IDR/report.html"
check "report.html 생성 (G15)" test -f "$RP"
check "보고서에 종료 사유(목표 달성) 포함" grep -q "목표 달성" "$RP"
check "보고서에 반복 기록 섹션" grep -q "반복 기록" "$RP"
check "자체완결 — 외부 URL 없음 (CSP 안전)" bash -c "! grep -qE 'https?://' '$RP'"
rm -f "$RP"
rout=$(loop_cli report "$IDR")
check "report 서브커맨드 재생성 + REPORT_HTML 출력" bash -c "echo '$rout' | grep -q 'REPORT_HTML:' && test -f '$RP'"
# G15 마스킹: action 의 토큰이 이미 redact 되어 보고서에도 원문 미노출
IDRK=$(new_loop)
MOCK_ACTION_EXTRA="ghp_abcdefghijklmnopqrstuvwxyz0123456789" run_loop "$IDRK" "goalmet-pass" >/dev/null
check "보고서에 원문 토큰 미노출 (G12→G15)" bash -c "! grep -q 'ghp_abcdef' '$PROJ/.hermes/loops/$IDRK/report.html'"

echo ""
echo "PASS=$pass FAIL=$fail"
[[ $fail -eq 0 ]]
