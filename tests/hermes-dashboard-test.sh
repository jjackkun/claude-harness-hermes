#!/usr/bin/env bash
# 대시보드 데이터 수집 (계획 2026-09-18-hermes-dashboard 목표 2~6) — 픽스처 소우주에서 dict 를 직접 단언한다(렌더 무관).
# 소환 토큰은 러너 API(hermes_summons.issue)로 발급한다 — 세션 안 직접 쓰기 금지(RV-06)를 픽스처도 지킨다.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"; S="$REPO_ROOT/scripts"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/fakehome"; mkdir -p "$HOME"
PASS=0; FAIL=0
assert() { if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; PASS=$((PASS+1)); else echo "  ✗ $1 (expected=$2 actual=$3)"; FAIL=$((FAIL+1)); fi; }
P="$TMP/proj"; mkdir -p "$P/.hermes" "$P/.harness" "$P/.claude" "$P/docs/exec-plans/active"; git -C "$P" init -q; git -C "$P" config user.name tester
python3 "$S/hermes-init.py" --project "$P" >/dev/null 2>&1; DB="$P/.hermes/state.db"
PYTHONPATH="$S" python3 -c "from hermes_universe import ensure_universe_id as e; e('$P')"
cat > "$P/.hermes/organization.yaml" <<'EOF2'
discipline: [백엔드, QA]
rank: [리드, 담당]
unit:
  users: {}
EOF2
py() { PYTHONPATH="$S" python3 -c "$1"; }
py "from hermes_org import ensure_unit_ids; ensure_unit_ids('$P')
from hermes_roster import load_roster, add_agent, save_roster, transition
from hermes_org import load_org
org=load_org('$P'); r=load_roster('$P')
for n,o in (('리드A',('백엔드','리드','users')),('담당B',('백엔드','담당','users')),('옛담당',('QA','담당','users'))):
    add_agent(r, n, dict(zip(('discipline','rank','unit'),o)), org, 'human:tester')
transition(r, '옛담당', 'retire', 'human:tester'); save_roster('$P', r)"
ID() { python3 -c "import json;print([a['agent_id'] for a in json.load(open('$P/.hermes/agents.json'))['agents'] if a['name']=='$1'][0])"; }
LA="$(ID 리드A)"; DB_="$(ID 담당B)"
touch "$P/ok.txt"
py "from hermes_handoff import open_handoff, resolve
h1=open_handoff('$DB','$P','agent:$DB_',{'goal':'열린 일','done_when':'file:ok.txt'},by='human:tester')
h2=open_handoff('$DB','$P','agent:$DB_',{'goal':'막힌 일','done_when':'file:ok.txt'},by='human:tester')
resolve('$DB','$P',h2,'question','agent:$DB_',reason='inputs 부족')"
py "import sqlite3
from hermes_memory_events import record, ensure_memory_schema
from hermes_uuid7 import uuid7_str
from hermes_summons import issue
con=sqlite3.connect('$DB'); ensure_memory_schema(con)
for i in range(3):
    record(con, {'memory_id': uuid7_str(), 'agent_id': '$DB_', 'universe_id': 'u', 'ts': '2026-09-20T0%d:00:00' % i, 'kind': 'memory.added', 'about': 'gate/r-size', 'body': '지적 %d' % i, 'source_event': 'review:x%d:corrected:agent:$LA' % i})
for i in range(12):
    issue(con, '$P', '$DB_', 'human:tester')
