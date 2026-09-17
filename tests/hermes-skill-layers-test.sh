#!/usr/bin/env bash
# 스킬 4층 스키마·저장 경로·색인 (계획 docs/exec-plans/active/2026-09-15-skill-layers-delivery.md 목표 1·2).
#
#   - skill_index 에 층 칸 5개(universe_id·layer·unit_id·agent_id·skill_id)가 붙고,
#     기존 행은 layer='common'·나머지 NULL 로 백필된다(행 수 불변)
#   - 층별 저장 경로가 코드로 고정된다(universe/common/unit/agent)
#   - 색인기가 네 자리를 모두 훑어 층·소유·skill_id 를 채운다
#   - skill_id 는 재색인해도 보존된다(신원 불변)
#   - 층 칸이 없는 구 DB 에서 마이그레이션이 죽지 않고 칸을 만든다(목표 16)
#
# 실행: bash tests/hermes-skill-layers-test.sh

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

q() { python3 -c "import sqlite3,sys;print(sqlite3.connect(sys.argv[1]).execute(sys.argv[2]).fetchone()[0])" "$1" "$2" 2>/dev/null || echo err; }

# ── 픽스처 소우주 ──────────────────────────────────────────────────────────
P="$TMP/proj"; mkdir -p "$P"
PYTHONPATH="$S" python3 -c "from hermes_universe import ensure_universe_id as e; e('$P')"
python3 "$S/hermes-init.py" --project "$P" >/dev/null 2>&1
DB="$P/.hermes/state.db"
UID_VAL="$(cat "$P/.hermes/universe.id")"

echo "== 1. 마이그레이션: 기존 행 백필 (목표 1) =="
# 층 칸이 없던 것처럼 기존 'common' 스킬 3행을 심는다(구 스키마 흉내: layer NULL 로 강제)
python3 - "$DB" <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
for i in range(3):
    c.execute("INSERT INTO skill_index (skill_path, keywords, layer, universe_id) VALUES (?,?,NULL,NULL)",
              (f"/old/skill{i}.md", "k"))
c.commit()
PY
BEFORE="$(q "$DB" "select count(*) from skill_index")"
PYTHONPATH="$S" python3 -c "
import sqlite3; from hermes_skill_layers import ensure_layer_columns
c=sqlite3.connect('$DB'); ensure_layer_columns(c, '$UID_VAL'); c.commit()"
assert "행 수 불변" "$BEFORE" "$(q "$DB" "select count(*) from skill_index")"
assert "심은 3행이 layer='common' 으로 백필" 3 "$(q "$DB" "select count(*) from skill_index where layer='common'")"
assert "universe_id 백필됨" 3 "$(q "$DB" "select count(*) from skill_index where universe_id='$UID_VAL'")"
assert "기존 행 skill_id 는 NULL(미부여)" 3 "$(q "$DB" "select count(*) from skill_index where skill_id is null")"

echo ""
echo "== 2. 층별 저장 경로 (목표 2) =="
LP="import sys; sys.path.insert(0,'$S'); from hermes_skill_layers import layer_dir"
assert "universe 경로" "$P/.claude/skills" "$(python3 -c "$LP; print(layer_dir('$P','universe'))")"
assert "common 경로" "$P/.hermes/skills" "$(python3 -c "$LP; print(layer_dir('$P','common'))")"
assert "unit 경로" "$P/.hermes/units/U7/skills" "$(python3 -c "$LP; print(layer_dir('$P','unit',unit_id='U7'))")"
assert "agent 경로" "$P/.hermes/agents/A7/skills" "$(python3 -c "$LP; print(layer_dir('$P','agent',agent_id='A7'))")"

