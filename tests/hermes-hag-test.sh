#!/usr/bin/env bash
# `@hag` 약속어 검증 (계획 docs/exec-plans/active/2026-09-28-hermes-chat.md 목표 6).
#
#   - 1 제안 스크립트(fileSuggestion): `@hag…` → 명부 에이전트 줄(hag:<slug>)만 · 뒤 글자로 거르기 · 은퇴자·slug 없는 사람 제외
#                                      그 밖 → 파일 경로(흩어진 글자 검색, 이름 일치가 앞) · 15줄 상한 · hermes 아니면 hag 도 파일 검색
#   - 2 보낸 뒤 훅: `@"hag:<slug> …"` → 그 에이전트로 넘기기 지시 · `@hag` 만 → 명부 표 · 백틱·메일 주소·붙은 말 무시 · hermes 아님 → 0 B
#   - 3 설정 생성: fileSuggestion 을 넣는다 · 사용자가 넣은 다른 fileSuggestion 은 보존 · 프리셋이 빠지면 우리 것만 걷는다
#   - 자기 검사: 제안 스크립트의 hag 분기를 끄면 1 이 빨개진다
#
# 실행: bash tests/hermes-hag-test.sh

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SUGGEST="$REPO_ROOT/scripts/hermes_file_suggest.py"
HOOK="$REPO_ROOT/assets/hooks/claude-userpromptsubmit-hag.sh"
PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo "  ✓ $desc"; PASS=$((PASS+1))
  else echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1)); fi
}
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME"
unset HERMES_AGENT_ID

P="$T/proj"; mkdir -p "$P/.hermes" "$P/docs/audits" "$P/src/components"
ln -s "$REPO_ROOT/scripts" "$P/scripts"
cat > "$P/.hermes/agents.json" <<'EOF'
{"agents": [
  {"agent_id": "01a0ad8a-e5ff-7026-bedf-0bbf3df3d334", "name": "main", "status": "active", "org": {}},
  {"agent_id": "01a0ae58-6aa6-7202-ae81-7d27af7b5617", "name": "게이트QA", "slug": "gate-qa", "status": "probation",
   "org": {"discipline": "QA", "rank": "담당", "unit": "공통"}},
  {"agent_id": "01a0b728-2040-7e30-ab2d-cee957be526e", "name": "백로그 관리자", "slug": "backlog-manager", "status": "probation",
   "org": {"discipline": "기획", "rank": "리드", "unit": "공통"}},
  {"agent_id": "01a0ae58-6a84-75bd-8bfa-9c85c2ce2be4", "name": "옛담당", "slug": "old-hand", "status": "retired", "org": {}}
]}
EOF
for f in docs/audits/2026-09-28-agent-chat.md docs/readme.md src/components/Button.tsx src/components/Modal.tsx src/doc-util.py; do
  printf 'x\n' > "$P/$f"
done
for i in $(seq 1 30); do printf 'x\n' > "$P/docs/note-$i.md"; done
git -C "$P" init -q; git -C "$P" add -A 2>/dev/null

sug() {  # sug <query> [cwd] → stdout
  python3 -c "import json,sys; print(json.dumps({'query':sys.argv[1],'cwd':sys.argv[2]}))" "$1" "${2:-$P}" \
    | python3 "$SUGGEST" 2>/dev/null
}

echo "== 1. 제안 스크립트"
O="$(sug hag)"
assert "@hag → 명령 4 + 명부 2" 6 "$(grep -c . <<<"$O")"
assert "  백로그 관리자 줄: 이름 · 분야 · hag:<slug>" 1 "$(grep -cx '백로그 관리자 · 기획/리드/공통 · hag:backlog-manager' <<<"$O")"
assert "  게이트QA 줄" 1 "$(grep -cx '게이트QA · QA/담당/공통 · hag:gate-qa' <<<"$O")"
assert "  줄마다 첫 글자가 다르다(Tab 공통 앞부분 완성 방지)" 6 "$(cut -c1-3 <<<"$O" | sort -u | grep -c .)"
assert "  은퇴자·main 없음" 0 "$(grep -cE '옛담당|main' <<<"$O")"
assert "  파일은 섞이지 않음(hag 표지 없는 줄 0)" 0 "$(grep -vcE ' · hag[:-]' <<<"$O")"
assert "@hag백로그 → 한 줄로 거름" "hag:backlog-manager" "$(sug 'hag백로그' | awk '{print $NF}')"
assert "@hag:gate → slug 로 거름" "hag:gate-qa" "$(sug 'hag:gate' | awk '{print $NF}')"
assert "대소문자 무관(@HAG)" 2 "$(sug HAG | grep -c ' · hag:')"
O="$(sug Button)"
assert "@Button → 파일" "src/components/Button.tsx" "$(head -1 <<<"$O")"
O="$(sug agtchat)"
assert "흩어진 글자(agtchat) → 감사 문서" 1 "$(grep -c 'docs/audits/2026-09-28-agent-chat.md' <<<"$O")"
O="$(sug doc)"
assert "이름에 doc 가 있는 파일이 경로에만 있는 것보다 앞" "src/doc-util.py" "$(head -1 <<<"$O")"
assert "15줄 상한" 15 "$(sug note | grep -c .)"
assert "맞는 것 없으면 0 줄" 0 "$(sug zzqqxx | grep -c .)"
Q="$T/plain"; mkdir -p "$Q"; printf 'x\n' > "$Q/hagfile.txt"
assert "hermes 아니면 hag 도 파일 검색" "hagfile.txt" "$(sug hag "$Q" | head -1)"
assert "하위 폴더 cwd 에서도 명부" 2 "$(sug hag "$P/src" | grep -c ' · hag:')"
assert "깨진 입력에도 exit 0" 0 "$(echo 'not json' | python3 "$SUGGEST" >/dev/null 2>&1; echo $?)"

