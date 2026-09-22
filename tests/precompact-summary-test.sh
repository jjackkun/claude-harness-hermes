#!/usr/bin/env bash
# PreCompact 훅 — 압축 직전에 5슬롯 요약을 한 번 더 남긴다 (계획 2026-09-21-precompact-summary).
#
#   (a) 요약 1행 — 픽스처 transcript 로 session_summary 가 는다(기존 요약기 재호출, 새 형식 없음)
#   (b) 비차단 — 훅 자체는 1초 안에 rc 0, 표준출력 0바이트(setsid 백그라운드)
#   (c) 전제 부재 — transcript 없음·DB 없음이면 조용히 rc 0, 부작용 0
#   (d) 마스킹 — CLAUDE_PROJECT_DIR 를 넘겨 `.env` 정답지 값이 요약에 원문으로 남지 않는다
#   (e) 설치 배선 — PRE_COMPACT_HOOKS 가 settings.json 의 PreCompact 로 생성된다
#
# `claude` 는 PATH 가짜 실행파일(요약기가 부른다). 실행: bash tests/precompact-summary-test.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ROOT/assets/hooks/claude-precompact-summary.sh"
PASS=0; FAIL=0
assert() { if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; PASS=$((PASS+1)); else echo "  ✗ $1 (expected=$2 actual=$3)"; FAIL=$((FAIL+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/home"
# 가짜 claude — 요약기가 5슬롯 JSON 을 받게 한다(hermes-pipeline-test 와 같은 방식)
cat > "$T/bin/claude" <<'MOCK'
#!/usr/bin/env bash
STDIN_PROMPT="$(cat 2>/dev/null || true)"   # 프롬프트는 stdin 으로 온다(계획 cli-prompt-via-stdin)
if printf '%s' "$* $STDIN_PROMPT" | grep -q '5슬롯 JSON'; then
  printf '%s' "$* $STDIN_PROMPT" >> "$HERMES_TEST_PROMPT_LOG"
  echo '{"decisions":["압축 직전 결정"],"open":["남은 일"],"prefs":[],"facts":["사실"],"next":[]}'
  exit 0
fi
echo SKIP
MOCK
chmod +x "$T/bin/claude"; export PATH="$T/bin:$PATH"
export HERMES_TEST_PROMPT_LOG="$T/claude-prompt.txt"; : > "$HERMES_TEST_PROMPT_LOG"

P="$T/proj"; mkdir -p "$P/scripts"
HOME="$T/home" python3 "$ROOT/scripts/hermes-init.py" --project "$P" >/dev/null 2>&1
DB="$P/.hermes/state.db"
cp -r "$ROOT/scripts" "$P/scripts-src" 2>/dev/null; rm -rf "$P/scripts"; mv "$P/scripts-src" "$P/scripts"
mkdir -p "$P/scripts/hooks"; cp "$HOOK" "$P/scripts/hooks/" 2>/dev/null
printf 'DB_PASSWORD=SUPERSECRETVALUE1\n' > "$P/.env"

TR="$P/transcript.jsonl"
python3 - "$TR" <<'PY'
import json, sys
def m(role, txt):
    return json.dumps({"type": role, "message": {"role": role, "content": [{"type": "text", "text": txt}]}})
lines = []
for i in range(3):
    lines.append(m("user", f"precompact 시험 상황 {i} — 비밀은 SUPERSECRETVALUE1 이다"))
    lines.append(m("assistant", f"precompact 규칙대로 진행합니다 {i}"))
open(sys.argv[1], "w").write("\n".join(lines))
PY

count_summary() { python3 -c "import sqlite3,sys;print(sqlite3.connect(sys.argv[1]).execute('SELECT COUNT(*) FROM session_summary').fetchone()[0])" "$DB"; }
run_hook() { # run_hook <json>
  printf '%s' "$1" | (cd "$P" && CLAUDE_PROJECT_DIR="$P" timeout 20 bash "$P/scripts/hooks/claude-precompact-summary.sh") 2>"$T/hook.err"
}

echo "[a] 요약 1행 증가"
before=$(count_summary)
run_hook "{\"transcript_path\":\"$TR\",\"session_id\":\"precompact-1\",\"trigger\":\"auto\"}" >/dev/null
for _ in $(seq 60); do [[ "$(count_summary)" -gt "$before" ]] && break; sleep 0.5; done
assert "session_summary 1행 증가" "$((before+1))" "$(count_summary)"
assert "그 세션 id 로 기록" "precompact-1" "$(python3 -c "import sqlite3,sys;r=sqlite3.connect(sys.argv[1]).execute(\"SELECT session_id FROM session_summary ORDER BY rowid DESC LIMIT 1\").fetchone();print(r[0] if r else '')" "$DB")"

echo "[b] 비차단"
start=$(date +%s%N)
out=$(run_hook "{\"transcript_path\":\"$TR\",\"session_id\":\"precompact-2\",\"trigger\":\"manual\"}")
rc=$?; ms=$(( ($(date +%s%N) - start) / 1000000 ))
assert "rc 0" "0" "$rc"
assert "표준출력 0바이트" "0" "$(printf '%s' "$out" | wc -c | tr -d ' ')"
assert "1초 안에 끝남" "yes" "$([[ $ms -lt 1000 ]] && echo yes || echo "no(${ms}ms)")"

echo "[c] 전제 부재는 조용히"
run_hook '{"transcript_path":"/nope/none.jsonl","session_id":"x"}' >/dev/null; assert "transcript 없음 rc 0" "0" "$?"
run_hook '{}' >/dev/null; assert "빈 입력 rc 0" "0" "$?"
NOP="$T/nodb"; mkdir -p "$NOP"
printf '{"transcript_path":"%s","session_id":"y"}' "$TR" | (cd "$NOP" && CLAUDE_PROJECT_DIR="$NOP" timeout 10 bash "$P/scripts/hooks/claude-precompact-summary.sh") >/dev/null 2>&1
assert "DB 없음 rc 0" "0" "$?"
assert "DB 없는 곳에 아무것도 안 만든다" "0" "$(ls -A "$NOP" 2>/dev/null | wc -l | tr -d ' ')"

echo "[d] 마스킹 경로 유지 — 모델에 들어가기 전에 가린다"
# 마스킹은 델타가 haiku 로 가기 전 경계에서 걸린다(hermes-summarize.messages_to_text).
# 그래서 "모델이 무엇을 받았는가" 를 본다 — 저장된 슬롯이 아니라.
assert "정답지 값이 모델 입력에 없다" "0" "$(grep -c 'SUPERSECRETVALUE1' "$HERMES_TEST_PROMPT_LOG" || true)"
assert "모델이 실제로 불렸다(빈 로그로 통과하지 않는다)" "yes" "$([[ -s "$HERMES_TEST_PROMPT_LOG" ]] && echo yes || echo no)"
# 자기 검사 — 정답지(.env)를 치우면 같은 값이 그대로 들어간다(시험에 이빨이 있는가)
rm -f "$P/.env"; : > "$HERMES_TEST_PROMPT_LOG"
run_hook "{\"transcript_path\":\"$TR\",\"session_id\":\"precompact-3\",\"trigger\":\"auto\"}" >/dev/null
for _ in $(seq 40); do [[ -s "$HERMES_TEST_PROMPT_LOG" ]] && break; sleep 0.5; done
assert "정답지 없으면 값이 그대로 간다(자기 검사)" "yes" "$(grep -q 'SUPERSECRETVALUE1' "$HERMES_TEST_PROMPT_LOG" && echo yes || echo no)"

echo "[e] 설치 배선"
grep -q 'PRE_COMPACT_HOOKS' "$ROOT/presets/workflow/hermes.conf"; assert "hermes.conf 가 PRE_COMPACT_HOOKS 로 등록" "0" "$?"
grep -q 'pre_compact' "$ROOT/lib/settings_gen.sh"; assert "settings_gen 이 배열을 넘긴다" "0" "$?"
grep -q '"PreCompact"' "$ROOT/lib/generate_settings_json.py"; assert "생성기가 PreCompact 이벤트를 만든다" "0" "$?"
grep -q 'claude-precompact-summary.sh' "$ROOT/presets/workflow/hermes.conf"; assert "복사 목록에 훅 파일" "0" "$?"

echo; echo "precompact-summary: PASS=$PASS FAIL=$FAIL"; [[ $FAIL -eq 0 ]]
