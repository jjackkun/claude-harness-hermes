#!/usr/bin/env bash
# 소환된 에이전트 정체성 주입 훅 검증 (계획 2026-09-17-summon-soul-injection 목표 1~4).
#
#   - 목표 1: HERMES_AGENT_ID + 정체성 폴더 → stdout 에 머리 줄 · SOUL 본문 · MEMORY 본문
#   - 목표 2: 환경변수 없음 · 폴더 없는 id · retired → stdout 빈 문자열, rc 0
#   - 목표 3: 10 KB SOUL → 4,096 B 이내로 잘리고 잘림 줄이 원문 경로를 가리킨다
#   - 목표 4: 명부 손상 · id 꼴 아님 → stdout 빈 문자열, rc 0 (세션은 서지 않는다)
#   - 자기 검사: 훅을 빈 파일로 바꾸면 목표 1 이 빨개진다 — 통과만 보는 검증 금지
#
# 실행: bash tests/hermes-soul-inject-test.sh

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$REPO_ROOT/assets/hooks/claude-sessionstart-agent-soul.sh"
PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo "  ✓ $desc"; PASS=$((PASS+1))
  else echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1)); fi
}

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
P="$T/proj"; mkdir -p "$P/.hermes/agents"
ID_ACTIVE="01a0ae58-6aa6-7202-ae81-7d27af7b5617"
ID_RETIRED="01a0ae58-6a84-75bd-8bfa-9c85c2ce2be4"
ID_NODIR="01a0ad8a-e5ff-7026-bedf-0bbf3df3d334"
cat > "$P/.hermes/agents.json" <<EOF
{"agents": [
  {"agent_id": "$ID_NODIR",   "name": "main",   "status": "active",  "org": {}},
  {"agent_id": "$ID_ACTIVE",  "name": "선적QA",  "status": "active",  "org": {"discipline": "QA"}},
  {"agent_id": "$ID_RETIRED", "name": "옛담당",  "status": "retired", "org": {"discipline": "QA"}}
]}
EOF
for id in "$ID_ACTIVE" "$ID_RETIRED"; do
  mkdir -p "$P/.hermes/agents/$id"
  printf '# 정체성\n\n## 역할\n선적 조회 화면의 회귀 테스트를 맡는다.\n' > "$P/.hermes/agents/$id/SOUL.md"
  printf '# 기억\n\n- 2026-09-17 회귀 테스트 3건 작성\n' > "$P/.hermes/agents/$id/MEMORY.md"
done

run() { # run <agent_id|""> → stdout 을 $OUT, rc 를 $RC 에
  local id="$1"; local errf="$T/err"
  if [[ -n "$id" ]]; then OUT="$(echo '{"session_id":"t"}' | HERMES_AGENT_ID="$id" HERMES_PROJECT_DIR="$P" bash "$HOOK" 2>"$errf")"; RC=$?
  else OUT="$(echo '{}' | env -u HERMES_AGENT_ID HERMES_PROJECT_DIR="$P" bash "$HOOK" 2>"$errf")"; RC=$?; fi
  ERR="$(cat "$errf")"
}

echo "[1] 목표 1 — 정체성 주입"
run "$ID_ACTIVE"
assert "rc 0" "0" "$RC"
assert "머리 줄에 이름·id" "1" "$(printf '%s' "$OUT" | grep -c "^\[헤르메스 출근\] 선적QA (agent:$ID_ACTIVE)")"
assert "SOUL 본문" "1" "$(printf '%s' "$OUT" | grep -c '선적 조회 화면의 회귀 테스트를 맡는다')"
assert "MEMORY 본문" "1" "$(printf '%s' "$OUT" | grep -c '회귀 테스트 3건 작성')"
assert "구획 머리 둘(SOUL·MEMORY)" "2" "$(printf '%s' "$OUT" | grep -cE '^--- (SOUL|MEMORY)\.md ---$')"
assert "stderr 무출력" "" "$ERR"

echo "[2] 목표 2 — 넣지 않는 경우"
run ""; assert "환경변수 없음 → 무출력" "" "$OUT"; assert "  rc 0" "0" "$RC"
run "$ID_NODIR"; assert "폴더 없는 id(main) → 무출력" "" "$OUT"; assert "  rc 0" "0" "$RC"
run "$ID_RETIRED"; assert "retired → 무출력" "" "$OUT"; assert "  rc 0" "0" "$RC"

echo "[3] 목표 3 — 상한과 잘림"
python3 -c "open('$P/.hermes/agents/$ID_ACTIVE/SOUL.md','w',encoding='utf-8').write('# 긴 정체성\n' + ('가나다라마바사아자차 ' * 500) + '\n끝표지\n')"
run "$ID_ACTIVE"
SOUL_PART="$(printf '%s' "$OUT" | awk '/^--- SOUL.md ---$/{f=1;next} /^--- MEMORY.md ---$/{f=0} f')"
assert "SOUL 구획 ≤ 4,096 B + 잘림 줄(≤ 4,300 B)" "1" "$(( $(printf '%s' "$SOUL_PART" | wc -c) <= 4300 ))"
assert "잘림 줄이 원문 경로를 가리킨다" "1" "$(printf '%s' "$SOUL_PART" | grep -c "잘림 .* B — 원문 .hermes/agents/$ID_ACTIVE/SOUL.md")"
assert "끝표지는 잘려 나감" "0" "$(printf '%s' "$SOUL_PART" | grep -c '끝표지')"
assert "MEMORY 는 그대로" "1" "$(printf '%s' "$OUT" | grep -c '회귀 테스트 3건 작성')"
assert "UTF-8 경계 보존(치환 문자 없음)" "0" "$(printf '%s' "$SOUL_PART" | grep -c $'\xef\xbf\xbd')"

