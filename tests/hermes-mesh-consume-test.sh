#!/usr/bin/env bash
# 그물망 소비 측 — hermes-search 가 --global-skills-dir 를 검색 풀에 포함하는지
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$ROOT/scripts"
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
nope() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

MESH="$TMP/mesh/skills"
mkdir -p "$MESH"
cat > "$MESH/relay-pagination.md" <<'EOF'
# GraphQL relay 커서 페이지네이션
relay 커서 규약으로 페이지네이션을 구현한다.
EOF

# --db 는 없는 경로여도 dir-scan 은 독립 동작. --no-fallback 로 claude 회피.
OUT="$(python3 "$SCRIPTS/hermes-search.py" \
  --db "$TMP/nonexistent.db" --query "relay 커서 페이지네이션 구현" \
  --global-skills-dir "$MESH" --no-fallback --max 3 2>/dev/null || true)"
if grep -q "relay-pagination" <<<"$OUT"; then
  ok "그물망 스킬이 주입 결과에 포함됨"
else
  nope "그물망 스킬이 주입 결과에 없음"
fi

# 격리: --global-skills-dir 미지정 시 그물망 스킬은 안 나와야 한다.
OUT2="$(python3 "$SCRIPTS/hermes-search.py" \
  --db "$TMP/nonexistent.db" --query "relay 커서 페이지네이션 구현" \
  --no-fallback --max 3 2>/dev/null || true)"
if grep -q "relay-pagination" <<<"$OUT2"; then
  nope "격리 실패 — global dir 미지정인데 그물망 스킬 노출"
else
  ok "global dir 미지정 시 그물망 스킬 비노출(격리 OK)"
fi

# init --global 이 그물망 골격 디렉토리를 만드는지 (HOME 격리)
HOME="$TMP/fakehome" python3 "$SCRIPTS/hermes-init.py" --global >/dev/null 2>&1 || true
if [[ -d "$TMP/fakehome/.hermes/mesh/skills" ]]; then
  ok "init --global 이 ~/.hermes/mesh/skills 생성"
else
  nope "init --global 이 그물망 골격 디렉토리 미생성"
fi

# 주입 훅이 --global-skills-dir 를 전달하는지 (정적 확인) — 플래그명 + 실제 경로값까지 검증
HOOK="$ROOT/assets/hooks/claude-userpromptsubmit-reminders.sh"
if grep -q -- "--global-skills-dir" "$HOOK"; then
  ok "주입 훅이 --global-skills-dir 전달"
else
  nope "주입 훅이 --global-skills-dir 미전달"
fi
if grep -q -- '--global-skills-dir "\$HOME/.hermes/mesh/skills"' "$HOOK"; then
  ok "주입 훅이 \$HOME/.hermes/mesh/skills 경로를 전달"
else
  nope "주입 훅이 잘못된 경로를 전달(또는 경로 누락)"
fi

# 현실적 조건 — 프로젝트 state.db 에 skill_index 로컬 스킬 2개(중복매칭 유발) + 그물망 스킬 1개,
# --max 3 으로 호출해도 그물망 결과가 할당량에서 밀려나지 않아야 한다 (Finding 1).
PROJ="$TMP/proj"; mkdir -p "$PROJ/.hermes/skills"
PDB="$PROJ/.hermes/state.db"
python3 "$SCRIPTS/hermes-init.py" --project "$PROJ" >/dev/null 2>&1

