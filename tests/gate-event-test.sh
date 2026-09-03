#!/usr/bin/env bash
# gate_event.py 단위 테스트 — 게이트 발화 기록의 유일한 검증 수단.
#
# 이 저장소는 자기 자신에 하네스를 설치하지 않으므로,
# emitter 계약(스키마·로테이션·무해 실패)의 정확성은 이 테스트로만 담보된다.
#
# 실행: bash tests/gate-event-test.sh
# 종료 코드: 0 = 모든 단언 통과, 1 = 실패

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MOD="$REPO_ROOT/assets/hooks/gate_event.py"
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

EVENTS=".harness/gate-events.jsonl"

# emit 은 CLAUDE_PROJECT_DIR 가 없으면 **git 최상위로 폴백**한다. 이 테스트를 저장소 안에서
# 그대로 돌리면, 변이 테스트가 그 판정을 뒤집었을 때 레코드가 저장소의 실제 관측 파일로 샌다.
# (2026-09-03 실측: mutation-probe 실행 후 R-a·R-x·R-z2 같은 픽스처 룰이 .harness/ 에 쌓였다.)
# 모든 emit 호출을 임시 디렉터리 안에서 실행해 폴백이 저장소에 닿지 못하게 한다.
# emit_at <root> [인자...] — 해당 루트를 cwd 로 삼아 실행
emit_at() {
  local root="$1"; shift
  (cd "$root" && CLAUDE_PROJECT_DIR="$root" python3 "$MOD" "$@" 2>&1)
}

echo "== 1. 기록과 스키마 =="

ROOT1="$TMP/proj1"; mkdir -p "$ROOT1"
rc=0
emit_at "$ROOT1" emit \
  --rule R-iface --verdict block --stage pretooluse \
  --path src/foo.py --detail "폭 9 > 8" >/dev/null 2>&1 || rc=$?
assert "emit 종료코드 0" "0" "$rc"
assert "파일 생성됨" "1" "$([[ -f "$ROOT1/$EVENTS" ]] && echo 1 || echo 0)"
assert "레코드 1줄" "1" "$(wc -l < "$ROOT1/$EVENTS")"

