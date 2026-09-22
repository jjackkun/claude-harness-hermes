#!/usr/bin/env bash
# 사용자 성향 추출 Step 1 — 대화 기록에서 사람의 말만 증분으로 뽑는다.
#
# 배경: ~/.claude/projects/*/*.jsonl 5,006개 중 entrypoint=sdk-cli 4,895개는 헤르메스가 띄운
# 한 턴짜리 기계 프롬프트다(요약기·결정화·드리밍). 사람 대화는 entrypoint=cli 뿐이다.
# 근거: docs/exec-plans/active/2026-09-22-user-persona-distill-plan.md §7
#
# 실행: bash tests/hermes-persona-source-test.sh
# 종료 코드: 0 = 모든 단언 통과, 1 = 실패

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  ✓ $desc"; PASS=$((PASS+1))
  else
    echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1))
  fi
}

# 기록 한 줄을 만든다: rec <entrypoint> <content(JSON 값)> [isMeta]
rec() {
  python3 -c 'import json,sys
ep, content, meta = sys.argv[1], json.loads(sys.argv[2]), sys.argv[3] == "1"
print(json.dumps({"type": "user", "entrypoint": ep, "isMeta": meta, "sessionId": "s1",
                  "timestamp": "2026-09-22T01:00:00Z", "message": {"role": "user", "content": content}},
                 ensure_ascii=False))' "$1" "$2" "${3:-0}"
}

T="$TMP/proj/a.jsonl"; mkdir -p "$TMP/proj"
{
  rec cli '"폼 질문을 연달아 띄우지 마"'
  rec sdk-cli '"다음은 진행 중인 대화의 직전 요약(5슬롯 JSON)"'
  rec cli '"<command-name>/clear</command-name>"'
  rec cli '"<task-notification>\n<task-id>x</task-id>"'
  rec cli '"Another Claude session sent a message:"'
  rec cli '"[SYSTEM NOTIFICATION - NOT USER INPUT]"'
  rec cli '"This session is being continued from a previous conversation that ran out of context."'
  rec cli '"숨은 메타"' 1
  rec cli '[{"type": "tool_result", "content": "ok"}]'
  echo '{깨진 줄'
  echo '{"type": "assistant", "entrypoint": "cli", "message": {"content": "네"}}'
  rec cli '"끝난 작업은 묻지 말고 커밋해"'
} > "$T"

run() {  # run <path> <start_line> → "개수|끝줄|첫 발화"
  python3 - "$REPO_ROOT" "$1" "$2" <<'EOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("src", sys.argv[1] + "/scripts/hermes_persona_source.py")
src = importlib.util.module_from_spec(spec); spec.loader.exec_module(src)
utts, end = src.read_new_utterances(sys.argv[2], int(sys.argv[3]))
print(f"{len(utts)}|{end}|{utts[0]['text'] if utts else ''}")
EOF
}

echo "== 1. 사람의 말만 남긴다 =="
out=$(run "$T" 0)
assert "cli 문자열 발화 2개만 (기계·압축 요약·메타·도구결과·깨진 줄 제외)" "2" "$(echo "$out" | cut -d'|' -f1)"
assert "끝줄 = 파일 줄 수" "$(wc -l < "$T" | tr -d ' ')" "$(echo "$out" | cut -d'|' -f2)"
assert "첫 발화" "폼 질문을 연달아 띄우지 마" "$(echo "$out" | cut -d'|' -f3)"

echo "== 2. 증분 =="
end=$(echo "$out" | cut -d'|' -f2)
assert "두 번째 읽기는 새 발화 0" "0" "$(run "$T" "$end" | cut -d'|' -f1)"
rec cli '"평소 말투로 해줘"' >> "$T"
assert "한 줄 덧붙이면 새 발화 1" "1|평소 말투로 해줘" "$(run "$T" "$end" | cut -d'|' -f1,3)"

echo "== 3. 파일이 줄어들면 처음부터 =="
rec cli '"새로 쓴 파일"' > "$T"
assert "워터마크가 파일보다 길면 0 부터 다시" "1|1|새로 쓴 파일" "$(run "$T" 50)"

echo "== 4. 워터마크 저장 =="
out=$(python3 - "$REPO_ROOT" "$TMP/g.db" <<'EOF'
import importlib.util, sqlite3, sys
spec = importlib.util.spec_from_file_location("st", sys.argv[1] + "/scripts/hermes_persona_store.py")
st = importlib.util.module_from_spec(spec); spec.loader.exec_module(st)
con = sqlite3.connect(sys.argv[2]); st.ensure_schema(con); st.ensure_schema(con)
print(st.get_watermark(con, "/x.jsonl"))
st.set_watermark(con, "/x.jsonl", 7); st.set_watermark(con, "/x.jsonl", 9)
print(st.get_watermark(con, "/x.jsonl"))
EOF
)
assert "처음 보는 파일은 0" "0" "$(echo "$out" | sed -n 1p)"
assert "마지막으로 적은 값" "9" "$(echo "$out" | sed -n 2p)"

echo ""
echo "결과: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
