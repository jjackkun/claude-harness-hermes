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

OUT3="$(python3 "$SCRIPTS/hermes-search.py" \
  --db "$PDB" --query "relay 커서 페이지네이션 구현" \
  --global-skills-dir "$MESH" --no-fallback --max 3 2>/dev/null || true)"

if grep -q "relay-pagination" <<<"$OUT3"; then
  ok "현실적 조건: 로컬 skill_index 매칭이 있어도 그물망 스킬이 노출됨(할당량 미굶주림)"
else
  nope "현실적 조건: 그물망 스킬이 할당량에서 밀려남(Finding 1 재현)"
fi

DUP_COUNT="$(grep -c "헤르메스 규칙.*pagination-guide.md" <<<"$OUT3" || true)"
if [[ "$DUP_COUNT" -le 1 ]]; then
  ok "동일 스킬이 중복 출력되지 않음(db-scan/dir-scan 중복 제거)"
else
  nope "동일 스킬이 중복 출력됨(중복 제거 실패, count=$DUP_COUNT)"
fi

echo ""
echo "  결과: $PASS 통과 / $FAIL 실패"
[[ $FAIL -eq 0 ]]
