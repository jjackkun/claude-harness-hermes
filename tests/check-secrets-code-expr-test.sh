#!/usr/bin/env bash
# check-secrets CODE_EXPR_RE 면제 회귀 테스트.
#
# 근거: docs/superpowers/specs/2026-08-21-check-secrets-code-expr-gap.md
#
# 왜 이 시험이 필요한가: 면제를 넓히는 변경은 탐지력을 조용히 깎을 수 있다.
#   실제로 (?-i:) 없이 넣었을 때 정규식 전체의 (?i) 때문에 [A-Z] 가 소문자까지
#   잡아, 따옴표 없이 적힌 진짜 비밀번호가 통과했다. 표로 재보고 나서야 발견했다.
#   면제 규칙을 건드리는 사람이 같은 함정에 빠지지 않도록 여덟 경우를 고정한다.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
nope() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }

run() {
CHECKER="$ROOT/assets/hooks/check-secrets.py" python3 - <<'PY'
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("cs", os.environ["CHECKER"])
cs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cs)

# (이름, 줄, 잡아야 하는가)
CASES = [
    # 잡아야 한다 — 값 자리가 리터럴이다
    ("따옴표 있는 하드코딩", 'password="Hunter2xyz"', True),
    ("따옴표 없는 비밀", 'password = Hunter2xyz', True),
    ("API 키", 'api_key=AbCd1234EfGh5678', True),
    ("대문자 시작 혼합", 'password=Hunter2Xyz', True),
    # 통과해야 한다 — 값 자리가 식별자·코드 식이다
    ("상수 참조", 'await login(conn, secret, email=email, password=PASSWORD)', False),
    ("변수 참조", 'issue(user_id=row.id, token=refresh_plain)', False),
    ("호출식", 'token = _CSRF_META.search(page)', False),
    ("타입 표기", 'function f(password: string) {}', False),
]

bad = []
for name, line, should_hit in CASES:
    hit = bool(cs.scan("sample.py", line, {}))
    if hit != should_hit:
        bad.append("%s: %s 여야 하는데 %s" % (
            name, "탐지" if should_hit else "통과", "탐지" if hit else "통과"))
print("FAIL " + " / ".join(bad) if bad else "OK 8/8")
PY
}

out="$(run 2>&1)"
if [[ "$out" == OK* ]]; then
  ok "면제 여덟 경우 — 넷은 잡고 넷은 통과한다 ($out)"
else
  nope "면제 여덟 경우"; echo "     $out"
fi

echo
echo "  PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