echo "[4] 목표 4 — 세션은 서지 않는다"
cp "$P/.hermes/agents.json" "$T/agents.bak"; echo '{"agents": [' > "$P/.hermes/agents.json"
run "$ID_ACTIVE"; assert "명부 손상 → 무출력" "" "$OUT"; assert "  rc 0" "0" "$RC"; assert "  stderr 에 이유" "1" "$(printf '%s' "$ERR" | grep -c '명부를 읽지 못해')"
cp "$T/agents.bak" "$P/.hermes/agents.json"
run "../../etc"; assert "id 꼴 아님 → 무출력" "" "$OUT"; assert "  rc 0" "0" "$RC"
chmod 000 "$P/.hermes/agents/$ID_ACTIVE/SOUL.md"
run "$ID_ACTIVE"; assert "SOUL 읽기 권한 없음 → rc 0" "0" "$RC"; assert "  MEMORY 는 여전히 주입" "1" "$(printf '%s' "$OUT" | grep -c '회귀 테스트 3건 작성')"
chmod 644 "$P/.hermes/agents/$ID_ACTIVE/SOUL.md"

echo "[6] 읽기 전 재생성 — 쌓인 기억 이벤트가 MEMORY.md 로 보인다 (계획 agent-memory-roundtrip 목표 1)"
PYTHONPATH="$REPO_ROOT/scripts" python3 - "$P/.hermes/state.db" "$ID_ACTIVE" <<'PY'
import sqlite3, sys
from hermes_memory_events import record, ensure_memory_schema
from hermes_uuid7 import uuid7_str
con = sqlite3.connect(sys.argv[1]); ensure_memory_schema(con)
record(con, {"memory_id": uuid7_str(), "agent_id": sys.argv[2], "universe_id": "u", "ts": "2026-09-20T00:00:01",
             "kind": "memory.added", "about": "gate/r-size", "body": "400줄 넘기 전에 파일을 나눈다", "source_event": "review:x"})
con.commit(); con.close()
PY
run "$ID_ACTIVE"
assert "rc 0" "0" "$RC"
assert "이벤트 본문이 주입된다" "1" "$(printf '%s' "$OUT" | grep -c '400줄 넘기 전에')"
assert "손으로 쓴 옛 MEMORY 줄은 사라진다(파생물)" "0" "$(printf '%s' "$OUT" | grep -c '회귀 테스트 3건 작성')"
assert "MEMORY.md 파일도 갱신됨" "1" "$(grep -c '400줄 넘기 전에' "$P/.hermes/agents/$ID_ACTIVE/MEMORY.md")"

echo "[7] 선별 주입 — 핀 → 과제 관련 → 최근, 나머지는 파일에만 (계획 agent-teaching 목표 10)"
PYTHONPATH="$REPO_ROOT/scripts" python3 - "$P/.hermes/state.db" "$ID_ACTIVE" <<'PY'
import sqlite3, sys
from hermes_memory_events import record, ensure_memory_schema
from hermes_uuid7 import uuid7_str
con = sqlite3.connect(sys.argv[1]); ensure_memory_schema(con)
ids = []
for i in range(15):
    ids.append(record(con, {"memory_id": uuid7_str(), "agent_id": sys.argv[2], "universe_id": "u", "ts": "2026-09-20T01:%02d:00" % i,
                            "kind": "memory.added", "about": "workflow/item-%02d" % i, "body": "잡다한 기억 %02d" % i, "source_event": "t"}))
rel = record(con, {"memory_id": uuid7_str(), "agent_id": sys.argv[2], "universe_id": "u", "ts": "2026-09-20T00:00:00",
                   "kind": "memory.added", "about": "sync/keys", "body": "열쇠는 설치기가 다룬다", "source_event": "t"})
con.execute("INSERT INTO memory_pins (agent_id, memory_id, pinned_at) VALUES (?,?,?)", (sys.argv[2], ids[0], "2026-09-20T00:00:00Z"))
con.commit(); con.close()
PY
OUT="$(echo '{}' | HERMES_AGENT_ID="$ID_ACTIVE" HERMES_PROJECT_DIR="$P" HERMES_TASK_HINT="sync 열쇠 정리" bash "$HOOK" 2>"$T/err")"
assert "선별 머리말(선별 n/전체)" "1" "$(printf '%s' "$OUT" | grep -c '기억 (선별 [0-9]*/17')"
assert "핀은 항상(item-00)" "1" "$(printf '%s' "$OUT" | grep -c '잡다한 기억 00')"
assert "과제 관련(sync/keys) 포함" "1" "$(printf '%s' "$OUT" | grep -c '열쇠는 설치기가 다룬다')"
assert "최근 4 포함(item-14)" "1" "$(printf '%s' "$OUT" | grep -c '잡다한 기억 14')"
assert "오래된 무관 기억(item-03)은 주입 밖" "0" "$(printf '%s' "$OUT" | grep -c '잡다한 기억 03')"
assert "핀 절 · 관련 절 · 최근 절 머리" "3" "$(printf '%s' "$OUT" | grep -cE '^## (핀|이번 과제 관련|최근)$')"

echo "[5] 자기 검사 — 빈 훅이면 목표 1 이 빨개진다"
EMPTY="$T/empty-hook.sh"; printf '#!/usr/bin/env bash\nexit 0\n' > "$EMPTY"
OUT2="$(echo '{}' | HERMES_AGENT_ID="$ID_ACTIVE" HERMES_PROJECT_DIR="$P" bash "$EMPTY")"
assert "빈 훅은 정체성을 못 넣는다(대조)" "0" "$(printf '%s' "$OUT2" | grep -c '헤르메스 출근')"

echo
echo "hermes-soul-inject: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
