#!/usr/bin/env bash
# 열쇠 CLI·마스터 감싸기 검증 (계획 docs/exec-plans/active/2026-09-15-sync-transport-encryption.md 목표 3·4).
#
#   - init: 마스터 + 컴퓨터 자물쇠, 감싼 마스터 1개
#   - add-computer: 자물쇠 2개 등록 → 감싼 마스터 2개, 어느 열쇠로도 마스터 복호 성공
#   - 조각은 마스터 자물쇠 **하나**에만 잠긴다(수신자 1개)
#   - emergency: 24단어 → 재입력 확인 → 시험 복호 → 등록, 평문 열쇠 파일은 남지 않음
#   - 니모닉 왕복 무손실, 단어 하나 오타는 체크섬으로 거부
#   - revoke: 등록 파일 제거
#   - rotate-master: 옛 마스터 보관, 옛 조각은 옛 마스터로만 열림
#
# 열쇠는 임시 HOME 에만 만든다. 실제 ~/.hermes/keys/ 는 건드리지 않는다.
# 24단어는 화면에 찍지 않고 임시 파일로 받아 그 안에서만 검사한다(T-11 과 같은 취지).
#
# 실행: bash tests/hermes-keys-test.sh
# 종료 코드: 0 = 모든 단언 통과, 1 = 실패

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$REPO_ROOT/scripts"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/fakehome"; mkdir -p "$HOME"

PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  ✓ $desc"; PASS=$((PASS+1))
  else
    echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1))
  fi
}

if ! command -v age >/dev/null 2>&1 || ! command -v age-keygen >/dev/null 2>&1; then
  echo "  ✗ 전제: age 미설치 — 이 테스트는 age 가 필요하다"; echo "PASS=0 FAIL=1"; exit 1
fi

# 프로젝트 사본(스크립트·사전 포함) — 설치본과 같은 배치
PROJ="$TMP/proj"; mkdir -p "$PROJ/scripts/data" "$PROJ/.hermes"
for m in hermes-keys.sh hermes_crypto.py hermes_keys.py hermes_mnemonic.py hermes_universe.py; do
  cp "$S/$m" "$PROJ/scripts/"
done
cp "$REPO_ROOT/assets/data/bip39-english.txt" "$PROJ/scripts/data/"
PYTHONPATH="$S" python3 -c "
from hermes_universe import ensure_universe_id; ensure_universe_id('$PROJ')"
UNI="$(cat "$PROJ/.hermes/universe.id")"
KEYS="$HOME/.hermes/keys/$UNI"
K() { bash "$PROJ/scripts/hermes-keys.sh" "$@" --project "$PROJ"; }
py() { PYTHONPATH="$S" python3 -c "$1"; }
n_pub()  { ls "$KEYS/wrapped/"*.pub 2>/dev/null | wc -l; }
n_wrap() { ls "$KEYS/wrapped/"master.*.age 2>/dev/null | wc -l; }
mode()   { stat -c '%a' "$1" 2>/dev/null; }

echo "== 1. init (목표 3) =="
K init >"$TMP/init.out" 2>&1
assert "init 종료 코드 0" 0 "$?"
assert "마스터 열쇠 존재" 1 "$([[ -f "$KEYS/master.key" ]] && echo 1 || echo 0)"
assert "마스터 권한 0600" 600 "$(mode "$KEYS/master.key")"
assert "컴퓨터 열쇠 권한 0600" 600 "$(mode "$KEYS/computer.key")"
assert "자물쇠 1개 등록" 1 "$(n_pub)"
assert "감싼 마스터 1개" 1 "$(n_wrap)"
K init >"$TMP/init2.out" 2>&1
assert "재실행은 덮어쓰지 않음" 1 "$(grep -c '이미 있다' "$TMP/init2.out")"

echo ""
echo "== 2. 조각은 마스터 자물쇠 하나에만 잠긴다 (목표 3) =="
MASTER_LOCK="$(py "
import sys; sys.path.insert(0,'$S')
from hermes_keys import master_recipient; print(master_recipient('$UNI'))")"
printf '턴 조각 원문' | age -r "$MASTER_LOCK" -o "$TMP/frag.age"
assert "조각 헤더의 수신자 stanza 1개" 1 "$(age --decrypt -i "$KEYS/master.key" "$TMP/frag.age" >/dev/null 2>&1 && grep -ac '^-> X25519' "$TMP/frag.age")"
assert "마스터로 복호 성공" "턴 조각 원문" "$(age --decrypt -i "$KEYS/master.key" "$TMP/frag.age")"