# 스키마 필드가 모듈 상수 FIELDS 와 정확히 일치하는지 — 하드코딩 대신 모듈에서 읽는다.
# `-B` 필수. mutation-probe 가 같은 초 안에 같은 크기로 원본을 덮어쓰면
# (mtime, size) 기반 pyc 검증이 통과해 **변이본 바이트코드가 재사용된다.**
# 그 상태에서 import 하면 모듈이 엉뚱하게 실행돼 이 단언이 조용히 깨졌다(2026-09-03 실측).
KEYS=$(python3 -B -c "
import json,sys
import importlib.util
spec=importlib.util.spec_from_file_location('ge','$MOD'); m=importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
rec=json.loads(open('$ROOT1/$EVENTS').readline())
print('OK' if tuple(rec.keys())==m.FIELDS else 'MISMATCH:%s vs %s'%(tuple(rec.keys()),m.FIELDS))
")
assert "레코드 키가 FIELDS 와 일치" "OK" "$KEYS"

VERDICT=$(python3 -c "import json;print(json.loads(open('$ROOT1/$EVENTS').readline())['verdict'])")
assert "verdict 보존" "block" "$VERDICT"

echo "== 2. verdict/stage 검증 =="

rc=0
OUT=$(emit_at "$ROOT1" emit --rule R-x --verdict bogus 2>&1) || rc=$?
assert "잘못된 verdict 도 종료코드 0 (게이트를 죽이지 않는다)" "0" "$rc"
assert "실패를 stderr 로 알린다 (조용한 실패 금지)" "1" "$(grep -qc "기록 실패" <<< "$OUT" && echo 1 || echo 0)"
assert "잘못된 verdict 는 기록되지 않음" "1" "$(wc -l < "$ROOT1/$EVENTS")"

# `skipped` 는 게이트가 판정하지 못한 상태다. pass 와 합치면 죽은 게이트가 통과로 보인다.
emit_at "$ROOT1" emit --rule R-cx --verdict skipped \
  --stage precommit --detail "complexity.py 없음" >/dev/null 2>&1
assert "skipped 는 유효한 verdict" "2" "$(wc -l < "$ROOT1/$EVENTS")"

echo "== 3. 루트를 못 찾으면 무기록·무해 =="

NOGIT="$TMP/nogit"; mkdir -p "$NOGIT"
rc=0
(cd "$NOGIT" && CLAUDE_PROJECT_DIR="" GIT_CEILING_DIRECTORIES="$TMP" \
  python3 "$MOD" emit --rule R-x --verdict pass >/dev/null 2>&1) || rc=$?
assert "git 루트 밖에서도 종료코드 0" "0" "$rc"
assert "파일을 만들지 않음" "0" "$([[ -e "$NOGIT/$EVENTS" ]] && echo 1 || echo 0)"

echo "== 4. 쓰기 실패가 훅을 죽이지 않는다 =="

RO="$TMP/readonly"; mkdir -p "$RO/.harness"
: > "$RO/$EVENTS"; chmod 444 "$RO/$EVENTS"; chmod 555 "$RO/.harness"
rc=0
emit_at "$RO" emit --rule R-x --verdict pass >/dev/null 2>&1 || rc=$?
assert "쓰기 불가여도 종료코드 0" "0" "$rc"
chmod 755 "$RO/.harness" 2>/dev/null; chmod 644 "$RO/$EVENTS" 2>/dev/null

echo "== 5. 로테이션 (상한 초과 시 오래된 줄부터 절삭) =="

ROT="$TMP/rot"; mkdir -p "$ROT/.harness"
python3 -c "
import json
with open('$ROT/$EVENTS','w') as f:
    for i in range(12):
        f.write(json.dumps({'ts':i,'rule':'R-old','verdict':'pass','stage':None,'path':None,'detail':str(i)})+'\n')
"
GATE_EVENTS_MAX_LINES=10 emit_at "$ROT" emit \
  --rule R-new --verdict pass >/dev/null 2>&1
assert "상한 10 으로 절삭" "10" "$(wc -l < "$ROT/$EVENTS")"
assert "가장 오래된 줄이 사라짐" "0" "$(grep -c '"detail": "0"' "$ROT/$EVENTS")"
assert "방금 쓴 줄은 남음" "1" "$(grep -c '"rule": "R-new"' "$ROT/$EVENTS")"

echo "== 6. 경로 폴백과 인자 검증 (R-mut 생존 변이에서 도출) =="

# git 저장소를 하나 만들어 CLAUDE_PROJECT_DIR 없이도 루트를 찾는지 본다.
GITROOT="$TMP/gitrepo"; mkdir -p "$GITROOT"
git -C "$GITROOT" init -q 2>/dev/null
(cd "$GITROOT" && env -u CLAUDE_PROJECT_DIR python3 "$MOD" emit --rule R-g --verdict pass >/dev/null 2>&1)
assert "CLAUDE_PROJECT_DIR 없으면 git 루트에 기록" "1" \
  "$([[ -f "$GITROOT/$EVENTS" ]] && echo 1 || echo 0)"

# 환경변수가 있어도 존재하지 않는 디렉터리면 git 루트로 넘어가야 한다.
rm -f "$GITROOT/$EVENTS"
(cd "$GITROOT" && CLAUDE_PROJECT_DIR="$TMP/does-not-exist" \
  python3 "$MOD" emit --rule R-g2 --verdict pass >/dev/null 2>&1)
assert "환경변수가 실재 디렉터리가 아니면 git 루트로 폴백" "1" \
  "$([[ -f "$GITROOT/$EVENTS" ]] && echo 1 || echo 0)"

# GATE_EVENTS_MAX_LINES 가 유효하지 않으면 기본값을 쓴다 (0 으로 전부 지우면 안 된다).
ZERO="$TMP/zero"; mkdir -p "$ZERO/.harness"
python3 -c "
import json
with open('$ZERO/$EVENTS','w') as f:
    for i in range(3):
        f.write(json.dumps({'ts':i,'rule':'R-z','verdict':'pass','stage':None,'path':None,'detail':str(i)})+'\n')
"
GATE_EVENTS_MAX_LINES=0 emit_at "$ZERO" emit \
  --rule R-z2 --verdict pass >/dev/null 2>&1
assert "상한 0 은 무시하고 기본값 사용 (레코드 보존)" "4" "$(wc -l < "$ZERO/$EVENTS")"

# 숫자가 아닌 상한도 기본값으로 떨어져야 한다 (int() 예외로 기록을 통째로 잃지 않는다).
ABC="$TMP/abc"; mkdir -p "$ABC"
OUT=$(GATE_EVENTS_MAX_LINES=abc emit_at "$ABC" emit \
  --rule R-a --verdict pass 2>&1)
assert "숫자 아닌 상한이어도 정상 기록" "1" "$([[ -f "$ABC/$EVENTS" ]] && echo 1 || echo 0)"
# 기록만 보면 부족하다 — 상한 파싱이 예외를 던져도 append 는 이미 끝난 뒤라
# 파일은 생긴다. 로테이션 단계가 조용히 죽지 않았는지 stderr 로 확인한다.
assert "상한 파싱이 예외를 내지 않음" "0" \
  "$(grep -qc "기록 실패" <<< "$OUT" && echo 1 || echo 0)"

# 서브커맨드 없이 호출해도 죽지 않는다.
rc=0; python3 "$MOD" >/dev/null 2>&1 || rc=$?
assert "인자 없이 호출해도 종료코드 0" "0" "$rc"
rc=0; python3 "$MOD" bogus >/dev/null 2>&1 || rc=$?
assert "모르는 서브커맨드도 종료코드 0" "0" "$rc"

# --rule 또는 --verdict 중 하나만 있어도 기록하지 않는다.
ARG="$TMP/args"; mkdir -p "$ARG"
OUT=$(emit_at "$ARG" emit --verdict pass 2>&1)
assert "--rule 없으면 기록 안 함" "0" "$([[ -e "$ARG/$EVENTS" ]] && echo 1 || echo 0)"
# 메시지까지 단언한다 — 하나만 빠졌을 때 KeyError 로 새는 경로와 구분되지 않으면
# "둘 다 빠져야 오류" 로 조건이 느슨해져도 테스트가 통과한다.
assert "--rule 누락은 필수 인자 오류로 보고" "1" \
  "$(grep -qc "필수다" <<< "$OUT" && echo 1 || echo 0)"
emit_at "$ARG" emit --rule R-only >/dev/null 2>&1
assert "--verdict 없으면 기록 안 함" "0" "$([[ -e "$ARG/$EVENTS" ]] && echo 1 || echo 0)"

echo
echo "통과 $PASS / 실패 $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
