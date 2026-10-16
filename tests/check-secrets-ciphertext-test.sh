#!/usr/bin/env bash
# check-secrets dotenvx 암호문 면제 회귀 테스트.
#
# 근거: 하류 jj-agent-room docs/exec-plans/active/2026-10-15-env-secrets-sync.md §7
#   (2026-10-16 실측: dotenvx 로 암호화한 .env.secrets 를 스테이징하면 `NAME_SECRET=encrypted:B…`
#    줄이 CREDENTIAL·ENV_SECRET 로 잡혀 rc=2. 암호문 형식은 바꿀 수 없다.)
#
# 왜 이 시험이 필요한가: 면제를 더하면 탐지력이 조용히 깎일 수 있다. 면제는 dotenvx 암호문
#   모양(`encrypted:` + 'B' + base64 120자 이상, 실측 최소 132자)과 **겹치는 구간만** 풀어야 한다.
#   `encrypted:` 딱지만 붙인 짧은 평문, 같은 줄의 다른 비밀은 계속 잡혀야 한다.
#   비밀처럼 보이는 값은 실행 때 만든다 — 이 파일 자체가 게이트에 걸리지 않게.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
nope() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }

run() {
CHECKER="$ROOT/assets/hooks/check-secrets.py" python3 - <<'PY'
import base64, importlib.util, os, secrets
spec = importlib.util.spec_from_file_location("cs", os.environ["CHECKER"])
cs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cs)

def sealed(nbytes=98):
    # ECIES 임시 공개키(0x04…)로 시작하는 dotenvx 암호문 모양 — base64 첫 글자가 'B'.
    return "encrypted:" + base64.b64encode(b"\x04" + secrets.token_bytes(nbytes)).decode()

plain = "Hu" + secrets.token_hex(6)
llm = "sk-" + secrets.token_hex(16)
CASES = [
    # 통과해야 한다 — dotenvx 암호문
    ("ENV 이름 + 암호문", f"GOOGLE_CLIENT_SECRET={sealed()}", False),
    ("따옴표 + 암호문", f'OPENAI_API_KEY="{sealed()}"', False),
    ("긴 값의 암호문", f"NEW_TOKEN={sealed(160)}", False),
    # 잡아야 한다
    ("딱지만 붙인 짧은 평문", f"PASSWORD=encrypted:{plain}", True),
    ("'B' 로 시작해도 짧은 값", f"API_KEY=encrypted:B{secrets.token_hex(20)}", True),
    ("같은 줄의 다른 비밀", f'password="{plain}" note={sealed()}', True),
    ("암호화 안 된 LLM 키", f"OPENAI_API_KEY={llm}", True),
]

bad = []
for name, line, should_hit in CASES:
    hit = bool(cs.scan(".env.secrets", line, {}))
    if hit != should_hit:
        bad.append("%s: %s 여야 하는데 %s" % (
            name, "탐지" if should_hit else "통과", "탐지" if hit else "통과"))
print("FAIL " + " / ".join(bad) if bad else "OK %d/%d" % (len(CASES), len(CASES)))
PY
}

out="$(run 2>&1)"
if [[ "$out" == OK* ]]; then
  ok "dotenvx 암호문 — 셋은 통과, 넷은 잡는다 ($out)"
else
  nope "dotenvx 암호문 면제"; echo "     $out"
fi

echo
echo "  PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