echo ""
echo "== 3. 색인기 네 자리 스캔 (목표 2) =="
mk() { mkdir -p "$(dirname "$1")"; printf -- '---\nname: %s\ndescription: %s\n---\n# %s\n' "$2" "$3" "$2" > "$1"; }
mk "$P/.claude/skills/uni/SKILL.md"                  uni  "우주 스킬"
mk "$P/.hermes/skills/com.md"                        com  "공통 스킬"
mk "$P/.hermes/units/UUU/skills/team/SKILL.md"       team "단위 스킬"
mk "$P/.hermes/agents/AAA/skills/mine.md"            mine "개인 스킬"
python3 "$S/hermes-index-skills.py" --db "$DB" --project "$P" >/dev/null 2>&1
assert "universe 층 1건" 1 "$(q "$DB" "select count(*) from skill_index where layer='universe'")"
assert "unit 층 소유 UUU" 1 "$(q "$DB" "select count(*) from skill_index where layer='unit' and unit_id='UUU'")"
assert "agent 층 소유 AAA" 1 "$(q "$DB" "select count(*) from skill_index where layer='agent' and agent_id='AAA'")"
assert "색인된 스킬은 skill_id 부여됨" 4 "$(q "$DB" "select count(*) from skill_index where skill_id is not null and skill_path like '$P/%'")"

echo ""
echo "== 4. skill_id 신원 불변 (재색인 보존) =="
SID1="$(q "$DB" "select skill_id from skill_index where skill_path='$P/.hermes/units/UUU/skills/team/SKILL.md'")"
python3 "$S/hermes-index-skills.py" --db "$DB" --project "$P" >/dev/null 2>&1
SID2="$(q "$DB" "select skill_id from skill_index where skill_path='$P/.hermes/units/UUU/skills/team/SKILL.md'")"
assert "재색인해도 skill_id 동일" "$SID1" "$SID2"

echo ""
echo "== 5. 구 스키마 호환 (목표 16) =="
OLD="$TMP/old.db"
python3 - "$OLD" <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.execute("CREATE TABLE skill_index (id INTEGER PRIMARY KEY, skill_path TEXT UNIQUE, keywords TEXT)")
c.execute("INSERT INTO skill_index (skill_path, keywords) VALUES ('/x.md','k')")
c.commit()
PY
RC=$(PYTHONPATH="$S" python3 -c "
import sqlite3; from hermes_skill_layers import ensure_layer_columns
c=sqlite3.connect('$OLD'); ensure_layer_columns(c,'u'); c.commit()
cols=[r[1] for r in c.execute('PRAGMA table_info(skill_index)')]
print('ok' if all(x in cols for x in ('universe_id','layer','unit_id','agent_id','skill_id')) else 'no')" 2>&1)
assert "구 DB 에 칸 5개 생성" ok "$RC"
assert "구 DB 기존 행 layer 백필" common "$(q "$OLD" "select layer from skill_index where skill_path='/x.md'")"

echo ""
echo "== 6. 실제 사본 리허설 (있으면) =="
ZD=/home/jjackkun/PROJECT/zeroday-frontend/.hermes/state.db
if [[ -f "$ZD" ]]; then
  cp "$ZD" "$TMP/zd.db"
  N0="$(q "$TMP/zd.db" "select count(*) from skill_index")"
  python3 "$S/hermes-init.py" --db "$TMP/zd.db" >/dev/null 2>&1
  assert "행 수 불변" "$N0" "$(q "$TMP/zd.db" "select count(*) from skill_index")"
  # "전부 common" 이 아니라 "NULL 없음" 이 불변식이다 — 라이브 DB 는 이미 재색인돼 universe 층이 섞여 있을 수 있다
  # (2026-09-17 전파 뒤 zeroday 에 universe 50건). 마이그레이션의 약속은 NULL 이던 행을 common 으로 채우는 것.
  assert "layer NULL 인 행 0(백필 누락 없음)" 0 "$(q "$TMP/zd.db" "select count(*) from skill_index where layer is null")"
  assert "층 값이 네 가지 밖에 없음" 0 "$(q "$TMP/zd.db" "select count(*) from skill_index where layer not in ('universe','common','unit','agent')")"
else
  echo "  ⊘ zeroday DB 없음 — 리허설 건너뜀"
fi

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
