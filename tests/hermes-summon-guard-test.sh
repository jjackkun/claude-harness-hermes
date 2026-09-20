#!/usr/bin/env bash
# 소환 토큰·러너·가드 검증 (계획 docs/exec-plans/active/2026-09-15-agent-identity.md 목표 5·6·7·16).
#
#   - 러너: summons 행 INSERT, HERMES_AGENT_ID·HERMES_SUMMON_NONCE 를 넣어 claude -p(모의) 실행,
#     task.assigned·task.finished(evidence.usage 포함) 기록, nonce 사용 표시 (목표 5)
#   - 시작 훅 검증 4케이스: ok · 짝 없음 · 재사용 · 만료 → 행위자 system:unverified-session (목표 6)
#   - 가드: 직접 claude -p 차단, 러너 경유 통과, 러너 이름 흉내는 pending 없어 차단 (목표 7)
#   - 구 스키마(summons 없음) DB 에서 훅 exit 0 + 표 생성 (목표 16)
#
# 실행: bash tests/hermes-summon-guard-test.sh

set -uo pipefail
export HARNESS_TOOL_INSTALL=0   # 설치기의 외부 도구 다운로드는 테스트에서 끈다(네트워크 0) — tests/tool-installers-test.sh 가 따로 실측

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$REPO_ROOT/scripts"
H="$REPO_ROOT/assets/hooks"
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

