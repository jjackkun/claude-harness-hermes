#!/usr/bin/env bash
# Bash 가드 — 사람 입력이 필요한 sudo 는 막고(R-sudo), 길 수 있는 명령을 앞에서 오래 막아 두면 경고한다(R-fg).
#
# 근거: docs/exec-plans/active/2026-10-14-long-command-visibility.md 목표 G4 · G5
#       (jj-agent-room 첫 세팅에서 sudo 가 Password: 를 기다리며 600초 동안 아무 말 없이 멈췄다)
#
# 실행: bash tests/bash-guard-interactive-test.sh
# 종료 코드: 0 = 모든 단언 통과, 1 = 실패

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$REPO_ROOT/assets/hooks/claude-pretooluse-bash-guard.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/proj/.claude"

PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  ✓ $desc"; PASS=$((PASS+1))
  else
    echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1))
  fi
}

# run_guard <command> [timeout_ms] [run_in_background] — 가드를 돌려 "rc|출력" 을 남긴다
run_guard() {
  python3 -c "
import json, sys
ti = {'command': sys.argv[1]}
if sys.argv[2]: ti['timeout'] = int(sys.argv[2])
if sys.argv[3]: ti['run_in_background'] = sys.argv[3] == '1'
print(json.dumps({'tool_name': 'Bash', 'tool_input': ti}))
" "$1" "${2:-}" "${3:-}" | CLAUDE_PROJECT_DIR="$TMP/proj" bash "$HOOK" > "$TMP/out" 2>&1
  echo $? > "$TMP/rc"
}
# blocked <command> — R-sudo 로 막히면(exit 2 + 표식) 1, 아니면 0
blocked() {
  run_guard "$1"
  [[ "$(cat "$TMP/rc")" == "2" ]] && grep -q '\[R-sudo BLOCK\]' "$TMP/out" && echo 1 || echo 0
}
# warned <command> <timeout_ms> [run_in_background] — R-fg 경고가 나오면 1, 아니면 0
warned() {
  run_guard "$1" "$2" "${3:-}"
  grep -q '\[R-fg\]' "$TMP/out" && echo 1 || echo 0
}

echo "== R-sudo — 반드시 막아야 하는 sudo (비밀번호 대기로 멈춘다) =="
assert "sudo apt-get install"           1 "$(blocked 'sudo apt-get install -y redis-server')"
assert "&& 뒤 sudo"                      1 "$(blocked 'npm run setup && sudo apt-get install redis-server')"
assert "; 뒤 sudo"                       1 "$(blocked 'cd /srv; sudo make install')"
assert "줄바꿈 뒤 sudo"                  1 "$(blocked $'npm ci\nsudo apt install x')"
assert "절대경로 /usr/bin/sudo"          1 "$(blocked '/usr/bin/sudo ls /root')"
assert "앞에 VAR=값"                     1 "$(blocked 'DEBIAN_FRONTEND=noninteractive sudo apt-get install x')"
assert "env·time 뒤 sudo"                1 "$(blocked 'time env A=1 sudo ls')"
assert "sudo -E (다른 플래그)"           1 "$(blocked 'sudo -E apt-get install x')"
assert "sudo -S (stdin 비밀번호)"        1 "$(blocked 'echo pw | sudo -S apt-get install x')"
assert "서브셸 (sudo …)"                 1 "$(blocked '(sudo ls)')"
assert "-n 이 sudo 뒤 명령의 인자면 통과 아님" 1 "$(blocked 'sudo head -n 5 /root/x')"
# code-reviewer 지적(2026-10-14): shlex 가 붙은 구분자를 한 토큰(`);` `;\n` `\n\n`)으로 묶어 명령 위치를 잃었다
assert "빈 줄 뒤 sudo"                   1 "$(blocked $'ls\n\nsudo ls')"
assert "\$(…); 뒤 sudo"                  1 "$(blocked 'x=$(ls); sudo ls')"
assert "; 와 줄바꿈 뒤 sudo"              1 "$(blocked $'ls;\nsudo ls')"
assert "if·then·do·! 뒤 sudo"            1 "$(blocked 'if sudo true; then :; fi')"
assert "then 뒤 sudo"                    1 "$(blocked 'if true; then sudo ls; fi')"
assert "do 뒤 sudo"                      1 "$(blocked 'for p in a b; do sudo apt install $p; done')"
assert "! 뒤 sudo"                       1 "$(blocked '! sudo ls')"
assert "{ 묶음 안 sudo"                   1 "$(blocked '{ sudo ls; }')"

