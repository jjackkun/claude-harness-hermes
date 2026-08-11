#!/usr/bin/env bash
# 세션 기록 비밀 마스킹 회귀 테스트 — 네 겹이 순서대로 뚫린 결함을 고정한다.
#
# 왜 이 테스트가 필요한가:
#   2026-08-10, 소비 프로젝트의 .hermes/history/*.jsonl 에 외부 계정 평문 자격증명이
#   실린 채 커밋·푸시까지 갔다. redact() 는 호출되고 있었지만 사람이 실제로 주는
#   형태(`아이디 | 비번`)를 못 잡았고, export 경계엔 마스킹이 없었고, 커밋 경계엔
#   스캐너가 없었고, 스캐너의 자리표시자 면제는 줄 단위라 긴 줄에서 무너졌다.
#   각 겹을 개별로 단언해야 한 겹이 되돌아가도 즉시 드러난다.
#
#   ⚠️ 이 파일에는 **가짜 값만 넣는다.** 진짜를 닮아야 규칙을 검사할 수 있으므로
#   check-secrets.py 의 EXCLUDE_RE 가 이 파일을 면제한다 — 면제된 구역이다.
#   근거: docs/superpowers/specs/2026-08-10-hermes-secret-masking-design.md
#
# 실행: bash tests/hermes-secret-masking-test.sh
# 종료 코드: 0 = 모든 단언 통과, 1 = 실패

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$ROOT/scripts"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
nope() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }
assert() { # assert <설명> <기대> <실제>
  if [[ "$2" == "$3" ]]; then ok "$1"; else nope "$1 (expected=$2 actual=$3)"; fi
}
report() { # OK::/FAIL:: 마커 스트림을 집계
  while IFS= read -r line; do
    case "$line" in
      OK::*)   ok   "${line#OK::}" ;;
      FAIL::*) nope "${line#FAIL::}" ;;
    esac
  done <<< "$1"
}

PROJ="$TMP/proj"
mkdir -p "$PROJ/.hermes/history"

# 정답지. 관측된 결함의 실제 형태를 가짜 값으로 재현한다.
cat > "$PROJ/.env" <<'ENVFILE'
# 주석은 무시된다
LDSP_USER=fakeuser
LDSP_PASSWORD=!Fakepw11aa
UNIPASSAPIKEY=Fakepw11aa
CRKY_CN=FAKE01
CRKY_PW="QWER1234*"
SHORT=ab
PLACEHOLDER_KEY=changeme
APP_BASE_URL=http://localhost:4101
PORT=4101
NODE_ENV=development
DATABASE_URL=postgresql://fakeuser:!Fakepw11aa@localhost:5432/db
ENVFILE

echo "== 1. hermes_secret_values — 정답지 추출 =="
OUT=$(cd "$PROJ" && PYTHONPATH="$SCRIPTS" python3 - <<'PY'
import os
import hermes_secret_values as sv

vals = sv.load_secret_values(os.getcwd())
def expect(name, cond):
    print(("OK::" if cond else "FAIL::") + name)

expect("일반 값을 정답지에 담는다", vals.get("LDSP_USER") == "fakeuser")
expect("특수문자로 시작하는 값도 담는다", vals.get("LDSP_PASSWORD") == "!Fakepw11aa")
expect("따옴표를 벗긴다", vals.get("CRKY_PW") == "QWER1234*")
expect("4자 미만 값은 제외한다 (과마스킹 방지)", "SHORT" not in vals)
expect("자리표시자는 제외한다", "PLACEHOLDER_KEY" not in vals)

# ★.env 는 비밀만 담지 않는다 — 설정값을 가리면 문서·로그가 깨진다.
# 실제로 APP_BASE_URL 때문에 정상 문서의 curl 예시가 마스킹돼 커밋이 막혔다.
expect("자격증명 없는 URL 은 제외 (주소일 뿐)", "APP_BASE_URL" not in vals)
expect("순수 숫자(포트)는 제외", "PORT" not in vals)
expect("실행 모드 리터럴은 제외", "NODE_ENV" not in vals)
expect("URL 에 비밀번호가 박히면 마스킹 대상", "DATABASE_URL" in vals)
PY
)
report "$OUT"

