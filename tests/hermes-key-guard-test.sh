#!/usr/bin/env bash
# 키 가드 훅 검증 (계획 docs/exec-plans/active/2026-09-15-sync-transport-encryption.md 목표 5, T-11).
#
#   - 세션 안 Bash 의 age-keygen · AGE-SECRET-KEY- · hermes-keys.sh init|emergency|rotate-master 차단
#   - hermes-keys.sh doctor · add-computer · revoke 와 무관한 명령은 통과
#   - Bash 가 아닌 도구 입력은 건드리지 않는다
#
# 실행: bash tests/hermes-key-guard-test.sh
# 종료 코드: 0 = 모든 단언 통과, 1 = 실패

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$REPO_ROOT/assets/hooks/claude-pretooluse-key-guard.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  ✓ $desc"; PASS=$((PASS+1))
  else
    echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1))
  fi
}

# run_hook <tool_name> <command> → 종료 코드 출력, stderr 는 $TMP/err
run_hook() {
  python3 -c 'import json,sys;print(json.dumps({"tool_name":sys.argv[1],"tool_input":{"command":sys.argv[2]}}))' "$1" "$2" \
    | bash "$HOOK" >/dev/null 2>"$TMP/err"
  echo $?
}

echo "== 1. 차단 (목표 5) =="
assert "age-keygen 차단" 2 "$(run_hook Bash 'age-keygen -o /tmp/k.txt')"
assert "차단 문구 접두어" 1 "$(grep -c '^\[key-guard BLOCK\]' "$TMP/err")"
REAL_LIKE='AGE-SECRET-KEY-1QQPZRY9X8GF2TVDW0S3JN54KHCE6MUA7LQQPZRY9X8GF2TVDW0S3JN54KHCE6MUA7L'
assert "실제 길이의 비밀열쇠 명령줄 차단" 2 "$(run_hook Bash "printf $REAL_LIKE | age -d -i - file.age")"
assert "따옴표 안 비밀열쇠도 차단" 2 "$(run_hook Bash "echo \"$REAL_LIKE\" > k.txt")"
assert "hermes-keys.sh init 차단" 2 "$(run_hook Bash 'bash scripts/hermes-keys.sh init --yes')"
assert "hermes-keys.sh emergency 차단" 2 "$(run_hook Bash 'scripts/hermes-keys.sh emergency')"
assert "hermes-keys.sh rotate-master 차단" 2 "$(run_hook Bash 'bash scripts/hermes-keys.sh rotate-master --yes')"
assert "경로가 앞에 붙어도 차단" 2 "$(run_hook Bash '/usr/local/bin/age-keygen')"
assert "파이프 뒤에 있어도 차단" 2 "$(run_hook Bash 'true && age-keygen')"

echo ""
echo "== 2. 통과 =="
assert "hermes-keys.sh doctor 통과" 0 "$(run_hook Bash 'bash scripts/hermes-keys.sh doctor')"
assert "hermes-keys.sh add-computer 통과" 0 "$(run_hook Bash 'bash scripts/hermes-keys.sh add-computer age1abc')"
assert "hermes-keys.sh revoke 통과" 0 "$(run_hook Bash 'bash scripts/hermes-keys.sh revoke 0123abcd --yes')"
assert "age --encrypt(수신자 공개키) 통과" 0 "$(run_hook Bash 'age -r age1abc -o out.age in.txt')"
assert "무관한 명령 통과" 0 "$(run_hook Bash 'ls -la && git status')"
assert "이름에 age 가 들어간 다른 명령 통과(stage·package)" 0 "$(run_hook Bash 'git stage . && cat package.json')"
# 오탐 방지 — 2026-09-16 실측: 커밋 메시지에 'age-keygen' 을 적었다가 이 가드에 막혔다
assert "커밋 메시지 안의 age-keygen 언급은 통과" 0 "$(run_hook Bash 'git commit -m "feat: age-keygen 감싸기 추가"')"
assert "문서용 접두어 AGE-SECRET-KEY- 만 있는 문자열은 통과" 0 "$(run_hook Bash 'echo "형식: AGE-SECRET-KEY-1..."')"
assert "따옴표 밖의 age-keygen 은 여전히 차단" 2 "$(run_hook Bash 'echo "x" && age-keygen')"
assert "Bash 아닌 도구는 무시" 0 "$(run_hook Write 'age-keygen')"
assert "빈 입력은 통과" 0 "$(printf '' | bash "$HOOK" >/dev/null 2>&1; echo $?)"
assert "JSON 아닌 입력은 통과" 0 "$(printf 'not json' | bash "$HOOK" >/dev/null 2>&1; echo $?)"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
