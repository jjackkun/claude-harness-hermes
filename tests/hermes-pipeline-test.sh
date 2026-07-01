#!/usr/bin/env bash
# 헤르메스 파이프라인 통합 테스트 — init → save-session → 패턴 집계 → 결정화 →
# 인덱싱 → 검색 → 진화 → Stop 훅 e2e → cleanup → cron-run 까지 전체 러닝 루프 검증.
#
# 격리 원칙:
#   - HOME 을 임시 디렉터리로 오버라이드 → 실 ~/.hermes (global.db) 절대 접근 금지
#   - 프로젝트 DB 는 임시 프로젝트 하위 .hermes/state.db
#   - `claude` 실행파일을 PATH 가짜 바이너리로 모킹 (MOCK_MODE=skip|normal|fail|evolve)
#
# 실행: bash tests/hermes-pipeline-test.sh
# 종료 코드: 0 = 모든 단언 통과, 1 = 실패

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$REPO_ROOT/scripts"

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export HOME="$T/fakehome"   # ~/.hermes 격리 — 실DB 보호
mkdir -p "$HOME" "$T/bin" "$T/proj"
PROJ="$T/proj"
DB="$PROJ/.hermes/state.db"

pass=0; fail=0
check() { # check <desc> <cond...>
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "  ✓ $desc"; pass=$((pass+1));
  else echo "  ✗ $desc"; fail=$((fail+1)); fi
}
sql() { python3 -c "
import sqlite3,sys
con=sqlite3.connect('$DB')
print(con.execute(sys.argv[1]).fetchone()[0])
" "$1"; }

# ── mock claude (PATH 가짜 실행파일) ──
cat > "$T/bin/claude" <<'EOF'
#!/usr/bin/env bash
# mock claude -p — MOCK_MODE=skip|normal|fail|evolve
# hermes-summarize 호출(프롬프트에 '5슬롯 JSON' 포함) → 고정 슬롯 JSON 출력
if printf '%s' "$*" | grep -q '5슬롯 JSON'; then
  echo '{"decisions":["A 먼저"],"open":["승인 대기"],"prefs":["비용 일정"],"facts":["Stop 훅 매 턴"],"next":["계획 작성"]}'
  exit 0
fi
# hermes-dream 결정화 후보 게이트 감지 — 고정 key 1개 반환
if printf '%s' "$*" | grep -q '결정화 후보 key'; then
  echo "dream-test-key"
  exit 0
fi
case "${MOCK_MODE:-normal}" in
  skip)   echo "SKIP" ;;
  fail)   echo "mock failure" >&2; exit 1 ;;
  evolve) cat <<'MD'
# hermes-pipeline-test
<!-- hermes:auto-generated version:2 created:2026-06-11 -->

## 문제 상황
진화 반영됨 — pnpm 으로 교체.

## 규칙
- [ ] pnpm 사용

## 근거
- 감지 횟수: 3회
- 패턴 키: hermes-pipeline-test
MD
  ;;
  *) cat <<'MD'
# hermes-pipeline-test
<!-- hermes:auto-generated version:1 created:2026-06-11 -->

## 문제 상황
파이프라인 테스트에서 반복된 가짜 실수.

## 규칙
- [ ] hermes-pipeline-test 절차를 먼저 확인한다

## 근거
- 감지 횟수: 3회
- 패턴 키: hermes-pipeline-test
MD
  ;;
esac
EOF
chmod +x "$T/bin/claude"
export PATH="$T/bin:$PATH"

echo "== 1. init =="
python3 "$S/hermes-init.py" --both "$PROJ" >/dev/null
check "project DB 생성" test -f "$DB"
check "fake global DB 생성 (HOME 격리)" test -f "$HOME/.hermes/global.db"
ss=$(python3 -c "import sqlite3;print(sqlite3.connect('$DB').execute(\"SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='session_summary'\").fetchone()[0])")
check "session_summary 테이블 생성" test "$ss" = "1"
rm_=$(python3 -c "import sqlite3;print(sqlite3.connect('$DB').execute(\"SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='recall_marker'\").fetchone()[0])")
check "recall_marker 테이블 생성" test "$rm_" = "1"
dlt=$(python3 -c "import sqlite3;print(sqlite3.connect('$DB').execute(\"SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='dream_log'\").fetchone()[0])")
check "dream_log 테이블 생성" test "$dlt" = "1"

