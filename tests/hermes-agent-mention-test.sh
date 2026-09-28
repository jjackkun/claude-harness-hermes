#!/usr/bin/env bash
# 명부 에이전트를 @agent-<slug> 로 부르는 연결 검증
# (계획 docs/exec-plans/active/2026-09-28-agent-mention-bridge.md).
#
#   1. slug (목표 1) — 형식·유일(은퇴자 포함)·예약 이름 거부, hire --slug · set-slug 저장, slug 없는 옛 명부 호환
#
# 실행: bash tests/hermes-agent-mention-test.sh

set -uo pipefail
export HARNESS_TOOL_INSTALL=0 HARNESS_SYNC_AUTOENABLE=0   # 설치기의 외부 도구 다운로드는 끈다(네트워크 0)

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
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

# 설치본 흉내 — 실제 설치기로 만든다(공장 에이전트 .claude/agents/*.md 까지 깔린다)
P="$TMP/proj"; mkdir -p "$P"; git -C "$P" init -q; git -C "$P" config user.name tester
bash "$REPO_ROOT/project-claude.sh" "$P" harness hermes >"$TMP/install.log" 2>&1
cp "$REPO_ROOT/assets/templates/organization/product.yaml" "$P/.hermes/organization.yaml"
A() { python3 "$P/scripts/hermes-agent.py" --project "$P" "$@"; }
slug_of() { python3 -c "
import json,sys; a=[x for x in json.load(open(sys.argv[1]))['agents'] if x['name']==sys.argv[2]]
print(a[0].get('slug','none') if a else 'no-agent')" "$P/.hermes/agents.json" "$1"; }
list_rc() { A list >/dev/null 2>&1; echo $?; }

echo "== 1. slug (목표 1) =="
A hire 백로그담당 --org 기획,담당,공통 >/dev/null 2>&1
A hire 품질담당 --org 기획,담당,공통 >/dev/null 2>&1
assert "slug 없는 명부도 그대로 읽힌다" 0 "$(list_rc)"
assert "slug 없이 입사하면 slug 칸이 없다" none "$(slug_of 백로그담당)"

A set-slug 백로그담당 backlog-manager >/dev/null 2>&1; assert "set-slug 정상 → 0" 0 "$?"
assert "set-slug 가 명부에 저장" backlog-manager "$(slug_of 백로그담당)"
A set-slug 백로그담당 backlog-manager >/dev/null 2>&1; assert "같은 에이전트에 같은 slug 다시 → 0(멱등)" 0 "$?"

A set-slug 품질담당 품질 >"$TMP/e1" 2>&1; assert "한글 slug 거부" 2 "$?"
assert "거부 이유에 형식 규칙" 1 "$(grep -c 'a-z' "$TMP/e1")"
A set-slug 품질담당 Gate-QA >/dev/null 2>&1; assert "대문자 slug 거부" 2 "$?"
A set-slug 품질담당 backlog-manager >"$TMP/e2" 2>&1; assert "다른 에이전트의 slug 거부(중복)" 2 "$?"
assert "중복 거부 이유에 주인 이름" 1 "$(grep -c '백로그담당' "$TMP/e2")"
assert "전제: 공장 에이전트 code-reviewer 가 설치됐다" 1 "$([[ -f "$P/.claude/agents/code-reviewer.md" ]] && echo 1 || echo 0)"
A set-slug 품질담당 code-reviewer >"$TMP/e3" 2>&1; assert "설치된 에이전트 이름 거부" 2 "$?"
assert "예약 거부 이유에 .claude/agents" 1 "$(grep -c '.claude/agents' "$TMP/e3")"
A set-slug 품질담당 main >/dev/null 2>&1; assert "main 거부" 2 "$?"
A set-slug 품질담당 general-purpose >/dev/null 2>&1; assert "내장 에이전트 이름 거부" 2 "$?"
assert "거부 뒤 slug 는 그대로 없음" none "$(slug_of 품질담당)"
A set-slug 없는사람 gate-qa >/dev/null 2>&1; assert "명부에 없는 이름 거부" 2 "$?"

A hire 설계담당 --org 기획,담당,공통 --slug design-lead >/dev/null 2>&1; assert "hire --slug → 0" 0 "$?"
assert "hire --slug 가 저장" design-lead "$(slug_of 설계담당)"
A hire 설계담당2 --org 기획,담당,공통 --slug 설계 >/dev/null 2>&1; assert "hire --slug 한글이면 입사 자체 거부" 2 "$?"
assert "거부된 입사는 명부에 없다" no-agent "$(slug_of 설계담당2)"

A retire 설계담당 >/dev/null 2>&1
A set-slug 품질담당 design-lead >/dev/null 2>&1; assert "은퇴자의 slug 도 재사용 금지" 2 "$?"

# 손으로 고친 명부도 읽을 때 잡는다
cp "$P/.hermes/agents.json" "$TMP/roster.bak"
python3 - "$P/.hermes/agents.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["agents"][-1]["slug"] = "백로그"; json.dump(d, open(sys.argv[1], "w"), ensure_ascii=False)
PY
assert "명부에 형식이 틀린 slug → 읽기 거부" 2 "$(list_rc)"
cp "$TMP/roster.bak" "$P/.hermes/agents.json"
python3 - "$P/.hermes/agents.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for a in d["agents"]:
    if a["name"] == "품질담당": a["slug"] = "backlog-manager"
json.dump(d, open(sys.argv[1], "w"), ensure_ascii=False)
PY
assert "명부에 겹치는 slug → 읽기 거부" 2 "$(list_rc)"
cp "$TMP/roster.bak" "$P/.hermes/agents.json"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