echo ""
echo "== 1b. \$HOME 에 포함된 값은 정답지에서 뺀다 =="
# 실제 사례: 계정 ID 가 홈 디렉터리명과 같아, 치환하면 /home/<id>/... 경로가 다 깨진다.
OUT=$(PYTHONPATH="$SCRIPTS" python3 - <<'PY'
import hermes_secret_values as sv

home = "/home/fakeuser"
vals = sv.parse_env_text("LDSP_USER=fakeuser\nOTHER=Fakepw11aa\n", home)
def expect(name, cond):
    print(("OK::" if cond else "FAIL::") + name)

expect("$HOME 에 포함된 값은 제외 (경로 파괴 방지)", "LDSP_USER" not in vals)
expect("무관한 값은 그대로 유지", vals.get("OTHER") == "Fakepw11aa")
PY
)
report "$OUT"

echo ""
echo "== 1c. 정답지 모듈은 값을 출력하지 않는다 =="
STDOUT_LEAK=$(cd "$PROJ" && PYTHONPATH="$SCRIPTS" python3 -c \
  "import os, hermes_secret_values as sv; sv.load_secret_values(os.getcwd())" 2>&1)
echo "$STDOUT_LEAK" | grep -q 'Fakepw11aa'
assert "로드만으로 값이 새어나오지 않음" "1" "$?"

echo ""
echo "== 2. redact — 관측된 7가지 입력 형태 =="
OUT=$(cd "$PROJ" && PYTHONPATH="$SCRIPTS" python3 - <<'PY'
import os
import hermes_redact as r

root = os.getcwd()
def expect(name, text, must_not=None, must_have=None):
    out = r.redact(text, root)
    if must_not is not None and must_not in out:
        print(f"FAIL::{name} (원문 잔존)"); return
    if must_have is not None and must_have not in out:
        print(f"FAIL::{name} (마스킹 토큰 없음)"); return
    print(f"OK::{name}")

# --- 이미 막히던 4가지 (회귀 방지) ---
expect("1 라벨=값", "password=Fakepw11aa",
       must_not="Fakepw11aa", must_have="[REDACTED")
expect("2 한글 라벨", "비밀번호: Fakepw11aa",
       must_not="Fakepw11aa", must_have="[REDACTED")
expect("3 공급자 접두 토큰", "sk-" + "A" * 40, must_have="[REDACTED:TOKEN]")
expect("4 휴대전화", "연락처 010-1234-5678", must_have="[REDACTED:PHONE]")

# --- 통과하던 3가지 (이번에 막는 것) ---
expect("5 딱지 없는 아이디|비번 (값 기반)", "fakeuser | !Fakepw11aa",
       must_not="!Fakepw11aa", must_have="[REDACTED:ENV:LDSP_PASSWORD]")
expect("6 URL 아래 줄바꿈 나열 (값 기반)",
       "https://example.com/login\nFAKE01\nQWER1234*",
       must_not="QWER1234*", must_have="[REDACTED:ENV:CRKY_PW]")
expect("7 라벨 접두어 (\\b 구멍)", "SOME_PASSWORD=Fakepw11aa",
       must_not="Fakepw11aa", must_have="[REDACTED")

# --- 음성: 과마스킹 금지 ---
expect("neg 한글 산문 보존", "비밀번호 변경 화면을 만들었다", must_not="[REDACTED")
expect("neg 짧은 값은 산문을 깨지 않음", "ab 로 시작하는 단어", must_not="[REDACTED")
expect("neg 설정 URL 이 든 문서는 안 깨진다",
       "curl -s http://localhost:4101/src/routes/X.svelte 로 확인", must_not="[REDACTED")

# --- 멱등: 두 번 돌려도 같은 결과 ---
once = r.redact("fakeuser | !Fakepw11aa", root)
print(("OK::" if r.redact(once, root) == once else "FAIL::") + "멱등 (재적용해도 불변)")
PY
)
report "$OUT"

