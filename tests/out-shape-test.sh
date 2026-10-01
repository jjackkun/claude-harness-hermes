#!/usr/bin/env bash
# out_shape.py — Bash 명령 한 줄에서 모양(seg · pipe · hd · heads)만 뽑고, 값·인자는 절대 돌려주지 않는다.
# 계획: docs/exec-plans/completed/2026-10-01-out-shape-agent-fields.md 목표 1 · 2 · 3
#
# 왜 모양인가: R-out 의 명령 머리는 `cd X &&` 를 걷어낸 첫 단어라, 한 호출에 여러 명령을 묶으면(전체의 65%)
# 바이트를 낸 명령이 가려진다(tool-output-budget §7-6 정정). 모양을 남기면 "묶음이 큰 출력을 내는가" 를 상시 볼 수 있다.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
assert() { if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; PASS=$((PASS+1)); else echo "  ✗ $1"; echo "      expected=[$2]"; echo "      actual  =[$3]"; FAIL=$((FAIL+1)); fi; }

# 명령 문자열(여러 줄 가능)을 받아 모양 글자를 낸다
shape() { PYTHONPATH="$REPO_ROOT/assets/hooks" python3 -c '
import sys, out_shape
print(out_shape.fields_text(out_shape.shape_of(sys.argv[1]), agent=sys.argv[2], sub=sys.argv[3] == "1"))' "$1" "${2:--}" "${3:-0}"; }

# 정상 출력(seg= 로 시작)이면서 주어진 패턴이 없을 때만 ok — 모듈이 죽어 출력이 비어도 통과하는 시험을 막는다
clean() { awk -v pat="$1" '/^seg=/ && $0 !~ pat {print "ok"}'; }

echo "== 1. 모양 (목표 1)"
assert "단일 명령" "seg=1 pipe=0 hd=0 sub=0 agent=- heads=ls" "$(shape 'ls -la')"
assert "파이프는 한 호출 · 단계 머리를 모두" "seg=1 pipe=1 hd=0 sub=0 agent=- heads=cat,head" "$(shape 'cat a.txt | head -5')"
assert "cd 접두는 걷는다 · ; 묶음 3" "seg=3 pipe=0 hd=0 sub=0 agent=- heads=cat,sed,grep" "$(shape 'cd /x && cat a; sed -n 1,5p b; grep x c')"
assert "&& 묶음 2 (make 는 인터프리터 목록 — 둘째 단어까지)" "seg=2 pipe=0 hd=0 sub=0 agent=- heads=make,make test" "$(shape 'make && make test')"
assert "|| 도 묶음" "seg=2 pipe=0 hd=0 sub=0 agent=- heads=test,echo" "$(shape 'test -f a || echo none')"
assert "heredoc 본문은 명령이 아니다 · 끝난 뒤 명령은 센다" "seg=2 pipe=0 hd=1 sub=0 agent=- heads=python3,echo" \
  "$(shape $'python3 - <<\'PY\'\nimport os; print(1)\nls -la\nPY\necho done')"
assert "cat > 파일 <<EOF 는 쓰기 — 본문의 ; 는 무시" "seg=1 pipe=0 hd=1 sub=0 agent=- heads=cat" "$(shape $'cat > f.txt <<\'EOF\'\nbody; ls\nEOF')"
assert "따옴표 안의 ; && | 는 구분자가 아니다" "seg=1 pipe=1 hd=0 sub=0 agent=- heads=echo,tr" "$(shape 'echo "a; b && c" | tr a b')"
assert "VAR=값 접두는 걷는다" "seg=1 pipe=0 hd=0 sub=0 agent=- heads=curl" "$(shape 'TOKEN=abc123xyz curl https://x')"
assert "인터프리터는 둘째 토큰 basename 까지(head_of 와 같은 규칙)" "seg=1 pipe=0 hd=0 sub=0 agent=- heads=python3 hermes-journal.py" "$(shape 'python3 scripts/hermes-journal.py emit')"
assert "머리 목록은 6개까지 · seg 는 실제 수" "seg=8 pipe=0 hd=0 sub=0 agent=- heads=a,b,c,d,e,f" "$(shape 'a; b; c; d; e; f; g; h')"
assert "빈 명령" "seg=0 pipe=0 hd=0 sub=0 agent=- heads=-" "$(shape '')"
assert "& 도 구분자(백그라운드)" "seg=2 pipe=0 hd=0 sub=0 agent=- heads=make,make test" "$(shape 'make & make test')"
assert "2>&1 의 & 는 구분자가 아니다" "seg=1 pipe=0 hd=0 sub=0 agent=- heads=make test" "$(shape 'make test 2>&1 > out.log')"
assert "서브셸은 한 덩어리 · 머리는 ?" "seg=1 pipe=0 hd=0 sub=0 agent=- heads=?" "$(shape '(cd x; ls)')"
assert "\$(…) 안의 ; 는 가르지 않는다" "seg=1 pipe=0 hd=0 sub=0 agent=- heads=echo" "$(shape 'echo $(cat a; ls)')"
assert "여러 줄 · 끝 표시 뒤 명령까지" "seg=3 pipe=0 hd=0 sub=0 agent=- heads=ls,cat,echo" "$(shape $'ls\ncat a\necho done')"

echo "== 2. 비밀값이 안 나온다 (목표 2)"
OUT="$(shape 'TOKEN=abc123xyz curl -H "Authorization: Bearer s3cretvalue" --password hunter2 https://x | tee out.txt')"
assert "인자·값이 결과에 0건(정상 출력)" ok "$(printf '%s' "$OUT" | clean 'abc123xyz|s3cretvalue|hunter2|Authorization|https')"
assert "  머리만 남는다" "seg=1 pipe=1 hd=0 sub=0 agent=- heads=curl,tee" "$OUT"
assert "따옴표로 시작하는 머리는 ?" "seg=1 pipe=0 hd=0 sub=0 agent=- heads=?" "$(shape '"secret value" arg')"
assert "치환 머리는 ? (정상 출력 · 값 0건)" ok "$(shape '$(cat /etc/secret) x' | clean 'secret')"
assert "백틱 머리는 ? (정상 출력 · 값 0건)" ok "$(shape '`cat /tmp/key` x' | clean 'key')"
assert "경로 머리는 basename 만" "seg=1 pipe=0 hd=0 sub=0 agent=- heads=tool" "$(shape '/home/x/secret-dir/tool --a')"
assert "  디렉터리 이름 0건(정상 출력)" ok "$(shape '/home/x/secret-dir/tool --a' | clean 'secret-dir')"
assert "heredoc 본문의 값은 안 나온다(정상 출력)" ok "$(shape $'cat <<\'EOF\'\npassword=hunter2\nEOF' | clean 'hunter2')"

# 리뷰(code-reviewer, 2026-10-01) Block: 따옴표·$( ) 안의 heredoc 본문 줄을 명령으로 세어 첫 단어가 heads 로 샜다.
# `git commit -m "$(cat <<'EOF' … EOF)"` 는 커밋마다 쓰는 흔한 모양이다.
CMD=$'git commit -q -m "$(cat <<\'EOF\'\nfeat: hunter2 is pw\nsk-ABC123 leaked\nEOF\n)"'
assert '$( ) 안 heredoc 본문의 단어는 0건(정상 출력)' ok "$(shape "$CMD" | clean 'hunter2|sk-ABC123|EOF|feat')"
assert "  모양: hd=1 · 명령은 git commit 하나(닫는 괄호 줄은 명령이 아니다)" "seg=1 pipe=0 hd=1 sub=0 agent=- heads=git commit" "$(shape "$CMD")"
assert "echo \$(cat <<EOF) 도 본문 0건" ok "$(shape $'echo $(cat <<EOF\nsecret1 a\nEOF\n)' | clean 'secret1')"
assert "heredoc 둘(한 줄에 <<A <<B) — 둘째 본문도 건너뛴다" "seg=2 pipe=0 hd=1 sub=0 agent=- heads=cat,ls" "$(shape $'cat <<A <<B\n1\nA\n2\nB\nls')"
assert "<<< (here-string)는 heredoc 이 아니다" "seg=2 pipe=0 hd=0 sub=0 agent=- heads=cat,ls" "$(shape $'cat <<< hello\nls')"

# 리뷰 Warn: 인터프리터 둘째 단어에 임의 인자(토큰 모양 단어)가 들어갔다 → 알려진 부명령·스크립트 이름만
assert "스크립트 확장자가 있으면 이름까지" "seg=1 pipe=0 hd=0 sub=0 agent=- heads=bash deploy.sh" "$(shape 'bash ./deploy.sh')"
assert "확장자 없는 임의 단어는 안 붙는다(python3)" "seg=1 pipe=0 hd=0 sub=0 agent=- heads=python3" "$(shape 'python3 hunter2')"
assert "알려지지 않은 git 부명령은 안 붙는다" "seg=1 pipe=0 hd=0 sub=0 agent=- heads=git" "$(shape 'git ghp_abc123')"
assert "알려진 부명령은 붙는다(git status · pnpm test · docker ps)" "seg=3 pipe=0 hd=0 sub=0 agent=- heads=git status,pnpm test,docker ps" "$(shape 'git status; pnpm test; docker ps')"
assert "sudo·timeout·nohup 뒤 단어는 안 붙는다" "seg=1 pipe=0 hd=0 sub=0 agent=- heads=sudo" "$(shape 'sudo s3cret_tok ls')"

# 리뷰 Warn: 입력 크기 — 수십만 자 한 줄이 PostToolUse 를 늦춘다(선형이지만 크다)
BIGT="$(python3 -c "
import time, sys
sys.path.insert(0, '$REPO_ROOT/assets/hooks'); import out_shape
t = time.perf_counter(); out_shape.shape_of('echo x; ' * 60000); print(int((time.perf_counter() - t) * 1000) < 150)")"
assert "  shape_of 자체는 150ms 안(입력 상한 16KB)" True "$BIGT"

# 속성 시험 — 비밀 표지를 명령의 **머리가 아닌 모든 자리**에 넣고, 결과에 한 번도 안 나오는지 본다
LEAKS="$(PYTHONPATH="$REPO_ROOT/assets/hooks" python3 - <<'PYEOF'
import out_shape
S = "zzSECRETzz"
templates = [
    "ls {S}", "ls -la --token {S}", "ls --token={S}", 'ls "{S} x"', "ls '{S}'", "ls $({S} x)", "ls `{S}`",
    "X={S} ls", "X={S} Y=2 ls -l", "ls > {S}.txt", "ls 2> /tmp/{S}", "cat < /tmp/{S}", "ls /home/{S}/dir",
    "cat <<EOF\n{S}\nEOF", "cat <<'EOF'\n{S} arg\nEOF\nls", 'git commit -m "$(cat <<\'EOF\'\n{S}\nEOF\n)"',
    'echo "$(cat <<EOF\n{S}\nEOF\n)" | tee x', "cat <<A <<B\n{S}\nA\n{S}\nB\nls",
    "ls | grep {S} | head", "ls; echo {S}", "make test {S}", "python3 {S}", "python3 {S}.py", "git {S}", "git status {S}",
    "sudo {S} ls", "docker run {S}", "pnpm {S}", "curl -H 'Authorization: {S}' https://x/{S}",
    "(cd /{S}; ls)", "{{ echo {S}; }}", "echo $(( 1 << 3 )) {S}", "ls <<< {S}", "f() {{ echo {S}; }}; f",
    "ls\n" + "echo {S}\n" * 3, "echo ${{{S}:-x}}", "ls #{S}", "ls \\\n{S}",
]
bad = []
for t in templates:
    out = out_shape.fields_text(out_shape.shape_of(t.replace("{S}", S) if "{{" not in t else t.format(S=S)))
    if S in out and not t.startswith(("python3 {S}.py",)):      # 스크립트 이름(확장자 있음)은 머리의 일부로 허용
        bad.append(t.split("\n")[0][:30])
print(len(bad), *bad)
PYEOF
)"
assert "비밀 표지가 머리 아닌 자리에서 새지 않는다(속성 시험 · 위반 건수 0)" "0" "$(printf '%s' "$LEAKS" | awk '{print $1}')"

