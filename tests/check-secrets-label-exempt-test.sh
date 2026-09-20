#!/usr/bin/env bash
# check-secrets 라벨 규칙(CREDENTIAL · ENV_SECRET) 면제 표 (계획 2026-09-20-check-secrets-false-positives).
#
# 왜: 면제를 넓히는 변경은 탐지력을 조용히 깎는다. 통과해야 하는 줄(오탐이었던 것)과 **계속 걸려야 하는 줄**(진짜 비밀)을
#     한 표에 고정한다. 새 면제를 넣는 사람은 이 표의 "걸림" 줄이 하나라도 통과로 바뀌면 멈춰야 한다.
#   - ENV 절: $변수 참조 · 코드 파일의 호출·첨자·환경 루트 · 정규식 리터럴은 통과 / 기본값에 박은 비밀 · 비코드 파일의 같은 모양은 걸림
#   - KV 절: 코드 파일의 식별자 참조 · 키 이름 상수 · 비ASCII 꼬리 더미는 통과 / 숫자 든 맨 낱말 · YAML 의 따옴표 없는 값 · 비밀 접미 상수는 걸림
#   - 자기 검사: 면제 함수를 "항상 면제" 로 바꾸면 감도 줄이 빨개진다
#
# 실행: bash tests/check-secrets-label-exempt-test.sh

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CS="$ROOT/assets/hooks/check-secrets.py"
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
nope() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }

# table <검사기 경로> → "불일치 목록"(없으면 빈 줄). 각 사례: (기대 걸림?, 경로, 줄, 설명)
table() {
  python3 - "$1" <<'PYEOF'
import importlib.util, sys
s = importlib.util.spec_from_file_location("cs", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
HIT, MISS = True, False
CASES = [
 # ── ENV_SECRET: 통과해야 하는 것(2026-09-20 실제 오탐) ─────────────────────────
 (MISS, "src/config.py", 'API_KEY = os.environ.get("API_KEY", "")', "env 에서 읽는 올바른 코드"),
 (MISS, "src/config.py", 'JWT_SECRET = os.environ["JWT_SECRET"]', "env 첨자"),
 (MISS, "src/app.ts", 'const API_TOKEN = process.env.API_TOKEN', "process.env"),
 (MISS, "src/config.py", 'SECRET_KEY = get_secret("app")', "비밀 저장소 호출"),
 (MISS, "hooks/guard.py", 'TARGET_TOKEN = r"[\\x27\\"]?([^\\s\\x27\\";|&<>]*\\.hermes/agents\\.json)"', "정규식 상수"),
 (MISS, "hooks/guard.py", 'SESSION_TOKEN = re.compile(r"^tok_[a-z]+(?:-\\d+)?$")', "컴파일된 정규식"),
 (MISS, ".gitlab-ci.yml", 'DEPLOY_TOKEN=$CI_DEPLOY_TOKEN', "CI 변수 참조(비코드 파일)"),
 (MISS, "deploy.sh", 'DB_PASSWORD="$PROD_DB_PASSWORD"', "따옴표 안 변수 참조"),
 # ── ENV_SECRET: 계속 걸려야 하는 것 ───────────────────────────────────────────
 (HIT, "src/config.py", 'DB_PASSWORD = "Xk9#mQ2$vL7pRw4z"', "코드 안 따옴표 리터럴"),
 (HIT, "src/config.py", 'API_KEY = os.environ.get("API_KEY", "prod-7f3a9c2e1b8d4f60")', "기본값에 박은 비밀"),
 (HIT, ".env.sample", 'JWT_SECRET=4f9a8b7c6d5e4f3a2b1c0d9e8f7a6b5c', ".env 실값"),
 (HIT, ".env", 'DB_PASSWORD=pa(ss)w0rd-real', "비코드 파일의 괄호 든 값은 호출이 아니다"),
 (HIT, "config.yaml", 'API_KEY=get_secret("app")', "비코드 파일에서는 호출 모양도 면제 없음"),
 (HIT, "src/config.py", 'ADMIN_PASSWORD = "plain-regex-free-r4w"', "r 로 시작하지 않는 평범한 리터럴"),
 # ── CREDENTIAL: 통과해야 하는 것(하류판 2026-08-22 실제 오탐) ─────────────────
 (MISS, "src/auth.py", 'login(password=body.password)', "식별자 참조 — 점 경로"),
 (MISS, "src/auth.ts", 'const token = refreshToken;', "식별자 참조 — 숫자 없는 맨 낱말"),
 (MISS, "src/keys.py", 'LLM_API_KEY = "llm_api_key"', "키 이름 상수"),
 (MISS, "tests/test_auth.py", 'token = "access-값"', "비ASCII 꼬리 시험 더미"),
 # ── CREDENTIAL: 계속 걸려야 하는 것 ───────────────────────────────────────────
 (HIT, "src/auth.py", 'password = "Hunter2xyz!"', "따옴표 리터럴"),
 (HIT, "src/auth.py", 'password = Hunter2Password9', "숫자 든 맨 낱말 — 가장 흔한 토큰 모양"),
 (HIT, "src/auth.py", 'password = Hunter2!xyz', "문장부호가 남는 값"),
 (HIT, "config.yaml", 'password: hunter2abc', "YAML 의 따옴표 없는 값은 진짜다"),
 (HIT, "src/keys.py", 'ADMIN_PASSWORD = "admin_password"', "비밀 접미 이름은 키 이름 상수로 면제하지 않는다"),
 (HIT, "src/keys.py", 'API_KEY = "api_key" + "sk-live-9f8e7d6c5b4a39281706"', "이름 뒤에 진짜가 붙은 줄"),
 (HIT, "src/app.py", 'api_key = "sk-live-9f8e7d6c5b4a39281706"', "키 모양(SHAPE)"),
]
bad = []
for expect, path, line, why in CASES:
    got = bool(m.scan(path, line + "\n", {}))
    if got != expect:
        bad.append(f"{'걸려야 하는데 통과' if expect else '통과해야 하는데 걸림'}: [{why}] {path}: {line[:70]}")
print(len(CASES)); print("\n".join(bad))
PYEOF
}

echo "== 면제 표 (ENV · KV · 감도)"
OUT="$(table "$CS")"; N="$(sed -n 1p <<<"$OUT")"; BAD="$(sed -n '2,$p' <<<"$OUT" | sed '/^$/d')"
[[ "${N:-0}" -ge 24 ]] && ok "사례 ${N}개를 검사했다" || nope "사례 수가 모자란다: ${N:-0}"
if [[ -z "$BAD" ]]; then ok "표 전체 일치(통과해야 할 12 · 걸려야 할 13)"; else nope "표 불일치"; sed 's/^/     /' <<<"$BAD"; fi

echo "== 자기 검사 — 면제를 '항상 면제' 로 바꾸면 감도 줄이 빨개진다"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
sed 's/^def _env_exempt(.*$/&\n    return True/; s/^def _kv_exempt(.*$/&\n    return True/' "$CS" > "$T/cs-broken.py"
BAD2="$(table "$T/cs-broken.py" | sed -n '2,$p' | grep -c '걸려야 하는데 통과')"
[[ "$BAD2" -ge 5 ]] && ok "면제를 무력화하면 '걸려야 하는데 통과' 가 ${BAD2}건 나온다(표가 감도를 지킨다)" || nope "자기 검사가 아무것도 못 잡는다(${BAD2}건)"

echo "== 기존 회귀"
for t in check-secrets-code-expr-test check-secrets-answerkey-test; do
  if bash "$ROOT/tests/$t.sh" >/dev/null 2>&1; then ok "$t 통과"; else nope "$t 실패"; fi
done

echo; echo "  PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