echo "== R-sudo — 오탐이어서는 안 되는 명령 =="
assert "sudo -n (비대화형)"              0 "$(blocked 'sudo -n true')"
assert "sudo --non-interactive"         0 "$(blocked 'sudo --non-interactive apt-get install x')"
assert "sudo -nE (묶음 플래그)"          0 "$(blocked 'sudo -nE ls')"
assert "sudo -u root -n"                0 "$(blocked 'sudo -u root -n ls')"
assert "echo sudo"                      0 "$(blocked 'echo sudo')"
assert "따옴표 안 ; sudo"                0 "$(blocked 'echo "a; sudo x"')"
assert "grep 패턴의 sudo"                0 "$(blocked 'grep -rn "sudo apt" docs/')"
assert "커밋 메시지의 sudo"              0 "$(blocked 'git commit -m "fix: sudo 처리"')"
assert "주석의 sudo"                     0 "$(blocked 'ls # 다음엔 sudo ls')"
assert "man sudo"                       0 "$(blocked 'man sudo')"
assert "sudoku (다른 명령)"              0 "$(blocked 'sudoku --help')"
assert "평범한 명령"                     0 "$(blocked 'ls -la')"
assert "sudo -k (자격 지우기, 묻지 않음)"  0 "$(blocked 'sudo -k')"
assert "sudo -V / --help"               0 "$(blocked 'sudo -V; sudo --help')"
assert "히어독 본문의 sudo (스크립트를 쓰는 중)" 0 "$(blocked $'cat > install.sh <<\'EOF\'\nsudo apt-get install x\nEOF')"
assert "<<- 히어독 본문의 sudo"           0 "$(blocked $'cat <<-EOF > a.sh\n\tsudo ls\n\tEOF')"
assert "히어독이 끝난 뒤의 sudo 는 잡는다"  1 "$(blocked $'cat > a.txt <<EOF\nhi\nEOF\nsudo ls')"

echo "== R-sudo — 막을 때 다음 행동을 준다 =="
run_guard 'sudo apt-get install -y redis-server'
assert "! <명령> 으로 넘기라고 말한다"     1 "$(grep -c '! <명령>' "$TMP/out")"
assert "sudo -n 길을 알려 준다"           1 "$(grep -c 'sudo -n' "$TMP/out")"
assert "게이트 기록에 R-sudo block"       yes "$(grep '"R-sudo"' "$TMP/proj/.harness/gate-events.jsonl" 2>/dev/null | tail -1 | grep -q '"block"' && echo yes || echo no)"

echo "== 가드 자신이 셸 오류를 내지 않는다 =="
# 인라인 python 은 bash 큰따옴표 안이다 — 주석의 백틱 하나가 명령 치환으로 실행된 적이 있다(2026-10-14).
ERR=$(python3 -c "import json;print(json.dumps({'tool_input':{'command':'ls -la','timeout':600000}}))" \
      | CLAUDE_PROJECT_DIR="$TMP/proj" bash "$HOOK" 2>&1 >/dev/null)
assert "stderr 가 비어 있다" "" "$ERR"

echo "== 새 판정이 깨져도 기존 R5 는 꺼지지 않는다 (code-reviewer 지적) =="
# 외톨이 서로게이트는 print(cmd) 를 UnicodeEncodeError 로 죽였다 → CMD 가 비어 R5 가 조용히 꺼졌다
OUT_R5=$(printf '%s' '{"tool_input":{"command":"git commit --no-verify -m \ud800"}}' | CLAUDE_PROJECT_DIR="$TMP/proj" bash "$HOOK" 2>&1)
assert "깨진 문자가 섞여도 R5 가 발화한다" 1 "$(grep -c '\[R5\]' <<< "$OUT_R5")"

echo "== R-fg — 앞에서 길게 막아 두면 경고한다 (차단 아님) =="
assert "timeout 600000 앞 실행 → 경고"     1 "$(warned 'npm run init:setting > init.log 2>&1' 600000)"
assert "timeout 300000 앞 실행 → 경고"     1 "$(warned 'bash tests/run-all.sh' 300000)"
run_guard 'npm run init:setting' 600000
assert "경고여도 막지 않는다 (rc 0)"        0 "$(cat "$TMP/rc")"
assert "배경 + Monitor 로 안내한다"          1 "$(grep -c 'run_in_background.*Monitor' "$TMP/out")"
assert "주입 출력이 유효한 JSON"             yes "$(python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$TMP/out" 2>/dev/null && echo yes || echo no)"
assert "게이트 기록에 R-fg warn"            yes "$(grep '"R-fg"' "$TMP/proj/.harness/gate-events.jsonl" 2>/dev/null | tail -1 | grep -q '"warn"' && echo yes || echo no)"

echo "== R-fg — 조용해야 하는 경우 =="
assert "timeout 없음"                      0 "$(warned 'ls -la' '')"
assert "짧은 timeout 120000"               0 "$(warned 'bash tests/x.sh' 120000)"
assert "299999 (기준 바로 아래)"            0 "$(warned 'bash tests/x.sh' 299999)"
assert "배경 실행이면 timeout 커도 조용"     0 "$(warned 'npm run init:setting' 600000 1)"
assert "git commit 은 커밋 안내만 (중복 없음)" 0 "$(warned 'git commit -m x' 600000)"

echo
echo "통과 $PASS / 실패 $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