echo ""
echo "== 3. add-computer — 자물쇠 2개, 어느 열쇠로도 마스터를 푼다 (목표 3) =="
age-keygen -o "$TMP/other-computer.key" >/dev/null 2>&1
OTHER_LOCK="$(age-keygen -y "$TMP/other-computer.key")"
K add-computer "$OTHER_LOCK" >"$TMP/add.out" 2>&1
assert "add-computer 종료 코드 0" 0 "$?"
assert "자물쇠 2개" 2 "$(n_pub)"
assert "감싼 마스터 2개" 2 "$(n_wrap)"
FP_OTHER="$(py "
import sys; sys.path.insert(0,'$S')
from hermes_keys import fingerprint; print(fingerprint('$OTHER_LOCK'))")"
age --decrypt -i "$TMP/other-computer.key" "$KEYS/wrapped/master.$FP_OTHER.age" >"$TMP/master-from-other.key" 2>/dev/null
assert "다른 컴퓨터 열쇠로 감싼 마스터를 풀면 원본과 동일" "$(cat "$KEYS/master.key")" "$(cat "$TMP/master-from-other.key")"
assert "풀린 마스터로 조각 복호" "턴 조각 원문" "$(age --decrypt -i "$TMP/master-from-other.key" "$TMP/frag.age")"
K add-computer "not-a-lock" >/dev/null 2>&1
assert "age1 로 시작하지 않으면 거부(rc=2)" 2 "$?"

echo ""
echo "== 4. emergency — 24단어·재입력·시험 복호·등록 (목표 4) =="
# 24단어는 화면에 찍지 않는다 — 임시 파일로만 받는다
K emergency --yes >"$TMP/emergency.out" 2>&1
assert "emergency 종료 코드 0" 0 "$?"
assert "24단어가 출력됨(파일 안에서만 확인)" 24 "$(grep -oE '[0-9]+\.[a-z]+' "$TMP/emergency.out" | wc -l)"
assert "확인 완료·등록 문구" 1 "$(grep -c '확인 완료 · 등록됨' "$TMP/emergency.out")"
assert "자물쇠 3개" 3 "$(n_pub)"
assert "감싼 마스터 3개" 3 "$(n_wrap)"
assert "비상 열쇠 평문 파일이 남지 않음" 0 "$(find "$TMP" "$HOME" -name 'emergency.key' 2>/dev/null | wc -l)"
# 출력에서 24단어를 복원해 실제로 마스터를 풀 수 있는지
WORDS="$(grep -oE '[0-9]+\.[a-z]+' "$TMP/emergency.out" | sed 's/^[0-9]*\.//' | tr '\n' ' ')"
RESTORED_KEY="$(py "
import sys; sys.path.insert(0,'$S')
from hermes_mnemonic import mnemonic_to_key; print(mnemonic_to_key('''$WORDS'''))")"
EMERG_LOCK="$(printf '%s\n' "$RESTORED_KEY" > "$TMP/em.key"; age-keygen -y "$TMP/em.key")"
FP_EM="$(py "
import sys; sys.path.insert(0,'$S')
from hermes_keys import fingerprint; print(fingerprint('$EMERG_LOCK'))")"
assert "24단어로 복원한 열쇠의 지문이 등록된 것과 일치" 1 "$([[ -f "$KEYS/wrapped/master.$FP_EM.age" ]] && echo 1 || echo 0)"
assert "복원 열쇠로 감싼 마스터를 풀면 원본과 동일" "$(cat "$KEYS/master.key")" "$(age --decrypt -i "$TMP/em.key" "$KEYS/wrapped/master.$FP_EM.age")"

echo ""
echo "== 5. 니모닉 왕복·오타 검출 (목표 4) =="
assert "열쇠 → 24단어 → 열쇠 바이트 동일" ok "$(py "
import sys; sys.path.insert(0,'$S')
from hermes_mnemonic import key_to_mnemonic, mnemonic_to_key
k='$RESTORED_KEY'; print('ok' if mnemonic_to_key(key_to_mnemonic(k))==k else 'bad')")"
assert "단어 하나 오타는 체크섬으로 거부" rejected "$(py "
import sys; sys.path.insert(0,'$S')
from hermes_mnemonic import key_to_mnemonic, mnemonic_to_key, MnemonicError
w=key_to_mnemonic('$RESTORED_KEY'); w[3]='zoo' if w[3]!='zoo' else 'abandon'
try: mnemonic_to_key(w); print('accepted')
except MnemonicError: print('rejected')")"
assert "사전에 없는 단어 거부" rejected "$(py "
import sys; sys.path.insert(0,'$S')
from hermes_mnemonic import mnemonic_to_key, MnemonicError
try: mnemonic_to_key(['notaword']*24); print('accepted')
except MnemonicError: print('rejected')")"

