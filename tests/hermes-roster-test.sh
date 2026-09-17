#!/usr/bin/env bash
# 명부·조직·입사 CLI 검증 (계획 docs/exec-plans/active/2026-09-15-agent-identity.md 목표 1·2·3·4·14·15).
#
#   - 명부 형식: UUIDv7 · 이름 유일(은퇴 포함) · 상태값 · org 값은 organization.yaml 에 있는 것만
#   - 전이 6경로: hire→probation, promote, retire(probation/active), rehire, 잘못된 전이 거부
#   - 정체성 폴더 .hermes/agents/<id>/{SOUL.md,MEMORY.md,skills/}
#   - 조직 템플릿 3종 검증 통과, unit_id 부여, rank 맨 위 human 고정
#   - 담당 매칭: 더 많은 축이 맞는 쪽 우선, 없으면 ask, 은퇴자는 제외
#   - git 추적: SOUL·개인 스킬·organization.yaml 은 추적, MEMORY.md·summons·그 밖은 무시
#
# 실행: bash tests/hermes-roster-test.sh

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

# 설치본 흉내 — 실제 설치기로 만든다(organization.yaml 기본·main·gitignore 까지)
P="$TMP/proj"; mkdir -p "$P"; git -C "$P" init -q; git -C "$P" config user.name tester
bash "$REPO_ROOT/project-claude.sh" "$P" harness hermes >"$TMP/install.log" 2>&1
A() { python3 "$P/scripts/hermes-agent.py" --project "$P" "$@"; }
py() { PYTHONPATH="$S" python3 -c "$1"; }
roster_field() { python3 -c "
import json,sys; a=[x for x in json.load(open(sys.argv[1]))['agents'] if x['name']==sys.argv[2]]
print(a[0][sys.argv[3]] if a else 'none')" "$P/.hermes/agents.json" "$1" "$2"; }

echo "== 1. 설치 직후 (목표 1·3) =="
assert "main 이 명부에 있음(active)" active "$(roster_field main status)"
assert "organization.yaml 생성됨(빈 조직)" 1 "$([[ -f "$P/.hermes/organization.yaml" ]] && echo 1 || echo 0)"
assert "SOUL 틀이 scripts/templates/agent/ 에 복사됨" 1 "$([[ -f "$P/scripts/templates/agent/SOUL.md" ]] && echo 1 || echo 0)"
assert "빈 조직도 rank 맨 위는 human" human "$(py "
from hermes_org import load_org; print(load_org('$P')['rank'][0])")"

echo ""
echo "== 2. 조직 템플릿 3종 (목표 3) =="
for t in empty product office; do
  assert "템플릿 $t 검증 통과, rank[0]=human" human "$(py "
from hermes_yaml_subset import parse; from hermes_org import validate_org
print(validate_org(parse(open('$REPO_ROOT/assets/templates/organization/$t.yaml',encoding='utf-8').read()))['rank'][0])")"
done
cp "$REPO_ROOT/assets/templates/organization/product.yaml" "$P/.hermes/organization.yaml"
assert "unit_id 없는 단위에 부여(1개)" 1 "$(py "
from hermes_org import ensure_unit_ids; print(ensure_unit_ids('$P'))")"
UNIT_ID="$(py "from hermes_org import load_org; print(load_org('$P')['unit']['공통']['unit_id'])")"
assert "부여된 unit_id 는 UUIDv7" 7 "$(python3 -c "import uuid;print(uuid.UUID('$UNIT_ID').version)")"
assert "두 번째 실행은 부여 0(불변)" 0 "$(py "from hermes_org import ensure_unit_ids; print(ensure_unit_ids('$P'))")"
assert "파일에 써진 뒤에도 같은 unit_id" "$UNIT_ID" "$(py "from hermes_org import load_org; print(load_org('$P')['unit']['공통']['unit_id'])")"
assert "human 을 맨 위 아닌 곳에 두면 거부" rejected "$(py "
from hermes_org import validate_org, OrgError
try: validate_org({'discipline':[], 'rank':['리드','human'], 'unit':{}}); print('accepted')
except OrgError: print('rejected')")"
assert "모르는 축은 거부" rejected "$(py "
from hermes_org import validate_org, OrgError
try: validate_org({'discipline':[], 'rank':[], 'unit':{}, 'team':[]}); print('accepted')
except OrgError: print('rejected')")"
assert "단위 이름을 바꿔도 unit_id 유지(파일 수정 시뮬)" "$UNIT_ID" "$(sed -i 's/^  공통:/  shared:/' "$P/.hermes/organization.yaml"; py "from hermes_org import load_org; print(load_org('$P')['unit']['shared']['unit_id'])"; sed -i 's/^  shared:/  공통:/' "$P/.hermes/organization.yaml")"

echo ""
echo "== 3. 입사·전이 6경로 (목표 1·2) =="
A hire 유저기획 --org 기획,담당,공통 --template planner >"$TMP/hire.out" 2>&1
assert "hire → probation" probation "$(roster_field 유저기획 status)"
assert "hire 가 agent.created 를 기록 (목표 2)" "1" "$(python3 -c "
import sqlite3;print(sqlite3.connect('$P/.hermes/state.db').execute(\"select count(*) from journal_events where kind='agent.created' and actor like 'human:%' and intent like 'hire 유저기획%'\").fetchone()[0])" 2>/dev/null || echo 0)"
assert "agent_id 는 UUIDv7" 7 "$(python3 -c "import uuid;print(uuid.UUID('$(roster_field 유저기획 agent_id)').version)")"
assert "created_by 는 human:" 1 "$(roster_field 유저기획 created_by | grep -c '^human:')"
assert "template 에 @factory" planner@factory "$(roster_field 유저기획 template)"
AID="$(roster_field 유저기획 agent_id)"
assert "정체성 폴더 3개 산출물" 3 "$(ls -d "$P/.hermes/agents/$AID/SOUL.md" "$P/.hermes/agents/$AID/MEMORY.md" "$P/.hermes/agents/$AID/skills" 2>/dev/null | wc -l)"
assert "SOUL.md 머리말에 agent_id" 1 "$(grep -c "^agent_id: $AID" "$P/.hermes/agents/$AID/SOUL.md")"
A promote 유저기획 >/dev/null 2>&1; assert "promote → active" active "$(roster_field 유저기획 status)"
A promote 유저기획 >/dev/null 2>&1; assert "active 에서 promote 거부(rc=2)" 2 "$?"
A retire 유저기획 >/dev/null 2>&1; assert "retire → retired" retired "$(roster_field 유저기획 status)"
A rehire 유저기획 >/dev/null 2>&1; assert "rehire → active" active "$(roster_field 유저기획 status)"
A rehire 유저기획 >/dev/null 2>&1; assert "active 에서 rehire 거부" 2 "$?"
A hire 수습이 --org 기획,담당,공통 >/dev/null 2>&1; A retire 수습이 >/dev/null 2>&1
assert "probation 에서 retire 가능" retired "$(roster_field 수습이 status)"
A hire 수습이 --org 기획,담당,공통 >/dev/null 2>&1
assert "은퇴한 이름 재사용 거부(rc=2)" 2 "$?"
A hire 이상한 --org 마케팅,담당,공통 >/dev/null 2>&1
assert "organization.yaml 에 없는 값 거부" 2 "$?"
A hire 사장 --org 기획,human,공통 >/dev/null 2>&1
assert "rank human 은 에이전트에게 못 줌" 2 "$?"
python3 - "$P/.hermes/agents.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["agents"][0]["status"] = "ghost"
json.dump(d, open(sys.argv[1], "w"), ensure_ascii=False)
PY
A list >/dev/null 2>&1; assert "모르는 상태값이 있는 명부는 거부" 2 "$?"
python3 - "$P/.hermes/agents.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["agents"][0]["status"] = "active"
json.dump(d, open(sys.argv[1], "w"), ensure_ascii=False)
PY

echo ""
echo "== 4. 담당 매칭 (목표 4·15) =="
A hire 공통기획 --org 기획,담당,공통 >/dev/null 2>&1
A hire 프론트 --org 프론트엔드,담당,공통 >/dev/null 2>&1
assert "discipline+unit 두 축 일치가 우선(유저기획·공통기획 둘 다 기획/공통 → 2명)" 2 "$(A match --discipline 기획 --unit 공통 2>/dev/null | wc -l)"
assert "한 축만 요청하면 그 축이 맞는 전부" 2 "$(A match --discipline 기획 2>/dev/null | wc -l)"
A match --discipline 디자인 >/dev/null 2>&1; assert "맞는 담당 없음 → ask(rc=3)" 3 "$?"
# 계획 design-gaps-tier2 목표 8 — "담당 두지 않음" 을 기억해 두면 그 영역은 다시 묻지 않는다 (creation-and-organization.md:95)
A no-owner --discipline 디자인 >"$TMP/noowner.out" 2>&1; assert "no-owner 기록 rc 0" 0 "$?"
assert "no-owner 가 decision 이벤트로 남음" 1 "$(python3 -c "
import sqlite3;print(sqlite3.connect('$P/.hermes/state.db').execute(\"select count(*) from journal_events where kind='decision' and intent like 'no-owner discipline:디자인%'\").fetchone()[0])")"
NO_OUT="$(A match --discipline 디자인 2>&1)"; assert "기억된 영역은 ask 대신 no-owner(rc 4)" 4 "$?"
assert "no-owner 출력에 날짜" 1 "$(grep -c '2026-' <<<"$NO_OUT")"
A match --discipline 퍼블리싱 >/dev/null 2>&1; assert "다른 영역은 여전히 ask(rc=3)" 3 "$?"
A retire 유저기획 >/dev/null 2>&1
assert "은퇴자는 매칭에서 빠진다" 1 "$(A match --discipline 기획 --unit 공통 2>/dev/null | grep -c '공통기획')"
assert "은퇴자 이름은 결과에 없음" 0 "$(A match --discipline 기획 --unit 공통 2>/dev/null | grep -c '유저기획')"
A rehire 유저기획 >/dev/null 2>&1
assert "복직하면 다시 매칭됨" 1 "$(A match --discipline 기획 --unit 공통 2>/dev/null | grep -c '유저기획')"
assert "whoami 기본은 main" 1 "$(A whoami | grep -c '(main, active)')"
assert "HERMES_AGENT_ID 로 행위자 지정" 1 "$(HERMES_AGENT_ID="$AID" A whoami | grep -c '유저기획')"

echo ""
echo "== 5. git 추적 6경로 (목표 14) =="
cd "$P"
ig() { git check-ignore -q "$1" && echo 무시 || echo 추적; }
assert "organization.yaml 추적" 추적 "$(ig .hermes/organization.yaml)"
assert "agents.json 추적" 추적 "$(ig .hermes/agents.json)"
assert "agents/<id>/SOUL.md 추적" 추적 "$(ig ".hermes/agents/$AID/SOUL.md")"
assert "agents/<id>/skills/** 추적" 추적 "$(ig ".hermes/agents/$AID/skills/x/y.md")"
assert "agents/<id>/MEMORY.md 무시(파생)" 무시 "$(ig ".hermes/agents/$AID/MEMORY.md")"
assert "agents/<id>/ 그 밖 파일 무시" 무시 "$(ig ".hermes/agents/$AID/scratch.txt")"
assert "summons/ 무시" 무시 "$(ig .hermes/summons/abc.pending)"
cd "$REPO_ROOT"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