echo ""
echo "== 2b. 정답지 기준 경로 — cwd 가 달라도 .env 를 찾는다 =="
# 하위 디렉터리에서 세션을 시작하면 cwd 폴백으로는 .env 를 못 찾는다.
# 그러면 값 기반 마스킹이 **조용히** 무력화되고 형태 규칙만 남는다.
mkdir -p "$PROJ/sub/deeper"
OUT=$(cd "$PROJ/sub/deeper" && CLAUDE_PROJECT_DIR="$PROJ" PYTHONPATH="$SCRIPTS" python3 - <<'PY'
import hermes_redact as r
out = r.redact("fakeuser | !Fakepw11aa")      # project_dir 생략 → 환경변수로 해결
print(("OK::" if "!Fakepw11aa" not in out else "FAIL::")
      + "CLAUDE_PROJECT_DIR 로 하위 디렉터리에서도 마스킹")
PY
)
report "$OUT"

# Stop 훅이 그 환경변수를 setsid 하위 셸로 넘기는지 — 안 넘기면 위 경로가 죽는다.
grep -q 'CLAUDE_PROJECT_DIR="\$project_dir"' "$ROOT/assets/hooks/claude-stop-retrospective.sh"
assert "Stop 훅이 CLAUDE_PROJECT_DIR 을 백그라운드로 전달" "0" "$?"

echo ""
echo "== 3. export 경계 — DB 가 오염돼도 파일은 깨끗하다 =="
DB="$PROJ/.hermes/state.db"
python3 - "$DB" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.execute("CREATE TABLE session_history (content TEXT, role TEXT, timestamp TEXT, "
            "project_id TEXT, session_id TEXT)")
# ★DB 적재 경계를 우회해 심는다 — 1번 겹이 뚫린 상황의 재현이다.
con.execute("INSERT INTO session_history VALUES (?,?,?,?,?)",
            ("계정은 fakeuser | !Fakepw11aa 입니다", "user",
             "2026-08-10T10:00:00", "proj", "sess1"))
con.commit(); con.close()
PY
(cd "$PROJ" && python3 "$SCRIPTS/hermes-export-history.py" \
  --db "$DB" --project "$PROJ" --session sess1 >/dev/null 2>&1)