# 프로젝트 사본(설치본 배치): scripts/ 에 모듈, .hermes 에 키·명부·DB
P="$TMP/proj"; mkdir -p "$P/scripts" "$P/.hermes"
cp "$S"/*.py "$P/scripts/"; git -C "$P" init -q; git -C "$P" config user.name tester
PYTHONPATH="$S" python3 -c "from hermes_universe import ensure_universe_id as e; e('$P')"
python3 "$S/hermes-init.py" --project "$P" >/dev/null 2>&1
MAIN_ID="$(PYTHONPATH="$S" python3 -c 'from hermes_uuid7 import uuid7_str; print(uuid7_str())')"
printf '{"agents":[{"agent_id":"%s","name":"main","status":"active","created_by":"system:installer"}]}\n' "$MAIN_ID" > "$P/.hermes/agents.json"
DB="$P/.hermes/state.db"
q() { python3 -c "import sqlite3,sys;print(sqlite3.connect(sys.argv[1]).execute(sys.argv[2]).fetchone()[0])" "$DB" "$1" 2>/dev/null || echo err; }

# 모의 claude — 받은 환경변수를 기록하고 usage 를 담은 JSON 을 낸다
MOCK="$TMP/bin"; mkdir -p "$MOCK"
cat > "$MOCK/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n%s\n' "${HERMES_AGENT_ID:-none}" "${HERMES_SUMMON_NONCE:-none}" > "$MOCK_OUT"
# 시작 훅 흉내: 실제 세션이라면 SessionStart 가 여기서 토큰을 검증한다
echo '{"session_id":"mock-s1"}' | CLAUDE_PROJECT_DIR="$MOCK_PROJECT" bash "$MOCK_HOOK" 2>>"$MOCK_OUT.err"
printf '{"result":"OK","usage":{"input_tokens":12,"output_tokens":3}}'
EOF
chmod +x "$MOCK/claude"
export MOCK_OUT="$TMP/mock.out" MOCK_PROJECT="$P" MOCK_HOOK="$H/claude-sessionstart-summons-verify.sh"
SUMMON() { HERMES_CLAUDE_BIN="$MOCK/claude" python3 "$P/scripts/hermes-summon.py" --project "$P" "$@"; }

echo "== 1. 러너 (목표 5) =="
SUMMON run main --task "테스트 작업 한 줄" >"$TMP/run.out" 2>&1
assert "러너 종료 코드 0" 0 "$?"
assert "summons 행 1개" 1 "$(q "select count(*) from summons")"
# 계획 design-gaps-tier2 목표 1 — 매칭 근거를 task.assigned 에 남긴다 (creation-and-organization.md:59)
assert "이름 지정 소환 → match=by-name" 1 "$(q "select count(*) from journal_events where kind='task.assigned' and decision like 'match=by-name%'")"
assert "summons.agent_id = main" "$MAIN_ID" "$(q "select agent_id from summons")"
assert "HERMES_AGENT_ID 가 claude 에 전달됨" "$MAIN_ID" "$(sed -n 1p "$MOCK_OUT")"
NONCE="$(sed -n 2p "$MOCK_OUT")"
assert "HERMES_SUMMON_NONCE 가 전달됨(32자 hex)" 32 "${#NONCE}"
assert "task.assigned 기록(지시자 = 사람)" 1 "$(q "select count(*) from journal_events where kind='task.assigned' and requested_by='human:tester'")"
assert "task.finished 기록(행위자 = agent:main id)" 1 "$(q "select count(*) from journal_events where kind='task.finished' and actor='agent:$MAIN_ID'")"
assert "evidence.usage 가 남음(V-8 러너 경로)" 1 "$(q "select count(*) from journal_events where kind='task.finished' and evidence like '%input_tokens%'")"
assert "시작 훅이 토큰을 사용 표시(used_at)" 1 "$(q "select count(*) from summons where used_at is not null")"
assert "판정 파일 ok" ok "$(cat "$P/.hermes/summons/$NONCE.verdict")"
assert "pending 파일은 소비 후 삭제" 0 "$(ls "$P/.hermes/summons/"*.pending 2>/dev/null | wc -l)"
SUMMON run 없는사람 --task x >/dev/null 2>&1
assert "명부에 없는 이름은 거부" 1 "$?"
QA_ID="$(PYTHONPATH="$S" python3 -c 'from hermes_uuid7 import uuid7_str; print(uuid7_str())')"
python3 - "$P/.hermes/agents.json" "$QA_ID" <<'PY'
import json, sys
p, qid = sys.argv[1:3]; d = json.load(open(p))
d["agents"].append({"agent_id": qid, "name": "QA담당", "status": "active", "created_by": "human:tester",
                    "org": {"discipline": "QA", "rank": "담당", "unit": "공통"}})
json.dump(d, open(p, "w"), ensure_ascii=False)
PY
SUMMON run --discipline QA --task "축 매칭 소환" >/dev/null 2>&1
assert "축 매칭 소환 → match=discipline:QA chosen=QA담당 among=1" 1 "$(q "select count(*) from journal_events where kind='task.assigned' and decision='match=discipline:QA chosen=QA담당 among=1'")"
# 계획 design-gaps-tier2 목표 9 — 사람 없는 세션은 main 이 수행하고 "담당 없음" 제안을 남긴다 (creation-and-organization.md:103)
SUMMON run --discipline 디자인 --task "담당 없는 일" >/dev/null 2>&1; assert "대화형: 담당 없으면 ask 로 중단(rc 1)" 1 "$?"
HERMES_HEADLESS=1 SUMMON run --discipline 디자인 --task "담당 없는 일" >"$TMP/headless.out" 2>&1; assert "무인: rc 0" 0 "$?"
assert "무인: main 이 소환됨" "$MAIN_ID" "$(sed -n 1p "$MOCK_OUT")"
assert "무인: owner-proposal 기록" 1 "$(q "select count(*) from journal_events where kind='decision' and intent='owner-proposal discipline:디자인'")"
assert "무인: task.assigned 의 매칭 근거가 fallback=main" 1 "$(q "select count(*) from journal_events where kind='task.assigned' and decision like 'match=discipline:디자인 fallback=main%'")"
OP_OUT="$(echo '{"source":"startup"}' | CLAUDE_PROJECT_DIR="$P" bash "$H/claude-sessionstart-owner-proposals.sh" 2>&1)"
assert "시작 훅: 답 없는 제안 1건 알림" 1 "$(grep -c '담당 없음 제안 1건' <<<"$OP_OUT")"
assert "시작 훅: 영역이 보임" 1 "$(grep -c 'discipline:디자인' <<<"$OP_OUT")"
python3 "$P/scripts/hermes-agent.py" --project "$P" no-owner --discipline 디자인 >/dev/null 2>&1
assert "no-owner 로 답하면 훅이 조용" "" "$(echo '{"source":"startup"}' | CLAUDE_PROJECT_DIR="$P" bash "$H/claude-sessionstart-owner-proposals.sh" 2>&1)"

echo ""
echo "== 2. 시작 훅 4케이스 (목표 6) =="
V() { echo '{"session_id":"s-x"}' | CLAUDE_PROJECT_DIR="$P" HERMES_SUMMON_NONCE="$1" HERMES_AGENT_ID="$2" bash "$H/claude-sessionstart-summons-verify.sh" >"$TMP/v.out" 2>"$TMP/v.err"; echo "$?"; }
assert "재사용: exit 0(세션은 멈추지 않음)" 0 "$(V "$NONCE" "$MAIN_ID")"
assert "재사용: 판정 unverified:used" "unverified:used" "$(cat "$P/.hermes/summons/$NONCE.verdict")"
assert "재사용: stderr 경고" 1 "$(grep -c 'summons-verify WARN' "$TMP/v.err")"
V "deadbeef00000000deadbeef00000000" "$MAIN_ID" >/dev/null
assert "짝 없음: 판정 unverified:missing" "unverified:missing" "$(cat "$P/.hermes/summons/deadbeef00000000deadbeef00000000.verdict")"
ISSUED="$(SUMMON issue main)"; N2="${ISSUED##* }"
V "$N2" "01a0a991-0000-7000-8000-000000000000" >/dev/null
assert "다른 에이전트 id: unverified:mismatch" "unverified:mismatch" "$(cat "$P/.hermes/summons/$N2.verdict")"
python3 -c "
import sqlite3; c=sqlite3.connect('$DB'); c.execute(\"update summons set expires_at='2000-01-01T00:00:00Z' where nonce=?\", ('$N2',)); c.commit()"
V "$N2" "$MAIN_ID" >/dev/null
assert "만료: unverified:expired" "unverified:expired" "$(cat "$P/.hermes/summons/$N2.verdict")"
assert "소환 아닌 보통 세션: 훅 무동작·exit 0" 0 "$(echo '{}' | CLAUDE_PROJECT_DIR="$P" bash "$H/claude-sessionstart-summons-verify.sh" >/dev/null 2>&1; echo $?)"
# 기록기가 판정을 따르는가
assert "unverified 세션의 이력 행위자 = system:unverified-session" "system:unverified-session" "$(cd "$P" && HERMES_SUMMON_NONCE="$N2" HERMES_AGENT_ID="$MAIN_ID" HERMES_PROJECT_DIR="$P" PYTHONPATH="$S" python3 -c "
from hermes_journal import resolve_actor; print(resolve_actor()[0])")"
ISSUED="$(SUMMON issue main)"; N3="${ISSUED##* }"; V "$N3" "$MAIN_ID" >/dev/null
assert "ok 세션의 이력 행위자 = agent:<id>" "agent:$MAIN_ID" "$(cd "$P" && HERMES_SUMMON_NONCE="$N3" HERMES_AGENT_ID="$MAIN_ID" HERMES_PROJECT_DIR="$P" PYTHONPATH="$S" python3 -c "
from hermes_journal import resolve_actor; print(resolve_actor()[0])")"
assert "판정 파일 없는 nonce 는 믿지 않음" "system:unverified-session" "$(cd "$P" && HERMES_SUMMON_NONCE="ffff0000ffff0000ffff0000ffff0000" HERMES_AGENT_ID="$MAIN_ID" HERMES_PROJECT_DIR="$P" PYTHONPATH="$S" python3 -c "
from hermes_journal import resolve_actor; print(resolve_actor()[0])")"

echo ""
echo "== 2b. summons 테이블 쓰기 가드 (계획 design-coverage-gaps 목표 7) =="
W() { python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$1" | CLAUDE_PROJECT_DIR="$P" bash "$H/claude-pretooluse-summons-write-guard.sh" >/dev/null 2>"$TMP/w.err"; echo $?; }
assert "sqlite3 INSERT summons → 차단" 2 "$(W 'sqlite3 .hermes/state.db "INSERT INTO summons(nonce,agent_id) VALUES (\x27x\x27,\x27y\x27)"')"
assert "차단 문구 접두어" 1 "$(grep -c '^\[summons-write-guard BLOCK\]' "$TMP/w.err")"
assert "python 으로 UPDATE summons → 차단" 2 "$(W 'python3 -c "import sqlite3; sqlite3.connect(\".hermes/state.db\").execute(\"update summons set used=1\")"')"
assert "DELETE FROM summons → 차단" 2 "$(W 'sqlite3 .hermes/state.db "delete from summons"')"
assert "SELECT 는 통과" 0 "$(W 'sqlite3 .hermes/state.db "select count(*) from summons"')"
assert "따옴표 결합 우회(summ\"\"ons) → 차단" 2 "$(W 'sqlite3 .hermes/state.db "insert into summ""ons values (1)"')"
assert "백슬래시 결합 우회(sum\\mons) → 차단" 2 "$(W 'sqlite3 .hermes/state.db "insert into sum\\mons values (1)"')"
assert "러너 호출은 통과" 0 "$(W 'python3 scripts/hermes-summon.py run main --task "x"')"
assert "summons 와 무관한 INSERT 는 통과" 0 "$(W 'sqlite3 .hermes/state.db "insert into notes values (1)"')"
assert "산문(커밋 메시지의 summons + update-all) 은 통과" 0 "$(W 'git commit -m "summons 쓰기 가드 추가 — update-all 12/12 반영"')"
assert "표 이름 앞 main. 접두도 차단" 2 "$(W 'sqlite3 .hermes/state.db "UPDATE main.summons SET used=1"')"
assert "Bash 아닌 도구는 무시" 0 "$(python3 -c 'import json;print(json.dumps({"tool_name":"Write","tool_input":{"command":"insert into summons"}}))' | CLAUDE_PROJECT_DIR="$P" bash "$H/claude-pretooluse-summons-write-guard.sh" >/dev/null 2>&1; echo $?)"

echo ""
echo "== 3. claude -p 가드 (목표 7) =="
G() { python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$1" | CLAUDE_PROJECT_DIR="$P" bash "$H/claude-pretooluse-summon-guard.sh" >/dev/null 2>"$TMP/g.err"; echo $?; }
rm -f "$P/.hermes/summons/"*.pending
assert "직접 claude -p 차단" 2 "$(G 'claude -p "hello"')"
assert "차단 문구 접두어" 1 "$(grep -c '^\[summon-guard BLOCK\]' "$TMP/g.err")"
assert "claude --print 도 차단" 2 "$(G 'claude --print hi')"
assert "러너 경유(hermes-summon.py run)는 통과" 0 "$(G 'python3 scripts/hermes-summon.py run main --task x')"
assert "hermes-loop-run.sh 호출은 통과" 0 "$(G 'scripts/hermes-loop-run.sh . "목표"')"
assert "러너 이름 흉내 + claude -p 는 pending 없어 차단" 2 "$(G 'bash -c "exec scripts/hermes-loop-run.sh . x; claude -p y"')"
assert "따옴표 안 claude -p 언급(커밋 메시지)은 통과" 0 "$(G 'git commit -m "claude -p 가드 추가"')"
SUMMON issue main >/dev/null          # 러너가 pending 을 남긴 상태
assert "pending 토큰이 있으면 claude -p 통과(러너가 띄우는 중)" 0 "$(G 'claude -p "hello"')"
rm -f "$P/.hermes/summons/"*.pending
assert "Bash 아닌 도구는 무시" 0 "$(python3 -c 'import json;print(json.dumps({"tool_name":"Write","tool_input":{"command":"claude -p"}}))' | CLAUDE_PROJECT_DIR="$P" bash "$H/claude-pretooluse-summon-guard.sh" >/dev/null 2>&1; echo $?)"

echo ""
echo "== 4. 구 스키마 호환 (목표 16) =="
OLD="$TMP/old"; mkdir -p "$OLD/scripts" "$OLD/.hermes"; cp "$S"/*.py "$OLD/scripts/"
python3 -c "
import sqlite3; c=sqlite3.connect('$OLD/.hermes/state.db'); c.execute('create table x(a)'); c.commit()"
assert "summons 없는 DB 에서 훅 exit 0" 0 "$(echo '{"session_id":"o"}' | CLAUDE_PROJECT_DIR="$OLD" HERMES_SUMMON_NONCE=abc HERMES_AGENT_ID=x bash "$H/claude-sessionstart-summons-verify.sh" >/dev/null 2>&1; echo $?)"
assert "첫 실행이 summons 표를 만든다" 1 "$(python3 -c "import sqlite3;print(sqlite3.connect('$OLD/.hermes/state.db').execute(\"select count(*) from sqlite_master where name='summons'\").fetchone()[0])")"
assert "판정은 missing(표는 있으나 행 없음)" "unverified:missing" "$(cat "$OLD/.hermes/summons/abc.verdict")"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
