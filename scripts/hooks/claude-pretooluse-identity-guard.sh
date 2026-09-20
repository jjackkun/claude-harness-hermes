#!/usr/bin/env bash
# PreToolUse hook — 명부(.hermes/agents.json)·기억 파생본(.hermes/agents/<id>/MEMORY.md) 손편집을 편집 순간에 막는다.
# (계획 2026-09-20-identity-files-edit-guard; 근거: 첫 행동 평가에서 competing 프롬프트의 직접 Edit 4/4 가 막는 훅 없이 통과)
#
# 왜: 두 파일은 CLI 가 쓰는 파일이다. 명부를 손으로 쓰면 조직 축 검증·id 발급·이력(agent.created)을 건너뛰고(RV-06),
#     MEMORY.md 는 기억 이벤트에서 계산되는 파생본이라 손으로 쓴 줄은 다음 refresh-memory 때 조용히 사라진다(C-20·D-01).
# 막는 것: Edit·Write·MultiEdit 의 file_path 가 프로젝트 안의 두 대상일 때 / Bash 의 쓰기 연산(> >> tee sed -i cp mv rm truncate)이 두 대상을 향할 때.
# 안 막는 것: SOUL.md(사람 승인 편집이 정상 경로) · organization.yaml · 읽기(cat grep jq) · 정식 CLI(hermes-agent.py …) ·
#            프로젝트 밖 경로(realpath 로 판정 — /tmp 여부와 무관)와 변수 경로($T/… — 테스트 픽스처). 단 $CLAUDE_PROJECT_DIR·$PWD 는 프로젝트로 본다.
# SOUL.md(계획 2026-09-20-soul-self-approval-gap): 편집은 막지 않되 **초안 표시 줄을 없애는 것**(= 승인)은 사람의 승인 말이 있는 턴에만.
#   Edit·MultiEdit·Write 가 표시 줄을 없애거나, 초안 상태인 SOUL.md 에 Bash 쓰기 연산을 하거나, `hermes-agent.py approve-soul` 을 부르면
#   (a) HERMES_AGENT_ID 가 있으면(소환된 에이전트) 항상 차단, (b) .hermes/.soul-approval-intent 가 approve=true 이고 60분 안이 아니면 차단.
# 한계: python -c "open(...,'w')" 같은 코드 경유 쓰기는 명령 문자열로 못 가린다 — 흔한 길만 막고 나머지는 harness-eval 로 본다.
# 세션 안 탈출구는 없다(key-guard 와 같은 원칙) — 사람이 손봐야 하면 세션 밖 터미널에서.
set -uo pipefail
INPUT="$(cat 2>/dev/null || true)"
[[ -n "$INPUT" ]] || exit 0
PROJECT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}"

verdict="$(printf '%s' "$INPUT" | IDG_PROJECT="$PROJECT" python3 -c '
import json, os, re, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
tool = d.get("tool_name") or ""
inp = d.get("tool_input") or {}
project = os.path.realpath(os.environ.get("IDG_PROJECT") or ".")
TARGET = re.compile(r"(^|/)\.hermes/(agents\.json|agents/[^/\s\x27\"]+/MEMORY\.md)$")

SOUL = re.compile(r"(^|/)\.hermes/agents/[^/\s\x27\"]+/SOUL\.md$")
MARK = "초안 — 기계가 조직 값에서 채웠다"

def label(path):
    return "명부(.hermes/agents.json)" if path.endswith("agents.json") else "기억 파생본(MEMORY.md)"

def inside(real):
    return real == project or real.startswith(project + os.sep)

def is_draft(real):
    try:
        return MARK in open(real, encoding="utf-8").read()
    except OSError:
        return False

def approval_ok():
    # 사람의 승인 말이 있는 턴인가 — 소환된 에이전트는 언제나 아니다.
    if os.environ.get("HERMES_AGENT_ID"):
        return False
    try:
        import time
        d = json.load(open(os.path.join(project, ".hermes", ".soul-approval-intent"), encoding="utf-8"))
        return bool(d.get("approve")) and (time.time() - float(d.get("ts", 0))) < 3600
    except Exception:
        return False

