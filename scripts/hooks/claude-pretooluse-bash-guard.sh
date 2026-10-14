#!/usr/bin/env bash
# PreToolUse(Bash) hook — Claude 가 Bash 도구로 위험 명령을 실행하려 할 때 가로챈다.
#
# 출처: rim-kanban Phase 1 (scripts/hooks/pre-commit-reviewer-check.sh) 를 generic 화.
# 근거: docs/design-docs/core-beliefs.md#r5, #r-review
#
# 두 가지를 검사한다:
#   1. `git commit` — 위험 신호가 있으면 리뷰 검토를 상기시킨다.
#   2. `--no-verify` / `-n` (단축) — 우회 시도 탐지. R5 강제.
#
# 메커니즘: stdin 으로 도구 호출 페이로드(JSON)가 들어오고,
# stdout 으로 hookSpecificOutput 을 출력하면 additionalContext 가
# 모델 컨텍스트에 주입된다.
#
# 등록: .claude/settings.json 의 hooks.PreToolUse[matcher=Bash] 항목.

set -euo pipefail

# CWD 가드 — Claude Code 가 주입하는 $CLAUDE_PROJECT_DIR 로 이동 (없으면 스크립트 위치 기반).
cd "${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}" 2>/dev/null || true

if [[ -f "$(dirname "$0")/gate_emit.sh" ]]; then
  # shellcheck source=/dev/null
  source "$(dirname "$0")/gate_emit.sh"
fi
declare -F gate_emit >/dev/null 2>&1 || gate_emit() { :; }