echo "== 3. 에이전트 (목표 3)"
assert "agent_type 있음 · 서브에이전트가 부름" "seg=1 pipe=0 hd=0 sub=1 agent=code-reviewer heads=ls" "$(shape 'ls' code-reviewer 1)"
assert "agent_type 없음 → -" "seg=1 pipe=0 hd=0 sub=0 agent=- heads=ls" "$(shape 'ls' '' 0)"
assert "허용 밖 글자는 걷는다(남는 글자는 허용 문자뿐)" "seg=1 pipe=0 hd=0 sub=0 agent=ab-cd_1.2:xrm-rfx heads=ls" "$(shape 'ls' 'ab-cd_1.2:x; rm -rf / $(x)' 0)"
assert "정화 후 비면 -" "seg=1 pipe=0 hd=0 sub=0 agent=- heads=ls" "$(shape 'ls' '; $() ' 0)"
assert "48자 상한" 48 "$(shape 'ls' "$(printf 'a%.0s' $(seq 1 100))" 0 | sed -E 's/.*agent=([^ ]*) .*/\1/' | tr -d '\n' | wc -c)"

echo "== 4. 훅을 통과한 이벤트 (목표 2 · 4 · 6)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/scripts" "$T/.harness"; git -C "$T" init -q 2>/dev/null
cp -r "$REPO_ROOT/assets/hooks" "$T/scripts/hooks"
EV="$T/.harness/gate-events.jsonl"
hook() { # hook <명령> <stdout 바이트> [agent_type] [agent_id] — 훅을 한 번 돌린다
  python3 -c '
import json, sys
d = {"tool_name": "Bash", "tool_input": {"command": sys.argv[1]}, "tool_response": {"stdout": "x" * int(sys.argv[2]), "stderr": ""},
     "duration_ms": 97, "session_id": "s"}
if sys.argv[3]: d["agent_type"] = sys.argv[3]
if sys.argv[4]: d["agent_id"] = sys.argv[4]
print(json.dumps(d))' "$1" "$2" "${3:-}" "${4:-}" | env -u R_OUT_THRESHOLD CLAUDE_PROJECT_DIR="$T" bash "$T/scripts/hooks/claude-posttooluse-output-budget.sh" >/dev/null 2>&1; }
lastfield() { python3 -c '
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1]) if "\"R-out\"" in l]
print(rows[-1].get(sys.argv[2]) or "")' "$EV" "$1"; }

