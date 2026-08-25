#!/usr/bin/env bash
# R-mut 회귀 테스트 — 변이 테스트 도구
#
# 스펙: docs/superpowers/specs/2026-08-24-mutation-testing-design.md
#
# 이 테스트의 핵심은 **복원 보장**이다.
# 소스를 망가뜨린 채 종료하는 도구는 도구가 아니라 사고다.
# 나머지 단언이 전부 통과해도 복원이 깨지면 이 도구는 쓰면 안 된다.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROBE="$ROOT/scripts/mutation-probe.py"
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
nope() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }

[[ -f "$PROBE" ]] || { echo "  ✗ 전제: 도구 없음 — $PROBE"; echo "PASS=0 FAIL=1"; exit 1; }
ok "전제: 도구 존재"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cd "$WORK"; mkdir -p src tests

# 변이 대상. 연산자 4종이 실코드에 있고, 문자열·주석 안에도 같은 글자가 있다.
write_target() {
cat > src/target.py <<'EOF'
# 주석 안의 >= 와 == 는 변이 대상이 아니다
LABEL = "문자열 안의 >= 와 and 도 마찬가지다"


def grade(score):
    if score >= 90:
        return "A"
    return "B"


def both(a, b):
    return a and b


def missing(value):
    if not value:
        return "empty"
    return "filled"
EOF
}
write_target
ORIGINAL="$(cat src/target.py)"

# 엄격한 테스트 — 경계와 논리를 모두 단언한다. 변이를 잡아야 한다.
cat > tests/strict.sh <<'EOF'
#!/usr/bin/env bash
python3 - <<'PY'
import sys
sys.path.insert(0, "src")
import target
assert target.grade(90) == "A", "경계 90"
assert target.grade(89) == "B", "경계 89"
assert target.both(True, False) is False, "and 논리"
assert target.missing("") == "empty", "not 경로"
assert target.missing("x") == "filled", "not 경로 반대"
PY
EOF

# 느슨한 테스트 — 실행만 하고 값을 단언하지 않는다. 변이를 못 잡아야 한다.
cat > tests/loose.sh <<'EOF'
#!/usr/bin/env bash
python3 - <<'PY'
import sys
sys.path.insert(0, "src")
import target
target.grade(95)
target.both(True, True)
target.missing("x")
PY
EOF
chmod +x tests/strict.sh tests/loose.sh

run() { python3 "$PROBE" --target src/target.py --test "$1" 2>&1; }

echo "── 엄격한 테스트는 변이를 잡는다 ──"
OUT="$(run tests/strict.sh)"; RC=$?
echo "$OUT" | grep -qi 'survived\|생존' || true
echo "$OUT" | grep -qE '생존[^0-9]*0|survived[^0-9]*0' && ok "생존 변이 0건으로 보고" \
  || nope "생존 변이 0건으로 보고 — 출력: $(echo "$OUT" | tail -3 | tr '\n' ' ')"
[[ "$RC" -eq 1 ]] && ok "생존 없음 → exit 1" || nope "생존 없음 → exit 1 (실제 $RC)"

echo "── 느슨한 테스트는 변이를 놓친다 ──"
OUT="$(run tests/loose.sh)"; RC=$?
[[ "$RC" -eq 0 ]] && ok "생존 있음 → exit 0" || nope "생존 있음 → exit 0 (실제 $RC)"
echo "$OUT" | grep -q 'src/target.py:' && ok "생존 변이의 위치가 보고된다" \
  || nope "생존 변이의 위치가 보고된다"

echo "── 문자열·주석 안의 연산자는 변이하지 않는다 ──"
# 정규식 구현이면 2행 주석과 3행 문자열의 >= / == / and 까지 변이 지점으로 센다.
COUNT="$(python3 "$PROBE" --target src/target.py --list 2>/dev/null | grep -c 'src/target.py:')"
# 실코드의 연산자는 >= , and, not 셋이다. 주석의 >= / == 와 문자열의 >= / and 는 제외.
# 정규식 구현이면 7개로 셌을 자리다.
[[ "$COUNT" == "3" ]] && ok "변이 지점 3개 (실코드의 >= , and, not 만)" \
  || nope "변이 지점 3개여야 함 (실제 $COUNT)"
python3 "$PROBE" --target src/target.py --list 2>/dev/null | grep -q ':2:' \
  && nope "주석 줄은 변이 대상이 아니다" || ok "주석 줄은 변이 대상이 아니다"
python3 "$PROBE" --target src/target.py --list 2>/dev/null | grep -q ':3:' \
  && nope "문자열 줄은 변이 대상이 아니다" || ok "문자열 줄은 변이 대상이 아니다"