INPUT=$(cat 2>/dev/null || true)
# 파싱과 판정을 python3 한 번에 끝낸다 — 이 훅은 모든 Bash 호출에 걸린다(gate_emit.sh 실측: 기동 1회 21ms).
#   1행: "<SUDO 0|1> <FG 0|1>"   2행부터: 명령 원문
#
# SUDO — 명령 위치의 sudo 가 -n/--non-interactive 없이 쓰였는가 (R-sudo, 계획 2026-10-14 G4).
#   에이전트 Bash 는 비밀번호를 줄 수 없어 sudo 는 Password: 에서 타임아웃까지 멈춘다.
#   shlex 의 punctuation_chars 로 따옴표·주석·`;&|()`·줄바꿈을 존중해 자른다 — `echo "a; sudo x"`·
#   `grep "sudo apt"`·`# sudo` 를 잡으면 R5 의 20/20 오탐을 되풀이한다.
#   -S 는 막는다: 비밀번호를 stdin 으로 흘리는 길은 비밀값이 명령·로그에 남는다.
#   알려진 한계: `bash -c "sudo …"`·`xargs sudo` 는 못 잡는다(따옴표 안·인자 위치).
# FG — timeout ≥ 300000ms 를 주고 배경이 아니다 (R-fg, G5). 명령 패턴이 아니라 에이전트가 준 타임아웃을 본다.
#   300초는 pytest_gate.sh 의 "앞에서 기다리기 위험해지는 선"(한도 600초의 절반)과 같은 값.
PARSED=$(printf '%s' "$INPUT" | python3 -c "
import sys, json, shlex, re
FG_TIMEOUT_MS = 300000
# 뒤의 단어를 명령 위치로 두는 것 — 감싸는 명령 + 셸 예약어(if·then·do … ! {).
WRAPPERS = {'env', 'time', 'nohup', 'exec', 'command', 'builtin',
            'if', 'then', 'elif', 'else', 'while', 'until', 'do', '!', '{'}
SEP_CHARS = set(';&|()\n')     # shlex 는 붙은 구분자(예: ');' ';' 와 줄바꿈)를 한 토큰으로 묶는다 — 글자 집합으로 본다
NO_PROMPT = {'-K', '-V', '--help', '--version'}   # 비밀번호를 묻지 않는 sudo
HEREDOC = re.compile(r'<<(?!<)-?\s*([\'\"]?)(\w+)\1')
def drop_heredoc_bodies(cmd):
    # 히어독 본문은 명령이 아니라 데이터다 — 설치 스크립트를 cat <<EOF 로 쓰는 중에 sudo 줄이 있어도 막지 않는다.
    out, ends = [], []
    for line in cmd.split('\n'):
        if ends:
            if line.strip() == ends[0]:
                ends.pop(0)
            continue
        out.append(line)
        ends = [m.group(2) for m in HEREDOC.finditer(line)]
    return '\n'.join(out)
def sudo_waits(cmd):
    lex = shlex.shlex(drop_heredoc_bodies(cmd), posix=True, punctuation_chars=';&|()\n')
    lex.whitespace = ' \t\r'
    lex.commenters = '#'
    try:
        toks = list(lex)
    except ValueError:
        return False                      # 따옴표가 안 닫혔다 — 판정 불가는 막지 않는다
    at_start, i = True, 0
    while i < len(toks):
        t = toks[i]
        if set(t) <= SEP_CHARS:
            at_start = True; i += 1; continue
        if not at_start:
            i += 1; continue
        if '=' in t and not t.startswith('-') or t in WRAPPERS:
            i += 1; continue              # VAR=값 · env · time … 은 명령 위치를 뒤로 민다
        at_start = False
        if t.rsplit('/', 1)[-1] != 'sudo':
            i += 1; continue
        j, kill_cache = i + 1, False
        while j < len(toks) and toks[j].startswith('-') and not set(toks[j]) <= SEP_CHARS:
            o = toks[j]
            if o in NO_PROMPT or o == '--non-interactive' or (not o.startswith('--') and 'n' in o[1:]):
                break
            kill_cache = kill_cache or o == '-k'
            j += 1
            if o in ('-u', '-g', '-h', '-p', '-C', '-D', '-r', '-t', '-U', '-T'):
                j += 1                    # 값을 받는 옵션 — 다음 토큰은 값이다
        else:
            if kill_cache and (j >= len(toks) or set(toks[j]) <= SEP_CHARS):
                i = j; continue           # 명령 없는 sudo -k 는 자격만 지운다 — 묻지 않는다
            return True
        i = j
    return False
try:
    d = json.load(sys.stdin)
    ti = d.get('tool_input', {}) if isinstance(d, dict) else {}
    ti = ti if isinstance(ti, dict) else {}
    cmd = str(ti.get('command', '') or '')
    try:
        timeout = int(ti.get('timeout') or 0)
    except (TypeError, ValueError):
        timeout = 0
    fg = timeout >= FG_TIMEOUT_MS and ti.get('run_in_background') is not True
except Exception:
    cmd, fg = '', False
# 새 판정이 깨져도 명령 원문은 반드시 내보낸다 — CMD 가 비면 아래 R5·커밋 안내가 조용히 꺼진다(code-reviewer 지적).
try:
    sudo = sudo_waits(cmd)
except Exception:
    sudo = False
print(f'{int(sudo)} {int(fg)}', flush=True)
sys.stdout.buffer.write(cmd.encode('utf-8', 'replace') + b'\n')
" 2>/dev/null || true)
read -r SUDO_TRIP FG_TRIP <<< "${PARSED%%$'\n'*}"
CMD=""
[[ "$PARSED" == *$'\n'* ]] && CMD="${PARSED#*$'\n'}"

# R-sudo — 차단. 판정이 명확하고(명령 위치 + -n 없음) 멈춤이 확정적이다(계획 §6).
if [[ "${SUDO_TRIP:-0}" == "1" ]]; then
  gate_emit R-sudo block pretooluse "" "비대화형 아닌 sudo"
  cat >&2 <<'EOF'
[R-sudo BLOCK] sudo 는 비밀번호(Password:)를 기다리며 멈춘다 — 에이전트 Bash 는 입력을 줄 수 없어 타임아웃까지 아무 말 없이 막힌다.
사용자에게 이 명령을 `! <명령>` 으로 직접 돌려 달라고 넘기고, 끝난 뒤 이어서 진행하십시오.
비밀번호 없이 되는지만 볼 때는 `sudo -n <명령>` (안 되면 바로 실패한다).
근거: docs/design-docs/core-beliefs.md#r-sudo
EOF
  exit 2
fi

# --no-verify 우회 시도 탐지 — 단순 grep 으로 100% 차단은 불가능하나
# 강한 경고로 에이전트가 자기 검열하도록 유도.
#
# `-n` 은 **`git commit` 문맥에서만** `--no-verify` 의 약어다.
# 문맥을 안 보던 이전 규칙은 `grep -n`·`sort -n`·`head -n`·`git log -n` 을 전부 잡아
# 발화율 100%(관측 20건 전부 오탐, 2026-09-03)를 냈다. 우회를 막는 룰의 경고가
# 상시 배경 소음이 되면 진짜 우회가 섞여도 눈에 띄지 않는다 — 경보가 무의미해진다.
# 근거: docs/audits/2026-09-03-gate-firing-first-observation.md
#
# 알려진 한계: 커밋 메시지 본문에 들어간 `-n`(`git commit -m "fix -n bug"`)은 여전히 오탐이다.
# 명령 문자열만으로 인자와 메시지를 가르려면 셸 파서가 필요하고 그 비용이 이득을 넘는다.
#
# **명령 세그먼트 단위로 본다.** 명령 전체에서 "git commit 이 있는가" 와 "-n 이 있는가" 를
# 따로 물으면 `git log -n 5 && git commit -m x` 가 발화한다 — 두 조건이 서로 다른
# 명령에서 충족되기 때문이다. 이는 이 수정이 없애려던 오탐과 정확히 같은 종류다.
# `;` `&&` `||` `|` 로 잘라, **같은 세그먼트 안에서** 둘이 함께 성립할 때만 발화한다.
R5_TRIP=0
if echo "$CMD" | grep -Eq -- '(^|[[:space:]])--no-verify([[:space:]]|$)'; then
  # 이 문자열은 git 외 쓰임이 사실상 없다. 문맥을 따지지 않는다 —
  # 우회 1건을 놓치는 비용이 오탐 1건보다 크다.
  R5_TRIP=1
else
  while IFS= read -r _seg; do
    echo "$_seg" | grep -Eq '(^|[[:space:]])git([[:space:]]+-c[[:space:]]+[^[:space:]]+)*[[:space:]]+commit([[:space:]]|$)' || continue
    # 묶음 단축 플래그(`git commit -nm x`)도 잡는다 — 유효한 우회인데 이전 규칙은 놓쳤다.
    if echo "$_seg" | grep -Eq -- '(^|[[:space:]])-[a-zA-Z]*n[a-zA-Z]*([[:space:]]|$)'; then
      R5_TRIP=1
      break
    fi
  done < <(printf '%s\n' "$CMD" | sed -e 's/&&/\n/g' -e 's/||/\n/g' -e 's/;/\n/g' -e 's/|/\n/g')
fi

if (( R5_TRIP )); then
  python3 <<'PY'
import json
out = {
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": (
      "[R5] --no-verify 금지. hook 이 막으면 코드/hook 을 고친다. "
      "근거: docs/design-docs/core-beliefs.md#r5"
    )
  }
}
print(json.dumps(out, ensure_ascii=False))
PY
  # R5 는 pass 를 세지 않는다. 분모가 "모든 Bash 호출" 이 되면 도구 호출마다 21ms 가 붙고,
  # 그 비율은 아무것도 말해주지 않는다 — 알고 싶은 것은 **우회 시도 횟수** 자체다.
  gate_emit R5 warn pretooluse "" "--no-verify 시도"
  exit 0