hook 'cd /x && cat a; sed -n 1p b' 100 code-reviewer sub1
assert "pass 이벤트 detail: 앞은 예전 그대로, 뒤에 필드" "100B 97ms seg=2 pipe=0 hd=0 sub=1 agent=code-reviewer heads=cat,sed" "$(lastfield detail)"
assert "  path 는 cmd:<머리> 한 토큰 그대로(필드가 안 샌다)" "cmd:cat" "$(lastfield path)"
assert "  path 의 머리 == heads 첫째(두 규칙이 어긋나지 않는다)" "cat" "$(lastfield detail | sed -E 's/.*heads=([^, ]*).*/\1/')"
hook 'ls' 9000
assert "warn 이벤트도 앞부분은 예전 형식 + 필드" 1 "$(lastfield detail | grep -cE '^9000B 97ms \(임계 8192B 초과\) seg=1 pipe=0 hd=0 sub=0 agent=- heads=ls$')"
assert "  verdict 는 warn" warn "$(lastfield verdict)"
hook 'TOKEN=abc123xyz curl -H "Authorization: Bearer s3cretvalue" --password hunter2 https://x' 50
assert "그 호출은 seg=1 heads=curl 로 남았다(기록이 실제로 있다)" 1 "$(lastfield detail | grep -c 'seg=1 .*heads=curl$')"
assert "  비밀값은 훅을 통과해도 이벤트 파일에 0건" 0 "$(grep -cE 'abc123xyz|s3cretvalue|hunter2' "$EV")"