con.execute(\"INSERT INTO skill_index (skill_path, keywords, scope) VALUES ('/s/a.md','a','local')\")
con.execute(\"INSERT INTO skill_index (skill_path, keywords, scope) VALUES ('/s/b.md','b','local')\")
for i in range(55): con.execute(\"INSERT INTO skill_injection (session_id, skill_path, correlated) VALUES ('s', '/s/a.md', 0)\")
for i in range(5):  con.execute(\"INSERT INTO skill_injection (session_id, skill_path, correlated) VALUES ('s', '/s/b.md', 1)\")
con.execute(\"INSERT INTO pattern_count (pattern_key, count, crystallized) VALUES ('세 번 본 패턴', 4, 0)\")
con.execute(\"INSERT INTO pattern_count (pattern_key, count, crystallized) VALUES ('굳은 패턴', 5, 1)\")
con.execute(\"INSERT INTO session_summary (session_id, project_id, slots_json) VALUES ('s1','p','{}')\")
con.execute(\"INSERT INTO dream_log (run_at, summary_count, crystallized, evolved) VALUES ('2026-09-19T01:00:00Z', 3, 1, 2)\")
con.execute(\"INSERT INTO dream_log (run_at, summary_count, crystallized, evolved) VALUES ('2026-09-20T01:00:00Z', 4, 0, 1)\")
con.commit()"
touch "$P/.hermes/dream-last-run"
for i in $(seq 1 20); do r=$([ $((i % 4)) -eq 0 ] && echo warn || echo pass); echo "{\"ts\": $i, \"rule\": \"R-size\", \"verdict\": \"$r\"}"; done > "$P/.harness/gate-events.jsonl"
for i in 1 2 3; do echo "{\"ts\": 30, \"rule\": \"R-lint\", \"verdict\": \"block\"}"; done >> "$P/.harness/gate-events.jsonl"
printf 'first: 2026-09-20 14:00:00  %s/scripts/x.py\nedit: 14:01:00  %s/scripts/x.py\nedit: 14:02:00  %s/scripts/y.py\n' "$P" "$P" "$P" > "$P/.claude/.review-dirty"
touch "$P/docs/exec-plans/active/2026-09-20-a.md" "$P/docs/exec-plans/active/2026-09-21-b.md"
echo "{\"remote_url\": \"x\", \"installed_version\": \"$(git -C "$REPO_ROOT" rev-parse HEAD)\"}" > "$P/.hermes/factory.json"

D="$(PYTHONPATH="$S" python3 -c "import json,sys; from hermes_dashboard_data import collect; print(json.dumps(collect('$P'), ensure_ascii=False))")"
g() { python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(eval(sys.argv[2]))" "$D" "$1"; }
echo "== 에이전트 판 (목표 2) =="
assert "명부 3명(은퇴 포함)" 3 "$(g "len(d['agents']['roster'])")"
assert "은퇴자 status=retired" 1 "$(g "sum(1 for a in d['agents']['roster'] if a['status']=='retired')")"
assert "열린 인계 2건(question 도 열린 채)" 2 "$(g "len(d['agents']['open_handoffs'])")"
assert "그중 blocked 1" 1 "$(g "sum(1 for h in d['agents']['open_handoffs'] if h['blocked'])")"
assert "최근 소환 10건(12 중)" 10 "$(g "len(d['agents']['summons_recent'])")"
assert "담당 없음 제안 0" 0 "$(g "d['agents']['owner_proposals']")"
assert "about 별 corrected 누적(gate/r-size=3, 담당B)" "3 담당B" "$(g "str(d['agents']['corrections'][0]['count'])+' '+d['agents']['corrections'][0]['name']")"
echo "== 스킬 판 (목표 3) =="
assert "층별 개수 common=2" 2 "$(g "d['skills']['by_layer']['common']")"
assert "주입 상위 1 = a.md 55건" "/s/a.md 55" "$(g "d['skills']['top_injected'][0]['skill_path']+' '+str(d['skills']['top_injected'][0]['injected'])")"
assert "강등 후보 = a.md 1건(hermes_skill_yield 재사용)" "1 /s/a.md" "$(g "str(len(d['skills']['demote_candidates']))+' '+d['skills']['demote_candidates'][0]['skill_path']")"
assert "결정화 대기 1(count≥3·미결정화)" "세 번 본 패턴" "$(g "d['skills']['pending_crystallize'][0]['key']")"
echo "== 학습 루프 판 (목표 4) =="
assert "요약 수 1" 1 "$(g "d['learning']['summaries']")"
assert "드림 2회 · 마지막 2026-09-20T01:00:00Z" "2 2026-09-20T01:00:00Z" "$(g "str(d['learning']['dream_runs'])+' '+d['learning']['last_dream']")"
assert "진화 합 3" 3 "$(g "d['learning']['evolved']")"
assert "다음 드림 가능 시각 있음(마커+20h)" 1 "$(g "1 if d['learning']['next_dream_at'] else 0")"
echo "== 건강 판 (목표 5) =="
assert "게이트 발화율 1위 R-lint(100%)" "R-lint 100.0%" "$(g "d['health']['gates_top'][0]['rule']+' '+d['health']['gates_top'][0]['rate']")"
assert "R-size 발화율 25.0%" "25.0%" "$(g "[r['rate'] for r in d['health']['gates_top'] if r['rule']=='R-size'][0]")"
assert "리뷰 빚 파일 2" 2 "$(g "len(d['health']['review_debt'])")"
assert "활성 계획 2" 2 "$(g "len(d['health']['active_plans'])")"
echo "== 우주 (목표 6) =="
REG="$TMP/reg"; NOH="$TMP/nohermes"; mkdir -p "$NOH"; printf '%s\n%s\n' "$P" "$NOH" > "$REG"
U="$(PYTHONPATH="$S" python3 -c "import json; from hermes_dashboard_data import collect_universe; print(json.dumps(collect_universe('$REPO_ROOT','$REG'), ensure_ascii=False))")"
gu() { python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(eval(sys.argv[2]))" "$U" "$1"; }
assert "행 2" 2 "$(gu "len(d)")"
assert "미설치 표시" False "$(gu "d[1]['installed']")"
assert "설치 소우주: 에이전트 2(은퇴 제외)·스킬 2·강등 1" "2 2 1" "$(gu "str(d[0]['agents'])+' '+str(d[0]['skills'])+' '+str(d[0]['demote_candidates'])")"
assert "factory_commit 일치" True "$(gu "d[0]['factory_match']")"
echo "== DB 없는 소우주 (목표 1 전제) =="
E="$TMP/empty"; mkdir -p "$E/.hermes"
assert "db_missing=True, 판은 비어도 죽지 않음" True "$(PYTHONPATH="$S" python3 -c "from hermes_dashboard_data import collect; print(collect('$E')['db_missing'])")"
echo "== HTML 생성 (목표 1·6) =="
# 승격 후보 칸 재료 — 같은 교훈이 두 계획서에 (계획 2026-09-22-rule-candidates-dashboard)
mkdir -p "$P/docs/exec-plans/completed"
printf '## 8. 회고\n- 다음 룰 후보: 훅 순서를 바꾸면 뒤 단계가 조용히 건너뛰는지 본다 — 1건\n' > "$P/docs/exec-plans/completed/2026-09-20-x.md"
printf '## 8. 회고\n- 다음 룰 후보: 훅 순서를 바꾸면 뒤 단계가 조용히 건너뛰는지 본다 — 2번째 사례\n' > "$P/docs/exec-plans/completed/2026-09-21-y.md"
echo "낡은 페이지" > "$P/.hermes/dashboard.html"   # 옛 경로에 남은 대시보드
python3 "$S/hermes-dashboard.py" --project-dir "$P" >/dev/null; assert "CLI rc 0" 0 "$?"
assert "옛 경로(.hermes/dashboard.html)의 낡은 페이지는 지운다" 0 "$([[ -f "$P/.hermes/dashboard.html" ]] && echo 1 || echo 0)"
H="$P/.hermes/dashboards/dashboard.html"
assert "dashboard.html 생성" 1 "$([[ -f "$H" ]] && echo 1 || echo 0)"
assert "외부 스크립트·스타일 0" 0 "$(grep -cE '<script src|<link href' "$H")"
assert "모델 호출 흔적 0" 0 "$(grep -ci 'claude' "$H")"
assert "명부 이름·은퇴 표시" "1 1" "$(grep -c '담당B' "$H") $(grep -c '>retired<' "$H")"
assert "막힌 인계 표시" 1 "$(grep -c '>막힘<' "$H")"
assert "지적 누적 about" 1 "$(grep -c 'gate/r-size' "$H")"
assert "강등 후보 a.md" 1 "$(grep -c '>a.md<' "$H")"
assert "게이트 R-lint" 1 "$(grep -c 'R-lint' "$H")"
assert "다크 모드 토큰" 1 "$(grep -c 'prefers-color-scheme:dark' "$H")"
assert "다섯째 칸: 승격 후보" 1 "$(grep -c 'id="rules"' "$H")"
assert "두 번 나온 교훈은 검토 필요로 보인다" 1 "$(grep -c '훅 순서를 바꾸면' "$H")"
assert "검토 필요 표지" 1 "$([[ $(grep -c '검토 필요' "$H") -ge 1 ]] && echo 1 || echo 0)"
python3 "$S/hermes-dashboard.py" --universe --factory "$REPO_ROOT" --registry "$REG" >/dev/null; assert "우주 CLI rc 0" 0 "$?"
UH="$REPO_ROOT/.hermes/dashboards/universe-dashboard.html"
assert "universe-dashboard.html 생성" 1 "$([[ -f "$UH" ]] && echo 1 || echo 0)"
assert "미설치 소우주 표시" 1 "$(grep -c '>미설치<' "$UH")"
assert "factory 일치 표시" 1 "$(grep -c '>일치<' "$UH")"
E2="$TMP/empty2"; mkdir -p "$E2/.hermes"; python3 "$S/hermes-dashboard.py" --project-dir "$E2" >/dev/null
assert "DB 없는 소우주도 HTML 생성 + 안내" 1 "$(grep -c 'state.db 가 없다' "$E2/.hermes/dashboards/dashboard.html")"

echo "== 세션 시작 훅 — 하루 1회 (목표 7) =="
HOOK="$REPO_ROOT/assets/hooks/claude-sessionstart-dashboard.sh"; MK="$P/.hermes/dashboard-last-run"; rm -f "$MK" "$P/.hermes/dashboards/dashboard.html"; : > "$P/.hermes/hooks.log"
OUT="$(echo '{"source":"startup"}' | HERMES_DASHBOARD_SYNC=1 CLAUDE_PROJECT_DIR="$P" bash "$HOOK")"; RC=$?
assert "startup: rc 0 · stdout 무출력" "0 " "$RC $OUT"
assert "startup: 마커 생성 + HTML 생성" "1 1" "$([[ -f "$MK" ]] && echo 1 || echo 0) $([[ -f "$P/.hermes/dashboards/dashboard.html" ]] && echo 1 || echo 0)"
rm -f "$P/.hermes/dashboards/dashboard.html"
echo '{"source":"startup"}' | HERMES_DASHBOARD_SYNC=1 CLAUDE_PROJECT_DIR="$P" bash "$HOOK" >/dev/null
assert "마커 24h 이내 → throttle 로 미실행" "1 0" "$(grep -c 'skip:throttle' "$P/.hermes/hooks.log") $([[ -f "$P/.hermes/dashboards/dashboard.html" ]] && echo 1 || echo 0)"
touch -d '-25 hours' "$MK"
echo '{"source":"resume"}' | HERMES_DASHBOARD_SYNC=1 CLAUDE_PROJECT_DIR="$P" bash "$HOOK" >/dev/null
assert "25h 지나면 resume 에서 다시 생성" 1 "$([[ -f "$P/.hermes/dashboards/dashboard.html" ]] && echo 1 || echo 0)"
echo '{"source":"clear"}' | HERMES_DASHBOARD_SYNC=1 CLAUDE_PROJECT_DIR="$P" bash "$HOOK" >/dev/null
assert "clear 는 source 게이트에서 건너뜀" 1 "$(grep -c 'skip:source' "$P/.hermes/hooks.log")"
echo '{"source":"startup"}' | HERMES_DASHBOARD_ON_SESSION_START=0 CLAUDE_PROJECT_DIR="$P" bash "$HOOK" >/dev/null; assert "끄기 변수 존중(rc 0)" 0 "$?"

echo; echo "hermes-dashboard: PASS=$PASS FAIL=$FAIL"; [[ $FAIL -eq 0 ]]