def removes_mark(tool, inp, real):
    if not is_draft(real):
        return False
    if tool == "Write":
        return MARK not in str(inp.get("content") or "")
    edits = inp.get("edits") if tool == "MultiEdit" else [inp]
    return any(MARK in str(e.get("old_string") or "") and MARK not in str(e.get("new_string") or "")
               for e in (edits or []) if isinstance(e, dict))

def soul_verdict(how, shown):
    if approval_ok():
        sys.exit(0)
    who = "소환된 에이전트는 SOUL 을 승인할 수 없습니다" if os.environ.get("HERMES_AGENT_ID") else "최근 사람 프롬프트에 승인 의사가 없습니다"
    print(f"{how}\t{shown}\tSOUL|{who}")
    sys.exit(0)

if tool in ("Edit", "Write", "MultiEdit"):
    fp = str(inp.get("file_path") or "")
    if not fp:
        sys.exit(0)
    real = os.path.realpath(fp if os.path.isabs(fp) else os.path.join(project, fp))
    if inside(real) and TARGET.search(real):
        print(f"{tool}\t{os.path.relpath(real, project)}\t{label(real)}")
    elif inside(real) and SOUL.search(real) and removes_mark(tool, inp, real):
        soul_verdict(f"{tool} 초안 표시 줄 삭제", os.path.relpath(real, project))
    sys.exit(0)

if tool != "Bash":
    sys.exit(0)
cmd = str(inp.get("command") or "")
# heredoc 본문은 명령이 아니다 — 커밋 메시지·문서에 명령 이름이 적혀 있다고 막으면 안 된다(2026-09-20: 이 가드가 자기 커밋을 막았다).
cmd = re.sub(r"(<<-?\s*[\x27\"]?(\w+)[\x27\"]?[^\n]*)\n.*?\n\s*\2\b", r"\1", cmd, flags=re.S)
# 호출 판정은 따옴표 안 글자를 걷어낸 뒤, 명령 자리에서만 본다(key-guard 와 같은 방식).
bare = re.sub(r"\"(?:\\.|[^\"\\])*\"|\x27[^\x27]*\x27", " ", cmd)
if re.search(r"(^|[;&|(]|\n)\s*(?:\w+=\S+\s+)*(?:python3?\s+)?[^\s;&|]*hermes-agent\.py\b[^;&|\n]*\bapprove-soul\b", bare):
    soul_verdict("Bash approve-soul", "hermes-agent.py approve-soul")
SOUL_ARG = r"[\x27\"]?([^\s\x27\";|&<>]*\.hermes/agents/[^/\s\x27\";|&<>]+/SOUL\.md)[\x27\"]?"
for rx in (r">>?\s*" + SOUL_ARG, r"\btee\b[^|;&]*?\s" + SOUL_ARG, r"\bsed\b[^|;&]*\s-i\b[^|;&]*?\s" + SOUL_ARG,
           r"\b(?:cp|mv)\b[^|;&]*\s" + SOUL_ARG + r"\s*(?:$|[;&|])", r"\b(?:rm|truncate)\b[^|;&]*?\s" + SOUL_ARG):
    m = re.search(rx, cmd)
    if m and "$" not in m.group(1):
        real = os.path.realpath(m.group(1) if os.path.isabs(m.group(1)) else os.path.join(project, m.group(1)))
        if inside(real) and is_draft(real):
            soul_verdict("Bash 쓰기(초안 상태의 SOUL.md)", os.path.relpath(real, project))