JSONL=$(cat "$PROJ"/.hermes/history/*-sess1.jsonl 2>/dev/null)
echo "$JSONL" | grep -q 'Fakepw11aa'
assert "export 된 파일에 원문 없음 (다층 방어)" "1" "$?"
echo "$JSONL" | grep -q 'REDACTED'
assert "마스킹 토큰이 기록됨" "0" "$?"

echo ""
echo "== 4. check-secrets — 커밋 경계 차단 =="
SCAN="$ROOT/assets/hooks/check-secrets.py"
mkdir -p "$PROJ/scripts"
cp "$SCRIPTS/hermes_secret_values.py" "$PROJ/scripts/"
# 실제 pre-commit 경로와 같게 **스테이징된 파일**을 검사한다.
(cd "$PROJ" && git init -q \
  && git config user.email "harness-test@example.com" \
  && git config user.name "harness-test") >/dev/null 2>&1

stage_only() { # stage_only <파일명> — 그 파일만 스테이징한 상태로 만든다
  (cd "$PROJ" && git reset -q && git add -f "$1")
}

# 4a. 자리표시자와 진짜 비밀이 같은 줄에 있어도 탐지한다 (구멍 5)
printf 'see the example config and password="Hunter2xyz!"\n' > "$PROJ/mixed.txt"
stage_only mixed.txt
OUT=$(cd "$PROJ" && python3 "$SCAN" 2>&1); RC=$?
assert "example 이 같은 줄에 있어도 차단 (줄 단위 면제 제거)" "2" "$RC"
echo "$OUT" | grep -q 'CREDENTIAL'
assert "차단 사유가 보고됨" "0" "$?"
rm -f "$PROJ/mixed.txt"

# 4b. 딱지 없는 .env 실재 값도 차단한다 (값 기반)
printf 'fakeuser | !Fakepw11aa\n' > "$PROJ/leak.txt"
stage_only leak.txt
OUT=$(cd "$PROJ" && python3 "$SCAN" 2>&1); RC=$?
assert "딱지 없는 평문 자격증명 차단" "2" "$RC"
echo "$OUT" | grep -q 'ENV_VALUE'
assert "값 기반 규칙으로 보고됨" "0" "$?"
echo "$OUT" | grep -q 'Fakepw11aa'
assert "차단 메시지에 값 자체는 찍지 않음" "1" "$?"
rm -f "$PROJ/leak.txt"

# 4c. 자리표시자·코드 식은 통과한다 (오탐 방지)
# 오탐이 남으면 사람이 --no-verify 로 도망가고 규율 전체가 무력해진다 — 차단기는
# "가짜를 안 잡는 것"이 아니라 "진짜를 잡는 것"으로 평가하되 오탐은 0 이어야 한다.
cat > "$PROJ/safe.txt" <<'SAFE'
API_KEY=your-api-key-here
token = os.environ["TOKEN"]
apiKey = process.env.OPENAI_KEY
const auth = req.headers.authorization
function login(password: string) {}
PRIVATE-TOKEN: $GITLAB_API_TOKEN
SAFE
stage_only safe.txt
(cd "$PROJ" && python3 "$SCAN" >/dev/null 2>&1)
assert "자리표시자·코드 식·타입 표기는 통과 (오탐 방지)" "0" "$?"
rm -f "$PROJ/safe.txt"

# 4d. 오탐 억제가 진짜 비밀을 놓치는 구멍이 되지 않는다
# 점(.)이 든 값을 일반 '점 경로'로 면제하면 `Hunter2.xyz` 같은 비밀번호가 빠져나간다.
printf 'password = "Hunter2.xyz.abc"\n' > "$PROJ/dotted.txt"
stage_only dotted.txt
(cd "$PROJ" && python3 "$SCAN" >/dev/null 2>&1)
assert "점이 든 비밀번호는 코드 식으로 오인되지 않음" "2" "$?"
rm -f "$PROJ/dotted.txt"
(cd "$PROJ" && git reset -q)

echo ""
echo "== 5. 소급 정리 — 멱등하고, 값을 출력하지 않는다 =="
# export 로 만들어진 깨끗한 파일 대신, 오염된 파일을 직접 심는다.
cat > "$PROJ/.hermes/history/2026-08-10-sess2.jsonl" <<'JSONL'
{"seq": 0, "session_id": "sess2", "role": "user", "content": "fakeuser | !Fakepw11aa", "compacted": true}
JSONL
OUT=$(python3 "$SCRIPTS/hermes-scrub-history.py" --db "$DB" --project "$PROJ" 2>&1)
grep -q 'Fakepw11aa' "$PROJ/.hermes/history/2026-08-10-sess2.jsonl"
assert "dry-run 이 기본 — 파일을 고치지 않음" "0" "$?"
echo "$OUT" | grep -q 'Fakepw11aa'
assert "리포트에 값을 찍지 않음" "1" "$?"

python3 "$SCRIPTS/hermes-scrub-history.py" --db "$DB" --project "$PROJ" --apply >/dev/null 2>&1
grep -q 'Fakepw11aa' "$PROJ/.hermes/history/2026-08-10-sess2.jsonl"
assert "--apply 후 원문 제거됨" "1" "$?"
grep -q '"compacted": true' "$PROJ/.hermes/history/2026-08-10-sess2.jsonl"
assert "compacted 마커 보존 (export 가드 무력화 방지)" "0" "$?"

OUT=$(python3 "$SCRIPTS/hermes-scrub-history.py" --db "$DB" --project "$PROJ" 2>&1)
echo "$OUT" | grep -q '0줄 / 0파일'
assert "멱등 — 재실행 시 변경 0건" "0" "$?"

echo ""
echo "secret-masking: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