echo "── 복원 보장 (핵심) ──"
[[ "$(cat src/target.py)" == "$ORIGINAL" ]] && ok "정상 종료 후 원본 그대로" \
  || nope "정상 종료 후 원본이 바뀌었다"

# 테스트가 죽어도 복원돼야 한다.
cat > tests/crash.sh <<'EOF'
#!/usr/bin/env bash
kill -9 $$
EOF
chmod +x tests/crash.sh
run tests/crash.sh >/dev/null 2>&1
[[ "$(cat src/target.py)" == "$ORIGINAL" ]] && ok "테스트가 죽어도 원본 복원" \
  || nope "테스트가 죽으면 원본이 남는다"

# 도구 자체가 중간에 죽어도 복원돼야 한다. 고정 sleep 대신 마커 파일을 폴링한다
# (고정 대기는 부하 시 흔들린다 — hermes-pipeline-test.sh 가 같은 이유로 폴링을 쓴다).
# 첫 실행은 베이스라인이라 소스가 원본 상태다. 그때 잡으면 "변이가 주입돼 있다"
# 단언이 공허하게 통과한다. 베이스라인은 즉시 끝내고 그다음(첫 변이) 실행에서만 붙잡는다.
cat > tests/slow.sh <<'EOF'
#!/usr/bin/env bash
if [[ -f "$PWD/.baseline-done" ]]; then
  touch "$PWD/.probe-running"
  sleep 30
else
  touch "$PWD/.baseline-done"
fi
EOF
chmod +x tests/slow.sh
rm -f .probe-running .baseline-done
python3 "$PROBE" --target src/target.py --test tests/slow.sh >/dev/null 2>&1 &
PROBE_PID=$!
for _ in $(seq 1 100); do [[ -f .probe-running ]] && break; sleep 0.1; done
if [[ -f .probe-running ]]; then
  MUTATED="$(cat src/target.py)"
  [[ "$MUTATED" != "$ORIGINAL" ]] && ok "실행 중에는 실제로 변이가 주입돼 있다" \
    || nope "실행 중에 변이가 주입되지 않았다 — 이 도구는 아무것도 안 하고 있다"
  kill -TERM "$PROBE_PID" 2>/dev/null
  wait "$PROBE_PID" 2>/dev/null
  pkill -f 'tests/slow.sh' 2>/dev/null
  [[ "$(cat src/target.py)" == "$ORIGINAL" ]] && ok "도구가 SIGTERM 을 받아도 원본 복원" \
    || nope "SIGTERM 시 변이가 소스에 남는다"
else
  nope "전제: 느린 테스트가 시작되지 않음"
  kill -9 "$PROBE_PID" 2>/dev/null
fi
rm -f .probe-running .baseline-done

echo "── 베이스라인 검증 ──"
# 원본에서 이미 실패하는 테스트로는 변이 결과가 무의미하다. 전부 killed 로 나와
# 100% 라는 거짓 점수가 만들어진다.
cat > tests/broken.sh <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x tests/broken.sh
OUT="$(run tests/broken.sh)"; RC=$?
[[ "$RC" -eq 2 ]] && ok "원본에서 테스트가 실패하면 exit 2(판정불가)" \
  || nope "원본에서 실패해도 진행한다 — 거짓 100% 가 나온다 (실제 $RC)"
echo "$OUT" | grep -q '베이스라인' && ok "베이스라인 실패를 메시지로 알린다" \
  || nope "베이스라인 실패를 메시지로 알린다"

echo "── 테스트 자동 매핑 ──"
# scripts/hermes_loop.py → tests/hermes-loop-test.sh 규칙.
mkdir -p scripts
cp src/target.py scripts/my_mod.py
cat > tests/my-mod-test.sh <<'EOF'
#!/usr/bin/env bash
python3 -c "import sys; sys.path.insert(0,'scripts'); import my_mod; assert my_mod.grade(90)=='A'"
EOF
chmod +x tests/my-mod-test.sh
python3 "$PROBE" --target scripts/my_mod.py >/dev/null 2>&1
[[ $? -ne 2 ]] && ok "--test 없으면 이름 규칙으로 테스트를 찾는다" \
  || nope "--test 없으면 이름 규칙으로 테스트를 찾는다"

python3 "$PROBE" --target scripts/nosuch.py >/dev/null 2>&1
[[ $? -eq 2 ]] && ok "대상 파일이 없으면 exit 2" || nope "대상 파일이 없으면 exit 2"

echo "── 견고성 ──"
printf 'def broken(\n' > src/syntax.py
python3 "$PROBE" --target src/syntax.py --list >/dev/null 2>&1
[[ $? -eq 2 ]] && ok "문법 오류 대상은 exit 2" || nope "문법 오류 대상은 exit 2"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