echo ""
echo "== 6. revoke =="
K revoke "$FP_OTHER" --yes >"$TMP/revoke.out" 2>&1
assert "revoke 종료 코드 0" 0 "$?"
assert "자물쇠 2개로 감소" 2 "$(n_pub)"
assert "감싼 마스터 2개로 감소" 2 "$(n_wrap)"
assert "옛 열쇠 보유자는 과거 조각을 계속 연다는 경고" 1 "$(grep -c '과거 조각' "$TMP/revoke.out")"

echo ""
echo "== 7. rotate-master — 옛 조각은 옛 마스터로만 (목표 4, G-4) =="
OLD_MASTER="$(cat "$KEYS/master.key")"
K rotate-master --yes >"$TMP/rotate.out" 2>&1
assert "rotate-master 종료 코드 0" 0 "$?"
assert "옛 마스터가 보관됨(retired-*)" 1 "$(ls "$KEYS"/master.key.retired-* 2>/dev/null | wc -l)"
assert "보관본이 옛 마스터와 동일" "$OLD_MASTER" "$(cat "$KEYS"/master.key.retired-* | head -c 100000)"
assert "새 마스터는 옛 것과 다름" 1 "$([[ "$(cat "$KEYS/master.key")" != "$OLD_MASTER" ]] && echo 1 || echo 0)"
assert "옛 조각은 새 마스터로 열리지 않음" fail "$(age --decrypt -i "$KEYS/master.key" "$TMP/frag.age" >/dev/null 2>&1 && echo open || echo fail)"
assert "옛 조각은 옛 마스터로 열림" "턴 조각 원문" "$(age --decrypt -i "$(ls "$KEYS"/master.key.retired-* | head -1)" "$TMP/frag.age")"
NEW_LOCK="$(py "
import sys; sys.path.insert(0,'$S')
from hermes_keys import master_recipient; print(master_recipient('$UNI'))")"
printf '새 조각' | age -r "$NEW_LOCK" -o "$TMP/frag2.age"
assert "새 조각은 새 마스터로 열림" "새 조각" "$(age --decrypt -i "$KEYS/master.key" "$TMP/frag2.age")"

echo ""
echo "== 9. lock — 두 번째 컴퓨터는 자물쇠만 만든다, 마스터 없음 (계획 agent-memory-roundtrip 목표 4) =="
HOME2="$TMP/fakehome2"; mkdir -p "$HOME2"; KEYS2="$HOME2/.hermes/keys/$UNI"
HOME="$HOME2" bash "$PROJ/scripts/hermes-keys.sh" lock --project "$PROJ" >"$TMP/lock.out" 2>&1
assert "lock 종료 코드 0" 0 "$?"
assert "컴퓨터 열쇠 생성(0600)" 600 "$(mode "$KEYS2/computer.key")"
assert "마스터 열쇠는 만들지 않음" 0 "$([[ -f "$KEYS2/master.key" ]] && echo 1 || echo 0)"
LOCK1="$(grep -E '^age1' "$TMP/lock.out")"
assert "자물쇠(age1…) 출력" 1 "$([[ "$LOCK1" == age1* ]] && echo 1 || echo 0)"
HOME="$HOME2" bash "$PROJ/scripts/hermes-keys.sh" lock --project "$PROJ" >"$TMP/lock2.out" 2>&1
assert "재실행은 같은 자물쇠(이미 있음)" "$LOCK1" "$(grep -E '^age1' "$TMP/lock2.out")"
assert "재실행 안내에 '이미 있음'" 1 "$(grep -c '이미 있음' "$TMP/lock2.out")"
K add-computer "$LOCK1" >/dev/null 2>&1
assert "첫 컴퓨터가 그 자물쇠로 마스터를 감쌀 수 있다" 1 "$(ls "$KEYS/wrapped/"master.*.age | grep -c "$(py "from hermes_keys import fingerprint;print(fingerprint('$LOCK1'))")")"

echo "== 8. doctor =="
K doctor >"$TMP/doctor.out" 2>&1
assert "doctor 종료 코드 0" 0 "$?"
assert "age 버전 표시" 1 "$(grep -cE 'age: v?[0-9]' "$TMP/doctor.out")"   # 배포판 패키지(apt 1.1.1)는 v 없이 찍는다 — CI 러너에서 실측(2026-09-20)
assert "권한 경고 없음" 0 "$(grep -c '⚠' "$TMP/doctor.out")"
chmod 644 "$KEYS/master.key"
K doctor >"$TMP/doctor2.out" 2>&1
assert "권한이 틀어지면 경고" 1 "$(grep -c '0600 이어야' "$TMP/doctor2.out")"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
