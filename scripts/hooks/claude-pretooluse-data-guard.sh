#!/usr/bin/env bash
# PreToolUse(Bash) hook — 데이터를 지우는 명령은 사람 승인 뒤에만 (R-del).
#
# 출처: 2026-10-27 jj-agent-room 번역 실측 뒤 에이전트가 개발 DB 의 번역 결과(건 7 · 문장 512 · 기록 252)를
#       `psql … DELETE` · `rm -rf` 로 묻지 않고 지웠다. 백업이 없어 되살릴 수 없었다. 규칙 문장은 이미 있었고
#       에이전트가 계획서의 "지운다" 를 승인으로 읽었다 — 그래서 기계가 멈춰 세운다.
# 근거: docs/exec-plans/completed/2026-10-27-data-delete-guard-plan.md
#
# 판정은 같은 폴더의 data_delete.py. 지우는 명령이면 permissionDecision "ask" — 사람이 승인 창에서 고른다.
# `-p` 실행에서는 Claude Code 가 ask 를 거부로 바꾸고 사유를 도구 결과로 돌려준다.
#
# 끄기: .harnessrc 에 HARNESS_DATA_GUARD=off
# 등록: .claude/settings.json 의 hooks.PreToolUse[matcher="Bash"].

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${CLAUDE_PROJECT_DIR:-$HOOK_DIR/../..}" 2>/dev/null || true

[[ -f .harnessrc ]] && source .harnessrc >/dev/null 2>&1
[[ "${HARNESS_DATA_GUARD:-on}" == "off" ]] && exit 0
command -v python3 >/dev/null 2>&1 || exit 0

INPUT="$(cat 2>/dev/null || true)"
[[ -z "$INPUT" ]] && exit 0

# 거의 모든 명령에 불린다 — 지우기·DB 도구와 관련된 글자가 없으면 python 을 띄우지 않는다(-f 파일 SQL 은 도구 이름만 보인다).
# JSON 은 줄바꿈을 \n 으로 적는다 — 줄 맨 앞 rm 의 앞 글자가 n 이 되므로 \n 도 경계로 친다(변이 시험이 찾음).
grep -Eiq 'delete|truncate|drop|flush|unlink|(^|[^a-z]|\\n)rm([^a-z]|$)|clean|(^|[^a-z]|\\n)del([^a-z]|$)|remove|psql|mysql|mariadb|sqlite3|sqlcmd|mongo|clickhouse' <<<"$INPUT" || exit 0

DATA_HOOK_DIR="$HOOK_DIR" python3 -c '
import json, os, sys
sys.path.insert(0, os.environ["DATA_HOOK_DIR"])
try:
    d = json.load(sys.stdin)
    ti = d.get("tool_input", {}) if isinstance(d, dict) else {}
    cmd = str((ti if isinstance(ti, dict) else {}).get("command", "") or "")
except Exception:
    sys.exit(0)
try:
    import data_delete
    found = data_delete.judge(cmd)
except Exception as e:
    print("[R-del] 판정 실패: %s" % e, file=sys.stderr)
    sys.exit(0)
if not found:
    sys.exit(0)
reason = ("[R-del] 데이터를 지우는 명령입니다 (%s). 실행 전에 사용자에게 ① 무엇을 몇 줄·몇 개 지우는지 "
          "② 되살릴 수 있는지(백업이 있는지)를 보이고 승인을 받으십시오. 계획서·문서의 \"지운다\" 문구는 승인이 아닙니다 — "
          "작업이 만든 데이터(개발 DB 의 줄, 결과 파일)도 같습니다. 근거: .claude/rules/harness/decision-ledger.md §1" % found)
try:
    import gate_event
    gate_event.emit("R-del", "ask", "pretooluse", None, found)
except Exception:
    pass
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": reason,
    "additionalContext": reason,
}}, ensure_ascii=False))
' <<<"$INPUT"
exit 0
