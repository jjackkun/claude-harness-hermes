#!/usr/bin/env bash
# 러너의 병렬 모드 (계획 2026-09-23-test-suite-parallel) — 순차와 **같은 판정**, **온전한 출력**.
#
# 러너 자신을 시험하므로 실 묶음(107개, 35분)을 돌리지 않는다. run-all.sh 를 임시 사본으로 떠서
# REGISTERED_TESTS 를 가짜 시험 몇 개로 갈아 끼우고, 그 사본을 돌린다.
set -uo pipefail
OUTER_JOBS="${HARNESS_TEST_JOBS:-1}"   # 바깥 묶음이 준 값 — 아래 run() 이 덮어쓰기 전에 잡는다
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
assert() { if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; PASS=$((PASS+1)); else echo "  ✗ $1 (expected=$2 actual=$3)"; FAIL=$((FAIL+1)); fi; }

# 사본 러너는 자기 위치로 REPO_ROOT 를 잡는다(`dirname $0/..`) — 가짜 저장소 모양을 그대로 만든다.
FAKE_REPO="$TMP/repo"; T="$FAKE_REPO/tests"; mkdir -p "$T"
for n in a b c; do
  cat > "$T/fake-$n-test.sh" <<EOF
#!/usr/bin/env bash
for i in 1 2 3 4 5; do echo "fake-$n line \$i"; sleep 0.2; done
exit 0
EOF
done
cat > "$T/fake-bad-test.sh" <<'EOF'
#!/usr/bin/env bash
for i in 1 2 3; do echo "fake-bad line $i"; sleep 0.2; done
exit 1
EOF
chmod +x "$T"/*.sh

# ── run-all.sh 사본: 정적·무결성 단계를 끄고 REGISTERED_TESTS 를 가짜로 교체
RUNNER="$T/run-all.sh"
python3 - "$REPO_ROOT/tests/run-all.sh" "$RUNNER" <<'PY'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
# 등록 목록을 가짜 넷으로
src = re.sub(r"REGISTERED_TESTS=\((.|\n)*?\n\)",
             'REGISTERED_TESTS=(\n  fake-a-test.sh\n  fake-b-test.sh\n  fake-c-test.sh\n  fake-bad-test.sh\n)',
             src, count=1)
# §1·§2 단계는 이 시험의 대상이 아니다 — 호출 줄만 지운다
for line in ('run_step "고아 테스트 검사" orphan_test_check',
             'run_step "bash -n (셸 문법 전수)" bash_syntax_check',
             'run_step "python3 -m py_compile (scripts + lib)" python_compile_check',
             'run_step "preset-integrity-test.sh" bash "$TESTS_DIR/preset-integrity-test.sh"',
             'run_step "sync-plugins.sh --check" bash "$REPO_ROOT/scripts/sync-plugins.sh" --check'):
    src = src.replace(line, ": # (시험용으로 비활성)")
open(sys.argv[2], "w", encoding="utf-8").write(src)
PY
run() { HARNESS_TEST_JOBS="$1" bash "$RUNNER" 2>&1; }
elapsed_ms() { local s e; s=$(date +%s%N); HARNESS_TEST_JOBS="$1" bash "$RUNNER" >/dev/null 2>&1; e=$(date +%s%N); echo $(( (e - s) / 1000000 )); }

echo "== 목표 1. 기본값(1)은 지금과 같다 =="
OUT1="$(run 1)"; RC1=$?
assert "실패가 있으므로 rc 1" 1 "$RC1"
assert "RUN 표지 4개" 4 "$(grep -c '── RUN: fake-' <<<"$OUT1")"
assert "PASS 3 · FAIL 1" "3 1" "$(grep -c '── PASS: fake-' <<<"$OUT1") $(grep -c '── FAIL: fake-' <<<"$OUT1")"
assert "실패 목록에 이름" 1 "$(grep -c 'fake-bad-test.sh' <<<"$(sed -n '/실패 목록/,$p' <<<"$OUT1")")"

echo "== 목표 2. 병렬이어도 판정 집합이 같다 =="
OUT4="$(run 4)"; RC4=$?
assert "병렬 rc 도 1" 1 "$RC4"
names() { grep -oE '── (PASS|FAIL): fake-[a-z]+-test\.sh' <<<"$1" | sort; }
assert "통과·실패 이름 집합 일치" "$(names "$OUT1")" "$(names "$OUT4")"
assert "요약 수치 일치" "$(grep -E '실행: ' <<<"$OUT1")" "$(grep -E '실행: ' <<<"$OUT4")"

echo "== 목표 3. 출력이 섞이지 않는다 =="
# 각 RUN 과 그 PASS/FAIL 사이에 **다른** 시험의 줄이 없어야 한다
inter=$(python3 - <<'PY' "$OUT4"
import re, sys
out = sys.argv[1]
bad = 0
for m in re.finditer(r"── RUN: (fake-[a-z]+-test\.sh) ──(.*?)── (?:PASS|FAIL): \1 ──", out, re.S):
    who = m.group(1).split("-")[1]
    for line in m.group(2).splitlines():
        if line.startswith("fake-") and not line.startswith(f"fake-{who} ") and not line.startswith(f"fake-{who} line"):
            bad += 1
print(bad)
PY
)
assert "블록 안에 남의 줄 0" 0 "$inter"
assert "각 시험의 줄이 모두 남아 있다" "5 5 5 3" "$(grep -c '^fake-a line' <<<"$OUT4") $(grep -c '^fake-b line' <<<"$OUT4") $(grep -c '^fake-c line' <<<"$OUT4") $(grep -c '^fake-bad line' <<<"$OUT4")"

echo "== 목표 2b. 병렬이 실제로 빠르다 (구현 없이는 통과할 수 없는 단언) =="
# 가짜 4개가 각자 ~0.6~1.0초 잔다. 순차면 합, 병렬(4)이면 가장 긴 하나 수준이어야 한다.
# 집합 비교만으로는 "구현 안 됨" 과 "구현 됨" 이 구분되지 않는다 — 오늘 그 헛통과를 실제로 봤다.
# 바깥 묶음이 이미 병렬로 돌면(HARNESS_TEST_JOBS>1 을 물려받음) 다른 설치 시험과 CPU 를 다퉈
# 벽시계 비율이 흔들린다 — 코드가 옳아도 떨어질 수 있다. 그때는 이 단언만 건너뛴다(2026-09-23 리뷰 지적).
if [[ "${OUTER_JOBS:-1}" -gt 1 ]]; then
  echo "  - (건너뜀) 바깥이 병렬(${OUTER_JOBS})로 도는 중 — 벽시계 비교가 공정하지 않다"
else
  MS1=$(elapsed_ms 1); MS4=$(elapsed_ms 4)
  echo "     순차 ${MS1}ms · 병렬(4) ${MS4}ms"
  assert "병렬이 순차의 60% 미만" 1 "$([[ $MS4 -lt $((MS1 * 60 / 100)) ]] && echo 1 || echo 0)"
fi

echo; echo "run-all-parallel: PASS=$PASS FAIL=$FAIL"; [[ $FAIL -eq 0 ]]
