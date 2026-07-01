#!/usr/bin/env bash
# 헤르메스 민감정보 마스킹(hermes_redact) 회귀 테스트
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$ROOT/scripts"
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
nope() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }

run() {
PYTHONPATH="$SCRIPTS" python3 - <<'PY'
import hermes_redact as r

def expect(name, text, must_have=None, must_not=None):
    out = r.redact(text)
    if must_have is not None and must_have not in out:
        print(f"FAIL::{name} (없음:{must_have})"); return
    if must_not is not None and must_not in out:
        print(f"FAIL::{name} (잔존:{must_not})"); return
    print(f"OK::{name}")

# --- 양성: 반드시 가려져야 함 ---
expect("email", "내 메일은 hong@example.com 이야",
       must_have="[REDACTED:EMAIL]", must_not="hong@example.com")
expect("phone", "연락처 010-1234-5678 로 줘",
       must_have="[REDACTED:PHONE]", must_not="1234-5678")
expect("github-pat", "키는 ghp_" + "a" * 36 + " 입니다",
       must_have="[REDACTED:TOKEN]")
expect("openai", "export OPENAI_API_KEY=sk-" + "A" * 40,
       must_have="[REDACTED:TOKEN]")
expect("aws-akia", "AWS AKIA" + "ABCDEFGHIJKLMNOP 노출",
       must_have="[REDACTED:TOKEN]")
expect("bearer", "Authorization: Bearer abcDEF123456._-tok",
       must_have="Bearer [REDACTED:TOKEN]")
expect("kv-password", "password: myP@ssw0rd",
       must_have="[REDACTED:SECRET]", must_not="myP@ssw0rd")
expect("kv-korean", "비밀번호는 mypw1234 야",
       must_have="[REDACTED:SECRET]", must_not="mypw1234")
expect("rrn", "주민번호 900101-1234567",
       must_have="[REDACTED:RRN]", must_not="1234567")
expect("card", "카드 1234-5678-9012-3456 결제",
       must_have="[REDACTED:CARD]", must_not="9012-3456")
expect("address", "집은 서울특별시 강남구 테헤란로 123 이야",
       must_have="[REDACTED:ADDRESS]", must_not="테헤란로 123")

# --- 음성: 일반 산문/코드는 보존(과마스킹 금지) ---
expect("neg-auth-prose", "auth middleware를 토큰 검증에 추가했다", must_not="[REDACTED")
expect("neg-account", "계정 생성 로직을 변경했다", must_not="[REDACTED")
expect("neg-pw-word", "비밀번호 변경 화면을 만들었다", must_not="[REDACTED")
expect("neg-empty", "", must_not="[REDACTED")
PY
}

OUT="$(run)"
while IFS= read -r line; do
  case "$line" in
    OK::*)   ok   "${line#OK::}" ;;
    FAIL::*) nope "${line#FAIL::}" ;;
  esac
done <<< "$OUT"

echo "redact: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
