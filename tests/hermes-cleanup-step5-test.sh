#!/usr/bin/env bash
# 정리 (계획 docs/exec-plans/active/2026-09-15-skill-layers-delivery.md 목표 11·13·14).
#
#   - global.db harness_rules 쓰기 중단(L-05): crystallize 에 record_global_summary 호출·INSERT 없음
#   - hermes-message.py 는 폐기 예정 경고 한 줄을 낸다(목표 13)
#   - 단위 층 스킬은 git 을 탄다: units/*/skills/ 추적, units/*/ 그 밖 파일·outbox/ 무시(목표 14)
#
# 실행: bash tests/hermes-cleanup-step5-test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$REPO_ROOT/scripts"
CONF="$REPO_ROOT/presets/workflow/hermes.conf"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/fakehome"; mkdir -p "$HOME/.hermes"

PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  ✓ $desc"; PASS=$((PASS+1))
  else
    echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1))
  fi
}

echo "== 1. global.db 쓰기 중단 (목표 11, L-05) =="
assert "crystallize 에 record_global_summary 호출 없음" 0 "$(grep -cE 'record_global_summary\(' "$S/hermes-crystallize.py")"
assert "crystallize 에 harness_rules INSERT 없음" 0 "$(grep -cE 'INSERT INTO harness_rules' "$S/hermes-crystallize.py")"
# 기능 확인: global.db 에 기존 행을 심고 결정화를 돌려도(콘텐츠 생성 없어 SKIP) 행 수 불변
GDB="$HOME/.hermes/global.db"
python3 - "$GDB" <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.execute("CREATE TABLE harness_rules (id INTEGER PRIMARY KEY, trigger_keywords TEXT, instruction TEXT, source_session_id TEXT, scope TEXT)")
c.execute("INSERT INTO harness_rules (trigger_keywords, instruction, scope) VALUES ('k','기존 1142행 흉내','local')")
c.commit()
PY
BEFORE="$(python3 -c "import sqlite3;print(sqlite3.connect('$GDB').execute('select count(*) from harness_rules').fetchone()[0])")"
P="$TMP/proj"; mkdir -p "$P/.hermes/skills"
PYTHONPATH="$S" python3 -c "from hermes_universe import ensure_universe_id as e; e('$P')"
python3 "$S/hermes-init.py" --project "$P" >/dev/null 2>&1
HERMES_DISABLED=1 python3 "$S/hermes-crystallize.py" --db "$P/.hermes/state.db" --keys "테스트키" >/dev/null 2>&1 || true
assert "결정화 후 global.db 행 수 불변" "$BEFORE" "$(python3 -c "import sqlite3;print(sqlite3.connect('$GDB').execute('select count(*) from harness_rules').fetchone()[0])")"

echo ""
echo "== 2. hermes-message 폐기 예정 경고 (목표 13) =="
assert "list 호출 시 폐기 예정 경고 1줄" 1 "$(python3 "$S/hermes-message.py" --db "$TMP/none.db" list 2>&1 | grep -c '폐기 예정')"
assert "send 호출 시에도 경고" 1 "$(python3 "$S/hermes-message.py" --db "$TMP/none.db" send --from a --to b --content x 2>&1 | grep -c '폐기 예정')"

echo ""
echo "== 3. 단위 층 스킬 git 추적 (목표 14) =="
G="$TMP/gitrepo"; mkdir -p "$G"; git -C "$G" init -q
# 설치기가 쓰는 것과 같은 순서로 units 예외를 뽑아 .gitignore 로 재현
grep -oE '"\.hermes/[^"]*"|"!\.hermes/[^"]*"' "$CONF" | tr -d '"' > "$G/.gitignore"
mkdir -p "$G/.hermes/units/U1/skills" "$G/.hermes/outbox/E1"
echo x > "$G/.hermes/units/U1/skills/team.md"
echo y > "$G/.hermes/units/U1/notes.txt"
echo z > "$G/.hermes/outbox/E1/envelope.json"
chk() { git -C "$G" check-ignore -q "$1" && echo ignored || echo tracked; }
assert "단위 스킬 team.md 추적" tracked "$(chk .hermes/units/U1/skills/team.md)"
assert "units/*/ 그 밖 파일 무시" ignored "$(chk .hermes/units/U1/notes.txt)"
assert "outbox/ 무시(봉투는 배달로 나감)" ignored "$(chk .hermes/outbox/E1/envelope.json)"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
