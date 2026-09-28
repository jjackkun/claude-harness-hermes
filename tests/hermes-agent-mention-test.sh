#!/usr/bin/env bash
# 명부 에이전트를 @agent-<slug> 로 부르는 연결 검증
# (계획 docs/exec-plans/active/2026-09-28-agent-mention-bridge.md).
#
#   1. slug (목표 1) — 형식·유일(은퇴자 포함)·예약 이름 거부, hire --slug · set-slug 저장, slug 없는 옛 명부 호환
#   2. 에이전트 파일 (목표 2) — slug 있는 재직자만 .claude/agents/<slug>.md, 템플릿 도구·모델 상속, SOUL 없음, 멱등, 은퇴 삭제·복직 복원, 고아 삭제·사용자 파일 보존
#   3. SubagentStart 주입 훅 (목표 3) — 명부 slug 면 세션 시작과 같은 출근 본문을 additionalContext 로, 그 밖·은퇴자·손상 입력은 무출력 rc 0
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
echo "== 2. 에이전트 파일 (목표 2) =="
AG="$P/.claude/agents"
fm() { python3 -c "
import re,sys; t=open(sys.argv[1],encoding='utf-8').read(); m=re.match(r'^---\n(.*?)\n---\n',t,re.S)
kv=dict(l.split(':',1) for l in m.group(1).splitlines() if ':' in l) if m else {}
print(kv.get(sys.argv[2],'(없음)').strip())" "$1" "$2"; }
has() { [[ -f "$1" ]] && echo 1 || echo 0; }

# 1 절이 남긴 상태: 백로그담당=backlog-manager(수습), 설계담당=design-lead(은퇴). 파일은 명령을 한 번 돌려야 맞춰진다.
A sync-mention-files >"$TMP/sync1" 2>&1; assert "sync-mention-files → 0" 0 "$?"
assert "slug 있는 재직자 파일 생성" 1 "$(has "$AG/backlog-manager.md")"
assert "name 은 slug" backlog-manager "$(fm "$AG/backlog-manager.md" name)"
assert "description 에 한글 명부 이름" 1 "$(fm "$AG/backlog-manager.md" description | grep -c '백로그담당')"
assert "은퇴자 파일은 없다" 0 "$(has "$AG/design-lead.md")"
assert "slug 없는 에이전트는 파일 없음(품질담당)" 0 "$(ls "$AG" | grep -c 품질)"
AID="$(python3 -c "import json;print([a['agent_id'] for a in json.load(open('$P/.hermes/agents.json'))['agents'] if a['name']=='백로그담당'][0])")"
SOUL_LINE="$(grep -m1 '^#' "$P/.hermes/agents/$AID/SOUL.md")"   # frontmatter 뒤 본문 첫 제목
assert "전제: SOUL.md 첫 줄이 비지 않음" 1 "$([[ -n "$SOUL_LINE" ]] && echo 1 || echo 0)"
assert "파일에 SOUL 본문이 없다(훅 몫)" 0 "$(grep -cF "$SOUL_LINE" "$AG/backlog-manager.md")"
assert "생성물 표지가 있다" 1 "$(grep -c 'hermes-mention-file' "$AG/backlog-manager.md")"

cp "$AG/backlog-manager.md" "$TMP/bm.before"
A sync-mention-files >"$TMP/sync2" 2>&1
assert "두 번째 sync 는 바꾼 것 0 (멱등)" 1 "$(grep -c '바꿈 0 · 지움 0' "$TMP/sync2")"
assert "두 번째 sync 뒤 내용 동일" 0 "$(diff -q "$TMP/bm.before" "$AG/backlog-manager.md" >/dev/null; echo $?)"

A hire 리뷰담당 --org 기획,담당,공통 --template code-reviewer --slug review-lead >/dev/null 2>&1
assert "hire --slug 가 바로 파일을 만든다" 1 "$(has "$AG/review-lead.md")"
assert "템플릿 도구를 물려받는다(code-reviewer)" "Read, Grep, Glob, Bash" "$(fm "$AG/review-lead.md" tools)"
assert "템플릿 모델을 물려받는다(sonnet)" sonnet "$(fm "$AG/review-lead.md" model)"
A hire 기획담당 --org 기획,담당,공통 --template product-manager --slug pm-lead >/dev/null 2>&1
assert "Claude Code 도구 이름이 아니면 tools 칸 없음(product-manager 의 bash)" "(없음)" "$(fm "$AG/pm-lead.md" tools)"
assert "빈 모델이면 model 칸 없음" "(없음)" "$(fm "$AG/pm-lead.md" model)"

A set-slug 품질담당 quality-lead >/dev/null 2>&1
assert "set-slug 가 바로 파일을 만든다" 1 "$(has "$AG/quality-lead.md")"
A retire 리뷰담당 >/dev/null 2>&1; assert "retire 가 파일을 지운다" 0 "$(has "$AG/review-lead.md")"
A rehire 리뷰담당 >/dev/null 2>&1; assert "rehire 가 파일을 되살린다" 1 "$(has "$AG/review-lead.md")"

printf -- '---\nname: my-own\ndescription: 사용자가 직접 둔 에이전트\n---\n본문\n' > "$AG/my-own.md"
sed 's/^name: .*/name: ghost-lead/' "$AG/quality-lead.md" > "$AG/ghost-lead.md"   # 명부에 없는 생성물(고아)
A sync-mention-files >/dev/null 2>&1
assert "표지 없는 사용자 에이전트는 지우지 않는다" 1 "$(has "$AG/my-own.md")"
assert "명부에 없는 생성물(고아)은 지운다" 0 "$(has "$AG/ghost-lead.md")"
assert "공장 에이전트는 그대로(code-reviewer)" 1 "$(has "$AG/code-reviewer.md")"
rm -f "$AG/quality-lead.md"; printf -- '---\nname: quality-lead\n---\n사람이 쓴 본문\n' > "$AG/quality-lead.md"   # slug 뒤에 사람이 같은 이름 파일을 둠
A sync-mention-files >"$TMP/sync3" 2>&1
assert "같은 이름의 사람 파일은 덮어쓰지 않는다" 1 "$(grep -c '사람이 쓴 본문' "$AG/quality-lead.md")"
assert "덮어쓰지 않은 것을 알린다" 1 "$(grep -c 'quality-lead' "$TMP/sync3")"

echo ""
echo "== 3. SubagentStart 주입 훅 (목표 3) =="
# 설치·설정 등록은 Step 6 — 여기서는 저장소 훅을 설치된 프로젝트에 대고 부른다.
SHOOK="$REPO_ROOT/assets/hooks/claude-subagentstart-agent-soul.sh"
sub() { printf '%s' "$1" | CLAUDE_PROJECT_DIR="$P" bash "$SHOOK" 2>"$TMP/sub.err"; }
ctx() { python3 -c "import json,sys; print(json.load(sys.stdin)['hookSpecificOutput']['additionalContext'])" 2>/dev/null; }
A teach 백로그담당 "백로그는 목표 수가 5개를 넘으면 쪼갠다" --about workflow/backlog-split >/dev/null 2>&1
OUT="$(sub '{"hook_event_name":"SubagentStart","agent_id":"x1","agent_type":"backlog-manager"}')"; RC=$?
assert "명부 slug → rc 0" 0 "$RC"
assert "출력은 hookEventName=SubagentStart JSON" SubagentStart "$(printf '%s' "$OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['hookSpecificOutput']['hookEventName'])" 2>/dev/null)"
assert "additionalContext 머리에 출근 줄과 명부 이름" 1 "$(printf '%s' "$OUT" | ctx | head -1 | grep -c '^\[헤르메스 출근\] 백로그담당 ')"
assert "additionalContext 에 SOUL 본문(제목 줄 그대로 1번)" 1 "$(printf '%s' "$OUT" | ctx | grep -cxF "$SOUL_LINE")"
assert "additionalContext 에 방금 가르친 기억" 1 "$(printf '%s' "$OUT" | ctx | grep -c '목표 수가 5개를 넘으면')"
assert "세션 시작 렌더러와 같은 본문" "$(CLAUDE_PROJECT_DIR="$P" python3 "$P/scripts/hermes_soul_render.py" "$P" "$AID" 2>/dev/null | md5sum)" \
  "$(printf '%s' "$OUT" | ctx | md5sum)"
assert "공장 에이전트(code-reviewer) → 무출력" "" "$(sub '{"agent_type":"code-reviewer"}')"
assert "내장 에이전트(Explore) → 무출력" "" "$(sub '{"agent_type":"Explore"}')"
assert "은퇴자(design-lead) → 무출력" "" "$(sub '{"agent_type":"design-lead"}')"
assert "JSON 아닌 입력 → 무출력" "" "$(sub 'not-json')"
sub 'not-json' >/dev/null; assert "  rc 0" 0 "$?"
mv "$P/.hermes/agents.json" "$TMP/agents.json.hold"
assert "명부 없음 → 무출력" "" "$(sub '{"agent_type":"backlog-manager"}')"
sub '{"agent_type":"backlog-manager"}' >/dev/null; assert "  rc 0" 0 "$?"
mv "$TMP/agents.json.hold" "$P/.hermes/agents.json"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