fi

# git commit 감지 — 리뷰 기록(.claude/.review-dirty)이 있으면 soft reminder 만 주입.
if echo "$CMD" | grep -q "git commit"; then
  # 사람이 정해야 할 것(문장 확인 대기 · 성향 승인 대기 · 정답지 표본)이 있으면 안내 맨 위에 싣는다.
  # 세션 ID 는 JSON 을 파이썬으로 읽는다(줄 단위로 자르면 여러 줄 값에서 어긋난다 — 2f0c623). 스크립트·세션 ID 가 없으면 조용히 건너뛴다.
  ASK_TEXT=""
  SESSION_ID=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
try:
    print(json.load(sys.stdin).get('session_id') or '')
except Exception:
    print('')
" 2>/dev/null || true)
  if [[ -n "$SESSION_ID" && -f scripts/hermes-ask.py ]]; then
    ASK_TEXT=$(python3 scripts/hermes-ask.py list --session "$SESSION_ID" 2>/dev/null || true)
  fi
  export ASK_TEXT
  # 여기는 분모가 성립한다 — 커밋 시도당 빚이 남아 있었는가.
  if [[ -f .claude/.review-dirty ]]; then
    gate_emit R-review warn pretooluse "" "빚이 남은 채 커밋 시도"
  else
    gate_emit R-review pass pretooluse "" "빚 없음"
  fi
  if [[ -f .claude/.review-dirty ]]; then
    DIRTY_SUMMARY=$(head -5 .claude/.review-dirty 2>/dev/null || echo "(read error)")
    python3 - "$DIRTY_SUMMARY" <<'PY'
