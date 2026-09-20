#!/usr/bin/env bash
# PreToolUse hook — 명부(.hermes/agents.json)·기억 파생본(.hermes/agents/<id>/MEMORY.md) 손편집을 편집 순간에 막는다.
# (계획 2026-09-20-identity-files-edit-guard; 근거: 첫 행동 평가에서 competing 프롬프트의 직접 Edit 4/4 가 막는 훅 없이 통과)
#
# 왜: 두 파일은 CLI 가 쓰는 파일이다. 명부를 손으로 쓰면 조직 축 검증·id 발급·이력(agent.created)을 건너뛰고(RV-06),
#     MEMORY.md 는 기억 이벤트에서 계산되는 파생본이라 손으로 쓴 줄은 다음 refresh-memory 때 조용히 사라진다(C-20·D-01).
# 막는 것: Edit·Write·MultiEdit 의 file_path 가 프로젝트 안의 두 대상일 때 / Bash 의 쓰기 연산(> >> tee sed -i cp mv rm truncate)이 두 대상을 향할 때.
# 안 막는 것: SOUL.md(사람 승인 편집이 정상 경로) · organization.yaml · 읽기(cat grep jq) · 정식 CLI(hermes-agent.py …) ·
#            프로젝트 밖 경로(realpath 로 판정 — /tmp 여부와 무관)와 변수 경로($T/… — 테스트 픽스처). 단 $CLAUDE_PROJECT_DIR·$PWD 는 프로젝트로 본다.
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

def label(path):
    return "명부(.hermes/agents.json)" if path.endswith("agents.json") else "기억 파생본(MEMORY.md)"

if tool in ("Edit", "Write", "MultiEdit"):
    fp = str(inp.get("file_path") or "")
    if not fp:
        sys.exit(0)
    real = os.path.realpath(fp if os.path.isabs(fp) else os.path.join(project, fp))
    inside = real == project or real.startswith(project + os.sep)
    if inside and TARGET.search(real):
        print(f"{tool}\t{os.path.relpath(real, project)}\t{label(real)}")
    sys.exit(0)

if tool != "Bash":
    sys.exit(0)
cmd = str(inp.get("command") or "")
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