rm "$T/scripts/hooks/out_shape.py"
hook 'cat a | head -3' 100
assert "out_shape 없음 → shape=err 로 보인다(조용히 꺼지지 않는다)" 1 "$(lastfield detail | grep -c 'shape=err')"
assert "  머리는 예전대로 기록" "cmd:cat" "$(lastfield path)"
assert "  앞부분(바이트·시간)은 그대로" 1 "$(lastfield detail | grep -c '^100B 97ms')"
cp "$REPO_ROOT/assets/hooks/out_shape.py" "$T/scripts/hooks/out_shape.py"

echo "{\"ts\":1,\"rule\":\"R-out\",\"verdict\":\"pass\",\"stage\":\"posttooluse\",\"path\":\"cmd:cat\",\"detail\":\"141B 97ms\"}" >> "$EV"
OUTR="$(python3 "$REPO_ROOT/assets/hooks/out_report.py" --events "$EV" 2>&1)"
assert "out_report 가 새·옛 형식 레코드를 섞어 읽는다(rc 0 · cat 행)" 1 "$(printf '%s' "$OUTR" | grep -cE '^cat[[:space:]]+[0-9]')"

echo "== 5. out_report --by (목표 5)"
F="$T/by-events.jsonl"
ev() { printf '{"ts":1,"rule":"R-out","verdict":"%s","stage":"posttooluse","path":"%s","detail":"%s"}\n' "$1" "$2" "$3" >> "$F"; }
: > "$F"
ev pass cmd:ls "100B 5ms seg=1 pipe=0 hd=0 sub=0 agent=claude heads=ls"
ev pass cmd:cat "300B 5ms seg=1 pipe=1 hd=0 sub=0 agent=claude heads=cat,head"
ev warn cmd:cat "9000B 5ms (임계 8192B 초과) seg=3 pipe=0 hd=0 sub=0 agent=claude heads=cat,sed,grep"
ev pass cmd:a "200B 5ms seg=2 pipe=0 hd=0 sub=1 agent=code-reviewer heads=a,b"
ev pass cmd:python3 "50B 5ms seg=1 pipe=0 hd=1 sub=0 agent=claude heads=python3"
ev pass cmd:cat "141B 97ms"
ev pass cmd:cat "70B 5ms shape=err"
rpt() { python3 "$REPO_ROOT/assets/hooks/out_report.py" --events "$F" "$@" 2>&1; }
row() { awk -v k="$1" '$1==k {print $2, $6, $7}'; }
assert "--by 없이는 예전 표 그대로(머리별: cat 4건)" "4 1 9,511" "$(rpt | row cat)"
assert "--by shape: 묶음(seg>=2) 2건 · 초과 1 · 합 9,200" "2 1 9,200" "$(rpt --by shape | row 묶음)"
assert "  파이프 1건" "1 0 300" "$(rpt --by shape | row 파이프)"
assert "  단일 1건" "1 0 100" "$(rpt --by shape | row 단일)"
assert "  heredoc 이 있으면 스크립트 1건" "1 0 50" "$(rpt --by shape | row 스크립트)"
assert "  필드 없는 옛 레코드는 (기록 이전) 1건" 1 "$(rpt --by shape | grep -cE '^\(기록 이전\)[[:space:]]+1[[:space:]]')"
assert "  shape=err 는 (shape 오류) 1건" 1 "$(rpt --by shape | grep -cE '^\(shape 오류\)[[:space:]]+1[[:space:]]')"
assert "--by agent: claude 4건" "4 1 9,450" "$(rpt --by agent | row claude)"
assert "  서브에이전트는 이름/서브" "1 0 200" "$(rpt --by agent | row 'code-reviewer/서브')"
assert "  옛 레코드·shape=err 는 (기록 이전)" 1 "$(rpt --by agent | grep -cE '^\(기록 이전\)[[:space:]]+2[[:space:]]')"
: > "$F"; ev pass cmd:cat "141B 97ms"
assert "옛 레코드만 있는 파일 → (기록 이전) 한 줄 · 깨지지 않는다" 1 "$(rpt --by shape | grep -cE '^\(기록 이전\)[[:space:]]+1[[:space:]]')"
assert "  rc 0" 0 "$(python3 "$REPO_ROOT/assets/hooks/out_report.py" --events "$F" --by shape >/dev/null 2>&1; echo $?)"

echo; echo "통과 $PASS · 실패 $FAIL"
[[ "$FAIL" -eq 0 ]]