import json, os, sys
summary = sys.argv[1]
ask = os.environ.get("ASK_TEXT", "").strip()
out = {
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": (
      (ask + "\n\n" if ask else "") +
      "[R-review] 최근 코드 편집 기록이 있습니다. 변경이 크거나 공유 경계/보안/DB/동시성에 "
      "영향이 있으면 commit 전 code-reviewer 를 사용하세요.\n\n"
      f"{summary}\n\n"
      "단순 변경이면 계속 진행해도 됩니다. 기록 정리: rm .claude/.review-dirty\n"
      "코드·훅·설정 동작을 바꿨다면 pre-commit-measure 스킬로 주장마다 가장 작은 실행을 돌려 메시지에 실측: 을 남기세요."
    )
  }
}
print(json.dumps(out, ensure_ascii=False))
PY
    exit 0
  fi
  python3 <<'PY'
import json, os
ask = os.environ.get("ASK_TEXT", "").strip()
out = {
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": (
      (ask + "\n\n" if ask else "") +
      "[HARNESS] git commit 감지. 큰 변경이나 공유 경계 변경이면 "
      "code-reviewer 사용을 고려하세요. 코드·훅·설정 동작을 바꿨다면 "
      "pre-commit-measure 스킬로 주장마다 가장 작은 실행을 돌려 메시지에 실측: 을 남기세요."
    )
  }
}
print(json.dumps(out, ensure_ascii=False))
PY
  exit 0   # 커밋은 위 안내 하나만 — 주입 JSON 은 호출당 하나여야 한다
fi

# R-fg — 경고만. 이 안내는 도구 결과와 함께 닿으므로 **이번 호출은 그대로 앞에서 막힌다** —
# 다음 호출을 바꾸는 근거다(R-out 과 같은 성격, 계획 §6). pass 는 세지 않는다(R5 와 같은 이유).
if [[ "${FG_TRIP:-0}" == "1" ]]; then
  gate_emit R-fg warn pretooluse "" "timeout ≥ 300000ms 앞 실행"
  python3 <<'PY'
import json
out = {
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": (
      "[R-fg] 5분 이상 걸릴 수 있는 명령을 앞에서 돌렸습니다. 끝날 때까지 진행·멈춤·입력 대기를 "
      "사용자에게 알릴 수 없습니다. 다음부터는 출력을 파일로 받아 run_in_background 로 돌리고, "
      "Monitor 로 진행·실패·입력 대기(Password·[y/N]) 줄을 걸러 지켜보며 중간 보고하십시오. "
      "결과는 같은 턴에서 읽습니다. 자세히: run-to-the-end 스킬 · docs/design-docs/core-beliefs.md#r-fg"
    )
  }
}
print(json.dumps(out, ensure_ascii=False))
PY
fi

exit 0