echo ""
echo "== 2. save-session — 같은 session_id 2회 재저장 (행 누적 없음) =="
TR="$T/transcript.jsonl"
mkmsg() { python3 -c "
import json,sys
def m(t,txt): return json.dumps({'type':t,'message':{'role':t,'content':[{'type':'text','text':txt}]}})
uniq=sys.argv[3]
lines=[]
for i in range(int(sys.argv[2])):
    lines.append(m('user',f'{uniq} 상황에서 hermes-pipeline-test 절차 다시 확인 부탁 {i}'))
    lines.append(m('assistant',f'{uniq} 컨텍스트 hermes-pipeline-test 규칙대로 진행합니다 워크플로 점검 {i}'))
open(sys.argv[1],'w').write('\n'.join(lines))
" "$1" "$2" "$3"; }
mkmsg "$TR" 3 alpha

python3 "$S/hermes-save-session.py" --db "$DB" --transcript "$TR" --project-id proj --session-id sessA >/dev/null
n1=$(sql "SELECT COUNT(*) FROM session_history WHERE session_id='sessA'")
mkmsg "$TR" 4 alpha   # 다음 턴 — transcript 가 자람
python3 "$S/hermes-save-session.py" --db "$DB" --transcript "$TR" --project-id proj --session-id sessA >/dev/null
n2=$(sql "SELECT COUNT(*) FROM session_history WHERE session_id='sessA'")
sess_cnt=$(sql "SELECT COUNT(DISTINCT session_id) FROM session_history")
echo "  (sessA 1차=${n1}행, 재저장 후=${n2}행 — 8 기대, 세션수=${sess_cnt} — 1 기대)"
check "재저장 시 행 교체 (누적 없음)" test "$n2" = "8"
check "세션 1개 유지" test "$sess_cnt" = "1"
pc=$(sql "SELECT COALESCE((SELECT count FROM pattern_count WHERE pattern_key='hermes-pipeline-test'),0)")
check "같은 세션 재저장 시 패턴 중복 집계 없음 (<=1)" test "$pc" -le 1

echo ""
echo "== 3. 세션 4개 → 교차검증(>=2세션) + 임계(3) 도달 → CRYSTALLIZE 출력 =="
out=""
for sid in sessB sessC sessD; do
  mkmsg "$TR" 3 "uniq-$sid"
  out=$(python3 "$S/hermes-save-session.py" --db "$DB" --transcript "$TR" --project-id proj --session-id "$sid")
done
check "CRYSTALLIZE 트리거" bash -c "echo '$out' | grep -q 'CRYSTALLIZE:.*hermes-pipeline-test'"
pc=$(sql "SELECT count FROM pattern_count WHERE pattern_key='hermes-pipeline-test'")
check "pattern count=3" test "$pc" = "3"

echo ""
echo "== 4. crystallize — SKIP(junk 거부) 경로 =="
MOCK_MODE=skip python3 "$S/hermes-crystallize.py" --db "$DB" --crystallize hermes-pipeline-test --project-dir "$PROJ" >/dev/null 2>&1
cz=$(sql "SELECT crystallized FROM pattern_count WHERE pattern_key='hermes-pipeline-test'")
check "SKIP 응답 시 crystallized=-1 마킹" test "$cz" = "-1"
retry_out=$(MOCK_MODE=skip python3 "$S/hermes-crystallize.py" --db "$DB" --crystallize hermes-pipeline-test --project-dir "$PROJ" 2>&1)
check "거부 후 재시도 차단" bash -c "echo '$retry_out' | grep -q 'junk 거부됨'"

echo ""
echo "== 5. crystallize — 정상 경로 (claude 모킹) =="
python3 - "$DB" <<'EOF'
import sqlite3,sys
con=sqlite3.connect(sys.argv[1]); con.execute("UPDATE pattern_count SET crystallized=0 WHERE pattern_key='hermes-pipeline-test'"); con.commit()
EOF
MOCK_MODE=normal python3 "$S/hermes-crystallize.py" --db "$DB" --crystallize hermes-pipeline-test --project-dir "$PROJ" >/dev/null 2>&1
SKILL_MD="$PROJ/.hermes/skills/hermes-pipeline-test.md"
check "스킬 .md 생성" test -f "$SKILL_MD"
cz=$(sql "SELECT crystallized FROM pattern_count WHERE pattern_key='hermes-pipeline-test'")
check "crystallized=1" test "$cz" = "1"
si=$(sql "SELECT COUNT(*) FROM skill_index WHERE skill_path='$SKILL_MD'")
check "skill_index 등록" test "$si" = "1"
gr=$(python3 -c "import sqlite3;print(sqlite3.connect('$HOME/.hermes/global.db').execute(\"SELECT COUNT(*) FROM harness_rules WHERE trigger_keywords='hermes-pipeline-test'\").fetchone()[0])")
check "global.db 패턴 요약 1행 기록" test "$gr" = "1"

echo ""
echo "== 5b. crystallize — claude 실패 시 stderr 로그 =="
python3 - "$DB" <<'EOF'
import sqlite3,sys
con=sqlite3.connect(sys.argv[1])
con.execute("INSERT OR REPLACE INTO pattern_count (pattern_key,count,crystallized) VALUES ('fail-path-test',3,0)"); con.commit()
EOF
errlog=$(MOCK_MODE=fail python3 "$S/hermes-crystallize.py" --db "$DB" --crystallize fail-path-test --project-dir "$PROJ" 2>&1 >/dev/null)
check "실패 시 stderr 에 rc/stderr 기록" bash -c "echo '$errlog' | grep -q 'claude -p 실패.*mock failure'"

echo ""
echo "== 6. increment — crystallized!=0 제외 =="
inc_out=$(python3 "$S/hermes-increment.py" --db "$DB" --key hermes-pipeline-test 2>&1)
check "결정화된 패턴 집계 제외" bash -c "echo '$inc_out' | grep -q '이미 결정화됨'"
pc=$(sql "SELECT count FROM pattern_count WHERE pattern_key='hermes-pipeline-test'")
check "count 불변 (3 유지)" test "$pc" = "3"
python3 "$S/hermes-increment.py" --db "$DB" --key new-mistake-key >/dev/null 2>&1
python3 "$S/hermes-increment.py" --db "$DB" --key new-mistake-key >/dev/null 2>&1
inc3=$(python3 "$S/hermes-increment.py" --db "$DB" --key new-mistake-key 2>&1)
check "신규 키 3회 → CRYSTALLIZE 출력" bash -c "echo '$inc3' | grep -q 'CRYSTALLIZE:new-mistake-key'"

echo ""
echo "== 7. index-skills — used_count 보존 =="
mkdir -p "$PROJ/.claude/skills/test-skill"
printf -- '---\ndescription: 폴더형 테스트 스킬\n---\n# test-skill\n\n## 트리거\n- pipeline 작업 시\n' > "$PROJ/.claude/skills/test-skill/SKILL.md"
python3 "$S/hermes-index-skills.py" --db "$DB" --skills-dir "$PROJ/.claude/skills" >/dev/null
python3 - "$DB" "$PROJ" <<'EOF'
import sqlite3,sys,os
con=sqlite3.connect(sys.argv[1])
p=os.path.join(sys.argv[2],".claude/skills/test-skill/SKILL.md")
con.execute("UPDATE skill_index SET used_count=7 WHERE skill_path=?",(p,)); con.commit()
EOF
python3 "$S/hermes-index-skills.py" --db "$DB" --skills-dir "$PROJ/.claude/skills" >/dev/null
uc=$(sql "SELECT used_count FROM skill_index WHERE skill_path LIKE '%test-skill/SKILL.md'")
check "재인덱싱 후 used_count=7 보존" test "$uc" = "7"

echo ""
echo "== 8. search — 평면 .md 스킬 검색 =="
sout=$(python3 "$S/hermes-search.py" --db "$DB" --query "hermes-pipeline-test 어떻게 하지" 2>/dev/null)
check "평면 .md 스킬 주입 출력" bash -c "echo '$sout' | grep -q 'hermes-pipeline-test'"
uc=$(sql "SELECT used_count FROM skill_index WHERE skill_path='$SKILL_MD'")
check "used_count 증가" test "$uc" = "1"

echo ""
echo "== 9. evolve — 진화 + 쿨다운 =="
ev1=$(MOCK_MODE=evolve python3 "$S/hermes-evolve-skill.py" --db "$DB" --keyword hermes-pipeline-test --feedback "npm 말고 pnpm 으로 수정" 2>&1)
check "1차 진화 성공 (EVOLVED v1>v2)" bash -c "echo '$ev1' | grep -q 'EVOLVED:hermes-pipeline-test.md:v1>v2'"
ver=$(sql "SELECT version FROM skill_index WHERE skill_path='$SKILL_MD'")
check "skill_index.version=2 갱신" test "$ver" = "2"
ev2=$(MOCK_MODE=evolve python3 "$S/hermes-evolve-skill.py" --db "$DB" --keyword hermes-pipeline-test --feedback "또 수정" 2>&1)
check "2차 진화 쿨다운 스킵" bash -c "echo '$ev2' | grep -q '쿨다운'"

echo ""
echo "== 10. Stop 훅 e2e — session_id 추출 + 재저장 교체 =="
HOOK="$REPO_ROOT/assets/hooks/claude-stop-retrospective.sh"
TRH="$T/transcript-hook.jsonl"
mkmsg "$TRH" 4 hook-uniq
echo "{\"session_id\":\"hook-sess-1\",\"transcript_path\":\"$TRH\"}" | CLAUDE_PROJECT_DIR="$PROJ" bash "$HOOK"
echo "{\"session_id\":\"hook-sess-1\",\"transcript_path\":\"$TRH\"}" | CLAUDE_PROJECT_DIR="$PROJ" bash "$HOOK"
# 두 훅의 백그라운드 파이프라인 완료를 hooks.log 의 완료 마커로 폴링 (sleep 고정 대기는 CI 고부하에서 flaky)
python3 - "$PROJ/.hermes/hooks.log" <<'EOF'
import sys, time
for _ in range(100):
    try:
        done = open(sys.argv[1]).read().count("hook done: session=hook-sess-1")
    except FileNotFoundError:
        done = 0
    if done >= 2:
        break
    time.sleep(0.3)
else:
    print("WARN: hook done 마커 2개 대기 타임아웃", file=sys.stderr)
EOF
hn=$(sql "SELECT COUNT(*) FROM session_history WHERE session_id='hook-sess-1'")
echo "  (hook-sess-1 행수=${hn} — 8 기대, 2회 실행에도 1벌)"
check "훅 2회 실행 후에도 8행 (중복 누적 없음)" test "$hn" = "8"
hsum=$(sql "SELECT COUNT(*) FROM session_summary WHERE session_id='hook-sess-1'")
check "Stop 훅이 롤링 요약 생성" test "$hsum" = "1"

echo ""
echo "== 11. cleanup — junk 정리 (dry-run → apply) =="
python3 - "$DB" "$PROJ" <<'EOF'
import sqlite3,sys,os
con=sqlite3.connect(sys.argv[1])
for k in ("오류","내가","먼저","그리고","합니다"):
    con.execute("INSERT OR IGNORE INTO pattern_count (pattern_key,count) VALUES (?,5)",(k,))
skills=os.path.join(sys.argv[2],".hermes","skills")
for k in ("오류","내가"):
    p=os.path.join(skills,f"{k}.md")
    open(p,"w").write(f"# {k}\njunk\n")
    con.execute("INSERT OR IGNORE INTO skill_index (skill_path,keywords,scope) VALUES (?,?,'local')",(p,k))
# 중복 세션: sessB 내용 그대로 다른 ID 로 복제
rows=con.execute("SELECT content,role,timestamp,project_id FROM session_history WHERE session_id='sessB'").fetchall()
for c,r,t,p in rows:
    con.execute("INSERT INTO session_history (content,role,timestamp,project_id,session_id) VALUES (?,?,?,?,'sessB-dup')",(c,r,t,p))
con.commit()
EOF
dry=$(python3 "$S/hermes-cleanup.py" --db "$DB")
junk_before=$(sql "SELECT COUNT(*) FROM pattern_count WHERE pattern_key IN ('오류','내가','먼저','그리고','합니다')")
check "dry-run 은 DB 변경 없음" test "$junk_before" = "5"
check "dry-run 보고에 junk/중복 포함" bash -c "echo '$dry' | grep -q 'junk 패턴: 5' && echo '$dry' | grep -q '중복 세션: 1'"
python3 "$S/hermes-cleanup.py" --db "$DB" --apply >/dev/null
junk_after=$(sql "SELECT COUNT(*) FROM pattern_count WHERE pattern_key IN ('오류','내가','먼저','그리고','합니다')")
check "apply 후 junk 패턴 0개" test "$junk_after" = "0"
check "junk 스킬 .md 삭제" bash -c "! test -f '$PROJ/.hermes/skills/오류.md'"
dup=$(sql "SELECT COUNT(DISTINCT session_id) FROM session_history WHERE session_id LIKE 'sessB%'")
check "중복 세션 1개로 압축" test "$dup" = "1"
keep=$(sql "SELECT COUNT(*) FROM session_history WHERE session_id IN ('sessB','sessB-dup')")
check "원본 세션 행 보존 (6행)" test "$keep" = "6"
good=$(sql "SELECT COUNT(*) FROM pattern_count WHERE pattern_key='new-mistake-key'")
check "정상 패턴은 보존" test "$good" = "1"

echo ""
echo "== 12. cron-run.sh — 매니저 파이프라인 =="
"$S/hermes-cron-run.sh" "$PROJ" start projA,projB
python3 -c "import time; time.sleep(1)"
cronlog="$PROJ/.hermes/logs/cron-start-$(date +%Y%m%d).log"
check "cron 로그 생성" test -f "$cronlog"
check "매니저 프롬프트가 mock claude 로 전달됨" bash -c "grep -q '매니저 에이전트 시작' '$cronlog'"
badargs=$("$S/hermes-cron-run.sh" "$PROJ" start 2>&1 || true)
check "start 인자 검증" bash -c "echo '$badargs' | grep -q 'projects-csv'"

echo ""
echo "== 13. B신호 — 테스트/빌드 실패 탐지 =="
BTR="$T/bsig.jsonl"
# tool_use(Bash) + tool_result 1쌍으로 transcript 생성
mktool() { # mktool <file> <command> <output> <is_error 0|1> <tuid>
  python3 -c "
import json,sys
fn,cmd,out,is_err,tuid=sys.argv[1:6]
lines=[
 json.dumps({'type':'assistant','message':{'role':'assistant','content':[
   {'type':'tool_use','id':tuid,'name':'Bash','input':{'command':cmd}}]}}),
 json.dumps({'type':'user','message':{'role':'user','content':[
   {'type':'tool_result','tool_use_id':tuid,'is_error':(is_err=='1'),
    'content':[{'type':'text','text':out}]}]}}),
]
open(fn,'w').write(chr(10).join(lines))
" "$1" "$2" "$3" "$4" "$5"; }

# (a) 테스트 실패 → test-fail:<file> 키 생성
mktool "$BTR" "pytest tests/test_auth.py" "FAILED auth_service.py:42 AssertionError" 1 tu-b1
python3 "$S/hermes-save-session.py" --db "$DB" --transcript "$BTR" --project-id proj --session-id bsig1 >/dev/null
bk=$(sql "SELECT COUNT(*) FROM pattern_count WHERE pattern_key='test-fail:auth_service.py'")
check "테스트 실패 → test-fail:auth_service.py 키 생성" test "$bk" = "1"

# (b) 성공 결과 → 키 생성 안 함 (거짓 양성 차단)
mktool "$BTR" "pytest tests/test_ok.py" "5 passed in 0.1s" 0 tu-b2
python3 "$S/hermes-save-session.py" --db "$DB" --transcript "$BTR" --project-id proj --session-id bsig-ok >/dev/null
okk=$(sql "SELECT COUNT(*) FROM pattern_count WHERE pattern_key LIKE 'test-fail:test_ok%'")
check "성공 테스트는 키 생성 안 함" test "$okk" = "0"

# (b2) is_error=1(비정상 종료)은 출력이 'passed' 여도 실패로 간주 — 명령 인자 파일로 키 생성
mktool "$BTR" "pytest tests/test_edge.py" "5 passed in 0.1s" 1 tu-edge
python3 "$S/hermes-save-session.py" --db "$DB" --transcript "$BTR" --project-id proj --session-id bsig-edge >/dev/null
edgek=$(sql "SELECT COUNT(*) FROM pattern_count WHERE pattern_key='test-fail:test_edge.py'")
check "비정상 종료(is_error=1)는 출력 무관 실패 처리" test "$edgek" = "1"

# (c) 같은 파일 다른 라인 → 같은 키로 합쳐짐 + 3세션 임계 → CRYSTALLIZE
mktool "$BTR" "pytest tests/test_auth.py" "FAILED auth_service.py:99 AssertionError" 1 tu-b3
python3 "$S/hermes-save-session.py" --db "$DB" --transcript "$BTR" --project-id proj --session-id bsig2 >/dev/null
mktool "$BTR" "pytest tests/test_auth.py" "FAILED auth_service.py:7 AssertionError" 1 tu-b4
bout=$(python3 "$S/hermes-save-session.py" --db "$DB" --transcript "$BTR" --project-id proj --session-id bsig3)
cnt=$(sql "SELECT count FROM pattern_count WHERE pattern_key='test-fail:auth_service.py'")
check "다른 라인이어도 같은 키로 합쳐짐 (count=3)" test "$cnt" = "3"
check "3세션 임계 → CRYSTALLIZE 출력" bash -c "echo '$bout' | grep -q 'CRYSTALLIZE:.*test-fail:auth_service.py'"

# (d) git reset → revert:HEAD, git checkout <file> → revert:<file>
mktool "$BTR" "git reset --hard HEAD~1" "HEAD is now at abc1234" 0 tu-b5
python3 "$S/hermes-save-session.py" --db "$DB" --transcript "$BTR" --project-id proj --session-id bsig-git1 >/dev/null
gk=$(sql "SELECT COUNT(*) FROM pattern_count WHERE pattern_key='revert:HEAD'")
check "git reset → revert:HEAD 키 생성" test "$gk" = "1"

mktool "$BTR" "git checkout -- src/app.py" "" 0 tu-b6
python3 "$S/hermes-save-session.py" --db "$DB" --transcript "$BTR" --project-id proj --session-id bsig-git2 >/dev/null
gk2=$(sql "SELECT COUNT(*) FROM pattern_count WHERE pattern_key='revert:app.py'")
check "git checkout 파일 → revert:app.py 키 생성" test "$gk2" = "1"

# (e) 실패 맥락이 session_history(role='tool')에 기록됨
ctx=$(sql "SELECT COUNT(*) FROM session_history WHERE role='tool' AND content LIKE '[B신호]%test-fail:auth_service.py%'")
check "B신호 맥락이 session_history 에 기록됨" test "$ctx" -ge 1

echo ""
echo "== 14. summarize — 롤링 요약 생성 + 델타 가드 =="
STR="$T/sum.jsonl"
mkmsg "$STR" 2 sum-alpha    # user 2 + assistant 2 = 4 메시지
python3 "$S/hermes-summarize.py" --db "$DB" --transcript "$STR" \
  --project-id proj --session-id sumS --project-dir "$PROJ" >/dev/null
sc=$(sql "SELECT COUNT(*) FROM session_summary WHERE session_id='sumS'")
check "session_summary 행 생성" test "$sc" = "1"
hasdec=$(sql "SELECT COUNT(*) FROM session_summary WHERE session_id='sumS' AND slots_json LIKE '%decisions%'")
check "슬롯 JSON 저장됨" test "$hasdec" = "1"
lc=$(sql "SELECT last_msg_count FROM session_summary WHERE session_id='sumS'")
check "last_msg_count=4 (전체 반영)" test "$lc" = "4"
# 재실행(새 핑퐁 없음) → 델타 가드: 행 1개 유지, last_msg_count 불변
sum2=$(python3 "$S/hermes-summarize.py" --db "$DB" --transcript "$STR" \
  --project-id proj --session-id sumS --project-dir "$PROJ")
check "델타 없으면 스킵 로그" bash -c "echo '$sum2' | grep -q '델타 없음'"
sc2=$(sql "SELECT COUNT(*) FROM session_summary WHERE session_id='sumS'")
check "재실행 후에도 행 1개 (중복 없음)" test "$sc2" = "1"
note="$PROJ/.hermes/vault/proj-sumS.md"
check "옵시디언 노트 생성" test -f "$note"
check "노트에 미해결 과제 섹션 포함" grep -q "미해결 과제" "$note"
check "노트 frontmatter 포함" grep -q "hermes: rolling-summary" "$note"

echo ""
echo "== 15. recall — 자동주입 1회 가드 =="
inj=$(python3 "$S/hermes-recall.py" --inject --db "$DB" --project-id proj --session-id sumNEW)
check "직전 세션 미해결 과제 주입" bash -c "echo '$inj' | grep -q '승인 대기'"
check "직전 세션 결정사항 주입" bash -c "echo '$inj' | grep -q 'A 먼저'"
mk=$(sql "SELECT COUNT(*) FROM recall_marker WHERE session_id='sumNEW'")
check "recall_marker 기록" test "$mk" = "1"
inj2=$(python3 "$S/hermes-recall.py" --inject --db "$DB" --project-id proj --session-id sumNEW)
check "2회차 주입 없음 (빈 출력)" test -z "$inj2"

echo ""
echo "== 16. recall — 키워드 검색 =="
q=$(python3 "$S/hermes-recall.py" --query "승인" --db "$DB" 2>/dev/null)
check "검색 결과에 sumS 세션 포함" bash -c "echo '$q' | grep -q 'sumS'"
qn=$(python3 "$S/hermes-recall.py" --query "절대없는키워드zzz" --db "$DB" 2>/dev/null)
check "미일치 시 안내 출력" bash -c "echo '$qn' | grep -q '일치 요약 없음'"

echo ""
echo "== 17. UserPromptSubmit 훅 — recall 주입 =="
UPS="$REPO_ROOT/assets/hooks/claude-userpromptsubmit-mistake-detect.sh"
upout=$(echo '{"prompt":"이어서 작업하자","session_id":"ups-new"}' \
  | CLAUDE_PROJECT_DIR="$PROJ" bash "$UPS")
check "훅이 직전 세션 미해결 과제 주입" bash -c "echo '$upout' | grep -q '승인 대기'"
upout2=$(echo '{"prompt":"또 이어서","session_id":"ups-new"}' \
  | CLAUDE_PROJECT_DIR="$PROJ" bash "$UPS")
check "같은 세션 2회차 주입 없음" test -z "$upout2"

echo ""
echo "== 20. dream — 수집 + 결정화 구동 + 조용한 날 + 삭제 게이트 =="
add_summary() { # add_summary <session_id> <slots_json>
  python3 -c "
import sqlite3,sys
con=sqlite3.connect('$DB')
con.execute('''CREATE TABLE IF NOT EXISTS session_summary(session_id TEXT PRIMARY KEY,project_id TEXT,slots_json TEXT,last_msg_count INTEGER DEFAULT 0,turn_count INTEGER DEFAULT 0,updated_at DATETIME DEFAULT CURRENT_TIMESTAMP)''')
con.execute('INSERT OR REPLACE INTO session_summary(session_id,project_id,slots_json) VALUES(?,?,?)',(sys.argv[1],'proj',sys.argv[2]))
con.commit()
" "$1" "$2"; }
# 워터마크가 초 단위라 직전 dream(run_at)과 다음 요약을 다른 초로 분리해야 결정적 — 1초 경계 강제
bump_clock() { python3 -c "import time; time.sleep(1.1)"; }
# 섹션 20 픽스처 격리 — 앞 A 섹션(14 summarize 등)이 남긴 요약 제거
python3 -c "import sqlite3;c=sqlite3.connect('$DB');c.execute('DELETE FROM session_summary');c.commit()"

# (a) 조용한 날 — 요약 0건이면 dream_log 안 남김
dl0=$(sql "SELECT COUNT(*) FROM dream_log")
python3 "$S/hermes-dream.py" --db "$DB" --project-dir "$PROJ" >/dev/null 2>&1
dl1=$(sql "SELECT COUNT(*) FROM dream_log")
check "요약 0건이면 dream_log 안 남김" test "$dl0" = "$dl1"

# (b) 요약 주입 → 결정화 구동 + dream_log 1행 + 리포트
add_summary dsess1 '{"decisions":["pnpm 버전 고정 결정"],"facts":["WSL2 환경"],"open":[],"prefs":[],"next":[]}'
dout=$(MOCK_MODE=normal python3 "$S/hermes-dream.py" --db "$DB" --project-dir "$PROJ")
check "결정화 스킬 .md 생성 (dream-test-key)" test -f "$PROJ/.hermes/skills/dream-test-key.md"
dlrun=$(sql "SELECT COUNT(*) FROM dream_log")
check "dream_log 1행 기록" test "$dlrun" = "1"
rp=$(sql "SELECT report_path FROM dream_log ORDER BY id DESC LIMIT 1")
check "드림 리포트 .md 생성" test -f "$rp"
check "리포트에 결정화 섹션" grep -q "결정화 (추가)" "$rp"

# (c) 델타 — 직전 드리밍 이후 새 요약 없으면 또 조용한 날
dl_before=$(sql "SELECT COUNT(*) FROM dream_log")
python3 "$S/hermes-dream.py" --db "$DB" --project-dir "$PROJ" >/dev/null 2>&1
dl_after=$(sql "SELECT COUNT(*) FROM dream_log")
check "새 요약 없으면 dream_log 증가 없음" test "$dl_before" = "$dl_after"

# (d) 삭제 게이트 — junk 스킬 있어도 dry-run 은 삭제 안 함
mkdir -p "$PROJ/.hermes/skills"
printf '# 내가\njunk\n' > "$PROJ/.hermes/skills/내가.md"
python3 - "$DB" "$PROJ" <<'EOF'
import sqlite3,sys,os
con=sqlite3.connect(sys.argv[1])
p=os.path.join(sys.argv[2],".hermes","skills","내가.md")
con.execute("INSERT OR IGNORE INTO skill_index (skill_path,keywords,scope) VALUES (?,?,'local')",(p,"내가")); con.commit()
EOF
bump_clock  # 직전 (b) dream 의 run_at 이후 초로 dsess2 를 확실히 분리
add_summary dsess2 '{"decisions":["새 결정"],"facts":["새 사실"],"open":[],"prefs":[],"next":[]}'
python3 "$S/hermes-dream.py" --db "$DB" --project-dir "$PROJ" >/dev/null 2>&1
check "dry-run 은 junk 스킬 삭제 안 함" test -f "$PROJ/.hermes/skills/내가.md"

# (e) --apply 는 junk 스킬 실제 삭제
bump_clock  # 직전 (d) dream 의 run_at 이후 초로 dsess3 를 확실히 분리
add_summary dsess3 '{"decisions":["또 결정"],"facts":["또 사실"],"open":[],"prefs":[],"next":[]}'
python3 "$S/hermes-dream.py" --db "$DB" --project-dir "$PROJ" --apply >/dev/null 2>&1
check "--apply 는 junk 스킬 삭제" bash -c "! test -f '$PROJ/.hermes/skills/내가.md'"

echo ""
echo "== 21. dream — 진화 구동 (요약 속 정정) =="
mkdir -p "$PROJ/.hermes/skills"
printf -- '# pnpm-rule\n<!-- hermes:auto-generated version:1 created:2026-06-18 -->\n\n## 규칙\n- [ ] npm 사용\n' > "$PROJ/.hermes/skills/pnpm-rule.md"
python3 - "$DB" "$PROJ" <<'EOF'
import sqlite3,sys,os
con=sqlite3.connect(sys.argv[1])
p=os.path.join(sys.argv[2],".hermes","skills","pnpm-rule.md")
con.execute("INSERT OR IGNORE INTO skill_index (skill_path,keywords,scope,version) VALUES (?,?,'local',1)",(p,"pnpm,rule")); con.commit()
EOF
bump_clock  # 직전 (e) dream 의 run_at 이후 초로 dsess-ev 를 확실히 분리
add_summary dsess-ev '{"decisions":["npm 말고 pnpm 으로 버전 고정"],"facts":["x"],"open":[],"prefs":[],"next":[]}'
evout=$(MOCK_MODE=evolve python3 "$S/hermes-dream.py" --db "$DB" --project-dir "$PROJ")
ev=$(sql "SELECT evolved FROM dream_log ORDER BY id DESC LIMIT 1")
check "정정 요약 → 진화 1건 기록" test "$ev" -ge 1

echo ""
echo "== 22. cron-run.sh — dream 액션 =="
bump_clock  # 직전 (21) dream 의 run_at 이후 초로 cron-dsess 를 확실히 분리
add_summary cron-dsess '{"decisions":["cron 드림 결정"],"facts":["cron 사실"],"open":[],"prefs":[],"next":[]}'
"$S/hermes-cron-run.sh" "$PROJ" dream
python3 -c "import time; time.sleep(0.5)"
cdlog="$PROJ/.hermes/logs/cron-dream-$(date +%Y%m%d).log"
check "cron dream 로그 생성" test -f "$cdlog"
dlc=$(sql "SELECT COUNT(*) FROM dream_log")
check "cron dream 이 dream_log 기록" test "$dlc" -ge 1

echo ""
echo "== 23. crystallize 장부: 드림 등 pattern_count-밖 키도 멱등/거부 마킹 적중 =="
ledger_ok() {
S_DIR="$S" python3 - "$DB" <<'PY'
import importlib.util, os, sys
spec=importlib.util.spec_from_file_location("hc", os.path.join(os.environ["S_DIR"],"hermes-crystallize.py"))
hc=importlib.util.module_from_spec(spec); spec.loader.exec_module(hc)
db=sys.argv[1]
def cr(k):  # 항상 최신 커밋 상태를 읽도록 짧은 커넥션
    c=hc.connect_db(db)
    r=c.execute("SELECT crystallized FROM pattern_count WHERE pattern_key=?",(k,)).fetchone()
    c.close(); return r[0] if r else None
assert cr("dream-semantic-key") is None          # 장부에 없던 의미론적 키
hc.ensure_pattern_row(db, "dream-semantic-key")
assert cr("dream-semantic-key")==0               # 행 생성(미결정화)
hc.register_skill(db, "/tmp/x/dream-semantic-key.md", "dream-semantic-key")
assert cr("dream-semantic-key")==1               # UPDATE 적중 → 멱등성 복원
hc.ensure_pattern_row(db, "dream-junk-key")
hc.mark_rejected(db, "dream-junk-key")
assert cr("dream-junk-key")==-1                   # 거부 마킹 적중 → 재시도 방지
hc.ensure_pattern_row(db, "dream-semantic-key")   # OR IGNORE 재보장은 상태 불변
assert cr("dream-semantic-key")==1
print("OK")
PY
}
if ledger_ok 2>/dev/null | grep -q OK; then check "crystallize 장부: 장부-밖 키 멱등/거부 마킹 적중" true; else check "crystallize 장부" false; fi

echo ""
echo "== 24. register_skill: 영문 슬러그 키도 한글 본문 키워드로 색인(①) =="
# 드림 자동생성 스타일 .md(영문 제목 + 한글 문제상황) 작성 후 register_skill 호출
mkdir -p "$PROJ/.hermes/skills"
printf '%s\n' '# token-ttl-auth-layer-issue' '' '## 문제 상황' '백오피스 API 호출 시 토큰 없으면 401 인증 에러' '' '## 규칙' '- [ ] Bearer 토큰 포함' > "$PROJ/.hermes/skills/token-ttl-auth-layer-issue.md"
kwidx_ok() {
S_DIR="$S" python3 - "$DB" "$PROJ" <<'PY'
import importlib.util, os, sys
spec=importlib.util.spec_from_file_location("hc", os.path.join(os.environ["S_DIR"],"hermes-crystallize.py"))
hc=importlib.util.module_from_spec(spec); spec.loader.exec_module(hc)
db, proj = sys.argv[1], sys.argv[2]
path=os.path.join(proj,".hermes","skills","token-ttl-auth-layer-issue.md")
hc.register_skill(db, path, "token-ttl-auth-layer-issue")
c=hc.connect_db(db)
kw=c.execute("SELECT keywords FROM skill_index WHERE skill_path=?",(path,)).fetchone()[0]
c.close()
assert "token" in kw, kw                     # 영문 슬러그 유지
assert "토큰" in kw and "인증" in kw, kw      # ① 한글 본문 키워드 색인
print("OK")
PY
}
if kwidx_ok 2>/dev/null | grep -q OK; then check "register_skill: 한글 본문 키워드 색인" true; else check "register_skill 한글 색인" false; fi

echo ""
echo "== 25. save-session: 민감정보 마스킹 후 적재(배선 회귀) =="
# redact() 호출이 제거되면 원문 비밀이 session_history에 그대로 남아 이 테스트가 깨진다
RTR="$T/redact.jsonl"
printf '%s\n' \
  '{"type":"user","message":{"role":"user","content":"토큰 ghp_abcdefghijklmnopqrstuvwxyz0123456789, 비밀번호는 superSecret99"}}' \
  '{"type":"assistant","message":{"role":"assistant","content":"auth middleware 토큰 검증 추가"}}' > "$RTR"
python3 "$S/hermes-save-session.py" --db "$DB" --transcript "$RTR" --project-id proj --session-id redactA >/dev/null 2>&1
redact_ok() {
python3 - "$DB" <<'PY'
import sqlite3, sys
con=sqlite3.connect(sys.argv[1])
joined="\n".join(r[0] for r in con.execute(
    "SELECT content FROM session_history WHERE session_id='redactA'"))
con.close()
for leak in ("ghp_abcdefghijklmnopqrstuvwxyz0123456789", "superSecret99"):
    assert leak not in joined, f"원문 비밀 잔존: {leak}"
assert "[REDACTED:TOKEN]" in joined and "[REDACTED:SECRET]" in joined, joined
assert "auth middleware" in joined, "산문 과마스킹"   # 일반 산문 보존
print("OK")
PY
}
if redact_ok 2>/dev/null | grep -q OK; then check "save-session: 비밀 마스킹·산문 보존" true; else check "save-session 마스킹" false; fi

echo ""
echo "PASS=$pass FAIL=$fail"
[[ $fail -eq 0 ]]
