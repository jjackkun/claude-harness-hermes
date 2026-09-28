#!/usr/bin/env bash
# 올리기 전 묻기 (계획 docs/exec-plans/active/2026-09-28-carry-agent-knowledge.md 목표 2 · 3).
#
#   1 요약 판정: 요약 호출이 돌려준 flagged 항목 → 검토 대기 · flagged 칸이 없거나 짝이 안 맞으면 기록 없이(묶음 판정이 다시)
#   2 묶음 판정: 기억·이력·스킬 문장 — 표시된 것만 대기, 나머지 clean · 실패한 묶음은 반씩 다시 · 끝내 실패하면 기록 없이(다음에 다시)
#   3 사람 결정: list 가 대기를 보인다 · decide keep/drop · 사람 결정은 기계 판정이 덮지 않는다 · 기억 drop → memory.retracted 추가
#
# 모델 호출은 가짜 claude(답을 $FAKE_OUT 파일에서 읽음)로 대신한다 — 사용량 0.
# 실행: bash tests/hermes-privacy-review-test.sh

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$REPO_ROOT/scripts"
PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo "  ✓ $desc"; PASS=$((PASS+1))
  else echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1)); fi
}
has() { grep -qF -- "$2" <<<"$1" && echo 1 || echo 0; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME"

BIN="$T/bin"; mkdir -p "$BIN"; export FAKE_OUT="$T/fake.out"; export FAKE_RC="$T/fake.rc"
cat > "$BIN/claude" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
[[ -f "$FAKE_RC" ]] && exit "$(cat "$FAKE_RC")"
cat "$FAKE_OUT"
EOF
chmod +x "$BIN/claude"; export PATH="$BIN:$PATH"

P="$T/p"; mkdir -p "$P/.hermes"; git -C "$P" init -q; git -C "$P" config user.name tester
DB="$P/.hermes/state.db"; python3 "$S/hermes-init.py" --db "$DB" >/dev/null 2>&1
q() { python3 -c "import sqlite3,sys; r=sqlite3.connect(sys.argv[1]).execute(sys.argv[2]).fetchone(); print('' if r is None or r[0] is None else r[0])" "$DB" "$1"; }
TR="$T/tr.jsonl"
printf '%s\n' '{"type":"user","message":{"role":"user","content":"회의"}}' '{"type":"assistant","message":{"role":"assistant","content":"네"}}' > "$TR"

echo "== 1. 요약 판정"
echo '{"decisions":["배포는 금요일"],"open":[],"prefs":[],"facts":["요즘 허리가 아프다"],"next":[],"flagged":["요즘 허리가 아프다"]}' > "$FAKE_OUT"
python3 "$S/hermes-summarize.py" --db "$DB" --transcript "$TR" --session-id s1 --project-dir "$P" >/dev/null 2>&1
assert "걸린 항목은 검토 대기" pending "$(q "SELECT status FROM privacy_review WHERE text='요즘 허리가 아프다'")"
assert "걸리지 않은 새 항목은 clean" clean "$(q "SELECT status FROM privacy_review WHERE text='배포는 금요일'")"
assert "요약 자체는 저장된다(로컬 DB)" 1 "$(q "SELECT COUNT(*) FROM session_summary WHERE session_id='s1'")"
echo '{"decisions":["배포는 금요일","새 결정"],"open":[],"prefs":[],"facts":[],"next":[]}' > "$FAKE_OUT"
printf '%s\n' '{"type":"user","message":{"role":"user","content":"하나 더"}}' >> "$TR"
python3 "$S/hermes-summarize.py" --db "$DB" --transcript "$TR" --session-id s1 --project-dir "$P" >/dev/null 2>&1
assert "flagged 칸 없음 → 새 항목은 기록 없음(내보내지 않고 묶음 판정이 다시)" "" "$(q "SELECT status FROM privacy_review WHERE text='새 결정'")"
assert "flagged 칸 없음 → 이전 항목은 그대로" clean "$(q "SELECT status FROM privacy_review WHERE text='배포는 금요일'")"
echo '{"decisions":["배포는 금요일","새 결정","셋째 결정"],"open":[],"prefs":[],"facts":["점심 뭐 먹지"],"next":[],"flagged":["  \"점심 뭐 먹지\" "]}' > "$FAKE_OUT"
printf '%s\n' '{"type":"user","message":{"role":"user","content":"셋"}}' >> "$TR"
python3 "$S/hermes-summarize.py" --db "$DB" --transcript "$TR" --session-id s1 --project-dir "$P" >/dev/null 2>&1
assert "공백·따옴표가 달라도 걸린 문장은 대기" pending "$(q "SELECT status FROM privacy_review WHERE text='점심 뭐 먹지'")"
assert "짝이 맞으면 나머지 새 항목은 clean" clean "$(q "SELECT status FROM privacy_review WHERE text='셋째 결정'")"
echo '{"decisions":["넷째 결정"],"open":[],"prefs":[],"facts":[],"next":[],"flagged":["항목에 없는 문장"]}' > "$FAKE_OUT"
printf '%s\n' '{"type":"user","message":{"role":"user","content":"넷"}}' >> "$TR"
python3 "$S/hermes-summarize.py" --db "$DB" --transcript "$TR" --session-id s1 --project-dir "$P" >/dev/null 2>&1
assert "걸린 문장이 항목과 짝이 안 맞으면 새 항목은 기록 없음" "" "$(q "SELECT status FROM privacy_review WHERE text='넷째 결정'")"

echo "== 2. 묶음 판정"
J() { PYTHONPATH="$S" python3 -c "
import sqlite3,sys; from hermes_privacy_judge import judge_and_mark
c=sqlite3.connect('$DB'); print(judge_and_mark(c, [('memory','m1','$1'),('journal','j1','$2')]))"; }
echo '{"flagged":[0]}' > "$FAKE_OUT"
assert "새 문장 2개 판정" 2 "$(J "주말에 가족 여행" "인계는 금요일까지")"
assert "표시된 문장 → 대기" pending "$(q "SELECT status FROM privacy_review WHERE text='주말에 가족 여행'")"
assert "나머지 → clean" clean "$(q "SELECT status FROM privacy_review WHERE text='인계는 금요일까지'")"
assert "이미 판정한 문장은 다시 안 부른다" 0 "$(J "주말에 가족 여행" "인계는 금요일까지")"
echo 1 > "$FAKE_RC"
assert "호출 실패 → 판정 0" 0 "$(J "실패 문장 가" "실패 문장 나")"
assert "호출 실패 → 기록 없음(대기로 쌓지 않는다)" 0 "$(q "SELECT COUNT(*) FROM privacy_review WHERE text LIKE '실패 문장%'")"
assert "기록 없는 문장은 내보내기 허용 아님" False "$(PYTHONPATH="$S" python3 -c "
import sqlite3; from hermes_privacy_pending import allowed; print(allowed(sqlite3.connect('$DB'), '실패 문장 가'))")"
rm -f "$FAKE_RC"
assert "다음 번에 다시 판정된다" 2 "$(J "실패 문장 가" "실패 문장 나")"
# 반씩 다시: 묶음(2문장)일 때만 실패하고 한 문장씩이면 성공하는 가짜
cat > "$BIN/claude" <<'EOF'
#!/usr/bin/env bash
in="$(cat)"; n="$(grep -cE '^[0-9]+\. ' <<<"$in")"
[[ "$n" -gt 1 ]] && exit 1
echo '{"flagged":[]}'
EOF
chmod +x "$BIN/claude"
assert "묶음이 실패하면 반씩 나눠 다시 물어 판정한다" 2 "$(J "나눔 문장 가" "나눔 문장 나")"
assert "나눠 물은 문장은 clean" 2 "$(q "SELECT COUNT(*) FROM privacy_review WHERE text LIKE '나눔 문장%' AND status='clean'")"

echo "== 3. 사람 결정"
OUT="$(python3 "$S/hermes-privacy-review.py" --project "$P" list)"
assert "list 가 대기 문장을 보인다" 1 "$(has "$OUT" "요즘 허리가 아프다")"
N="$(grep "요즘 허리가 아프다" <<<"$OUT" | head -1 | awk '{print $1}')"
python3 "$S/hermes-privacy-review.py" --project "$P" decide "$N" keep >/dev/null
assert "keep → 둠" keep "$(q "SELECT status FROM privacy_review WHERE text='요즘 허리가 아프다'")"
PYTHONPATH="$S" python3 -c "
import sqlite3; from hermes_privacy_pending import mark
c=sqlite3.connect('$DB'); mark(c,'summary','s1','요즘 허리가 아프다','pending'); c.commit()"
assert "사람 결정은 기계 판정이 덮지 않는다" keep "$(q "SELECT status FROM privacy_review WHERE text='요즘 허리가 아프다'")"
PYTHONPATH="$S" python3 -c "
import sqlite3; from hermes_memory_events import record
c=sqlite3.connect('$DB')
record(c, {'memory_id':'mem-1','kind':'memory.added','agent_id':'ag','universe_id':'u','ts':'2026-09-28T00:00:00Z','about':'x','body':'주말에 가족 여행'})"
PYTHONPATH="$S" python3 -c "
import sqlite3; c=sqlite3.connect('$DB'); c.execute(\"UPDATE privacy_review SET ref='mem-1' WHERE text='주말에 가족 여행'\"); c.commit()"
H="$(q "SELECT hash FROM privacy_review WHERE text='주말에 가족 여행'")"
python3 "$S/hermes-privacy-review.py" --project "$P" decide "${H:0:8}" drop >/dev/null
assert "drop → 지움" drop "$(q "SELECT status FROM privacy_review WHERE text='주말에 가족 여행'")"
assert "기억 drop → memory.retracted 가 더해진다" 1 "$(q "SELECT COUNT(*) FROM memory_events WHERE kind='memory.retracted' AND revises='mem-1'")"
assert "없는 해시 → 실패" 1 "$(python3 "$S/hermes-privacy-review.py" --project "$P" decide zzzzzzzz keep >/dev/null 2>&1; echo $?)"
assert "번호로는 고르지 않는다" 1 "$(python3 "$S/hermes-privacy-review.py" --project "$P" decide 1 keep >/dev/null 2>&1; echo $?)"

echo
echo "결과: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
