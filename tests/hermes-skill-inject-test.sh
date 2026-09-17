#!/usr/bin/env bash
# 스킬 주입 필터·형식·본문 읽기 (계획 docs/exec-plans/active/2026-09-15-skill-layers-delivery.md 목표 3·4·5·15·16).
#
#   - 주입 필터(RV-12): 소환된 에이전트의 unit·agent 층만 검색, 타 단위·타 개인 0건
#   - 형식 하위호환: description 있으면 `이름 — 설명` 한 줄, 없으면 스니펫 여러 줄
#   - 본문 읽기: hermes-skill.py read → 파일 본문, skill_injection source='read' 기록
#   - 색인 안 된 타 단위 파일도 dir-scan 에서 0건(목표 15)
#   - 층 칸 없는 구 DB 에서 검색이 안 죽고 지연 마이그레이션(목표 16)
#
# 실행: bash tests/hermes-skill-inject-test.sh

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
has()  { grep -qE "$2" <<<"$1" && echo yes || echo no; }

# ── 픽스처: 소우주 + 조직(단위 팀A) + 입사(백엔드담당→팀A) ────────────────
P="$TMP/proj"; mkdir -p "$P/.hermes"
PYTHONPATH="$S" python3 -c "from hermes_universe import ensure_universe_id as e; e('$P')"
python3 "$S/hermes-init.py" --project "$P" >/dev/null 2>&1
DB="$P/.hermes/state.db"
cat > "$P/.hermes/organization.yaml" <<'YAML'
discipline: [백엔드, 프론트엔드]
rank: [리드, 담당]
unit:
  팀A: {code: [src/a/**]}
  팀B: {code: [src/b/**]}
YAML
python3 "$S/hermes-agent.py" --project "$P" hire "백엔드담당" --org "백엔드,담당,팀A" >/dev/null 2>&1
AID="$(python3 -c "import json;print(next(a['agent_id'] for a in json.load(open('$P/.hermes/agents.json'))['agents'] if a['name']=='백엔드담당'))")"
UIDA="$(python3 -c "import json,sys;sys.path.insert(0,'$S');from hermes_org import load_org;print(load_org('$P')['unit']['팀A']['unit_id'])")"
UIDB="$(python3 -c "import json,sys;sys.path.insert(0,'$S');from hermes_org import load_org;print(load_org('$P')['unit']['팀B']['unit_id'])")"

mk() { mkdir -p "$(dirname "$1")"; printf -- '---\nname: %s\ndescription: %s\n---\n# %s 본문\n둘째 줄.\n' "$2" "$3" "$2" > "$1"; }
mk "$P/.hermes/skills/common-skill.md"                    common-skill "공통 배포 절차 스킬"
mk "$P/.hermes/units/$UIDA/skills/teama-skill.md"         teama-skill  "팀A 전용 스킬"
mk "$P/.hermes/units/$UIDB/skills/teamb-skill.md"         teamb-skill  "팀B 전용 스킬"
mk "$P/.hermes/agents/$AID/skills/my-skill.md"            my-skill     "백엔드담당 개인 스킬"
# description 없는 스킬(스니펫 경로)
printf '# nodesc-skill 설명없음스킬\n첫 줄 본문\n둘째 줄 본문\n' > "$P/.hermes/skills/nodesc-skill.md"
python3 "$S/hermes-index-skills.py" --db "$DB" --project "$P" >/dev/null 2>&1

srch() { HERMES_AGENT_ID="$1" python3 "$S/hermes-search.py" --db "$DB" --query "$2" --max 8 --no-fallback 2>&1; }

echo "== 1. 주입 필터: 팀A 담당 시점 (목표 3) =="
OUT="$(srch "$AID" "common-skill teama-skill teamb-skill my-skill")"
assert "공통 스킬 보임"       yes "$(has "$OUT" 'common-skill')"
assert "내 단위(팀A) 스킬 보임" yes "$(has "$OUT" 'teama-skill')"
assert "타 단위(팀B) 스킬 안 보임" no  "$(has "$OUT" 'teamb-skill')"
assert "내 개인 스킬 보임"     yes "$(has "$OUT" 'my-skill')"

echo ""
echo "== 2. 주입 필터: main(미소환) 시점 — 공통만 =="
OUT="$(srch "main" "common-skill teama-skill teamb-skill my-skill")"
assert "공통 보임"        yes "$(has "$OUT" 'common-skill')"
assert "팀A 스킬 안 보임"  no  "$(has "$OUT" 'teama-skill')"
assert "개인 스킬 안 보임" no  "$(has "$OUT" 'my-skill')"

echo ""
echo "== 3. 형식 하위호환 (목표 4) =="
OUT="$(srch "$AID" "common-skill")"
assert "description 스킬은 한 줄(이름 — 설명)" yes "$(has "$OUT" '\] 공통 배포 절차 스킬')"
OUT="$(srch "$AID" "nodesc-skill 설명없음스킬")"
assert "description 없으면 스니펫(본문 줄 포함)" yes "$(has "$OUT" '첫 줄 본문')"

echo ""
echo "== 4. 본문 읽기 CLI (목표 5) =="
BODY="$(python3 "$S/hermes-skill.py" --db "$DB" --project "$P" --session-id SESS read common-skill)"
assert "read 는 파일 본문(본문 줄 포함)" yes "$(has "$BODY" '# common-skill 본문')"
assert "read 가 source='read' 기록" 1 "$(python3 -c "import sqlite3;print(sqlite3.connect('$DB').execute(\"select count(*) from skill_injection where source='read'\").fetchone()[0])")"
WHERE="$(python3 "$S/hermes-skill.py" --db "$DB" --project "$P" where teama-skill)"
assert "where 는 층·소유 판정" yes "$(has "$WHERE" "unit.*$UIDA")"

echo ""
echo "== 5. 색인 안 된 타 단위 파일도 0건 (목표 15) =="
# 색인하지 않은 팀B 스킬을 --skills-dir 로 직접 던져도 팀A 담당에겐 안 보인다
OUT="$(HERMES_AGENT_ID="$AID" python3 "$S/hermes-search.py" --db "$DB" --query "teamb-skill" --max 8 --no-fallback --skills-dir "$P/.hermes/units/$UIDB/skills" 2>&1)"
assert "타 단위 dir-scan 주입 0건" no "$(has "$OUT" 'teamb-skill')"

echo ""
echo "== 6. 구 스키마 호환 (목표 16) =="
OLD="$TMP/old"; mkdir -p "$OLD/.hermes/skills"
python3 - "$OLD/.hermes/state.db" <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.execute("CREATE TABLE skill_index (id INTEGER PRIMARY KEY, skill_path TEXT UNIQUE, keywords TEXT, used_count INTEGER DEFAULT 0)")
c.execute("CREATE TABLE skill_injection (id INTEGER PRIMARY KEY, session_id TEXT, skill_path TEXT)")
c.execute("INSERT INTO skill_index (skill_path, keywords) VALUES ('/x/old-skill.md','오래된')")
c.commit()
PY
printf -- '---\nname: old-skill\ndescription: 옛 스킬\n---\n본문\n' > "$OLD/.hermes/skills/old-skill.md"
RC=$(python3 "$S/hermes-search.py" --db "$OLD/.hermes/state.db" --query "오래된" --max 3 --no-fallback >/dev/null 2>&1; echo $?)
assert "구 DB 검색 exit 0" 0 "$RC"
assert "구 DB 에 layer 칸 생성됨" 1 "$(python3 -c "import sqlite3;print(1 if 'layer' in [r[1] for r in sqlite3.connect('$OLD/.hermes/state.db').execute('PRAGMA table_info(skill_index)')] else 0)")"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