echo "== 2. 보낸 뒤 훅"
run() {  # run <prompt> [project]
  python3 -c "import json,sys; print(json.dumps({'hook_event_name':'UserPromptSubmit','prompt':sys.argv[1]}))" "$1" \
    | CLAUDE_PROJECT_DIR="${2:-$P}" bash "$HOOK" 2>/dev/null
}
has() { grep -qF -- "$2" <<<"$1" && echo 1 || echo 0; }
O="$(run '@"백로그 관리자 · 기획/리드/공통 · hag:backlog-manager" 백로그 정리해')"
assert "골라 넣은 줄 → 넘기기 지시" 1 "$(has "$O" '[hag:call]')"
assert "  subagent_type=backlog-manager" 1 "$(has "$O" 'subagent_type=backlog-manager')"
assert "  이름" 1 "$(has "$O" '백로그 관리자')"
assert "  명부 표는 안 붙임" 0 "$(has "$O" '[hag:list]')"
O="$(run '@hag:gate-qa 이거 봐줘')"
assert "따옴표 없는 @hag:<slug> 도" 1 "$(has "$O" 'subagent_type=gate-qa')"
O="$(run '@hag:old-hand 봐줘')"
assert "은퇴자 slug → 넘기지 않음" 0 "$(has "$O" 'subagent_type=old-hand')"
O="$(run '@hag')"
assert "@hag 만 → 명부 표" 1 "$(has "$O" '[hag:list]')"
assert "  표에 호출" 1 "$(has "$O" '@agent-gate-qa')"
assert "@hag + 말(고른 항목 없음) → 0 B (논의 오인 방지)" 0 "$(run '@hag 로 하나 골랐어. 그러면 골라져야해' | wc -c | tr -d ' ')"
assert "백틱 안은 무시" 0 "$(run '아니 `@hag` 는 왜 안 돼' | wc -c | tr -d ' ')"
assert "메일 주소 무시" 0 "$(run 'me@hag.com 로' | wc -c | tr -d ' ')"
assert "붙은 말(@hagfile) 무시" 0 "$(run '@hagfile 봐' | wc -c | tr -d ' ')"
assert "hermes 아님 → 0 B" 0 "$(run '@hag' "$Q" | wc -c | tr -d ' ')"
bash "$HOOK" </dev/null >/dev/null 2>&1; assert "빈 입력 exit 0" 0 "$?"

echo "== 3. 설정 생성"
SFS() { PYTHONPATH="$REPO_ROOT/lib" python3 -c "
import json, sys
from settings_file_suggestion import apply_file_suggestion
existing = json.loads(sys.argv[1]); cmd = sys.argv[2] or None
print(json.dumps(apply_file_suggestion(existing, cmd), ensure_ascii=False, sort_keys=True))" "$1" "$2"; }
OURS='python3 "${CLAUDE_PROJECT_DIR}/scripts/hermes_file_suggest.py"'
O="$(SFS '{}' "$OURS")"
assert "없으면 넣는다" 1 "$(has "$O" 'hermes_file_suggest.py')"
assert "  type=command" 1 "$(has "$O" '"type": "command"')"
O="$(SFS '{"fileSuggestion":{"type":"command","command":"~/my.sh"}}' "$OURS")"
assert "사용자 것은 보존" 1 "$(has "$O" '~/my.sh')"
assert "  우리 것으로 덮지 않음" 0 "$(has "$O" 'hermes_file_suggest')"
O="$(SFS "$(SFS '{}' "$OURS")" '')"
assert "프리셋 빠지면 우리 것 걷음" 0 "$(has "$O" 'fileSuggestion')"
O="$(SFS '{"fileSuggestion":{"type":"command","command":"~/my.sh"}}' '')"
assert "프리셋 빠져도 사용자 것은 둠" 1 "$(has "$O" '~/my.sh')"
O="$(SFS '{"a":1}' "$OURS")"
assert "다른 키는 그대로" 1 "$(has "$O" '"a": 1')"

echo "== 자기 검사 — hag 분기를 끄면 1 이 빨개진다"
M="$T/mut.py"; sed 's/HAG_PREFIX = "hag"/HAG_PREFIX = "zzz-off"/' "$SUGGEST" > "$M"
O="$(python3 -c "import json; print(json.dumps({'query':'hag','cwd':'$P'}))" | PYTHONPATH="$REPO_ROOT/scripts" python3 "$M" 2>/dev/null)"
assert "변이 스크립트는 명부 줄을 내지 않는다" 0 "$(grep -c ' · hag:' <<<"$O")"

echo ""; echo "결과: $PASS 통과 / $FAIL 실패"
[[ $FAIL -eq 0 ]]