# db 스캔과 dir 스캔이 동일 파일을 이중으로 매칭하도록 skill_index 에 실제 스킬 파일을 등록한다.
cat > "$PROJ/.hermes/skills/pagination-guide.md" <<'MD'
# pagination-guide
relay 커서 페이지네이션 가이드 문서.
cursor 기반으로 다음 페이지를 조회한다.
MD
cat > "$PROJ/.hermes/skills/cursor-guide.md" <<'MD'
# cursor-guide
relay 커서 구현 시 주의사항.
페이지네이션 cursor 값은 opaque 하게 다룬다.
MD
python3 - "$PDB" "$PROJ/.hermes/skills/pagination-guide.md" "$PROJ/.hermes/skills/cursor-guide.md" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.execute(
    "INSERT OR REPLACE INTO skill_index (skill_path,keywords,scope) VALUES (?,?,?)",
    (sys.argv[2], "relay,cursor,pagination", "local"),
)
con.execute(
    "INSERT OR REPLACE INTO skill_index (skill_path,keywords,scope) VALUES (?,?,?)",
    (sys.argv[3], "relay,cursor,pagination", "local"),
)
con.commit()
PY

SESS1="mesh-consume-test-session-1"
OUT3="$(python3 "$SCRIPTS/hermes-search.py" \
  --db "$PDB" --query "relay 커서 페이지네이션 구현" \
  --global-skills-dir "$MESH" --no-fallback --max 3 --session-id "$SESS1" 2>/dev/null || true)"

if grep -q "relay-pagination" <<<"$OUT3"; then
  ok "현실적 조건: 로컬 skill_index 매칭이 있어도 그물망 스킬이 노출됨(할당량 미굶주림)"
else
  nope "현실적 조건: 그물망 스킬이 할당량에서 밀려남(Finding 1 재현)"
fi

# Finding E — 그물망 예약 슬롯이 생겼다고 로컬 스킬이 굶주리지 않았는지도 확인한다.
if grep -q "pagination-guide" <<<"$OUT3"; then
  ok "현실적 조건: 로컬 스킬(pagination-guide)도 함께 노출됨(로컬 굶주림 없음)"
else
  nope "현실적 조건: 로컬 스킬(pagination-guide)이 노출되지 않음(로컬 굶주림)"
fi

# 동일 스킬의 중복 출력 검사 — 라벨이 아니라 스킬별 고유 본문 줄로 카운트한다.
# (라벨 패턴은 dir-scan 라벨에 .md 접미사가 없어 절대 매칭되지 않는 검증 무효 문제가 있었다.)
for _line in "cursor 기반으로 다음 페이지를 조회한다." "페이지네이션 cursor 값은 opaque 하게 다룬다."; do
  _n="$(grep -cF "$_line" <<<"$OUT3" || true)"
  if [[ "$_n" -le 1 ]]; then
    ok "동일 스킬 중복 출력 없음: ${_line:0:12}… (count=$_n)"
  else
    nope "동일 스킬 중복 출력됨: ${_line:0:12}… (count=$_n)"
  fi
done

# Finding D — 실제로 프롬프트에 찍힌 스킬 개수와 skill_injection 원장 행 수,
# used_count 증가분이 서로 일치하는지 검증한다(할당량 예약/중복제거 이후 상태 기준).
PRINTED_COUNT="$(python3 - "$OUT3" <<'PY'
import sys
out = sys.argv[1]
print(out.count("[헤르메스 규칙"))
PY
)"
LEDGER_COUNT="$(python3 - "$PDB" "$SESS1" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
n = con.execute(
    "SELECT COUNT(*) FROM skill_injection WHERE session_id=?", (sys.argv[2],)
).fetchone()[0]
con.close()
print(n)
PY
)"
if [[ "$LEDGER_COUNT" == "$PRINTED_COUNT" ]]; then
  ok "원장(skill_injection) 행 수가 실제 출력 스킬 수와 일치함(printed=$PRINTED_COUNT, ledger=$LEDGER_COUNT)"
else
  nope "원장 행 수가 출력 스킬 수와 불일치(printed=$PRINTED_COUNT, ledger=$LEDGER_COUNT)"
fi

