#!/usr/bin/env bash
# 확장 기준 버전 대조·주입 합성 (계획 docs/exec-plans/active/2026-09-15-skill-layers-delivery.md 목표 6).
#
#   - extends: <skill_id>@<version> 머리말 파싱
#   - 기준(version)이 현재 공장 커밋과 다르면 [extends WARN] (공장 커밋 바뀐 뒤 재설치 상황)
#   - 기준이 같으면 경고 0, extends 없으면 대상 아님
#   - 주입 합성: 확장은 위 층(같은 skill_id) 본문 뒤에 "[확장]" 으로 붙는다
#
# 실행: bash tests/hermes-skill-extends-test.sh

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
has() { grep -qE "$2" <<<"$1" && echo yes || echo no; }

P="$TMP/proj"; mkdir -p "$P/.hermes/skills"
PYTHONPATH="$S" python3 -c "from hermes_universe import ensure_universe_id as e; e('$P')"
python3 "$S/hermes-init.py" --project "$P" >/dev/null 2>&1
DB="$P/.hermes/state.db"

mkbase() { printf -- '---\nname: base-skill\ndescription: 기본 배포 스킬\n---\n# base-skill 본문\n기본 절차 상세.\n' > "$P/.hermes/skills/base-skill.md"; }
mkbase
python3 "$S/hermes-index-skills.py" --db "$DB" --project "$P" >/dev/null 2>&1
BSID="$(python3 -c "import sqlite3;print(sqlite3.connect('$DB').execute(\"select skill_id from skill_index where skill_path like '%base-skill%'\").fetchone()[0])")"
NEWVER="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"   # '재설치된' 새 공장 커밋
python3 -c "import json;json.dump({'remote_url':'x','installed_version':'$NEWVER'},open('$P/.hermes/factory.json','w'))"

echo "== 1. extends 파싱 (목표 6) =="
printf -- '---\nname: ext-old\nextends: %s@oldcommit99\n---\n# ext-old 본문\n팀 차이.\n' "$BSID" > "$P/.hermes/skills/ext-old.md"
PARSED="$(PYTHONPATH="$S" python3 -c "from hermes_skill_extends import parse_extends;print(parse_extends('$P/.hermes/skills/ext-old.md'))")"
assert "skill_id·version 파싱" yes "$(has "$PARSED" "$BSID.*oldcommit99")"
assert "extends 없으면 None" None "$(PYTHONPATH="$S" python3 -c "from hermes_skill_extends import parse_extends;print(parse_extends('$P/.hermes/skills/base-skill.md'))")"

echo ""
echo "== 2. 기준 버전 대조 (목표 6) =="
# 공장 커밋이 NEWVER 로 바뀌었는데 확장은 oldcommit99 기준 → 경고 1
N="$(PYTHONPATH="$S" python3 -c "from hermes_skill_extends import warn_stale;print(warn_stale('$P'))" 2>/dev/null)"
assert "기준 다른 확장 1건 경고(공장 커밋 바뀐 뒤 재설치)" 1 "$N"
WARN="$(PYTHONPATH="$S" python3 -c "from hermes_skill_extends import warn_stale;warn_stale('$P')" 2>&1 1>/dev/null)"
assert "경고 문구가 [extends WARN]" yes "$(has "$WARN" '\[extends WARN\]')"
# 기준을 현재 공장 커밋으로 맞추면 경고 0
rm "$P/.hermes/skills/ext-old.md"
printf -- '---\nname: ext-cur\nextends: %s@%s\n---\n# ext-cur\n' "$BSID" "$NEWVER" > "$P/.hermes/skills/ext-cur.md"
assert "기준이 현재와 같으면 경고 0" 0 "$(PYTHONPATH="$S" python3 -c "from hermes_skill_extends import warn_stale;print(warn_stale('$P'))" 2>/dev/null)"
# factory.json 없으면(공장 커밋 모름) 경고 안 냄
rm "$P/.hermes/factory.json"
assert "factory.json 없으면 경고 0(남발 금지)" 0 "$(PYTHONPATH="$S" python3 -c "from hermes_skill_extends import warn_stale;print(warn_stale('$P'))" 2>/dev/null)"

echo ""
echo "== 3. 주입 합성: 위 층 본문 + 확장 (목표 6) =="
printf -- '---\nname: ext-inj\nextends: %s@old\n---\n# ext-inj 본문\n우리 팀 차이 내용\n' "$BSID" > "$P/.hermes/skills/ext-inj.md"
python3 "$S/hermes-index-skills.py" --db "$DB" --project "$P" >/dev/null 2>&1
OUT="$(python3 "$S/hermes-search.py" --db "$DB" --query "ext-inj" --max 3 --no-fallback 2>&1)"
assert "확장 주입에 위 층(base) 본문 포함" yes "$(has "$OUT" '기본 배포 스킬')"
assert "확장 주입에 [확장] 표시" yes "$(has "$OUT" '\[확장\]')"
assert "확장 주입에 확장 본문 포함" yes "$(has "$OUT" '우리 팀 차이 내용')"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