TARGET_ARG = r"[\x27\"]?([^\s\x27\";|&<>]*\.hermes/(?:agents\.json|agents/[^/\s\x27\";|&<>]+/MEMORY\.md))[\x27\"]?"
WRITES = [
    (r">>?\s*" + TARGET_ARG, "리다이렉트(> >>)"),
    (r"\btee\b(?:\s+-\w+)*[^|;&]*?\s" + TARGET_ARG, "tee"),
    (r"\bsed\b[^|;&]*\s-i\b[^|;&]*?\s" + TARGET_ARG, "sed -i"),
    (r"\b(?:cp|mv)\b[^|;&]*\s" + TARGET_ARG + r"\s*(?:$|[;&|])", "cp/mv 목적지"),
    (r"\b(?:rm|truncate)\b[^|;&]*?\s" + TARGET_ARG, "rm/truncate"),
]
for rx, op in WRITES:
    m = re.search(rx, cmd)
    if not m:
        continue
    tok = m.group(1)
    if "$" in tok:
        # 변수 경로는 테스트 픽스처($T/…)로 본다. 단 프로젝트를 가리키는 변수는 프로젝트다.
        if not re.search(r"\$\{?(CLAUDE_PROJECT_DIR|PWD)\b", tok):
            continue
    else:
        # 글자 그대로의 경로는 "프로젝트 안인가" 로 판정한다 — /tmp 로 시작한다고 픽스처가 아니다
        # (2026-09-20 실측: 프로젝트가 /tmp 아래인 평가 픽스처에서 `cat >> /tmp/…/MEMORY.md` 로 우회됐다).
        real = os.path.realpath(os.path.expanduser(tok) if os.path.isabs(os.path.expanduser(tok)) else os.path.join(project, tok))
        if not (real == project or real.startswith(project + os.sep)):
            continue
    print(f"Bash {op}\t{tok}\t{label(tok)}")
    sys.exit(0)
' 2>/dev/null)"

[[ -n "$verdict" ]] || exit 0
IFS=$'\t' read -r how path what <<< "$verdict"

if [[ -f "$(dirname "$0")/gate_emit.sh" ]]; then
  # shellcheck source=/dev/null
  source "$(dirname "$0")/gate_emit.sh"
  declare -F gate_emit >/dev/null 2>&1 && gate_emit R-identity block pretooluse "$path" "$how"
fi

if [[ "$what" == SOUL\|* ]]; then
  cat >&2 <<EOF
[identity-guard BLOCK] SOUL 승인은 사람의 몫입니다 (D-01) — ${what#SOUL|} ($how → $path).
  초안 표시 줄을 지우는 것이 곧 승인입니다. 에이전트가 스스로 지우지 않습니다.
  → 사용자에게 SOUL 의 역할 문단을 보여 주고 승인 여부를 물으십시오. 사용자가 "승인" 이라고 말한 턴에:
     python3 scripts/hermes-agent.py approve-soul "<이름>"
  표시 줄을 **남기는** 편집(내용 다듬기)은 막지 않습니다.
  근거: docs/exec-plans/completed/2026-09-20-soul-self-approval-gap.md · D-01
EOF
  exit 2
fi

cat >&2 <<EOF
[identity-guard BLOCK] $what 을(를) 손으로 쓰려 했습니다 ($how → $path).
  이 파일은 CLI 가 씁니다 — 손으로 쓰면 명부는 검증·id 발급·이력을 건너뛰고, MEMORY.md 는 다음 재계산 때 사라집니다.
  → 입사: python3 scripts/hermes-agent.py hire "<이름>" --org "<분야>,<직급>,<조직>" [--template <템플릿>]
  → 가르침·기억: python3 scripts/hermes-agent.py teach "<이름>" "<한 줄>" --about <domain>/<slug>   (소환된 에이전트는 note)
  → 기억 다시 만들기: python3 scripts/hermes-agent.py refresh-memory [이름]
  SOUL.md 는 사람 승인 편집이 정상 경로라 막지 않습니다. 사람이 직접 손봐야 하면 세션 밖 터미널에서 하십시오.
  근거: docs/exec-plans/completed/2026-09-20-identity-files-edit-guard.md · D-01 · C-20 · RV-06
EOF
exit 2