# max=1 로 강제 절단하여, 절단으로 탈락한 스킬은 used_count 가 오르지 않는지 확인한다.
USED_BEFORE_PAG="$(python3 - "$PDB" "$PROJ/.hermes/skills/pagination-guide.md" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
print(con.execute("SELECT used_count FROM skill_index WHERE skill_path=?", (sys.argv[2],)).fetchone()[0])
con.close()
PY
)"
USED_BEFORE_CUR="$(python3 - "$PDB" "$PROJ/.hermes/skills/cursor-guide.md" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
print(con.execute("SELECT used_count FROM skill_index WHERE skill_path=?", (sys.argv[2],)).fetchone()[0])
con.close()
PY
)"

SESS2="mesh-consume-test-session-2"
OUT4="$(python3 "$SCRIPTS/hermes-search.py" \
  --db "$PDB" --query "relay 커서 페이지네이션 구현" \
  --global-skills-dir "$MESH" --no-fallback --max 1 --session-id "$SESS2" 2>/dev/null || true)"

LEDGER_COUNT2="$(python3 - "$PDB" "$SESS2" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
n = con.execute(
    "SELECT COUNT(*) FROM skill_injection WHERE session_id=?", (sys.argv[2],)
).fetchone()[0]
con.close()
print(n)
PY
)"
if [[ "$LEDGER_COUNT2" == "1" ]]; then
  ok "max=1 절단 시 원장 행이 실제 출력(1개)과 일치함(ledger=$LEDGER_COUNT2)"
else
  nope "max=1 절단 시 원장 행 수가 출력과 불일치(ledger=$LEDGER_COUNT2, 기대=1)"
fi

USED_AFTER_PAG="$(python3 - "$PDB" "$PROJ/.hermes/skills/pagination-guide.md" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
print(con.execute("SELECT used_count FROM skill_index WHERE skill_path=?", (sys.argv[2],)).fetchone()[0])
con.close()
PY
)"
USED_AFTER_CUR="$(python3 - "$PDB" "$PROJ/.hermes/skills/cursor-guide.md" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
print(con.execute("SELECT used_count FROM skill_index WHERE skill_path=?", (sys.argv[2],)).fetchone()[0])
con.close()
PY
)"

DELTA_PAG=$((USED_AFTER_PAG - USED_BEFORE_PAG))
DELTA_CUR=$((USED_AFTER_CUR - USED_BEFORE_CUR))
DELTA_SUM=$((DELTA_PAG + DELTA_CUR))
if grep -q "pagination-guide" <<<"$OUT4"; then
  EXPECTED_PRINTED="pagination-guide"
else
  EXPECTED_PRINTED="cursor-guide"
fi
if [[ "$DELTA_SUM" == "1" ]]; then
  ok "max=1 절단: 실제 출력된 db 매칭 스킬($EXPECTED_PRINTED)만 used_count 증가(delta 합=$DELTA_SUM)"
else
  nope "max=1 절단: used_count 증가분이 출력 스킬 수와 불일치(delta 합=$DELTA_SUM, 기대=1) — pag=$DELTA_PAG cur=$DELTA_CUR"
fi

# 지원 훅이 --global-skills-dir 를 전달하는지 (정적 확인) — 플래그명 + 실제 경로값까지 검증
ASSIST_HOOK="$ROOT/assets/hooks/claude-posttooluse-hermes-assist.sh"
if grep -q -- "--global-skills-dir" "$ASSIST_HOOK"; then
  ok "지원 훅이 --global-skills-dir 전달"
else
  nope "지원 훅이 --global-skills-dir 미전달"
fi
if grep -q -- '--global-skills-dir "\$HOME/.hermes/mesh/skills"' "$ASSIST_HOOK"; then
  ok "지원 훅이 \$HOME/.hermes/mesh/skills 경로를 전달"
else
  nope "지원 훅이 잘못된 경로를 전달(또는 경로 누락)"
fi

echo ""
echo "  결과: $PASS 통과 / $FAIL 실패"
[[ $FAIL -eq 0 ]]
