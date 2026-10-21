#!/usr/bin/env bash
# PreToolUse(Bash · Task|Agent) hook — 사용자 자원(구독 사용량)을 크게 쓰는 호출을 멈춰 세운다 (R-cost).
#
# 출처: 2026-10-21 기획 사슬 작업 중 평가를 묻지 않고 대량 실행 → 사용자 터미널 측정이
#       구독 한도에 걸려 무효. 모델을 정하지 않은 general-purpose 24개가 부모 모델(Opus)로 돌았다.
# 근거: docs/exec-plans/active/2026-10-21-cost-guard-plan.md
#
# 판정 (모듈은 같은 폴더의 형제 파일):
#   Bash       G1 cost_command.py     비싼 평가 실행 → ask
#   Task|Agent G2 cost_agent_model.py 모델을 못 정함 → deny (사유에 고칠 방법)
#              G3 agent_count.py      세션 누적 HARNESS_AGENT_ASK_AT 배수 번째 → ask
# `-p` 실행에서는 Claude Code 가 ask 를 거부로 바꾸고 사유를 도구 결과로 돌려준다(공식 문서) —
# 그래서 헤드리스 판별을 하지 않는다. 여러 훅의 결정은 deny > ask > allow 로 합쳐진다.
#
# 끄기: .harnessrc 에 HARNESS_COST_GUARD=off
# 등록: .claude/settings.json 의 hooks.PreToolUse[matcher="Bash"] 와 [matcher="Task|Agent"].

set -uo pipefail

# $0 이 상대 경로일 수 있으므로 프로젝트로 옮기기 전에 훅 폴더를 잡는다 — 늦으면 모듈 import 가 조용히 실패한다.
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${CLAUDE_PROJECT_DIR:-$HOOK_DIR/../..}" 2>/dev/null || true

# .harnessrc 가 무엇을 찍든 판정 JSON(stdout)에 섞이지 않게 한다.
[[ -f .harnessrc ]] && source .harnessrc >/dev/null 2>&1
[[ "${HARNESS_COST_GUARD:-on}" == "off" ]] && exit 0
command -v python3 >/dev/null 2>&1 || exit 0

INPUT="$(cat 2>/dev/null || true)"
[[ -z "$INPUT" ]] && exit 0

# Bash 는 거의 모든 명령에 불린다 — 후보 이름이 글자로도 없으면 python 을 띄우지 않는다.
if ! grep -Eq '"tool_name" *: *"(Agent|Task)"' <<<"$INPUT"; then
  grep -Eq 'run_eval|run_loop|harness-eval' <<<"$INPUT" || exit 0
fi

read -r -d '' PYSRC <<'PY' || true
import json, os, sys
sys.path.insert(0, os.environ["COST_HOOK_DIR"])

DEFAULT_ASK_AT = 8  # 계획 G3 — 사고 세션의 정상 작업 최대치(6)를 넘는 첫 지점

def emit(verdict, detail):
    try:
        import gate_event
        gate_event.emit("R-cost", verdict, "pretooluse", None, detail)
    except Exception as e:
        print("[R-cost] 관측 기록 실패: %s" % e, file=sys.stderr)

def out(decision, reason):
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": decision,
        "permissionDecisionReason": reason,
        # permissionDecision 을 무시하는 구버전에서는 컨텍스트 주입으로 강등된다.
        "additionalContext": reason,
    }}, ensure_ascii=False))

def ask_at():
    raw = os.environ.get("HARNESS_AGENT_ASK_AT", "")
    return int(raw) if raw.isdigit() and int(raw) > 0 else DEFAULT_ASK_AT

def on_bash(ti):
    import cost_command
    if cost_command.classify(ti.get("command", "")) == "allow":
        emit("pass", "bash")
        return
    emit("warn", "bash ask")
    out("ask", "[R-cost] 모델을 여러 번 부르는 평가 실행입니다. 사용자에게 호출 수 · 모델 · "
               "더 싼 판 하나를 보이고 승인받은 뒤 다시 실행하십시오. "
               "근거: assets/rules/harness/decision-ledger.md §1")

def on_agent(d, ti):
    import cost_agent_model, agent_count
    kind = ti.get("subagent_type") or "general-purpose"
    if cost_agent_model.resolve(ti, os.getcwd(), os.path.expanduser("~")) is None:
        emit("block", "agent model 없음: %s" % kind)
        out("deny", "[R-cost] %s 는 모델이 정해지지 않아 부모 모델을 물려받습니다. "
                    "model 인자를 지정하십시오 — 기계적 작업 haiku · 일반 sonnet · 깊은 설계 opus." % kind)
        return
    n, every = agent_count.bump(d.get("session_id"), os.getcwd()), ask_at()
    if n is None or n % every:
        emit("pass", "agent %s" % ("세지 않음(session_id 없음)" if n is None else n))
        return
    emit("warn", "agent count %d" % n)
    out("ask", "[R-cost] 이 세션의 서브에이전트 %d번째 호출입니다(%d개마다 확인). 사용자에게 "
               "지금까지의 수와 남은 호출 계획(수 · 모델)을 보이고 승인받은 뒤 다시 부르십시오." % (n, every))

try:
    d = json.loads(sys.stdin.read())
except ValueError:
    sys.exit(0)
ti = d.get("tool_input") or {}
if d.get("tool_name") == "Bash":
    on_bash(ti)
elif d.get("tool_name") in ("Agent", "Task"):
    on_agent(d, ti)
PY

printf '%s' "$INPUT" \
  | COST_HOOK_DIR="$HOOK_DIR" HARNESS_AGENT_ASK_AT="${HARNESS_AGENT_ASK_AT:-}" python3 -c "$PYSRC"
exit 0
